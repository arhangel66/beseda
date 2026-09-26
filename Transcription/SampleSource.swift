import AVFoundation
import Foundation

/// 16 kHz mono float32 in [-1, 1], read a window at a time so a four-hour call never sits in memory whole
/// Unchecked: the file's reused buffer is not locked, and every caller reads from one thread at a time.
struct SampleSource: @unchecked Sendable {
    let count: Int
    let read: (Range<Int>) throws -> [Float]

    init(count: Int, read: @escaping (Range<Int>) throws -> [Float]) {
        self.count = count
        self.read = read
    }

    init(_ samples: [Float]) {
        self.init(count: samples.count) { Array(samples[$0]) }
    }

    /// the normalized file; one buffer, reused, as large as the largest window asked for
    static func file(at url: URL) throws -> SampleSource {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        var buffer: AVAudioPCMBuffer?
        return SampleSource(count: Int(file.length)) { range in
            guard !range.isEmpty else {
                return []
            }
            if (buffer?.frameCapacity ?? 0) < range.count {
                buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(range.count))
            }
            guard let buffer else {
                throw BesedaError.processFailed("Не хватило памяти под \(url.lastPathComponent)")
            }
            guard let channel = buffer.floatChannelData?[0] else {
                throw BesedaError.processFailed("В \(url.lastPathComponent) нет звука")
            }
            // a read can stop short of the frame count (at 399360 of 400001 in the test), so read until full
            file.framePosition = AVAudioFramePosition(range.lowerBound)
            var samples: [Float] = []
            samples.reserveCapacity(range.count)
            while samples.count < range.count {
                try file.read(into: buffer, frameCount: AVAudioFrameCount(range.count - samples.count))
                guard buffer.frameLength > 0 else {
                    break
                }
                samples += UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            }
            return samples
        }
    }
}
