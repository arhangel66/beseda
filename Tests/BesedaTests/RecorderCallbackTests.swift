import AVFAudio
import CoreAudio
import Foundation
import Testing

@testable import Beseda

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("beseda-callback-\(UUID().uuidString)", isDirectory: true)
}

/// stereo buffers of a different ramp each, so a lost, repeated or swapped frame changes the file
private func syntheticBuffers(count: Int, frames: Int) -> [AVAudioPCMBuffer] {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
    return (0..<count).map { index in
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            buffer.floatChannelData![0][frame] = Float(index * frames + frame) / 1_000_000
            buffer.floatChannelData![1][frame] = -Float(frame) / Float(frames)
        }
        return buffer
    }
}

/// the recorder before BESEDA-101: interleave, copy into a fresh buffer and write, all inside the callback
private final class SynchronousRecorder {
    private let file: AVAudioFile
    private let format: AVAudioFormat
    private let lock = NSLock()

    init(url: URL, format: AVAudioFormat) throws {
        self.format = format
        file = try AVAudioFile(forWriting: url, settings: format.settings)
    }

    func append(pcmBuffer: AVAudioPCMBuffer) throws {
        let frames = Int(pcmBuffer.frameLength)
        let channels = Int(pcmBuffer.format.channelCount)
        var chunk: [Float] = []
        chunk.reserveCapacity(frames * channels)
        for frame in 0..<frames {
            for channel in 0..<channels {
                chunk.append(pcmBuffer.floatChannelData![channel][frame])
            }
        }
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for frame in 0..<frames {
            for channel in 0..<channels {
                buffer.floatChannelData![channel][frame] = chunk[frame * channels + channel]
            }
        }
        try lock.withLock { try file.write(from: buffer) }
    }
}

@Test func buffersThroughTheCallbackPathLandOnDiskAsTheOldPathWroteThem() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let buffers = syntheticBuffers(count: 200, frames: 512)
    let oldURL = directory.appendingPathComponent("old.raw.wav")
    let newURL = directory.appendingPathComponent("new.raw.wav")
    var old: SynchronousRecorder? = try SynchronousRecorder(url: oldURL, format: buffers[0].format)
    let recorder = try PCMFloatRecorder(url: newURL, sampleRate: 48_000, channelCount: 2, activityTracker: nil)

    for buffer in buffers {
        try old!.append(pcmBuffer: buffer)
        try recorder.append(pcmBuffer: buffer)
    }
    old = nil
    let metadata = try recorder.finish()

    #expect(metadata.frameCount == 200 * 512)
    #expect(recorder.droppedFrameCount == 0)
    #expect(try Data(contentsOf: newURL) == Data(contentsOf: oldURL))
}

@Test func interleavedInt16FromTheSystemTapIsConvertedAsBefore() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("them.raw.wav")
    var samples: [Int16] = [Int16.max, -Int16.max, 0, 16_384]
    let format = AudioStreamBasicDescription(
        mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsSignedInteger,
        mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0
    )
    let recorder = try PCMFloatRecorder(url: url, sampleRate: 48_000, channelCount: 2, activityTracker: nil)

    try samples.withUnsafeMutableBytes { bytes in
        var list = AudioBufferList(
            mNumberBuffers: 1,
            mBuffers: AudioBuffer(mNumberChannels: 2, mDataByteSize: UInt32(bytes.count), mData: bytes.baseAddress)
        )
        try recorder.append(audioBufferList: &list, format: format)
    }
    _ = try recorder.finish()

    let file = try AVAudioFile(forReading: url)
    let readBack = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 2)!
    try file.read(into: readBack)
    #expect(readBack.frameLength == 2)
    #expect(readBack.floatChannelData![0][0] == 1)
    #expect(readBack.floatChannelData![1][0] == -1)
    #expect(readBack.floatChannelData![1][1] == 16_384 / Float(Int16.max))
}

