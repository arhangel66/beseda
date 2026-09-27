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
    /// the classifier's «exactly one other person» answer the stub hands back
    var oneOtherPerson: Bool?
    var failure: Error?

    func summarize(_ detail: StoredCallDetail, _ type: CallType?) async throws -> (type: CallType, text: String, oneOtherPerson: Bool?) {
        calls.append(detail.id)
        while heldCallID == detail.id {
            try await Task.sleep(for: .milliseconds(10))
        }
        if let failure {
            throw failure
        }
        return (CallType(name: CallType.otherName, description: "", prompt: ""), "summary of \(detail.id)", oneOtherPerson)
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

@MainActor
@Test func aFailedResumeAtLaunchIsNotReportedAsAnUnavailableIndex() throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    try harness.store.prepare()
    try harness.addCall("call", status: "ready")
    let transcript = try harness.folder("call").appendingPathComponent("transcript.md")
    // not UTF-8: reading the transcript to resume the call throws
    try Data([0xFF, 0xFE, 0xFD]).write(to: transcript)
    try harness.store.markReady(callID: "call", transcriptURL: transcript, segments: [])
    try harness.store.setProcessingPending(callID: "call", true)

    let controller = harness.controller()

    guard case .failed(let message) = controller.status else {
        Issue.record("status is \(controller.status)")
        return
    }
    #expect(message.contains("возобновить обработку"))
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

// MARK: - BESEDA-107: the classifier's «one other person» is stored, never relabels

/// a finished call with three remote speakers auto-processed through a stub answering `oneOtherPerson`;
/// returns the speakers in the index, the transcript file and the stored answer afterwards
@MainActor
private func remoteSpeakersAfterProcessing(
    oneOtherPerson: Bool?, failure: Error? = nil
) async throws -> (indexed: [String], transcript: String, stored: Bool?) {
    let harness = try Harness()
    defer { harness.cleanUp() }
    harness.settings.autoProcessCalls = true
    let stub = StubSummarizer()
    stub.oneOtherPerson = oneOtherPerson
    stub.failure = failure
    let controller = harness.controller(summarize: stub.summarize)
    try harness.addCall("call", status: "transcribing")
    let folder = try harness.folder("call")
    let speakers = ["me", "them-1", "them-2", "them-3"]
    let lines = speakers.map(line)
    let dialogue = speakers.map { "**\(SpeakerNaming.defaultName(for: $0))** [00:00] Долгий разговор\n\n" }.joined()
    try "# Beseda Dual Transcript\n\n## Dialogue\n\n\(dialogue)## Channels\n"
        .write(to: folder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)

    try controller.finishCall("call", in: folder, segments: lines, audio: [])
    try await waitUntil { try harness.store.fetchProcessingPendingCallIDs().isEmpty && controller.summarizingCallID == nil }

    return (
        try harness.store.fetchSegments(callID: "call").map(\.speaker),
        try String(contentsOf: folder.appendingPathComponent("transcript.md"), encoding: .utf8),
        storedOneOtherPerson(harness.paths.callIndexURL, callID: "call")
    )
}

/// `calls.one_other_person` read straight from the index; nil when the column is NULL
private func storedOneOtherPerson(_ dbURL: URL, callID: String) -> Bool? {
    var db: OpaquePointer?
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement); sqlite3_close(db) }
    sqlite3_open(dbURL.path, &db)
    sqlite3_prepare_v2(db, "SELECT one_other_person FROM calls WHERE id = '\(callID)'", -1, &statement, nil)
    guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
    return sqlite3_column_int(statement, 0) == 1
}

@MainActor
@Test func theClassifierSayingOneOtherPersonIsStoredAndKeepsTheDiarizerSpeakers() async throws {
    let (indexed, transcript, stored) = try await remoteSpeakersAfterProcessing(oneOtherPerson: true)

    #expect(indexed == ["me", "them-1", "them-2", "them-3"])
    #expect(transcript.contains("Собеседник 3"))
    #expect(stored == true)
}

