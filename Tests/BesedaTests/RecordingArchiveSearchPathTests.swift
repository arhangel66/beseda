import Foundation
import Testing

@testable import Beseda

@Test func recordingTranscriptArchiveAndSearchRoundTrip() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-core-path-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let audioURL = directory.appendingPathComponent("recording.wav")
    try Data([
        0x52, 0x49, 0x46, 0x46, 0x28, 0, 0, 0, 0x57, 0x41, 0x56, 0x45,
        0x66, 0x6d, 0x74, 0x20, 16, 0, 0, 0, 1, 0, 1, 0,
        0x80, 0x3e, 0, 0, 0x00, 0x7d, 0, 0, 2, 0, 16, 0,
        0x64, 0x61, 0x74, 0x61, 4, 0, 0, 0, 0, 0, 0, 0
    ]).write(to: audioURL)

    let transcribe: (URL) throws -> ASRTranscription = { input in
        let audio = try Data(contentsOf: input)
        #expect(audio.prefix(4) == Data("RIFF".utf8))
        return ASRTranscription(
            id: "asr-1",
            text: "Обсудили редкий поисковый маркер",
            segments: [
                TranscriptSegment(
                    start: 0, end: 1, text: "Обсудили редкий поисковый маркер", confidence: nil, words: nil
                )
            ],
            audioDurationSec: 1,
            wallTimeSec: 0.01,
            realTimeFactor: 0.01
        )
    }
    let transcription = try transcribe(audioURL)

    let asrURL = directory.appendingPathComponent("mic.asr.json")
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(transcription).write(to: asrURL)
    let asrJSON = try String(contentsOf: asrURL, encoding: .utf8)
    #expect(asrJSON.contains("\"audio_duration_sec\""))
    #expect(asrJSON.contains("\"wall_time_sec\""))
    #expect(asrJSON.contains("\"real_time_factor\""))
    #expect(!asrJSON.contains("audioDurationSec"))

    let transcriptURL = directory.appendingPathComponent("transcript.md")
    let result = TranscriptResult(
        id: transcription.id,
        createdAt: Date(),
        sessionDirectory: directory,
        rawAudioURL: audioURL,
        normalizedAudioURL: audioURL,
        markdownURL: transcriptURL,
        text: transcription.text,
        segments: transcription.segments,
        audioDurationSec: transcription.audioDurationSec,
        wallTimeSec: transcription.wallTimeSec,
        realTimeFactor: transcription.realTimeFactor
    )
    try TranscriptMerger.writeMicrophoneTranscript(result, to: transcriptURL)

    let store = CallStore(dbURL: directory.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    try store.upsertCall(
        id: "call-1",
        kind: "mic",
        startedAt: Date(),
        endedAt: Date(),
        durationSec: 1,
        status: "ready",
        transcriptURL: transcriptURL,
        audioDirectoryURL: directory,
        error: nil,
        appName: nil
    )
    try store.replaceSegments(
        callID: "call-1",
        segments: transcription.segments.enumerated().map { index, segment in
            StoredTranscriptSegment(
                speaker: "me",
                startSec: segment.start,
                endSec: segment.end,
                text: segment.text,
                orderIndex: index
            )
        }
    )

    #expect(try store.fetchCall(id: "call-1")?.status == "ready")
    #expect(try store.fetchSegments(callID: "call-1").map(\.text) == [transcription.text])
    #expect(try store.searchCalls(matching: "редкий поисковый").map(\.id) == ["call-1"])
    #expect(FileManager.default.fileExists(atPath: transcriptURL.path))
}
