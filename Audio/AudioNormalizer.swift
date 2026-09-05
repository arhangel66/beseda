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
            throw PodushkaError.processFailed("Cannot convert \(inputURL.lastPathComponent) to 16 kHz mono")
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
            throw PodushkaError.processFailed("Cannot allocate audio buffers")
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

enum ProcessRunner {
    @discardableResult
    static func run(executableURL: URL, arguments: [String], currentDirectoryURL: URL?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let stdoutText = String(
                    data: stdout.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderrText = String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stderrText.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let detail = stderrText.isEmpty ? stdoutText : stderrText
                    continuation.resume(
                        throwing: PodushkaError.processFailed(
                            "\(executableURL.lastPathComponent) exited with \(process.terminationStatus): \(detail)"
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// a long-running tool whose output the UI follows live; the exit status is the result
    static func stream(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        onStdoutLine: @escaping @Sendable (String) -> Void,
        onStderr: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = stdout
        process.standardError = stderr

        let lines = LineSplitter(onLine: onStdoutLine)
        stdout.fileHandleForReading.readabilityHandler = { handle in
            lines.feed(handle.availableData)
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            if let text = String(data: handle.availableData, encoding: .utf8), !text.isEmpty {
                onStderr(text)
            }
        }
        try process.run()
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { process in
                stdout.fileHandleForReading.readabilityHandler = nil
                stderr.fileHandleForReading.readabilityHandler = nil
                lines.feed(stdout.fileHandleForReading.readDataToEndOfFile())
                lines.flush()
                if let text = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8), !text.isEmpty {
                    onStderr(text)
                }
                continuation.resume(returning: process.terminationStatus)
            }
        }
    }

    /// same shape as `run`, but for tools that write their result to stdout instead of stderr
    @discardableResult
    static func output(executableURL: URL, arguments: [String], currentDirectoryURL: URL?) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let stdoutText = String(
                    data: stdout.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                let stderrText = String(
                    data: stderr.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: stdoutText.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let detail = stderrText.isEmpty ? stdoutText : stderrText
                    continuation.resume(
                        throwing: PodushkaError.processFailed(
                            "\(executableURL.lastPathComponent) exited with \(process.terminationStatus): \(detail)"
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

/// Turns a byte stream into whole lines; the pipe hands over arbitrary chunks.
private final class LineSplitter: @unchecked Sendable {
    private let onLine: @Sendable (String) -> Void
    private var buffer = Data()
    private let lock = NSLock()

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func feed(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var lines: [String] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            if let line = String(data: buffer[buffer.startIndex..<newline], encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
            buffer.removeSubrange(buffer.startIndex...newline)
        }
        lock.unlock()
        lines.forEach(onLine)
    }

    func flush() {
        lock.lock()
        let rest = String(data: buffer, encoding: .utf8) ?? ""
        buffer.removeAll()
        lock.unlock()
        if !rest.isEmpty {
            onLine(rest)
        }
    }
}