@MainActor
@Test func theClassifierSayingSeveralPeopleKeepsTheDiarizerSpeakers() async throws {
    let (indexed, transcript, _) = try await remoteSpeakersAfterProcessing(oneOtherPerson: false)

    #expect(indexed == ["me", "them-1", "them-2", "them-3"])
    #expect(transcript.contains("Собеседник 3"))
}

@MainActor
@Test func noClassifierAnswerKeepsTheDiarizerSpeakers() async throws {
    let (indexed, transcript, _) = try await remoteSpeakersAfterProcessing(oneOtherPerson: nil)

    #expect(indexed == ["me", "them-1", "them-2", "them-3"])
    #expect(transcript.contains("Собеседник 3"))
}

@MainActor
@Test func aFailedClassificationKeepsTheDiarizerSpeakers() async throws {
    let (indexed, transcript, _) = try await remoteSpeakersAfterProcessing(
        oneOtherPerson: true, failure: SummarizationError.unavailable("down")
    )

    #expect(indexed == ["me", "them-1", "them-2", "them-3"])
    #expect(transcript.contains("Собеседник 3"))
}


// Critic item 22: a recording killed mid-call and a disk that refuses writes, each played in a child
// process — the same test binary re-run on one test — so a SIGKILL or a file size limit hits only the child.

private let childDirectoryKey = "BESEDA_CHILD_DIRECTORY"
private let childDirectory = ProcessInfo.processInfo.environment[childDirectoryKey].map { URL(fileURLWithPath: $0) }

/// runs one test of this binary in a child process with `childDirectoryKey` pointing at `directory`
private func startChildTest(named name: String, directory: URL) throws -> Process {
    // swift test runs `swiftpm-testing-helper --test-bundle-path <binary> … <binary> --testing-library swift-testing`
    let arguments = CommandLine.arguments
    let bundleIndex = try #require(arguments.firstIndex(of: "--test-bundle-path"), "run through swift test")
    let binary = arguments[bundleIndex + 1]
    let child = Process()
    child.executableURL = URL(fileURLWithPath: arguments[0])
    child.arguments = ["--test-bundle-path", binary, "--filter", name, binary, "--testing-library", "swift-testing"]
    child.environment = ProcessInfo.processInfo.environment.merging([childDirectoryKey: directory.path]) { $1 }
    child.standardOutput = FileHandle(forWritingAtPath: "/dev/null")
    try child.run()
    return child
}

private func stereoBuffer(frames: Int, value: Float) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    for frame in 0..<frames {
        buffer.floatChannelData![0][frame] = value
        buffer.floatChannelData![1][frame] = -value
    }
    return buffer
}

// MARK: - kill mid-recording

private let killedCallID = "20260105-100000"

