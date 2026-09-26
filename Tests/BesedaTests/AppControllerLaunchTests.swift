import AVFAudio
import Foundation
import SQLite3
import Testing

@testable import Beseda

/// a controller over a temp data folder and its own defaults suite and Keychain service
@MainActor
private final class Harness {
    let root: URL
    let paths: AppPaths
    let store: CallStore
    let suiteName = "beseda-test-\(UUID().uuidString)"
    let settings: AppSettings

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("beseda-launch-\(UUID().uuidString)", isDirectory: true)
        paths = AppPaths(dataDirectory: root)
        try FileManager.default.createDirectory(at: paths.callsDirectory, withIntermediateDirectories: true)
        store = CallStore(dbURL: paths.callIndexURL)
        settings = AppSettings(defaults: UserDefaults(suiteName: suiteName)!, keychain: Keychain(service: suiteName))
    }

    func controller(summarize: AppController.Summarize? = nil) -> AppController {
        AppController(paths: paths, settings: settings, summarize: summarize)
    }

    func folder(_ id: String) throws -> URL {
        let folder = paths.callsDirectory.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func addCall(_ id: String, status: String) throws {
        try store.upsertCall(
            id: id, kind: "dual", startedAt: Date(), endedAt: Date(), durationSec: 3000, status: status,
            transcriptURL: nil, audioDirectoryURL: try folder(id), error: nil, appName: "Zoom"
        )
    }

    func execute(_ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open(paths.callIndexURL.path, &db) == SQLITE_OK else {
            throw CallStoreError.sqlite("open failed")
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    func cleanUp() {
        UserDefaults().removePersistentDomain(forName: suiteName)
        Keychain(service: suiteName).deleteAll()
        try? FileManager.default.removeItem(at: root)
    }
}

/// summaries in the order they were asked for; a call named in `heldCallID` waits until released
@MainActor
private final class StubSummarizer {
    var calls: [String] = []
    var heldCallID: String?

    func summarize(_ detail: StoredCallDetail, _ type: CallType?) async throws -> (type: CallType, text: String) {
        calls.append(detail.id)
        while heldCallID == detail.id {
            try await Task.sleep(for: .milliseconds(10))
        }
        return (CallType(name: CallType.otherName, description: "", prompt: ""), "summary of \(detail.id)")
    }
}

@MainActor
private func waitUntil(_ condition: () throws -> Bool) async throws {
    for _ in 0..<500 where try !condition() {
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(try condition())
}

private func writeWAV(_ url: URL, frames: Int = 4_800) throws {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}

private func line(_ speaker: String) -> SpeakerTranscriptSegment {
    SpeakerTranscriptSegment(
        speaker: speaker,
        segment: TranscriptSegment(start: 0, end: 60, text: "Долгий разговор", confidence: nil, words: nil)
    )
}

// MARK: - 7: a failed write keeps the call, its audio, and no webhook

@MainActor
@Test func aFailedSegmentWriteInFinishCallKeepsTheAudioAndSendsNoWebhook() throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    harness.settings.webhookEnabled = true
    harness.settings.webhookURL = "https://example.com/hook"
    harness.settings.rawAudioRetention = .immediately
    harness.settings.normalizedAudioRetention = .immediately
    let controller = harness.controller()
    try harness.addCall("call", status: "transcribing")
    let folder = try harness.folder("call")
    let audio = try ["me.raw.wav", "them.raw.wav", "me.asr.wav", "them.asr.wav"].map { name in
        let url = folder.appendingPathComponent(name)
        try writeWAV(url)
        return url
    }
    try harness.execute("""
        CREATE TRIGGER fail_segments BEFORE INSERT ON transcript_segments
        BEGIN SELECT RAISE(ABORT, 'disk full'); END
        """)

    #expect(throws: CallStoreError.self) {
        try controller.finishCall("call", in: folder, segments: [line("me"), line("them-1")], audio: audio)
    }

    #expect(try harness.store.fetchCall(id: "call")?.status == "transcribing")
    #expect(audio.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    #expect(try harness.store.fetchWebhookDeliveries(callID: "call").isEmpty)
}

// MARK: - 8: launch finds call folders the index lost

@MainActor
@Test func aCallFolderMissingFromTheIndexAppearsAsFailedAndRetryable() throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.folder("20260101-120000")
    try writeWAV(folder.appendingPathComponent("me.raw.wav"))
    try writeWAV(folder.appendingPathComponent("them.raw.wav"))
    try Data(#"{"startedAt": "2026-01-01T09:00:00.000Z", "endedAt": "2026-01-01T09:30:00.000Z", "durationSec": 1800}"#.utf8)
        .write(to: folder.appendingPathComponent("session.json"))

    let controller = harness.controller()

    let call = try #require(try harness.store.fetchCall(id: "20260101-120000"))
    #expect(call.status == "failed")
    #expect(call.kind == "dual")
    #expect(call.durationSec == 1800)
    #expect(call.error?.contains("без записи в индексе") == true)
    // the janitor compares standardized paths, so a failed call's audio survives the sweep
    #expect(try harness.store.protectedAudioDirectories().map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        .contains(folder.standardizedFileURL.path))
    #expect(controller.recentCalls.map(\.id) == ["20260101-120000"])
}

@MainActor
@Test func aCorruptWAVThatCannotBeRepairedIsRecordedOnTheCall() throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let folder = try harness.folder("20260101-130000")
    try Data("not a wav at all".utf8).write(to: folder.appendingPathComponent("me.raw.wav"))
    try writeWAV(folder.appendingPathComponent("them.raw.wav"))

    _ = harness.controller()

    let call = try #require(try harness.store.fetchCall(id: "20260101-130000"))
    #expect(call.status == "failed")
    #expect(call.error?.contains("me.raw.wav") == true)
    #expect(call.error?.contains("them.raw.wav") == false)
}

