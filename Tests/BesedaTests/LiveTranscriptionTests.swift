import AVFAudio
import Foundation
import Testing

@testable import Beseda

private func word(_ text: String, _ start: Double, _ end: Double) -> TranscriptWord {
    TranscriptWord(start: start, end: end, text: text)
}

/// an open recorder with `seconds` of a constant stereo 48 kHz signal written, like a call in progress
private func recordingInProgress(seconds: Int, at url: URL) throws -> PCMFloatRecorder {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000)!
    buffer.frameLength = 48_000
    for frame in 0..<48_000 {
        buffer.floatChannelData![0][frame] = 0.2
        buffer.floatChannelData![1][frame] = 0.4
    }
    let recorder = try PCMFloatRecorder(url: url, sampleRate: 48_000, channelCount: 2, activityTracker: nil)
    for _ in 0..<seconds {
        try recorder.append(pcmBuffer: buffer)
    }
    return recorder
}

@Test func overlappingChunksKeepEachWordOnce() {
    let first = [word("раз", 15.0, 15.5), word("два", 18.2, 18.6), word("три", 19.4, 19.9)]
    let second = [word("два", 18.25, 18.65), word("три", 19.4, 19.8), word("четыре", 20.5, 21.0)]

    let merged = LiveChunkMerge.merge(first, chunk: second, chunkStart: 18, overlap: 2)

    #expect(merged.map(\.text) == ["раз", "два", "три", "четыре"])
}

@Test func aWordStraddlingTheCutIsNotRepeated() {
    let first = [word("привет", 18.7, 19.05)]
    let second = [word("привет", 18.75, 19.1), word("мир", 19.3, 19.6)]

    let merged = LiveChunkMerge.merge(first, chunk: second, chunkStart: 18, overlap: 2)

    #expect(merged.map(\.text) == ["привет", "мир"])
}

@Test func aChunkAfterASkipKeepsAllItsWords() {
    let merged = LiveChunkMerge.merge([word("старое", 5, 6)], chunk: [word("новое", 60.1, 60.5)], chunkStart: 60, overlap: 0)

    #expect(merged.map(\.text) == ["старое", "новое"])
}

@Test func nextChunkWaitsForAFullChunkOnDisk() {
    #expect(LiveBackoff.nextChunkStart(transcribedUntil: 0, recordedSeconds: 19) == nil)
    #expect(LiveBackoff.nextChunkStart(transcribedUntil: 0, recordedSeconds: 20) == 0)
    #expect(LiveBackoff.nextChunkStart(transcribedUntil: 20, recordedSeconds: 37) == nil)
    #expect(LiveBackoff.nextChunkStart(transcribedUntil: 20, recordedSeconds: 38) == 18)
}

@Test func aBacklogOfMoreThanAChunkIsSkipped() {
    let start = LiveBackoff.nextChunkStart(transcribedUntil: 20, recordedSeconds: 100)

    #expect(start == 80)
}

@Test func slowChunksWidenTheRestAndCleanOnesNarrowIt() {
    var backoff = LiveBackoff()

    backoff.chunkFinished(wallSeconds: 25, audioSeconds: 20, droppedBuffers: 0)
    #expect(backoff.restSeconds == 10)
    backoff.chunkFinished(wallSeconds: 25, audioSeconds: 20, droppedBuffers: 0)
    #expect(backoff.restSeconds == 20)
    for _ in 0..<5 {
        backoff.chunkFinished(wallSeconds: 25, audioSeconds: 20, droppedBuffers: 0)
    }
    #expect(backoff.restSeconds == LiveBackoff.maxRestSeconds)
    for _ in 0..<7 {
        backoff.chunkFinished(wallSeconds: 2, audioSeconds: 20, droppedBuffers: 0)
    }
    #expect(backoff.restSeconds == 0)
}

@Test func droppedBuffersWidenTheRestOnlyWhenTheyGrow() {
    var backoff = LiveBackoff()

    backoff.chunkFinished(wallSeconds: 2, audioSeconds: 20, droppedBuffers: 3)
    #expect(backoff.restSeconds == 10)
    backoff.chunkFinished(wallSeconds: 2, audioSeconds: 20, droppedBuffers: 3)
    #expect(backoff.restSeconds == 5)
}

