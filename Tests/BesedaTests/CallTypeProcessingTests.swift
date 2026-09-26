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

    let (type, _, _) = try await SummarizationService.process(
        call, types: [work, personal], characterBudget: 1000, provider: model.provider
    )

    #expect(type == personal)
    #expect(model.prompts == [SummarizationService.classifierPrompt([work, personal]), "промпт личного"])
}

@Test func aGarbageAnswerFallsBackToTheFirstTypeWhateverItIsNamed() async throws {
    let model = StubModel(answer: "не знаю")

    let (type, _, _) = try await SummarizationService.process(
        call, types: [work, personal], characterBudget: 1000, provider: model.provider
    )

    #expect(type == work)
    #expect(model.prompts.last == "промпт работы")
}

@Test func oneTypeRunsItsPromptWithoutAskingTheClassifier() async throws {
    let model = StubModel(answer: "итоги")

    let (type, text, _) = try await SummarizationService.process(
        call, types: [work], characterBudget: 1000, provider: model.provider
    )

    #expect(type == work)
    #expect(text == "итоги")
    #expect(model.prompts == ["промпт работы"])
}

@Test func aGivenTypeSkipsTheClassifier() async throws {
    let model = StubModel(answer: "итоги")

    let (type, _, _) = try await SummarizationService.process(
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

private let other = CallType(name: "Другое", description: "ни один другой тип не подходит", prompt: "промпт другого", isOther: true)

/// the recorded response from OpenRouter's Jev tutorial, with its `team` question renamed to ours
private let recordedJevResponse = """
    {
      "id": "gen-dec-1790015143-AIaTutprXsJ5EwohRSjb",
      "model": "typesafe/jev-1.13-20260917",
      "provider": "TypeSafe",
      "answers": {
        "is_bug": { "type": "noul", "noul": 0.96 },
        "call_type": {
          "type": "choice",
          "choice": "payments",
          "confidence": 0.67,
          "probabilities": { "payments": 0.78, "frontend": 0.22, "account": 0 }
        }
      },
      "usage": { "input_tokens": 476, "output_tokens": 70, "cost": 0.000019992 }
    }
    """

private func jev(answering choice: String, probability: Double) -> JevClassifier {
    let body = #"{"answers":{"call_type":{"type":"choice","choice":"\#(choice)","probabilities":{"\#(choice)":\#(probability)}}}}"#
    return JevClassifier(apiKey: "k", transport: { request in
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    })
}

@Test func aGarbageAnswerFromTheLocalModelFallsBackToOtherWhereverItIsListed() async throws {
    let model = StubModel(answer: "не знаю")

    let (type, _, _) = try await SummarizationService.process(
        call, types: [work, other], characterBudget: 1000, provider: model.provider
    )

    #expect(type == other)
}

@Test func jevsConfidentPickIsUsedWithoutAskingTheSummaryModel() async throws {
    let model = StubModel(answer: "итоги")

    let (type, _, _) = try await SummarizationService.process(
        call, types: [other, work], characterBudget: 1000, provider: model.provider,
        jev: jev(answering: "Рабочая встреча", probability: 0.9)
    )

    #expect(type == work)
    #expect(model.prompts == ["промпт работы"])
}

@Test func aLowConfidenceJevPickFallsBackToOther() async throws {
    let model = StubModel(answer: "итоги")

    let (type, _, _) = try await SummarizationService.process(
        call, types: [other, work], characterBudget: 1000, provider: model.provider,
        jev: jev(answering: "Рабочая встреча", probability: 0.3)
    )

    #expect(type == other)
}

@Test func anUnknownJevChoiceFallsBackToOther() async throws {
    let model = StubModel(answer: "итоги")

    let (type, _, _) = try await SummarizationService.process(
        call, types: [other, work], characterBudget: 1000, provider: model.provider,
        jev: jev(answering: "payments", probability: 0.99)
    )

    #expect(type == other)
}

@Test func aFailingJevFallsBackToTheLocalModelAndIsLogged() async throws {
    let model = StubModel(answer: "Рабочая встреча")
    let failing = JevClassifier(apiKey: "k", transport: { _ in throw URLError(.notConnectedToInternet) })
    var logs: [String] = []

    let (type, _, _) = try await SummarizationService.process(
        call, types: [other, work], characterBudget: 1000, provider: model.provider, jev: failing,
        log: { logs.append($0) }
    )

    #expect(type == work)
    #expect(model.prompts.first == SummarizationService.classifierPrompt([other, work]))
    #expect(logs.contains { $0.hasPrefix("Jev failed") })
}

@Test func theClassifierContextHasTheWeekdayLocalTimeAndDuration() {
    let context = ClassifierContext(call, timeZone: TimeZone(identifier: "Europe/Moscow")!)

    #expect(context.started == "суббота, 13:15")
    #expect(context.duration == "1 мин")
    #expect(context.opening.contains("Что сделали вчера?"))
    #expect(context.asText.hasPrefix("Начало: суббота, 13:15. Длительность: 1 мин."))
}

@Test func theJevRequestIsOneChoiceOverTheTypesWithTheCallInState() throws {
    let context = ClassifierContext(call, timeZone: TimeZone(identifier: "Europe/Moscow")!)

    let request = try JevClassifier.request(context, types: [other, work], apiKey: "sk-or-v1-secret")

    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let state = body["state"] as! [String: String]
    let question = (body["questions"] as! [String: Any])["call_type"] as! [String: Any]
    #expect(request.url == URL(string: "https://openrouter.ai/api/alpha/decisions"))
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-v1-secret")
    #expect(body["model"] as? String == "typesafe/jev-1.13")
    #expect(state["started"] == "суббота, 13:15")
    #expect(state["duration"] == "1 мин")
    #expect(state["transcript_opening"] == context.opening)
    #expect(question["type"] as? String == "choice")
    #expect(question["criteria"] as? [String: String] == ["Другое": other.description, "Рабочая встреча": work.description])
}

@Test func theRecordedJevResponseParsesToTheChoiceItsProbabilityAndCost() throws {
    let answer = try JevClassifier.parse(Data(recordedJevResponse.utf8))

    #expect(answer == JevClassifier.Answer(choice: "payments", probability: 0.78, cost: 0.000019992))
}

/// Live, once: classifies a tiny synthetic excerpt when OPENROUTER_API_KEY is set, else skipped.
@Test(.enabled(if: ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] != nil))
func jevClassifiesATinySyntheticExcerptLive() async throws {
    let key = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]!
    let context = ClassifierContext(call)

    let answer = try await JevClassifier(apiKey: key).classify(context, types: [other, work, personal])

    print("Jev live: «\(answer.choice)» p=\(answer.probability) cost=$\(answer.cost ?? 0)")
    #expect([other, work, personal].map(\.name).contains(answer.choice))
}

