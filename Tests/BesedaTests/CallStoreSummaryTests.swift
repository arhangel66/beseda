import Foundation
import Testing

@testable import Beseda

@Test func aStoredSummaryIsReadBackFromTheDatabase() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-summary-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

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

    try store.setSummary(callID: "20260830-101500", text: "**Коротко**\nНи о чём не договорились.")

    #expect(try store.fetchCall(id: "20260830-101500")?.summaryText == "**Коротко**\nНи о чём не договорились.")
}
