import AVFAudio
import Foundation

/// Resamples a raw capture to what the ASR model expects: 16 kHz, one channel, 16-bit.
/// Done with AVAudioConverter so the app has no ffmpeg to install on a fresh Mac.
enum AudioNormalizer {
    static let sampleRate: Double = 16_000

    static func normalize(inputURL: URL, outputURL: URL) async throws -> URL {
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // resampling a long call is seconds of CPU; keep it off the caller's actor
        return try await Task.detached(priority: .userInitiated) {
            try convert(inputURL: inputURL, outputURL: outputURL)
            return outputURL
        }.value
    }

    private static func convert(inputURL: URL, outputURL: URL) throws {
        let input = try AVAudioFile(forReading: inputURL)
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: 1, interleaved: true
        ), let converter = AVAudioConverter(from: input.processingFormat, to: target) else {
            throw BesedaError.processFailed("Cannot convert \(inputURL.lastPathComponent) to 16 kHz mono")
        }
        converter.sampleRateConverterQuality = .max
        try? FileManager.default.removeItem(at: outputURL)
        let output = try AVAudioFile(
            forWriting: outputURL, settings: target.settings, commonFormat: .pcmFormatInt16, interleaved: true
        )

        let inputCapacity: AVAudioFrameCount = 32_768
        let ratio = target.sampleRate / input.processingFormat.sampleRate
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: inputCapacity),
              let outputBuffer = AVAudioPCMBuffer(
                  pcmFormat: target, frameCapacity: AVAudioFrameCount(Double(inputCapacity) * ratio) + 64
              ) else {
            throw BesedaError.processFailed("Cannot allocate audio buffers")
        }

        let feed = InputFeed(file: input, buffer: inputBuffer)
        var reachedEnd = false
        while !reachedEnd {
            var convertError: NSError?
            let status = converter.convert(to: outputBuffer, error: &convertError) { _, outStatus in
                feed.next(outStatus)
            }
            if let readError = feed.readError {
                throw readError
            }
            if let convertError {
                throw convertError
            }
            if outputBuffer.frameLength > 0 {
                try output.write(from: outputBuffer)
            }
            reachedEnd = status == .endOfStream || status == .error
        }
    }
}

/// The converter pulls input through a `@Sendable` block; this hands it the next slice of the file.
/// The block runs synchronously on the converting thread, so the unchecked marker is honest.
private final class InputFeed: @unchecked Sendable {
    private let file: AVAudioFile
    private let buffer: AVAudioPCMBuffer
    private(set) var readError: Error?

    init(file: AVAudioFile, buffer: AVAudioPCMBuffer) {
        self.file = file
        self.buffer = buffer
    }

    func next(_ outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioPCMBuffer? {
        // reading at the end throws instead of returning an empty buffer
        guard file.framePosition < file.length else {
            outStatus.pointee = .endOfStream
            return nil
        }
        do {
            try file.read(into: buffer)
        } catch {
            readError = error
            outStatus.pointee = .endOfStream
            return nil
        }
        outStatus.pointee = .haveData
        return buffer
    }
}
