import Foundation
import Testing

@testable import Beseda

/// Answers every request with `answer` and remembers which system prompts were asked.
private final class StubModel: @unchecked Sendable {
    let answer: String
    private(set) var prompts: [String] = []

    init(answer: String) {
        self.answer = answer
    }

    func provider(_ prompt: String) -> SummarizationProvider {
        prompts.append(prompt)
        return Reply(text: answer)
    }

    private struct Reply: SummarizationProvider {
        let text: String
        func summarize(text _: String) async throws -> String { text }
    }
}

private let work = CallType(name: "Рабочая встреча", description: "дейли, планирование", prompt: "промпт работы")
private let personal = CallType(name: "Личный 1:1", description: "разговор с другом", prompt: "промпт личного")

private let call = StoredCallDetail(
    summary: StoredCallSummary(
        id: "20260926-101500", kind: "dual", startedAt: "2026-09-26T10:15:00.000Z", endedAt: nil,
        durationSec: 60, status: "ready", transcriptPath: nil, audioDirectoryPath: "/tmp/call", error: nil,
        appName: nil, previewText: nil, summaryText: nil, eventTitle: nil, eventID: nil, eventPinned: false
    ),
    segments: [StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 3, text: "Что сделали вчера?", orderIndex: 0)],
    speakerNames: [:],
    markdownText: nil,
    jobStats: nil
)

@Test func theClassifierPicksTheTypeTheModelNamesAndRunsItsPrompt() async throws {
    let model = StubModel(answer: "  «личный 1:1»\n")

    let (type, _) = try await SummarizationService.process(
        call, types: [work, personal], characterBudget: 1000, provider: model.provider
    )

    #expect(type == personal)
    #expect(model.prompts == [SummarizationService.classifierPrompt([work, personal]), "промпт личного"])
}

@Test func aGarbageAnswerFallsBackToTheFirstType() async throws {
    let model = StubModel(answer: "не знаю")

    let (type, _) = try await SummarizationService.process(
        call, types: [work, personal], characterBudget: 1000, provider: model.provider
    )

    #expect(type == work)
    #expect(model.prompts.last == "промпт работы")
}

@Test func oneTypeRunsItsPromptWithoutAskingTheClassifier() async throws {
    let model = StubModel(answer: "итоги")

    let (type, text) = try await SummarizationService.process(
        call, types: [work], characterBudget: 1000, provider: model.provider
    )

    #expect(type == work)
    #expect(text == "итоги")
    #expect(model.prompts == ["промпт работы"])
}

@Test func aGivenTypeSkipsTheClassifier() async throws {
    let model = StubModel(answer: "итоги")

    let (type, _) = try await SummarizationService.process(
        call, types: [work, personal], chosen: personal, characterBudget: 1000, provider: model.provider
    )

    #expect(type == personal)
    #expect(model.prompts == ["промпт личного"])
}

@Test func anOldDatabaseWithoutTheTypeColumnOpensAndTheTypeRoundTrips() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-type-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let dbURL = directory.appendingPathComponent("calls.sqlite")
    let old = Process()
    old.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
    old.arguments = [dbURL.path, """
        CREATE TABLE calls (id TEXT PRIMARY KEY, kind TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT,
          duration_sec REAL, status TEXT NOT NULL, transcript_path TEXT, audio_dir TEXT NOT NULL, error TEXT,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL);
        INSERT INTO calls VALUES ('old', 'dual', '2026-01-01T00:00:00Z', NULL, 60, 'ready', NULL, '/tmp', NULL, 'x', 'x');
        """]
    try old.run()
    old.waitUntilExit()

    let store = CallStore(dbURL: dbURL)
    try store.prepare()
    let before = try store.fetchCall(id: "old")
    try store.setCallType(callID: "old", name: "Личный 1:1")

    #expect(before?.callType == nil)
    #expect(try store.fetchCall(id: "old")?.callType == "Личный 1:1")
}
