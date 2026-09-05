import Foundation
import Testing

@testable import Beseda

private func makeStore() throws -> (CallStore, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-webhook-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = CallStore(dbURL: directory.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    try store.upsertCall(
        id: "20260830-101500",
        kind: "dual",
        startedAt: Date(),
        endedAt: nil,
        durationSec: 180,
        status: "ready",
        transcriptURL: nil,
        audioDirectoryURL: directory,
        error: nil,
        appName: nil
    )
    return (store, directory)
}

private func insert(_ store: CallStore, id: String, attempt: Int = 1, nextRetryAt: Date = Date()) throws {
    try store.insertWebhookDelivery(
        id: id,
        callID: "20260830-101500",
        callTitle: "Синк",
        attempt: attempt,
        event: "transcript_created",
        url: "https://kushetka.example/api/webhooks/krisp",
        nextRetryAt: nextRetryAt
    )
}

@Test func aDeliveryRoundTripsThroughItsThreeStates() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try insert(store, id: "d-1")

    #expect(try store.fetchWebhookDeliveries(callID: "20260830-101500").first?.state == "queued")
    try store.markWebhookSending(id: "d-1", url: "https://kushetka.example/api/webhooks/krisp")
    #expect(try store.fetchWebhookDeliveries(callID: "20260830-101500").first?.state == "sending")
    try store.finishWebhookDelivery(
        id: "d-1", state: "delivered", httpStatus: 200, responseAction: "ingested",
        responseBody: "{\"action\":\"ingested\"}", error: nil
    )

    let row = try #require(try store.fetchWebhookDeliveries(callID: "20260830-101500").first)
    #expect(row.state == "delivered")
    #expect(row.httpStatus == 200)
    #expect(row.responseAction == "ingested")
    #expect(row.callTitle == "Синк")
    #expect(row.sentAt != nil)
    #expect(row.finishedAt != nil)
    #expect(row.detailLine == "HTTP 200 · ingested")
    #expect(try store.fetchRecentWebhookDeliveries().map(\.id) == ["d-1"])
}

@Test func deletingTheCallDropsItsDeliveries() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try insert(store, id: "d-1")

    try store.deleteCall(id: "20260830-101500")

    #expect(try store.fetchRecentWebhookDeliveries().isEmpty)
}

@Test func onlyQueuedRowsWhoseTimeHasComeAreDue() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    let now = Date()
    try insert(store, id: "past", attempt: 1, nextRetryAt: now.addingTimeInterval(-1))
    try insert(store, id: "future", attempt: 2, nextRetryAt: now.addingTimeInterval(60))
    try insert(store, id: "done", attempt: 3, nextRetryAt: now.addingTimeInterval(-1))
    try store.finishWebhookDelivery(id: "done", state: "failed", httpStatus: 503, responseAction: nil, responseBody: nil, error: "HTTP 503")

    let due = try store.fetchDueWebhookDeliveries(now: now)

    #expect(due.map(\.id) == ["past"])
}

@Test func aRowLeftSendingIsFailedOnLaunchAndReturned() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try insert(store, id: "d-1")
    try store.markWebhookSending(id: "d-1", url: "https://kushetka.example/api/webhooks/krisp")

    let interrupted = try store.failInterruptedWebhookDeliveries(reason: "Interrupted before the app restarted")

    #expect(interrupted.map(\.id) == ["d-1"])
    let row = try #require(try store.fetchWebhookDeliveries(callID: "20260830-101500").first)
    #expect(row.state == "failed")
    #expect(row.error == "Interrupted before the app restarted")
    #expect(row.detailLine == "Interrupted before the app restarted")
}

@Test func theAttemptCountCountsEveryRowOfTheCall() throws {
    let (store, directory) = try makeStore()
    defer { try? FileManager.default.removeItem(at: directory) }
    try insert(store, id: "d-1", attempt: 1)
    try insert(store, id: "d-2", attempt: 2)
    try insert(store, id: "d-3", attempt: 3)

    #expect(try store.webhookAttemptCount(callID: "20260830-101500") == 3)
    #expect(try store.fetchWebhookDeliveries(callID: "20260830-101500").map(\.attempt) == [3, 2, 1])
}
