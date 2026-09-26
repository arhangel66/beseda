import AVFoundation
import Foundation
import TranscribeCpp

/// Runs the selected GGUF model in-process through transcribe.cpp. Replaces the Python worker:
/// same surface as the old `ASRClient` so the controller did not have to change, but the model
/// lives in this process and the only file on disk is the model itself.
final class LocalTranscriber: @unchecked Sendable {
    var diagnosticsHandler: (@Sendable (String) -> Void)?
    /// share of the audio the running job has reached; only one job runs at a time
    var progressHandler: (@Sendable (Double) -> Void)?

    /// The library windows long audio itself for parakeet, so this is only about the progress
    /// bar moving — and it is the chunk length the Python worker used, so nothing gets coarser.
    private static let progressChunkSeconds: Double = 120
    private static let idleTimeout: TimeInterval = 10 * 60
    private static let sampleRate = 16_000.0

    private struct Loaded {
        let model: SpeechModel
        let handle: TranscribeCpp.Model
        let session: Session
    }

    private let paths: AppPaths
    private let queue = DispatchQueue(label: "app.beseda.transcriber")
    private var selected: SpeechModel
    private var loaded: Loaded?
    private var idleShutdown: DispatchWorkItem?

    init(paths: AppPaths, model: SpeechModel = .default) {
        self.paths = paths
        self.selected = model
    }

    /// Switching models unloads the old one; the next job loads the new one.
    func select(_ model: SpeechModel) {
        queue.async {
            guard model != self.selected else {
                return
            }
            self.selected = model
            self.unload()
        }
    }

    func start() async throws -> ASRReadyEvent {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.cancelIdleShutdown()
                do {
                    let loaded = try self.load()
                    continuation.resume(returning: ASRReadyEvent(
                        model: loaded.model.id,
                        version: Transcribe.version()
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func transcribe(audioURL: URL) async throws -> ASRTranscription {
        let samples = try Self.readSamples(at: audioURL)
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.cancelIdleShutdown()
                do {
                    continuation.resume(returning: try self.run(samples: samples))
                } catch {
                    continuation.resume(throwing: error)
                }
                self.scheduleIdleShutdown()
            }
        }
    }

    func stop() {
        queue.async {
            self.cancelIdleShutdown()
            self.unload()
        }
    }

    /// Frees the model before the process exits. ggml asserts that every Metal resource is gone
    /// by then and aborts otherwise, which macOS would report as a crash on quit. Waits for a
    /// running job, but not past `timeout` — a hung quit is worse than that crash report.
    func shutdown(timeout: TimeInterval = 5) {
        let done = DispatchSemaphore(value: 0)
        queue.async {
            self.cancelIdleShutdown()
            self.unload()
            done.signal()
        }
        _ = done.wait(timeout: .now() + timeout)
    }

    private func run(samples: [Float]) throws -> ASRTranscription {
        let loaded = try load()
        let started = Date()
        let chunkSeconds = loaded.model.maxUtteranceSec ?? Self.progressChunkSeconds
        let pieces = UtteranceSplitter.split(samples, sampleRate: Self.sampleRate, maxSeconds: chunkSeconds)
        let options = RunOptions(timestamps: .word, language: "ru")

        var words: [TranscriptWord] = []
        for (index, piece) in pieces.enumerated() {
            let transcript = try loaded.session.run(piece.samples, options: options)
            words += Self.words(in: transcript).map { word in
                TranscriptWord(
                    start: word.start + piece.offsetSec,
                    end: word.end + piece.offsetSec,
                    text: word.text
                )
            }
            progressHandler?(Double(index + 1) / Double(pieces.count))
        }

        let segments = SentenceBuilder.segments(from: words)
        let audioDuration = Double(samples.count) / Self.sampleRate
        let wallTime = Date().timeIntervalSince(started)
        return ASRTranscription(
            id: UUID().uuidString,
            text: segments.map(\.text).joined(separator: " "),
            segments: segments,
            audioDurationSec: audioDuration,
            wallTimeSec: wallTime,
            realTimeFactor: audioDuration > 0 ? wallTime / audioDuration : nil
        )
    }

    private func load() throws -> Loaded {
        if let loaded, loaded.model == selected {
            return loaded
        }
        unload()

        let modelURL = selected.localURL(in: paths.modelsDirectory)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw BesedaError.runtimeMissing
        }
        let handle = try TranscribeCpp.Model(path: modelURL.path)
        let loaded = Loaded(model: selected, handle: handle, session: try handle.session())
        self.loaded = loaded
        diagnosticsHandler?("Speech model loaded: \(selected.id) on \(handle.backend)")
        return loaded
    }

    private func unload() {
        guard loaded != nil else {
            return
        }
        loaded = nil
        diagnosticsHandler?("Speech model unloaded")
    }

    private func scheduleIdleShutdown() {
        // the model sits in memory, and the app runs from login
        let shutdown = DispatchWorkItem { [weak self] in
            self?.unload()
        }
        idleShutdown = shutdown
        queue.asyncAfter(deadline: .now() + Self.idleTimeout, execute: shutdown)
    }

    private func cancelIdleShutdown() {
        idleShutdown?.cancel()
        idleShutdown = nil
    }

    /// GigaAM's family only times tokens, so its words have to be reassembled from them
    private static func words(in transcript: Transcript) -> [TranscriptWord] {
        guard transcript.words.isEmpty else {
            return transcript.words.map {
                TranscriptWord(start: Double($0.t0Ms) / 1000, end: Double($0.t1Ms) / 1000, text: $0.text)
            }
        }
        return WordAssembler.words(from: transcript.tokens.map {
            WordAssembler.Token(start: Double($0.t0Ms) / 1000, end: Double($0.t1Ms) / 1000, text: $0.text)
        })
    }

    /// the normalized file is already 16 kHz mono; the engine wants it as float32 in [-1, 1]
    static func readSamples(at url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw BesedaError.processFailed("Could not allocate a buffer for \(url.lastPathComponent)")
        }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else {
            throw BesedaError.processFailed("No audio in \(url.lastPathComponent)")
        }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
