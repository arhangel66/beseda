import Foundation
import Testing

@testable import Beseda

@Test func segmentsNamesAndSearchRoundTripThroughTheDatabase() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-transcript-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CallStore(dbURL: directory.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    try store.upsertCall(
        id: "call-1", kind: "dual", startedAt: Date(), endedAt: nil, durationSec: 60, status: "ready",
        transcriptURL: nil, audioDirectoryURL: directory, error: nil, appName: "Zoom"
    )
    let segments = [
        StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 2, text: "Скидка 50% до пятницы", orderIndex: 0),
        StoredTranscriptSegment(speaker: "them-1", startSec: 3, endSec: nil, text: "Договорились", orderIndex: 1)
    ]

    try store.replaceSegments(callID: "call-1", segments: segments)
    try store.setSpeakerName(callID: "call-1", speakerKey: "them-1", displayName: "Аня")

    #expect(try store.fetchSegments(callID: "call-1") == segments)
    #expect(try store.fetchSpeakerNames(callID: "call-1") == ["them-1": "Аня"])
    #expect(try store.searchCallIDs(matching: "50%") == ["call-1"])
    #expect(try store.searchCallIDs(matching: "5_%").isEmpty)
    #expect(try store.fetchCalls().map(\.previewText) == ["Скидка 50% до пятницы. Договорились"])
    #expect(try store.fetchCall(id: "call-1")?.appName == "Zoom")
}
