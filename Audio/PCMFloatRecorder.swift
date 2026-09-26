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
    let url: URL?

    private let lock = NSLock()
    private let activityTracker: AudioActivityTracker?
    private let format: AVAudioFormat
    // samples reach the disk on every write; after a crash `repairWAVHeader` makes the file readable
    private var file: AVAudioFile?
    private var frameCount = 0
    private var paused = false
    private var failedWrites = 0
    private var firstWriteError: String?
    private let maximumDataBytes: Int

    /// a WAV header holds 32-bit sizes: past 4 GiB (~3 h of 48 kHz stereo) the file is unreadable,
    /// so the recorder refuses to grow the data chunk beyond this and leaves room for the header
    static let wavDataLimit = 4_000_000_000

    /// opens `url` for writing at once: every appended buffer goes straight to disk; nil only meters levels
    init(
        url: URL?,
        sampleRate: Double,
        channelCount: Int,
        activityTracker: AudioActivityTracker?,
        maximumDataBytes: Int = PCMFloatRecorder.wavDataLimit
    ) throws {
        self.url = url
        self.maximumDataBytes = maximumDataBytes
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.activityTracker = activityTracker
        format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        )!
        if let url {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            file = try AVAudioFile(forWriting: url, settings: format.settings)
        }
    }

    /// while paused both channels drop their buffers, so the two files stay aligned
    var isPaused: Bool {
        get { lock.withLock { paused } }
        set { lock.withLock { paused = newValue } }
    }

    /// buffers that did not reach the file: the live transcription backs off when this grows
    var droppedBufferCount: Int {
        lock.withLock { failedWrites }
    }

    /// the first write that failed (disk full, the file size limit), kept for the user to see
    var writeError: String? {
        lock.withLock { firstWriteError }
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

        try write(interleaved: chunk)
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

        try write(interleaved: chunk)
        activityTracker?.observe(samples: chunk)
    }

    /// closes the file; the audio is already on disk
    func finish() throws -> AudioFileMetadata {
        let frames = lock.withLock {
            file = nil
            return frameCount
        }
        guard frames > 0 else {
            throw AudioCaptureError.noFrames("No frames captured for \(url?.path ?? "a level check")")
        }
        return AudioFileMetadata(path: url?.path ?? "", sampleRate: sampleRate, channelCount: channelCount, frameCount: frames)
    }

    private func write(interleaved chunk: [Float]) throws {
        let frames = chunk.count / channelCount
        guard frames > 0, url != nil else {
            return
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let channelData = buffer.floatChannelData!
        for frame in 0..<frames {
            for channel in 0..<channelCount {
                channelData[channel][frame] = chunk[frame * channelCount + channel]
            }
        }
        try lock.withLock {
            guard let file else {
                return
            }
            do {
                guard (frameCount + frames) * channelCount * MemoryLayout<Float>.size <= maximumDataBytes else {
                    throw AudioCaptureError.fileFull("The recording reached the 4 GB WAV limit")
                }
                try file.write(from: buffer)
            } catch {
                failedWrites += 1
                firstWriteError = firstWriteError ?? error.localizedDescription
                throw error
            }
            frameCount += frames
        }
    }

    /// a WAV whose writer died: AudioFile fills in the header sizes only at close, so a killed
    /// recording has all its samples on disk and a header that says zero frames
    static func repairWAVHeader(at url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let fileLength = try handle.seekToEnd()
        var offset: UInt64 = 12
        while offset + 8 <= fileLength {
            try handle.seek(toOffset: offset)
            let header = try handle.read(upToCount: 8) ?? Data()
            guard header.count == 8 else {
                return
            }
            let chunkSize = header.suffix(4).withUnsafeBytes { UInt64($0.loadUnaligned(as: UInt32.self).littleEndian) }
            if header.prefix(4) == Data("data".utf8) {
                // `wavDataLimit` keeps a live recording under 4 GB, so the sizes fit
                try write(UInt32(clamping: fileLength - offset - 8), at: offset + 4, in: handle)
                try write(UInt32(clamping: fileLength - 8), at: 4, in: handle)
                return
            }
            offset += 8 + chunkSize + chunkSize % 2
        }
    }

    private static func write(_ value: UInt32, at offset: UInt64, in handle: FileHandle) throws {
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: withUnsafeBytes(of: value.littleEndian) { Data($0) })
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
