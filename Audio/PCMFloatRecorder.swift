import AVFAudio
import CoreAudio
import Foundation

struct AudioFileMetadata: Codable, Hashable {
    let path: String
    let sampleRate: Double
    let channelCount: Int
    let frameCount: Int
}

final class PCMFloatRecorder: @unchecked Sendable {
    let sampleRate: Double
    let channelCount: Int

    private let lock = NSLock()
    private let activityTracker: AudioActivityTracker?
    private var samples: [Float] = []
    private var paused = false

    init(
        sampleRate: Double,
        channelCount: Int,
        expectedDuration: TimeInterval,
        activityTracker: AudioActivityTracker? = nil
    ) {
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.activityTracker = activityTracker
        let reserveDuration = min(expectedDuration, 120)
        samples.reserveCapacity(Int(sampleRate * reserveDuration) * channelCount)
    }

    var frameCount: Int {
        lock.withLock {
            samples.count / channelCount
        }
    }

    /// while paused both channels drop their buffers, so the two files stay aligned
    var isPaused: Bool {
        get { lock.withLock { paused } }
        set { lock.withLock { paused = newValue } }
    }

    func append(pcmBuffer: AVAudioPCMBuffer) throws {
        guard !isPaused else {
            return
        }
        guard pcmBuffer.format.commonFormat == .pcmFormatFloat32 else {
            throw AudioCaptureError.unsupportedFormat("Microphone buffer is not Float32 PCM: \(pcmBuffer.format)")
        }
        guard let channelData = pcmBuffer.floatChannelData else {
            throw AudioCaptureError.unsupportedFormat("Microphone buffer has no Float32 channel data")
        }

        let frames = Int(pcmBuffer.frameLength)
        let channels = Int(pcmBuffer.format.channelCount)
        var chunk: [Float] = []
        chunk.reserveCapacity(frames * channels)

        for frame in 0..<frames {
            for channel in 0..<channels {
                chunk.append(channelData[channel][frame])
            }
        }

        lock.withLock {
            samples.append(contentsOf: chunk)
        }
        activityTracker?.observe(samples: chunk)
    }

    func append(audioBufferList: UnsafePointer<AudioBufferList>, format: AudioStreamBasicDescription) throws {
        guard !isPaused else {
            return
        }
        guard format.mFormatID == kAudioFormatLinearPCM else {
            throw AudioCaptureError.unsupportedFormat("System tap format is not linear PCM: \(format)")
        }

        let flags = format.mFormatFlags
        let isFloat = (flags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (flags & kAudioFormatFlagIsSignedInteger) != 0
        let isNonInterleaved = (flags & kAudioFormatFlagIsNonInterleaved) != 0
        let bitsPerChannel = Int(format.mBitsPerChannel)

        guard isFloat || isSignedInteger else {
            throw AudioCaptureError.unsupportedFormat("System tap PCM format is neither float nor signed integer: \(format)")
        }
        guard bitsPerChannel == 32 || bitsPerChannel == 16 else {
            throw AudioCaptureError.unsupportedFormat("Unsupported system tap bit depth: \(bitsPerChannel)")
        }

        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: audioBufferList))
        var chunk: [Float] = []

        if isNonInterleaved {
            let frames = buffers.map { buffer -> Int in
                let bytesPerSample = max(1, bitsPerChannel / 8)
                let channelsInBuffer = max(1, Int(buffer.mNumberChannels))
                return Int(buffer.mDataByteSize) / bytesPerSample / channelsInBuffer
            }.min() ?? 0
            chunk.reserveCapacity(frames * channelCount)

            for frame in 0..<frames {
                for channel in 0..<channelCount {
                    guard channel < buffers.count else {
                        chunk.append(0)
                        continue
                    }
                    let buffer = buffers[channel]
                    guard let data = buffer.mData else {
                        chunk.append(0)
                        continue
                    }
                    chunk.append(readSample(data: data, index: frame, isFloat: isFloat, bitsPerChannel: bitsPerChannel))
                }
            }
        } else {
            guard let firstBuffer = buffers.first, let data = firstBuffer.mData else {
                return
            }
            let bytesPerFrame = max(1, Int(format.mBytesPerFrame))
            let frames = Int(firstBuffer.mDataByteSize) / bytesPerFrame
            let sampleCount = frames * channelCount
            chunk.reserveCapacity(sampleCount)

            for index in 0..<sampleCount {
                chunk.append(readSample(data: data, index: index, isFloat: isFloat, bitsPerChannel: bitsPerChannel))
            }
        }

        lock.withLock {
            samples.append(contentsOf: chunk)
        }
        activityTracker?.observe(samples: chunk)
    }

    func writeWAV(to url: URL) throws -> AudioFileMetadata {
        let snapshot = lock.withLock {
            samples
        }
        let frames = snapshot.count / channelCount
        guard frames > 0 else {
            throw AudioCaptureError.noFrames("No microphone frames captured for \(url.path)")
        }

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)

        guard let channelData = buffer.floatChannelData else {
            throw AudioCaptureError.unsupportedFormat("Could not allocate Float32 output buffer")
        }

        for frame in 0..<frames {
            for channel in 0..<channelCount {
                channelData[channel][frame] = snapshot[frame * channelCount + channel]
            }
        }

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return AudioFileMetadata(path: url.path, sampleRate: sampleRate, channelCount: channelCount, frameCount: frames)
    }

    private func readSample(data: UnsafeMutableRawPointer, index: Int, isFloat: Bool, bitsPerChannel: Int) -> Float {
        if isFloat && bitsPerChannel == 32 {
            return data.assumingMemoryBound(to: Float.self)[index]
        }
        if bitsPerChannel == 16 {
            return Float(data.assumingMemoryBound(to: Int16.self)[index]) / Float(Int16.max)
        }
        return 0
    }
}
