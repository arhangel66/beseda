import Foundation

/// The JSON body of a webhook delivery. `event`, `meeting` and `transcript` mirror the Krisp
/// shape kushetka already accepts; everything else is podushka's own and is ignored there.
struct WebhookPayload: Encodable {
    struct Meeting: Encodable {
        let id: String
        let name: String
        let startedAt: String

        enum CodingKeys: String, CodingKey {
            case id, name
            case startedAt = "started_at"
        }
    }

    struct Transcript: Encodable {
        let text: String
    }

    struct Call: Encodable {
        let id: String
        let startedAt: String
        let endedAt: String?
        let durationSec: Double?
        let app: String?
        let kind: String

        enum CodingKeys: String, CodingKey {
            case id, app, kind
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case durationSec = "duration_sec"
        }
    }

    struct Participant: Encodable {
        let key: String
        let name: String
        let isMe: Bool

        enum CodingKeys: String, CodingKey {
            case key, name
            case isMe = "is_me"
        }
    }

    struct Line: Encodable {
        let startSec: Double
        let endSec: Double?
        let speaker: String
        let text: String

        enum CodingKeys: String, CodingKey {
            case speaker, text
            case startSec = "start_sec"
            case endSec = "end_sec"
        }
    }

    static let transcriptEvent = "transcript_created"
    /// kushetka checks the meeting start before the event name, so a probe still carries one;
    /// an unknown event is then skipped without writing anything
    static let testEvent = "podushka_test"

    let event: String
    let meeting: Meeting
    let transcript: Transcript
    let call: Call
    let participants: [Participant]
    let dialogue: [Line]
    let summary: String?

    static func make(detail: StoredCallDetail) -> WebhookPayload {
        // one payload from the stored segments and renamed speakers, never from transcript.md
        let summary = detail.summary
        let names = detail.speakerNames
        var keys: [String] = []
        for segment in detail.segments where !keys.contains(segment.speaker) {
            keys.append(segment.speaker)
        }
        return WebhookPayload(
            event: transcriptEvent,
            meeting: Meeting(id: summary.id, name: summary.displayTitle, startedAt: summary.startedAt),
            transcript: Transcript(text: TranscriptCopy.render(detail, format: .clean)),
            call: Call(
                id: summary.id,
                startedAt: summary.startedAt,
                endedAt: summary.endedAt,
                durationSec: summary.durationSec,
                app: summary.appName,
                kind: summary.kind
            ),
            participants: keys.map { key in
                Participant(
                    key: key,
                    name: SpeakerNaming.name(for: key, overrides: names),
                    isMe: key == TranscriptChannel.microphone.speakerID
                )
            },
            dialogue: detail.segments.map { segment in
                Line(
                    startSec: segment.startSec,
                    endSec: segment.endSec,
                    speaker: SpeakerNaming.name(for: segment.speaker, overrides: names),
                    text: segment.text
                )
            },
            summary: summary.summaryText
        )
    }

    static func test(now: Date) -> WebhookPayload {
        let stamp = now.iso8601WithFractions
        return WebhookPayload(
            event: testEvent,
            meeting: Meeting(id: "test", name: "Тестовая отправка из Podushka", startedAt: stamp),
            transcript: Transcript(text: "Вы: тест"),
            call: Call(id: "test", startedAt: stamp, endedAt: stamp, durationSec: 0, app: nil, kind: "test"),
            participants: [],
            dialogue: [],
            summary: nil
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
