import Foundation
import SQLite3
import Testing

@testable import Beseda

/// a store with one old-diarizer call per id; `withAudio` ones get them.asr.wav and them.asr.json
private func makeStore(withAudio: [String], withoutAudio: [String] = []) throws -> (CallStore, URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-resplit-\(UUID().uuidString)", isDirectory: true)
    let store = CallStore(dbURL: root.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    for id in withAudio + withoutAudio {
        let folder = root.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try store.upsertCall(
            id: id, kind: "dual", startedAt: Date(), endedAt: nil, durationSec: 60, status: "ready",
            transcriptURL: nil, audioDirectoryURL: folder, error: nil, appName: nil
        )
        try store.replaceSegments(callID: id, segments: [
            StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 1, text: "Привет", orderIndex: 0),
            StoredTranscriptSegment(speaker: "them-1", startSec: 1, endSec: 2, text: "Здравствуйте", orderIndex: 1),
            StoredTranscriptSegment(speaker: "them-2", startSec: 3, endSec: 4, text: "Добрый день", orderIndex: 2)
        ])
        guard withAudio.contains(id) else {
            continue
        }
        try Data().write(to: folder.appendingPathComponent("them.asr.wav"))
        let words = ASRTranscription(
            id: id, text: "",
            segments: [
                TranscriptSegment(start: 1, end: 2, text: "Здравствуйте", confidence: nil, words: nil),
                TranscriptSegment(start: 3, end: 4, text: "Добрый день", confidence: nil, words: nil)
            ],
            audioDurationSec: nil, wallTimeSec: nil, realTimeFactor: nil
        )
        try JSONEncoder().encode(words).write(to: folder.appendingPathComponent("them.asr.json"))
    }
    return (store, root)
}

private final class Calls: @unchecked Sendable {
    var diarized: [URL] = []
    var paused = false
    var logs: [String] = []
}

private func makeResplitter(_ store: CallStore, _ calls: Calls, fails: Bool = false) -> SpeakerResplitter {
    SpeakerResplitter(
        store: store,
        timeline: { url in
            calls.diarized.append(url)
            if fails {
                throw BesedaError.processFailed("boom")
            }
            return [SpeakerInterval(speaker: "spk-0", start: 0, end: 10)]
        },
        isPaused: { calls.paused },
        log: { calls.logs.append($0) },
        progress: { _, _ in },
        pausePoll: .milliseconds(5)
    )
}

@Test func resplitRedoesOnlyOldCallsWithAudioAndWithoutMerges() async throws {
    let (store, root) = try makeStore(withAudio: ["with-audio", "merged", "current"], withoutAudio: ["no-audio"])
    defer { try? FileManager.default.removeItem(at: root) }
    try store.mergeSpeaker(callID: "merged", speakerKey: "them-2", into: "them-1")
    try store.replaceSegments(callID: "current", segments: try store.fetchSegments(callID: "current"), diarizer: Diarizer.id)
    let calls = Calls()

    await makeResplitter(store, calls).run()

    #expect(calls.diarized.map { $0.deletingLastPathComponent().lastPathComponent } == ["with-audio"])
    #expect(try store.fetchSegments(callID: "with-audio").map(\.speaker) == ["me", "them-1", "them-1"])
    #expect(try store.fetchSegments(callID: "no-audio").map(\.speaker) == ["me", "them-1", "them-2"])
    #expect(try store.fetchSegments(callID: "merged").map(\.speaker) == ["me", "them-1", "them-1"])
    #expect(try store.hasSpeakerMerges(callID: "merged"))
}

@Test func resplitSkipsRenamedSpeakers() async throws {
    let (store, root) = try makeStore(withAudio: ["renamed"])
    defer { try? FileManager.default.removeItem(at: root) }
    try store.setSpeakerName(callID: "renamed", speakerKey: "them-1", displayName: "Анна")
    let calls = Calls()

    await makeResplitter(store, calls).run()

    #expect(calls.diarized.isEmpty)
    #expect(calls.logs.contains { $0.contains("manual speaker edits") })
    #expect(try store.fetchSpeakerNames(callID: "renamed") == ["them-1": "Анна"])
}

