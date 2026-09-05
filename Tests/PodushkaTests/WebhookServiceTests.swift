import Foundation
import Testing

@testable import Podushka

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

    init(status: Int, enabled: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("podushka-webhook-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suiteName = "podushka-test-\(UUID().uuidString)"
        settings = AppSettings(defaults: UserDefaults(suiteName: suiteName)!)
        settings.webhookEnabled = enabled
        settings.webhookURL = "https://kushetka.example/api/webhooks/krisp"
        settings.webhookSecret = "s3cret"

        store = CallStore(dbURL: directory.appendingPathComponent("calls.sqlite"))
        try store.prepare()
        try store.upsertCall(
            id: "20260830-101500", kind: "dual", startedAt: Date(), endedAt: nil, durationSec: 180,
            status: "ready", transcriptURL: nil, audioDirectoryURL: directory, error: nil, appName: "Zoom"
        )
        try store.replaceSegments(callID: "20260830-101500", segments: [
            StoredTranscriptSegment(speaker: "me", startSec: 1, endSec: 2, text: "Привет.", orderIndex: 0),
            StoredTranscriptSegment(speaker: "them", startSec: 3, endSec: 4, text: "Привет.", orderIndex: 1)
        ])

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
@Test func aReadyCallIsDeliveredThroughTheSender() async throws {
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
@Test func aManualSendAddsOneMoreAttempt() async throws {
    let harness = try Harness(status: 200)
    defer { harness.tearDown() }
    harness.service.enqueue(callID: "20260830-101500")
    _ = try await harness.settledRows()

    harness.service.sendNow(callID: "20260830-101500")

    var rows: [StoredWebhookDelivery] = []
    for _ in 0..<200 {
        rows = try harness.store.fetchWebhookDeliveries(callID: "20260830-101500")
        if rows.count == 2, rows.allSatisfy(\.isFinished) {
            break
        }
        try await Task.sleep(for: .milliseconds(10))
    }
    #expect(rows.map(\.attempt) == [2, 1])
    #expect(rows.map(\.state) == ["delivered", "delivered"])
    #expect(await harness.transport.bodies.count == 2)
}
