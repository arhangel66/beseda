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
    #expect(try store.searchCalls(matching: "50%").map(\.id) == ["call-1"])
    #expect(try store.searchCalls(matching: "5_%").map(\.id).isEmpty)
    #expect(try store.fetchCalls().map(\.previewText) == ["Скидка 50% до пятницы. Договорились"])
    #expect(try store.fetchCall(id: "call-1")?.appName == "Zoom")
}

@Test func mergingASpeakerRelabelsItsSegmentsAndPersists() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-merge-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let dbURL = directory.appendingPathComponent("calls.sqlite")
    let store = CallStore(dbURL: dbURL)
    try store.prepare()
    try store.upsertCall(
        id: "call-1", kind: "dual", startedAt: Date(), endedAt: nil, durationSec: 60, status: "ready",
        transcriptURL: nil, audioDirectoryURL: directory, error: nil, appName: nil
    )
    try store.replaceSegments(callID: "call-1", segments: [
        StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 1, text: "Привет", orderIndex: 0),
        StoredTranscriptSegment(speaker: "them-1", startSec: 1, endSec: 2, text: "Привет", orderIndex: 1),
        StoredTranscriptSegment(speaker: "them-2", startSec: 2, endSec: 3, text: "Ага", orderIndex: 2)
    ])
    try store.setSpeakerName(callID: "call-1", speakerKey: "them-2", displayName: "Лишний")

    try store.mergeSpeaker(callID: "call-1", speakerKey: "them-2", into: "them-1")

    let reopened = CallStore(dbURL: dbURL)
    try reopened.prepare()
    let speakers = try reopened.fetchSegments(callID: "call-1").map(\.speaker)
    #expect(speakers == ["me", "them-1", "them-1"])
    #expect(Set(speakers).count == 2)
    #expect(try reopened.fetchSpeakerNames(callID: "call-1").isEmpty)
}