@Test func resplitWithNoDiarizerSpeechIsNotRepeated() async throws {
    let (store, root) = try makeStore(withAudio: ["silent"])
    defer { try? FileManager.default.removeItem(at: root) }
    let before = try store.fetchSegments(callID: "silent")
    let calls = Calls()
    let resplitter = SpeakerResplitter(
        store: store, timeline: { _ in [] }, isPaused: { false }, log: { _ in }, progress: { _, _ in }
    )

    await resplitter.run()

    #expect(try store.fetchSegments(callID: "silent") == before)
    #expect(try resplitter.pendingCalls().isEmpty)
}

@Test func resplitIsNotRepeatedAfterARestart() async throws {
    let (store, root) = try makeStore(withAudio: ["call-1"], withoutAudio: ["no-audio"])
    defer { try? FileManager.default.removeItem(at: root) }
    let calls = Calls()
    await makeResplitter(store, calls).run()

    let reopened = CallStore(dbURL: root.appendingPathComponent("calls.sqlite"))
    try reopened.prepare()
    await makeResplitter(reopened, calls).run()

    #expect(calls.diarized.count == 1)
    #expect(try makeResplitter(reopened, calls).pendingCalls().isEmpty)
}

@Test func resplitWaitsWhileTheAppIsBusy() async throws {
    let (store, root) = try makeStore(withAudio: ["call-1"])
    defer { try? FileManager.default.removeItem(at: root) }
    let calls = Calls()
    calls.paused = true

    let job = Task { await makeResplitter(store, calls).run() }
    try await Task.sleep(for: .milliseconds(100))
    #expect(calls.diarized.isEmpty)
    calls.paused = false
    await job.value

    #expect(calls.diarized.count == 1)
}

private actor ReleaseGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
    }
}

@Test func aUserDiarizationJumpsAheadOfWaitingBackgroundWork() async throws {
    let queue = DiarizationQueue()
    let gate = ReleaseGate()
    let events = Calls()
    let first = Task {
        try await queue.perform(priority: .background) {
            events.logs.append("background-1-start")
            await gate.wait()
            events.logs.append("background-1-end")
        }
    }
    while !(await queue.state.running) {
        await Task.yield()
    }
    let second = Task { try await queue.perform(priority: .background) { events.logs.append("background-2") } }
    let user = Task { try await queue.perform(priority: .user) { events.logs.append("user") } }
    while true {
        let state = await queue.state
        if state.users == 1 && state.background == 1 { break }
        await Task.yield()
    }
    await gate.release()
    _ = try await (first.value, second.value, user.value)

    #expect(events.logs == ["background-1-start", "background-1-end", "user", "background-2"])
}

@Test func aLegacyDatabaseMissingSpeakerMergeTableIsRepairedWithoutLosingCalls() throws {
    let (_, root) = try makeStore(withAudio: ["legacy"])
    defer { try? FileManager.default.removeItem(at: root) }
    let dbURL = root.appendingPathComponent("calls.sqlite")
    var db: OpaquePointer?
    #expect(sqlite3_open(dbURL.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    #expect(sqlite3_exec(db, "DROP TABLE call_speaker_merges; PRAGMA user_version = 3", nil, nil, nil) == SQLITE_OK)

    let reopened = CallStore(dbURL: dbURL)
    try reopened.prepare()

    #expect(try reopened.fetchCall(id: "legacy") != nil)
    #expect(try !reopened.hasSpeakerEdits(callID: "legacy"))
}

@Test func failedResplitLeavesTheCallUntouched() async throws {
    let (store, root) = try makeStore(withAudio: ["call-1"])
    defer { try? FileManager.default.removeItem(at: root) }
    let before = try store.fetchSegments(callID: "call-1")
    let calls = Calls()

    await makeResplitter(store, calls, fails: true).run()

    #expect(try store.fetchSegments(callID: "call-1") == before)
    #expect(try makeResplitter(store, calls).pendingCalls().map(\.id) == ["call-1"])
}
