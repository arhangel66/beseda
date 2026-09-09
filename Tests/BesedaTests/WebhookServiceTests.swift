import Foundation
import Testing

@testable import Beseda

/// Answers every request with one status and keeps the bodies it saw.
private actor SpyTransport {
    private(set) var bodies: [Data] = []
    private let status: Int

    init(status: Int) {
        self.status = status
    }

    func handle(_ request: URLRequest) -> (Data, URLResponse) {
        bodies.append(request.httpBody ?? Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data("{\"action\":\"ingested\"}".utf8), response)
    }
}

@MainActor
private struct Harness {
    let store: CallStore
    let settings: AppSettings
    let transport: SpyTransport
    let service: WebhookService
    let directory: URL
    let suiteName: String

    init(
        status: Int,
        enabled: Bool = true,
        url: String = "https://kushetka.example/api/webhooks/krisp",
        durationSec: Double? = 2400.1,
        segments: [StoredTranscriptSegment] = [
            StoredTranscriptSegment(speaker: "me", startSec: 1, endSec: 31, text: "Привет.", orderIndex: 0),
            StoredTranscriptSegment(speaker: "them", startSec: 40, endSec: 70, text: "Привет.", orderIndex: 1)
        ]
    ) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("beseda-webhook-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "beseda-test-\(UUID().uuidString)"
        settings = AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
        settings.webhookEnabled = enabled
        settings.webhookURL = url
        settings.webhookSecret = "s3cret"

        store = CallStore(dbURL: directory.appendingPathComponent("calls.sqlite"))
        try store.prepare()
        try store.upsertCall(
            id: "20260830-101500", kind: "dual", startedAt: Date(), endedAt: nil, durationSec: durationSec,
            status: "ready", transcriptURL: nil, audioDirectoryURL: directory, error: nil, appName: "Zoom"
        )
        try store.replaceSegments(callID: "20260830-101500", segments: segments)

        let transport = SpyTransport(status: status)
        self.transport = transport
        service = WebhookService(
            store: store, settings: settings,
            sender: WebhookSender(transport: { await transport.handle($0) })
        )
    }

    func tearDown() {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }

    /// the delivery runs in its own task; wait until the first attempt has settled
    func settledRows() async throws -> [StoredWebhookDelivery] {
        for _ in 0..<200 {
            let rows = try store.fetchWebhookDeliveries(callID: "20260830-101500")
            if let first = rows.last, first.isFinished, !service.sending.contains("20260830-101500") {
                return rows
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        return try store.fetchWebhookDeliveries(callID: "20260830-101500")
    }
}

@Test func theRetryScheduleStopsAfterTheFourthAttempt() {
    #expect(WebhookService.retryDelay(afterAttempt: 1) == 60)
    #expect(WebhookService.retryDelay(afterAttempt: 2) == 300)
    #expect(WebhookService.retryDelay(afterAttempt: 3) == 1800)
    #expect(WebhookService.retryDelay(afterAttempt: 4) == nil)
}

@MainActor
@Test func justOverFortyMinutesWithExactlyThirtySecondsPerSideIsDelivered() async throws {
    let harness = try Harness(status: 200)
    defer { harness.tearDown() }

    harness.service.enqueue(callID: "20260830-101500")

    let rows = try await harness.settledRows()
    #expect(rows.map(\.state) == ["delivered"])
    #expect(rows.first?.responseAction == "ingested")
    #expect(rows.first?.attempt == 1)
    let body = try #require(await harness.transport.bodies.first)
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["event"] as? String == "transcript_created")
    #expect((json["transcript"] as? [String: Any])?["text"] as? String == "Вы: Привет.\nСобеседник: Привет.")
    #expect(harness.service.recent.map(\.id) == rows.map(\.id))
}

@MainActor
@Test func nothingIsQueuedWhileTheWebhookIsOff() async throws {
    let harness = try Harness(status: 200, enabled: false)
    defer { harness.tearDown() }

    harness.service.enqueue(callID: "20260830-101500")

    #expect(try harness.store.fetchWebhookDeliveries(callID: "20260830-101500").isEmpty)
    #expect(await harness.transport.bodies.isEmpty)
}

@MainActor
@Test func exactlyFortyMinutesIsNotAutomaticallyQueued() async throws {
    let harness = try Harness(status: 200, durationSec: 2400)
    defer { harness.tearDown() }

    harness.service.enqueue(callID: "20260830-101500")

    #expect(try harness.store.fetchWebhookDeliveries(callID: "20260830-101500").isEmpty)
    #expect(await harness.transport.bodies.isEmpty)
}

@MainActor
@Test func lessThanThirtySecondsFromMeIsNotAutomaticallyQueued() async throws {
    let harness = try Harness(status: 200, segments: [
        StoredTranscriptSegment(speaker: "me", startSec: 1, endSec: 30.999, text: "Привет.", orderIndex: 0),
        StoredTranscriptSegment(speaker: "them", startSec: 40, endSec: 70, text: "Привет.", orderIndex: 1)
    ])
    defer { harness.tearDown() }

    harness.service.enqueue(callID: "20260830-101500")

    #expect(try harness.store.fetchWebhookDeliveries(callID: "20260830-101500").isEmpty)
    #expect(await harness.transport.bodies.isEmpty)
}

@MainActor
@Test func lessThanThirtySecondsFromRemoteIsNotAutomaticallyQueued() async throws {
    let harness = try Harness(status: 200, segments: [
        StoredTranscriptSegment(speaker: "me", startSec: 1, endSec: 31, text: "Привет.", orderIndex: 0),
        StoredTranscriptSegment(speaker: "them", startSec: 40, endSec: 69.999, text: "Привет.", orderIndex: 1)
    ])
    defer { harness.tearDown() }

    harness.service.enqueue(callID: "20260830-101500")

    #expect(try harness.store.fetchWebhookDeliveries(callID: "20260830-101500").isEmpty)
    #expect(await harness.transport.bodies.isEmpty)
}

@MainActor
@Test func remoteSpeechMustReachThirtySecondsForOneParticipant() async throws {
    let harness = try Harness(status: 200, segments: [
        StoredTranscriptSegment(speaker: "me", startSec: 1, endSec: 31, text: "Привет.", orderIndex: 0),
        StoredTranscriptSegment(speaker: "them-1", startSec: 40, endSec: 55, text: "Один.", orderIndex: 1),
        StoredTranscriptSegment(speaker: "them-2", startSec: 60, endSec: 75, text: "Два.", orderIndex: 2)
    ])
    defer { harness.tearDown() }

    harness.service.enqueue(callID: "20260830-101500")

    #expect(try harness.store.fetchWebhookDeliveries(callID: "20260830-101500").isEmpty)
    #expect(await harness.transport.bodies.isEmpty)
}

@MainActor
@Test func overlappingAndInvalidSegmentsDoNotInflateRecognizedSpeech() async throws {
    let harness = try Harness(status: 200, segments: [
        StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 20, text: "Первая.", orderIndex: 0),
        StoredTranscriptSegment(speaker: "me", startSec: 10, endSec: 30, text: "Вторая.", orderIndex: 1),
        StoredTranscriptSegment(speaker: "me", startSec: 30, endSec: 90, text: "   ", orderIndex: 2),
        StoredTranscriptSegment(speaker: "me", startSec: 100, endSec: nil, text: "Нет конца.", orderIndex: 3),
        StoredTranscriptSegment(speaker: "me", startSec: 110, endSec: 109, text: "Назад.", orderIndex: 4),
        StoredTranscriptSegment(speaker: "them-1", startSec: 40, endSec: 70, text: "Ответ.", orderIndex: 5)
    ])
    defer { harness.tearDown() }