@MainActor
@Test func anInterruptedCallWithABrokenChannelSaysSo() throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.store.prepare()
    try harness.addCall("call", status: "recording")
    try writeWAV(try harness.folder("call").appendingPathComponent("me.raw.wav"))

    _ = harness.controller()

    let call = try #require(try harness.store.fetchCall(id: "call"))
    #expect(call.status == "failed")
    #expect(call.error?.contains("Interrupted") == true)
    #expect(call.error?.contains("them.raw.wav") == true)
}

@MainActor
@Test func anUnavailableCallIndexIsShownToTheUser() throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    // a folder where the database file should be: SQLite cannot open it
    try FileManager.default.createDirectory(at: harness.paths.callIndexURL, withIntermediateDirectories: true)

    let controller = harness.controller()

    guard case .failed(let message) = controller.status else {
        Issue.record("status is \(controller.status)")
        return
    }
    #expect(message.contains("Индекс звонков недоступен"))
}

// MARK: - 13: the auto-processing queue survives quit

@MainActor
@Test func aPendingProcessingJobResumesOnceAfterRelaunch() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.store.prepare()
    try harness.addCall("call", status: "ready")
    try harness.store.setProcessingPending(callID: "call", true)
    let stub = StubSummarizer()

    let controller = harness.controller(summarize: stub.summarize)
    try await waitUntil { try harness.store.fetchProcessingPendingCallIDs().isEmpty && controller.summarizingCallID == nil }
    _ = harness.controller(summarize: stub.summarize)
    try await Task.sleep(for: .milliseconds(100))

    #expect(stub.calls == ["call"])
    #expect(try harness.store.fetchCall(id: "call")?.summaryText == "summary of call")
}

@MainActor
@Test func twoCallsFinishingBackToBackAreBothProcessed() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    harness.settings.autoProcessCalls = true
    let stub = StubSummarizer()
    stub.heldCallID = "first"
    let controller = harness.controller(summarize: stub.summarize)
    try harness.addCall("first", status: "transcribing")
    try harness.addCall("second", status: "transcribing")

    try controller.finishCall("first", in: try harness.folder("first"), segments: [line("me")], audio: [])
    try await waitUntil { controller.summarizingCallID == "first" }
    try controller.finishCall("second", in: try harness.folder("second"), segments: [line("me")], audio: [])
    #expect(try harness.store.fetchProcessingPendingCallIDs().sorted() == ["first", "second"])
    stub.heldCallID = nil
    try await waitUntil { try harness.store.fetchProcessingPendingCallIDs().isEmpty }

    #expect(stub.calls == ["first", "second"])
    #expect(try harness.store.fetchCall(id: "second")?.summaryText == "summary of second")
}
