import Foundation
import Testing

@testable import Beseda

private let now = Date(timeIntervalSince1970: 1_790_000_000)

private func makeCall(
    id: String,
    daysAgo: Double,
    status: String = "ready",
    title: String? = nil,
    seriesID: String? = nil,
    callType: String? = nil,
    participants: [String] = [],
    summary: String? = "**Главное**\n— договорились"
) -> StoredCallSummary {
    StoredCallSummary(
        id: id,
        kind: "dual",
        startedAt: now.addingTimeInterval(-daysAgo * 86_400).iso8601WithFractions,
        endedAt: nil,
        durationSec: 600,
        status: status,
        transcriptPath: nil,
        audioDirectoryPath: "/tmp",
        error: nil,
        appName: nil,
        previewText: nil,
        summaryText: summary,
        eventTitle: title,
        eventID: nil,
        eventPinned: false,
        callType: callType,
        eventSeriesID: seriesID,
        participants: participants
    )
}

private func makeTarget(
    title: String? = nil,
    seriesID: String? = nil,
    callType: String? = nil,
    participants: [String] = []
) -> RelatedCallTarget {
    RelatedCallTarget(
        callID: "target", startsAt: now, title: title, seriesID: seriesID,
        callType: callType, participants: participants
    )
}

@Test func theSameCalendarSeriesIsRelated() {
    let calls = [makeCall(id: "other", daysAgo: 1), makeCall(id: "weekly", daysAgo: 7, title: "Renamed", seriesID: "S1")]

    let previous = RelatedCalls.previousCall(to: makeTarget(title: "Sync", seriesID: "S1"), among: calls)

    #expect(previous?.id == "weekly")
}

@Test func theSameTitleIgnoringCaseAndSpacesIsRelated() {
    let calls = [makeCall(id: "old", daysAgo: 14, title: "Sync"), makeCall(id: "recent", daysAgo: 7, title: "  sync ")]

    let previous = RelatedCalls.previousCall(to: makeTarget(title: "SYNC"), among: calls)

    #expect(previous?.id == "recent")
}

@Test func theSameTypeWithASharedParticipantIsRelated() {
    let calls = [
        makeCall(id: "stranger", daysAgo: 1, callType: "Интервью", participants: ["x@a.com"]),
        makeCall(id: "otherType", daysAgo: 2, callType: "Планёрка", participants: ["anna@a.com"]),
        makeCall(id: "match", daysAgo: 3, callType: "Интервью", participants: ["anna@a.com", "bob@a.com"]),
    ]

    let previous = RelatedCalls.previousCall(
        to: makeTarget(title: "Something else", callType: "Интервью", participants: ["anna@a.com"]),
        among: calls
    )

    #expect(previous?.id == "match")
}

@Test func nothingRelatedGivesNil() {
    let calls = [makeCall(id: "a", daysAgo: 1, title: "Other", callType: "Интервью", participants: ["x@a.com"])]

    let previous = RelatedCalls.previousRelatedCall(
        to: makeTarget(title: "Sync", callType: "Интервью", participants: ["anna@a.com"]), among: calls
    )

    #expect(previous == nil)
}

@Test func laterAndUnreadyCallsAreIgnored() {
    let calls = [
        makeCall(id: "later", daysAgo: -1, title: "Sync"),
        makeCall(id: "failed", daysAgo: 1, status: "failed", title: "Sync"),
        makeCall(id: "target", daysAgo: 0.5, title: "Sync"),
        makeCall(id: "ready", daysAgo: 7, title: "Sync"),
    ]

    let previous = RelatedCalls.previousRelatedCall(to: makeTarget(title: "Sync"), among: calls)

    #expect(previous?.callID == "ready")
    #expect(previous?.startedAt.timeIntervalSince1970 == now.addingTimeInterval(-7 * 86_400).timeIntervalSince1970)
}

@Test func theDigestKeepsAgreementsNextStepsAndOpenQuestions() {
    let summary = """
        **О чём говорили**
        Обсудили релиз.

        **Главное**
        — релиз в пятницу

        **Что делать**
        — Анна пишет заметки

        **Открытые вопросы**
        — кто дежурит
        """

    let digest = RelatedCalls.digest(ofSummary: summary)

    #expect(digest == "**Главное**\n— релиз в пятницу\n\n**Что делать**\n— Анна пишет заметки\n\n**Открытые вопросы**\n— кто дежурит")
}

@Test func theDigestKeepsTheCurrentDefaultSections() {
    let summary = """
        **О чём говорили**
        Обсудили релиз.

        **Договорились**
        — релиз 17 октября

        **Кто что делает**
        — Ольга — макеты — к среде

        **Открытые вопросы**
        — что с данными
        """
    let calls = [makeCall(id: "default", daysAgo: 7, title: "Sync", summary: summary)]

    let previous = RelatedCalls.previousRelatedCall(to: makeTarget(title: "Sync"), among: calls)

    #expect(previous?.digest == "**Договорились**\n— релиз 17 октября\n\n**Кто что делает**\n— Ольга — макеты — к среде\n\n**Открытые вопросы**\n— что с данными")
    #expect(previous?.isWholeSummary == false)
}

@Test func aCustomPromptResultIsShownWhole() {
    let summary = "**Настроение**\nСпокойное.\n\n**Темы**\n— отпуск\n— нагрузка\n— обучение\n— ревью\n\n**Решили**\n— меньше встреч"
    let calls = [makeCall(id: "custom", daysAgo: 7, title: "1:1", summary: summary)]

    let previous = RelatedCalls.previousRelatedCall(to: makeTarget(title: "1:1"), among: calls)

    #expect(previous?.digest == summary)
    #expect(previous?.isWholeSummary == true)
}

@Test func aCallWithoutSummaryHasNothingToShow() {
    let calls = [makeCall(id: "bare", daysAgo: 7, title: "Sync", summary: nil)]

    let previous = RelatedCalls.previousRelatedCall(to: makeTarget(title: "Sync"), among: calls)

    #expect(previous == nil)
    #expect(RelatedCalls.digest(ofSummary: "  \n ") == nil)
}

@Test func seriesAndParticipantsSurviveTheDatabase() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-related-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CallStore(dbURL: directory.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    for (id, started) in [("old", now.addingTimeInterval(-86_400)), ("new", now)] {
        try store.upsertCall(
            id: id, kind: "dual", startedAt: started, endedAt: nil, durationSec: 60, status: "ready",
            transcriptURL: nil, audioDirectoryURL: directory, error: nil, appName: nil
        )
        try store.setEvent(callID: id, title: id, eventID: nil, pinned: false, seriesID: "S1", participants: ["anna@a.com", "bob@a.com"])
    }
    try store.setSummary(callID: "old", text: "**Что делать**\n— отправить план")

    let previous = try store.previousRelatedCall(toCallID: "new")

    #expect(try store.fetchCall(id: "old")?.participants == ["anna@a.com", "bob@a.com"])
    #expect(previous?.callID == "old")
    #expect(previous?.digest == "**Что делать**\n— отправить план")
}
