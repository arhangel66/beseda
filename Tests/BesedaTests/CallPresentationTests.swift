import Foundation
import Testing

@testable import Beseda

private let noon = Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: 29, hour: 12))!

@Test func titleSkipsTheFillerOpenerForTheFirstSentenceThatCarriesSomething() {
    let title = StoredCallSummary.title(fromTranscriptOpening: "Окей, тогда я начну. Первое — про bare metal.")

    #expect(title == "Первое — про bare metal")
}

@Test func titleCutsALongFirstSentenceOnAWordBoundary() {
    let line = "Один из них ответил, у него сейчас свободен один узел, и он предлагает отдать доступ через BMC"

    let title = StoredCallSummary.title(fromTranscriptOpening: line)

    #expect(title?.hasSuffix("…") == true)
    #expect(title?.count ?? 0 <= 65)
    #expect(title?.contains("свободен") == true)
}

@Test func titleFallsBackToTheFirstSentenceWhenEveryLineIsShort() {
    let title = StoredCallSummary.title(fromTranscriptOpening: "Привет. Слышно? Ага.")

    #expect(title == "Привет")
}

@Test func titleIsNilForAnEmptyTranscript() {
    #expect(StoredCallSummary.title(fromTranscriptOpening: "   \n ") == nil)
}

@Test func callWithoutATranscriptFallsBackToTheAppAndDate() {
    let call = makeCall(kind: "dual", appName: "Zoom", previewText: nil)

    #expect(call.displayTitle.hasPrefix("Zoom · "))
}

@Test func microphoneNoteWithoutATranscriptGetsItsOwnTitle() {
    let call = makeCall(kind: "mic", appName: nil, previewText: nil)

    #expect(call.displayTitle == ArchiveText.get("Заметка с микрофона"))
    #expect(call.appLabel == ArchiveText.get("Микрофон"))
    #expect(ArchiveText.get("Заметка с микрофона", locale: Locale(identifier: "ru_RU")) == "Заметка с микрофона")
    #expect(ArchiveText.get("Заметка с микрофона", locale: Locale(identifier: "en_US")) == "Microphone note")
    #expect(ArchiveText.get("Микрофон", locale: Locale(identifier: "ru_RU")) == "Микрофон")
    #expect(ArchiveText.get("Микрофон", locale: Locale(identifier: "en_US")) == "Microphone")
}

@Test func dayGroupSplitsTodayYesterdayThisWeekAndEarlier() {
    let calendar = Calendar.current

    #expect(CallDayGroup.of(noon, now: noon, calendar: calendar) == .today)
    #expect(CallDayGroup.of(noon - 24 * 3600, now: noon, calendar: calendar) == .yesterday)
    #expect(CallDayGroup.of(noon - 3 * 24 * 3600, now: noon, calendar: calendar) == .thisWeek)
    #expect(CallDayGroup.of(noon - 30 * 24 * 3600, now: noon, calendar: calendar) == .earlier)
}

@Test func humanDurationReadsAsTheProtoypeWritesIt() {
    let russian = Locale(identifier: "ru_RU")
    let english = Locale(identifier: "en_US")
    #expect(CallFormatting.humanDuration(42, locale: russian) == "42 сек")
    #expect(CallFormatting.humanDuration(214, locale: russian) == "4 мин")
    #expect(CallFormatting.humanDuration(3155, locale: russian) == "53 мин")
    #expect(CallFormatting.humanDuration(3900, locale: russian) == "1 ч 5 мин")
    #expect(CallFormatting.humanDuration(42, locale: english) == "42s")
    #expect(CallFormatting.humanDuration(214, locale: english) == "4m")
}

private func makeCall(
    kind: String,
    appName: String?,
    previewText: String?,
    eventTitle: String? = nil,
    startedAt: String = "2026-08-29T16:20:00.000Z"
) -> StoredCallSummary {
    StoredCallSummary(
        id: "20260829-162000",
        kind: kind,
        startedAt: startedAt,
        endedAt: nil,
        durationSec: 214,
        status: "ready",
        transcriptPath: nil,
        audioDirectoryPath: "/tmp/call",
        error: nil,
        appName: appName,
        previewText: previewText,
        summaryText: nil,
        eventTitle: eventTitle,
        eventID: eventTitle == nil ? nil : "event-1",
        eventPinned: false
    )
}


@Test func anUnparseableStoredDateIsNotShownAsData() {
    let call = makeCall(kind: "dual", appName: "Zoom", previewText: nil, startedAt: "not-a-date")

    #expect(call.whenDescription == "—")
    #expect(call.clockDescription == "—")
}

@Test func aCalendarEventOutranksTheTitleGuessedFromTheTranscript() {
    let call = makeCall(
        kind: "dual",
        appName: "Zoom",
        previewText: "Окей, тогда я начну. Первое — про bare metal.",
        eventTitle: "Релиз 0.6 — синк"
    )

    #expect(call.displayTitle == "Релиз 0.6 — синк")
}

@Test func withoutAnEventTheTitleStillComesFromTheTranscript() {
    let call = makeCall(kind: "dual", appName: "Zoom", previewText: "Окей, тогда я начну. Первое — про bare metal.")

    #expect(call.displayTitle == "Первое — про bare metal")
}
