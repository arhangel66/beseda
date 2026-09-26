import AVFoundation
import Foundation
import TranscribeCpp

// Beseda's dual-call pipeline (AppController.transcribeDualCall at 03dae95) on every eval recording:
// normalize both channels, ASR mic, ASR system, diarize system, split its words into speaker turns.
// Writes <eval>/hyp/baseline-<engine>/ in the format of ../README.md, plus the diarizer's raw timeline.

let evalRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let audioDirectory = evalRoot.appendingPathComponent("data/audio")
let modelsDirectory = evalRoot.appendingPathComponent("baseline/models")
let scratchDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("beseda-baseline")

struct HypothesisSegment: Encodable {
    let start: Double
    let end: Double
    let speaker: String
    let channel: String
    let text: String
}

struct Hypothesis: Encodable {
    let segments: [HypothesisSegment]
    let processing_seconds: Double
}

/// LocalTranscriber.run without the app's queue, progress and idle unload
func transcribe(_ audioURL: URL, model: SpeechModel, session: Session) throws -> [TranscriptSegment] {
    let samples = try readSamples(at: audioURL)
    let chunkSeconds = model.maxUtteranceSec ?? 120
    let pieces = UtteranceSplitter.split(samples, sampleRate: 16_000, maxSeconds: chunkSeconds)
    let options = RunOptions(timestamps: .word, language: model.transcriptionLanguage)
    var words: [TranscriptWord] = []
    for piece in pieces {
        let transcript = try session.run(piece.samples, options: options)
        words += engineWords(in: transcript).map {
            TranscriptWord(start: $0.start + piece.offsetSec, end: $0.end + piece.offsetSec, text: $0.text)
        }
    }
    return SentenceBuilder.segments(from: words)
}

/// LocalTranscriber.words(in:)
func engineWords(in transcript: Transcript) -> [TranscriptWord] {
    guard transcript.words.isEmpty else {
        return transcript.words.map {
            TranscriptWord(start: Double($0.t0Ms) / 1000, end: Double($0.t1Ms) / 1000, text: $0.text)
        }
    }
    return WordAssembler.words(from: transcript.tokens.map {
        WordAssembler.Token(start: Double($0.t0Ms) / 1000, end: Double($0.t1Ms) / 1000, text: $0.text)
    })
}

/// LocalTranscriber.readSamples(at:)
func readSamples(at url: URL) throws -> [Float] {
    let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw BesedaError.processFailed("Could not allocate a buffer for \(url.lastPathComponent)")
    }
    try file.read(into: buffer)
    guard let channel = buffer.floatChannelData?[0] else {
        throw BesedaError.processFailed("No audio in \(url.lastPathComponent)")
    }
    return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
}

/// the app's result type, only so its own `speakerSegments` merges the channels
func channelResult(_ segments: [TranscriptSegment]) -> TranscriptResult {
    TranscriptResult(
        id: "", createdAt: Date(), sessionDirectory: scratchDirectory, rawAudioURL: scratchDirectory,
        normalizedAudioURL: scratchDirectory, markdownURL: scratchDirectory, text: "", segments: segments,
        audioDurationSec: nil, wallTimeSec: nil, realTimeFactor: nil
    )
}

func rttm(_ fileID: String, _ segments: [HypothesisSegment]) -> String {
    segments.filter { $0.end > $0.start }.map {
        String(format: "SPEAKER %@ 1 %.3f %.3f <NA> <NA> %@ <NA> <NA>\n", fileID, $0.start, $0.end - $0.start, $0.speaker)
    }.joined()
}

func write(_ hypothesis: Hypothesis, fileID: String, to directory: URL) throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(hypothesis).write(to: directory.appendingPathComponent("\(fileID).json"))
    try rttm(fileID, hypothesis.segments).write(
        to: directory.appendingPathComponent("\(fileID).rttm"), atomically: true, encoding: .utf8
    )
}

/// every recording of the eval set through `model`; the raw diarizer timeline goes to its own dir once
func runEvalSet(with model: SpeechModel, diarizer: Diarizer, writeRawTimeline: Bool) async throws {
    let handle = try TranscribeCpp.Model(path: model.localURL(in: modelsDirectory).path)
    let session = try handle.session()
    // ggml compiles its Metal kernels on the first run; the app pays that once per model load, not per call
    _ = try await session.run([Float](repeating: 0, count: 16_000), options: RunOptions(timestamps: .word, language: model.transcriptionLanguage))
    let hypothesisDirectory = evalRoot.appendingPathComponent("hyp/baseline-\(model.id.split(separator: "-").first!)")
    let rawDirectory = evalRoot.appendingPathComponent("hyp/baseline-diarizer-raw")
    let systemFiles = try FileManager.default.contentsOfDirectory(atPath: audioDirectory.path)
        .filter { $0.hasSuffix(".system.wav") }.sorted()

    for systemFile in systemFiles {
        let fileID = String(systemFile.dropLast(".system.wav".count))
        let micURL = audioDirectory.appendingPathComponent("\(fileID).mic.wav")
        let hasMic = FileManager.default.fileExists(atPath: micURL.path)
        let started = Date()

        let systemASR = try await AudioNormalizer.normalize(
            inputURL: audioDirectory.appendingPathComponent(systemFile),
            outputURL: scratchDirectory.appendingPathComponent("them.asr.wav")
        )
        var mine: [TranscriptSegment] = []
        if hasMic {
            let micASR = try await AudioNormalizer.normalize(
                inputURL: micURL, outputURL: scratchDirectory.appendingPathComponent("me.asr.wav")
            )
            mine = try transcribe(micASR, model: model, session: session)
        }
        let theirs = try transcribe(systemASR, model: model, session: session)
        // AppController.diarizedTurns: a diarizer failure keeps the single `them` label
        let timeline = (try? await diarizer.timeline(for: systemASR)) ?? []
        let turns = SpeakerAssignment.remoteTurns(segments: theirs, timeline: timeline)
        let elapsed = Date().timeIntervalSince(started)

        let result = DualTranscriptResult(
            id: fileID, createdAt: Date(), sessionDirectory: scratchDirectory, markdownURL: scratchDirectory,
            microphone: channelResult(mine), systemAudio: channelResult(theirs), remoteTurns: turns
        )
        let segments = result.speakerSegments.map {
            HypothesisSegment(
                start: $0.segment.start, end: $0.segment.end, speaker: $0.speaker,
                channel: $0.speaker == "me" ? "mic" : "system", text: $0.segment.text
            )
        }
        try write(Hypothesis(segments: segments, processing_seconds: elapsed), fileID: fileID, to: hypothesisDirectory)

        if writeRawTimeline {
            let raw = timeline.map {
                HypothesisSegment(start: $0.start, end: $0.end, speaker: "spk-\($0.speaker)", channel: "system", text: "")
            } + mine.map { HypothesisSegment(start: $0.start, end: $0.end, speaker: "me", channel: "mic", text: "") }
            try write(Hypothesis(segments: raw, processing_seconds: elapsed), fileID: fileID, to: rawDirectory)
        }
        print("\(model.id) \(fileID): \(String(format: "%.1f", elapsed)) s, \(Set(turns.map(\.speaker)).count) remote speakers")
    }
}

let diarizer = Diarizer()
// the first call downloads and compiles the CoreML models; keep that out of the timings
try await diarizer.prepareModels()
try await runEvalSet(with: .parakeetV3, diarizer: diarizer, writeRawTimeline: true)
try await runEvalSet(with: .gigaamV3, diarizer: diarizer, writeRawTimeline: false)