// MARK: - BESEDA-104: the same classification also says whether one other person spoke

@Test func theLocalClassifiersSecondLineSaysWhetherOneOtherPersonSpoke() async throws {
    let one = StubModel(answer: "Рабочая встреча\nодин")
    let several = StubModel(answer: "Рабочая встреча\n\nнесколько")
    let silent = StubModel(answer: "Рабочая встреча")

    let (typeOfOne, _, oneOtherPerson) = try await SummarizationService.process(
        call, types: [other, work], characterBudget: 1000, provider: one.provider
    )
    let (_, _, severalPeople) = try await SummarizationService.process(
        call, types: [other, work], characterBudget: 1000, provider: several.provider
    )
    let (_, _, noAnswer) = try await SummarizationService.process(
        call, types: [other, work], characterBudget: 1000, provider: silent.provider
    )

    #expect(typeOfOne == work)
    #expect(oneOtherPerson == true)
    #expect(severalPeople == false)
    #expect(noAnswer == nil)
}

@Test func jevsOtherPeopleAnswerCountsAsOneOnlyAtTheProbabilityBar() throws {
    func answer(one: Double) throws -> Bool? {
        let body = #"{"answers":{"call_type":{"choice":"Другое","probabilities":{"Другое":0.9}},"other_people":{"choice":"one","probabilities":{"one":\#(one),"several":\#(1 - one)}}}}"#
        return try JevClassifier.parse(Data(body.utf8)).oneOtherPerson
    }

    #expect(try answer(one: 0.8) == true)
    #expect(try answer(one: 0.3) == false)
    #expect(try JevClassifier.parse(Data(recordedJevResponse.utf8)).oneOtherPerson == nil)
}

@Test func theClassifierSeesEveryRemoteSpeakerUnderOneLabel() {
    let detail = StoredCallDetail(
        summary: call.summary,
        segments: [
            StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 1, text: "Привет", orderIndex: 0),
            StoredTranscriptSegment(speaker: "them-1", startSec: 1, endSec: 2, text: "Привет", orderIndex: 1),
            StoredTranscriptSegment(speaker: "them-2", startSec: 2, endSec: 3, text: "Да", orderIndex: 2)
        ],
        speakerNames: ["them-2": "Анна"],
        markdownText: nil,
        jobStats: nil
    )

    let context = ClassifierContext(detail)

    #expect(context.opening == "Вы: Привет\nУдалённо: Привет\nУдалённо: Да")
}

/// BESEDA-104 measurement, never in the check: the app's classification of each call in a read-only copy of
/// `calls.sqlite` against llama-server serving the bundled model. Driven by
/// untracked/epics/speaker-accuracy/one_other_person.sh, which sets BESEDA_ONE_OTHER_PERSON_DB.
@Test(.enabled(if: ProcessInfo.processInfo.environment["BESEDA_ONE_OTHER_PERSON_DB"] != nil))
func oneOtherPersonOnRealCallsWithTheBundledModel() async throws {
    let environment = ProcessInfo.processInfo.environment
    let store = CallStore(dbURL: URL(fileURLWithPath: environment["BESEDA_ONE_OTHER_PERSON_DB"]!))
    // Mikhail's call types as the settings hold them on 2026-09-26
    let types = [
        CallType(name: "Другое", description: "ни один другой тип не подходит", prompt: "", isOther: true),
        CallType(name: "Дейли", description: "ежедневный отчет с командой о сделанном за день", prompt: "")
    ]
    for callID in environment["BESEDA_ONE_OTHER_PERSON_CALLS"]!.split(separator: " ").map(String.init) {
        let detail = StoredCallDetail(
            summary: try #require(try store.fetchCall(id: callID)),
            segments: try store.fetchSegments(callID: callID),
            speakerNames: try store.fetchSpeakerNames(callID: callID),
            markdownText: nil,
            jobStats: nil
        )
        let provider = { (prompt: String) -> SummarizationProvider in
            ChatCompletionsProvider(
                baseURL: URL(string: environment["BESEDA_ONE_OTHER_PERSON_SERVER"]!)!, model: BundledSummary.current.modelID,
                prompt: prompt, serviceName: "llama-server", timeout: 900
            )
        }
        var answers: [String] = []
        let (type, oneOtherPerson) = try await SummarizationService.classify(
            detail, types: types, provider: provider, jev: nil, log: { answers.append($0) }
        )
        let remoteSpeakers = Set(detail.segments.map(\.speaker).filter { SpeakerNaming.remoteIndex(of: $0) != nil }).count
        print("ONE_OTHER_PERSON \(callID) type=\(type.name) answer=\(oneOtherPerson.map(String.init) ?? "nil") remote=\(remoteSpeakers) \(answers)")
    }
}