@Test func aWriterThatCannotKeepUpStopsTheRecordingVisibly() throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let recorder = try PCMFloatRecorder(
        url: directory.appendingPathComponent("me.raw.wav"),
        sampleRate: 48_000, channelCount: 2, activityTracker: nil, ringFrames: 2_048
    )
    recorder.writerStall = 0.2

    for buffer in syntheticBuffers(count: 20, frames: 512) {
        try recorder.append(pcmBuffer: buffer)
    }
    let metadata = try recorder.finish()

    #expect(recorder.droppedFrameCount > 0)
    #expect(metadata.frameCount + recorder.droppedFrameCount == 20 * 512)
    #expect(recorder.droppedBufferCount > 0)
    let writeError = try #require(recorder.writeError)
    guard case AudioCaptureError.writerBehind = writeError else {
        Issue.record("expected writerBehind, got \(writeError)")
        return
    }
    #expect(AppController.recordingWarning(forWriteError: writeError).contains("не успевала"))
}

/// callback durations in microseconds, sorted
private func callbackTimes(buffers: [AVAudioPCMBuffer], append: (AVAudioPCMBuffer) throws -> Void) rethrows -> [Double] {
    var times: [Double] = []
    times.reserveCapacity(buffers.count)
    for buffer in buffers {
        let started = DispatchTime.now().uptimeNanoseconds
        try append(buffer)
        times.append(Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000)
        // 10 ms buffers at their real pace, as a device would deliver them
        Thread.sleep(forTimeInterval: 0.01)
    }
    return times.sorted()
}

private func summary(_ sorted: [Double]) -> String {
    let p50 = sorted[sorted.count / 2]
    let p99 = sorted[sorted.count * 99 / 100]
    return String(format: "p50 %.1f µs, p99 %.1f µs, max %.1f µs", p50, p99, sorted.last!)
}

/// headless: synthetic buffers, temp dirs, no capture. Run with BESEDA_CALLBACK_LOAD=1
@Test(.enabled(if: ProcessInfo.processInfo.environment["BESEDA_CALLBACK_LOAD"] == "1"))
func callbackTimeUnderCPUAndDiskLoad() throws {
    let directory = temporaryDirectory()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let buffers = syntheticBuffers(count: 1_000, frames: 480)
    let running = NSLock()
    nonisolated(unsafe) var loadRunning = true
    let isLoadRunning = { running.withLock { loadRunning } }
    let load = DispatchGroup()
    for _ in 0..<ProcessInfo.processInfo.activeProcessorCount {
        DispatchQueue.global(qos: .userInitiated).async(group: load) {
            var spin = 0.0
            while isLoadRunning() {
                for step in 0..<100_000 { spin += sin(Double(step)) }
            }
            _ = spin
        }
    }
    DispatchQueue.global(qos: .userInitiated).async(group: load) {
        let block = Data(count: 8 << 20)
        let url = directory.appendingPathComponent("load.bin")
        while isLoadRunning() {
            FileManager.default.createFile(atPath: url.path, contents: nil)
            let handle = try! FileHandle(forWritingTo: url)
            for _ in 0..<8 {
                handle.write(block)
                fsync(handle.fileDescriptor)
            }
            try! handle.close()
        }
    }

    let old = try SynchronousRecorder(url: directory.appendingPathComponent("old.raw.wav"), format: buffers[0].format)
    let before = try callbackTimes(buffers: buffers) { try old.append(pcmBuffer: $0) }
    let recorder = try PCMFloatRecorder(
        url: directory.appendingPathComponent("new.raw.wav"), sampleRate: 48_000, channelCount: 2, activityTracker: AudioActivityTracker()
    )
    let after = try callbackTimes(buffers: buffers) { try recorder.append(pcmBuffer: $0) }
    _ = try recorder.finish()
    running.withLock { loadRunning = false }
    load.wait()

    print("callback before (write in callback): \(summary(before))")
    print("callback after (ring buffer): \(summary(after)); dropped frames \(recorder.droppedFrameCount)")
    #expect(recorder.droppedFrameCount == 0)
}
