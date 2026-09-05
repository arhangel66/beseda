import Foundation
import Testing

@testable import Podushka

private func detail(
    segments: [StoredTranscriptSegment],
    speakerNames: [String: String] = [:],
    summaryText: String? = nil
) -> StoredCallDetail {
    StoredCallDetail(
        summary: StoredCallSummary(
            id: "20260830-101500",
            kind: "dual",
            startedAt: "2026-08-30T10:15:00.000Z",
            endedAt: "2026-08-30T10:18:00.000Z",
            durationSec: 180,
            status: "ready",
            transcriptPath: nil,
            audioDirectoryPath: "/tmp/call",
            error: nil,
            appName: "Zoom",
            previewText: nil,
            summaryText: summaryText,
            eventTitle: "Синк по релизу",
            eventID: nil,
            eventPinned: false
        ),
        segments: segments,
        speakerNames: speakerNames,
        markdownText: nil,
        jobStats: nil
    )
}

private let twoSpeakers = [
    StoredTranscriptSegment(speaker: "me", startSec: 1, endSec: 3, text: "Привет.", orderIndex: 0),
    StoredTranscriptSegment(speaker: "them", startSec: 4, endSec: 6, text: "Привет, слышно?", orderIndex: 1),
    StoredTranscriptSegment(speaker: "me", startSec: 7, endSec: nil, text: "Да.", orderIndex: 2)
]

private func json(_ payload: WebhookPayload) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: payload.encoded()) as? [String: Any])
}

@Test func thePayloadCarriesTheKrispKeysNextToPodushkasOwn() throws {
    let payload = WebhookPayload.make(detail: detail(segments: twoSpeakers, summaryText: "Договорились."))

    let body = try json(payload)

    #expect(body["event"] as? String == "transcript_created")
    let meeting = try #require(body["meeting"] as? [String: Any])
    #expect(meeting["id"] as? String == "20260830-101500")
    #expect(meeting["name"] as? String == "Синк по релизу")
    #expect(meeting["started_at"] as? String == "2026-08-30T10:15:00.000Z")
    let transcript = try #require(body["transcript"] as? [String: Any])
    #expect(transcript["text"] as? String == "Вы: Привет.\nСобеседник: Привет, слышно?\nВы: Да.")
    let call = try #require(body["call"] as? [String: Any])
    #expect(call["id"] as? String == "20260830-101500")
    #expect(call["app"] as? String == "Zoom")
    #expect(call["duration_sec"] as? Double == 180)
    let participants = try #require(body["participants"] as? [[String: Any]])
    #expect(participants.map { $0["key"] as? String } == ["me", "them"])
    #expect(participants[0]["is_me"] as? Bool == true)
    let dialogue = try #require(body["dialogue"] as? [[String: Any]])
    #expect(dialogue.count == 3)
    #expect(dialogue[1]["speaker"] as? String == "Собеседник")
    #expect(dialogue[1]["start_sec"] as? Double == 4)
    #expect(body["summary"] as? String == "Договорились.")
    #expect(body["data"] == nil)
}

@Test func renamedSpeakersReachBothTheTextAndTheParticipants() throws {
    let payload = WebhookPayload.make(detail: detail(segments: twoSpeakers, speakerNames: ["them": "Аня"]))

    let body = try json(payload)

    let transcript = try #require(body["transcript"] as? [String: Any])
    #expect((transcript["text"] as? String)?.contains("Аня: Привет, слышно?") == true)
    let participants = try #require(body["participants"] as? [[String: Any]])
    #expect(participants[1]["name"] as? String == "Аня")
}

@Test func aMissingSummaryLeavesTheKeyOut() throws {
    let payload = WebhookPayload.make(detail: detail(segments: twoSpeakers))

    let body = try json(payload)

    #expect(body["summary"] == nil)
}

@Test func theTestPayloadStillHasAMeetingStartTime() throws {
    let payload = WebhookPayload.test(now: Date(timeIntervalSince1970: 1_756_548_900))

    let body = try json(payload)

    #expect(body["event"] as? String == "podushka_test")
    let meeting = try #require(body["meeting"] as? [String: Any])
    #expect(meeting["started_at"] as? String == "2025-08-30T10:15:00.000Z")
    #expect((body["dialogue"] as? [Any])?.isEmpty == true)
}