@Test func keyPointsRunEveryIntervalOnlyWithNewText() {
    var schedule = KeyPointsSchedule()

    let round1 = schedule.startRound(recordedSeconds: 100, textLength: 50)
    #expect(!round1)
    let round2 = schedule.startRound(recordedSeconds: 180, textLength: 50)
    #expect(round2)
    schedule.roundFinished()
    let round3 = schedule.startRound(recordedSeconds: 300, textLength: 80)
    #expect(!round3)
    let round4 = schedule.startRound(recordedSeconds: 360, textLength: 50)
    #expect(!round4)
    let round5 = schedule.startRound(recordedSeconds: 361, textLength: 90)
    #expect(round5)
}

@Test func keyPointsSkipARoundWhileThePreviousRuns() {
    var schedule = KeyPointsSchedule()

    let round6 = schedule.startRound(recordedSeconds: 180, textLength: 50)
    #expect(round6)
    let round7 = schedule.startRound(recordedSeconds: 400, textLength: 90)
    #expect(!round7)
    schedule.roundFinished()
    let round8 = schedule.startRound(recordedSeconds: 401, textLength: 90)
    #expect(round8)
}

@Test func growingFileReadsTheOpenRecordingAt16kMono() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("beseda-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("me.raw.wav")
    let recorder = try recordingInProgress(seconds: 3, at: url)
    let file = GrowingWAVFile(url: url)

    let recorded = file.recordedSeconds()
    let samples = try file.samples16k(from: 1, seconds: 1)

    #expect(recorded == 3)
    #expect(abs(samples.count - 16_000) < 100)
    #expect(abs(samples[8_000] - 0.3) < 0.001)
    _ = try recorder.finish()
}

@Test func liveLoopTranscribesChunksOfTheGrowingFilesUntilCancelled() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("beseda-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let me = try recordingInProgress(seconds: 21, at: directory.appendingPathComponent("me.raw.wav"))
    let them = try recordingInProgress(seconds: 21, at: directory.appendingPathComponent("them.raw.wav"))
    let updates = AsyncStream<[LiveLine]>.makeStream()
    let loop = LiveTranscriptionLoop(
        microphoneURL: directory.appendingPathComponent("me.raw.wav"),
        systemURL: directory.appendingPathComponent("them.raw.wav"),
        transcribe: { samples in [TranscriptWord(start: 1, end: Double(samples.count) / 16_000, text: "слово.")] },
        droppedBuffers: { 0 },
        isPaused: { false },
        log: { _ in },
        update: { lines, _ in updates.continuation.yield(lines) }
    )

    let running = Task { await loop.run() }
    var lines: [LiveLine] = []
    for await update in updates.stream where update.count == 2 {
        lines = update
        break
    }
    running.cancel()
    await running.value

    #expect(lines.map(\.channel) == [.microphone, .systemAudio])
    #expect(lines.allSatisfy { $0.start == 1 && $0.text == "слово." })
    _ = try me.finish()
    _ = try them.finish()
}

@Test func liveLoopLogsOnceAndStopsWhenTheSpeechModelIsMissing() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("beseda-live-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let me = try recordingInProgress(seconds: 60, at: directory.appendingPathComponent("me.raw.wav"))
    let them = try recordingInProgress(seconds: 60, at: directory.appendingPathComponent("them.raw.wav"))
    let logs = LockedLog()
    let loop = LiveTranscriptionLoop(
        microphoneURL: directory.appendingPathComponent("me.raw.wav"),
        systemURL: directory.appendingPathComponent("them.raw.wav"),
        transcribe: { _ in throw BesedaError.runtimeMissing },
        droppedBuffers: { 0 },
        isPaused: { false },
        log: { logs.append($0) },
        update: { _, _ in }
    )

    await loop.run()

    #expect(logs.messages.count == 1)
    _ = try me.finish()
    _ = try them.finish()
}

private final class LockedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String] = []

    var messages: [String] { lock.withLock { stored } }

    func append(_ message: String) {
        lock.withLock { stored.append(message) }
    }
}