/// the child: indexes a call as recording, as `runDualRecording` does, and streams both channels until killed
@Test(.enabled(if: childDirectory != nil))
func childRecordsUntilKilled() throws {
    let paths = AppPaths(dataDirectory: try #require(childDirectory))
    let folder = paths.callsDirectory.appendingPathComponent(killedCallID, isDirectory: true)
    let store = CallStore(dbURL: paths.callIndexURL)
    try store.prepare()
    try store.upsertCall(
        id: killedCallID, kind: "dual", startedAt: Date(), endedAt: nil, durationSec: nil, status: "recording",
        transcriptURL: nil, audioDirectoryURL: folder, error: nil, appName: "Zoom"
    )
    let recorders = try ["me.raw.wav", "them.raw.wav"].map {
        try PCMFloatRecorder(url: folder.appendingPathComponent($0), sampleRate: 48_000, channelCount: 2, activityTracker: nil)
    }
    var frames = 0
    while true {
        for recorder in recorders {
            try recorder.append(pcmBuffer: stereoBuffer(frames: 4_800, value: 0.25))
            recorder.waitUntilWritten()
        }
        frames += 4_800
        if frames == 48_000 {
            try Data("\(frames)".utf8).write(to: paths.dataDirectory.appendingPathComponent("written"))
        }
        Thread.sleep(forTimeInterval: 0.01)
    }
}

@MainActor
@Test(.enabled(if: childDirectory == nil))
func aRecordingKilledMidCallIsReadableAndFailedAfterRelaunch() async throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let marker = harness.root.appendingPathComponent("written")
    let child = try startChildTest(named: "childRecordsUntilKilled", directory: harness.root)
    defer { if child.isRunning { kill(child.processIdentifier, SIGKILL) } }
    for _ in 0..<1_200 where !FileManager.default.fileExists(atPath: marker.path) && child.isRunning {
        try await Task.sleep(for: .milliseconds(50))
    }
    let writtenFrames = try #require(Int(String(decoding: try Data(contentsOf: marker), as: UTF8.self)))

    kill(child.processIdentifier, SIGKILL)
    child.waitUntilExit()
    #expect(child.terminationReason == .uncaughtSignal)

    let controller = harness.controller()

    let call = try #require(try harness.store.fetchCall(id: killedCallID))
    #expect(call.status == "failed")
    #expect(call.error?.contains("Interrupted") == true)
    #expect(call.error?.contains(".raw.wav") == false)
    #expect(controller.recentCalls.map(\.id) == [killedCallID])
    for name in ["me.raw.wav", "them.raw.wav"] {
        let file = try AVAudioFile(forReading: harness.paths.callsDirectory
            .appendingPathComponent(killedCallID).appendingPathComponent(name))
        #expect(file.length >= Int64(writtenFrames))
        let readBack = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_800)!
        try file.read(into: readBack)
        #expect(readBack.floatChannelData![1][4_799] == -0.25)
    }
}

// MARK: - disk full

/// the child: a file size limit makes the OS refuse the WAV's growth, as a full disk does
@MainActor
@Test(.enabled(if: childDirectory != nil))
func childHitsAFileSizeLimitWhileRecording() throws {
    let harness = try Harness()
    defer { harness.cleanUp() }
    let controller = harness.controller()
    let url = try #require(childDirectory).appendingPathComponent("me.raw.wav")
    let recorder = try PCMFloatRecorder(url: url, sampleRate: 48_000, channelCount: 2, activityTracker: nil)
    signal(SIGXFSZ, SIG_IGN)
    var limit = rlimit()
    getrlimit(RLIMIT_FSIZE, &limit)
    limit.rlim_cur = 256 * 1024
    #expect(setrlimit(RLIMIT_FSIZE, &limit) == 0)

    for _ in 0..<100 where recorder.writeError == nil {
        try recorder.append(pcmBuffer: stereoBuffer(frames: 4_800, value: 0.5))
        recorder.waitUntilWritten()
    }
    // what the live ticker does with a capture whose recorder failed
    let writeError = try #require(recorder.writeError)
    controller.stopRecording(after: writeError, capture: DualCapture())
    let metadata = try recorder.finish()

    #expect(controller.recordingWarning?.hasPrefix("Запись остановлена: не удалось записать звук на диск") == true)
    #expect(controller.recordingWarning?.contains("Всё записанное до этого будет расшифровано") == true)
    #expect(metadata.frameCount > 0)
    let file = try AVAudioFile(forReading: url)
    #expect(file.length > 0 && file.length == Int64(metadata.frameCount))
    let readBack = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: readBack)
    #expect(readBack.floatChannelData![0][Int(file.length) - 1] == 0.5)
}

@Test(.enabled(if: childDirectory == nil))
func aDiskThatRefusesWritesStopsTheRecordingVisiblyAndKeepsWhatWasWritten() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("beseda-full-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let child = try startChildTest(named: "childHitsAFileSizeLimitWhileRecording", directory: directory)
    child.waitUntilExit()

    // the child's own expectations decide its exit status
    #expect(child.terminationReason == .exit)
    #expect(child.terminationStatus == 0)
}
