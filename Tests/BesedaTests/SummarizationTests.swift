import Foundation
import Testing

@testable import Beseda

/// Records what the service handed it and answers at once — the 1.5 s mock has no place in a test.
private actor SpyProvider: SummarizationProvider {
    private(set) var receivedText: String?

    func summarize(text: String) async throws -> String {
        receivedText = text
        return "саммари"
    }
}

private func detail(
    segments: [StoredTranscriptSegment],
    speakerNames: [String: String] = [:],
    markdownText: String? = nil
) -> StoredCallDetail {
    StoredCallDetail(
        summary: StoredCallSummary(
            id: "20260830-101500",
            kind: "dual",
            startedAt: "2026-08-30T10:15:00.000Z",
            endedAt: nil,
            durationSec: 180,
            status: "ready",
            transcriptPath: nil,
            audioDirectoryPath: "/tmp/call",
            error: nil,
            appName: nil,
            previewText: nil,
            summaryText: nil,
            eventTitle: nil,
            eventID: nil,
            eventPinned: false
        ),
        segments: segments,
        speakerNames: speakerNames,
        markdownText: markdownText,
        jobStats: nil
    )
}

@Test func aCallWithNeitherLinesNorMarkdownNeverReachesTheProvider() async throws {
    let spy = SpyProvider()
    let service = SummarizationService(provider: spy)

    do {
        _ = try await service.summarize(detail(segments: []))
        Issue.record("пустая расшифровка должна была остановиться в сервисе")
    } catch SummarizationError.emptyTranscript {
        #expect(await spy.receivedText == nil)
    }
}

@Test func aCallWithOnlyMarkdownStillGoesToTheProvider() async throws {
    let spy = SpyProvider()
    let service = SummarizationService(provider: spy)

    _ = try await service.summarize(detail(segments: [], markdownText: "# Разговор\n\nтекст"))

    #expect(await spy.receivedText == "# Разговор\n\nтекст")
}

@Test func aRenamedSpeakerReachesTheProviderUnderTheNewName() async throws {
    let spy = SpyProvider()
    let service = SummarizationService(provider: spy)

    _ = try await service.summarize(
        detail(
            segments: [
                StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 3, text: "Начнём.", orderIndex: 0),
                StoredTranscriptSegment(speaker: "them-1", startSec: 4, endSec: 8, text: "Давай.", orderIndex: 1)
            ],
            speakerNames: ["them-1": "Ира"]
        )
    )

    #expect(await spy.receivedText == "Вы: Начнём.\nИра: Давай.")
}

@Test func aTranscriptUnderBudgetReachesTheProviderUntouched() async throws {
    let spy = SpyProvider()
    let service = SummarizationService(provider: spy)

    let result = try await service.summarize(
        detail(segments: [
            StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 3, text: "Начнём.", orderIndex: 0)
        ])
    )

    #expect(await spy.receivedText == "Вы: Начнём.")
    #expect(result == "саммари")
}

@Test func aTranscriptOverBudgetIsCutAtTheLastNewlineAndFlagged() async throws {
    let spy = SpyProvider()
    let service = SummarizationService(provider: spy, characterBudget: 40)

    let firstLine = String(repeating: "а", count: 30)
    let result = try await service.summarize(
        detail(segments: [
            StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 3, text: firstLine, orderIndex: 0),
            StoredTranscriptSegment(speaker: "them-1", startSec: 4, endSec: 8, text: "конец", orderIndex: 1)
        ], speakerNames: ["them-1": "Ира"])
    )

    let received = try #require(await spy.receivedText)
    #expect(received == "Вы: \(firstLine)")
    #expect(received.count <= 40)
    #expect(result == "Пересказано только начало разговора — целиком в модель не поместилось.\n\nсаммари")
}
