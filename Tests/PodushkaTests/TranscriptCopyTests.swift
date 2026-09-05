import Foundation
import Testing

@testable import Podushka

private let detail = StoredCallDetail(
    summary: StoredCallSummary(
        id: "20260829-140800",
        kind: "dual",
        startedAt: "2026-08-29T14:08:00.000Z",
        endedAt: nil,
        durationSec: 214,
        status: "ready",
        transcriptPath: nil,
        audioDirectoryPath: "/tmp/call",
        error: nil,
        appName: "Zoom",
        previewText: nil,
        summaryText: nil,
        eventTitle: "Релиз 0.6 — синк",
        eventID: "event-1",
        eventPinned: false
    ),
    segments: [
        StoredTranscriptSegment(speaker: "me", startSec: 41, endSec: 44, text: "Начнём с релиза.", orderIndex: 0),
        StoredTranscriptSegment(speaker: "them", startSec: 52, endSec: 58, text: "Давай.", orderIndex: 1)
    ],
    speakerNames: [:],
    markdownText: nil,
    jobStats: nil
)

@Test func timestampedFormatPutsTheClockBeforeTheSpeaker() {
    let text = TranscriptCopy.render(detail, format: .timestamped)

    #expect(text == "00:41 Вы: Начнём с релиза.\n00:52 Собеседник: Давай.")
}

@Test func cleanFormatDropsTheClock() {
    let text = TranscriptCopy.render(detail, format: .clean)

    #expect(text == "Вы: Начнём с релиза.\nСобеседник: Давай.")
}

@Test func markdownFormatOpensWithTheConversationName() {
    let text = TranscriptCopy.render(detail, format: .markdown)

    #expect(text.hasPrefix("## Релиз 0.6 — синк"))
    #expect(text.contains("**Вы** 00:41"))
}

@Test func withoutSegmentsTheStoredMarkdownIsCopiedAsItIs() {
    let empty = StoredCallDetail(
        summary: detail.summary,
        segments: [],
        speakerNames: [:],
        markdownText: "# Разговор\n\nтекст",
        jobStats: nil
    )

    #expect(TranscriptCopy.render(empty, format: .clean) == "# Разговор\n\nтекст")
}

@Test func renamedSpeakersReplaceTheDefaultNamesEverywhere() {
    let renamed = StoredCallDetail(
        summary: detail.summary,
        segments: [
            StoredTranscriptSegment(speaker: "me", startSec: 41, endSec: 44, text: "Начнём.", orderIndex: 0),
            StoredTranscriptSegment(speaker: "them-1", startSec: 52, endSec: 58, text: "Давай.", orderIndex: 1),
            StoredTranscriptSegment(speaker: "them-2", startSec: 60, endSec: 64, text: "Секунду.", orderIndex: 2)
        ],
        speakerNames: ["them-1": "Ира"],
        markdownText: nil,
        jobStats: nil
    )

    let text = TranscriptCopy.render(renamed, format: .clean)

    #expect(text == "Вы: Начнём.\nИра: Давай.\nСобеседник 2: Секунду.")
}