    harness.service.enqueue(callID: "20260830-101500")

    let rows = try await harness.settledRows()
    #expect(rows.map(\.state) == ["delivered"])
    #expect(await harness.transport.bodies.count == 1)
}

@MainActor
@Test func aBrokenURLStillQueuesNothing() async throws {
    let harness = try Harness(status: 200, url: "not a URL")
    defer { harness.tearDown() }

    harness.service.enqueue(callID: "20260830-101500")

    #expect(try harness.store.fetchWebhookDeliveries(callID: "20260830-101500").isEmpty)
    #expect(await harness.transport.bodies.isEmpty)
}

@MainActor
@Test func aRetryableFailureQueuesTheNextAttempt() async throws {
    let harness = try Harness(status: 503)
    defer { harness.tearDown() }

    harness.service.enqueue(callID: "20260830-101500")

    let rows = try await harness.settledRows()
    #expect(rows.map(\.state) == ["queued", "failed"])
    #expect(rows.map(\.attempt) == [2, 1])
    #expect(rows[1].error == "HTTP 503")
    let retryAt = try #require(rows[0].nextRetryAt.flatMap(CallFormatting.parseISO8601))
    #expect(abs(retryAt.timeIntervalSinceNow - 60) < 5)
    #expect(rows[0].detailLine.hasPrefix("повтор в "))
}

@MainActor
@Test func aRejectionQueuesNothing() async throws {
    let harness = try Harness(status: 401)
    defer { harness.tearDown() }

    harness.service.enqueue(callID: "20260830-101500")

    let rows = try await harness.settledRows()
    #expect(rows.map(\.state) == ["failed"])
    #expect(rows[0].httpStatus == 401)
}

@MainActor
@Test func aManualSendBypassesTheAutomaticFilter() async throws {
    let harness = try Harness(status: 200, durationSec: 60, segments: [
        StoredTranscriptSegment(speaker: "me", startSec: 1, endSec: 2, text: "Заметка.", orderIndex: 0)
    ])
    defer { harness.tearDown() }
    harness.service.enqueue(callID: "20260830-101500")
    #expect(try harness.store.fetchWebhookDeliveries(callID: "20260830-101500").isEmpty)

    harness.service.sendNow(callID: "20260830-101500")

    var rows: [StoredWebhookDelivery] = []
    for _ in 0..<200 {
        rows = try harness.store.fetchWebhookDeliveries(callID: "20260830-101500")
        if rows.count == 1, rows.allSatisfy(\.isFinished) {
            break
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(rows.map(\.attempt) == [1])
    #expect(rows.map(\.state) == ["delivered"])
    #expect(await harness.transport.bodies.count == 1)
}
