import Foundation
import Testing

@testable import Beseda

private func makeStoreWithCall(speakers: [String]) throws -> (CallStore, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-one-to-one-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = CallStore(dbURL: directory.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    try store.upsertCall(
        id: "c", kind: "dual", startedAt: Date(), endedAt: nil, durationSec: 60, status: "transcribing",
        transcriptURL: nil, audioDirectoryURL: directory, error: nil, appName: nil
    )
    try store.markReady(
        callID: "c", transcriptURL: directory.appendingPathComponent("transcript.md"),
        segments: speakers.enumerated().map {
            StoredTranscriptSegment(speaker: $1, startSec: Double($0), endSec: Double($0) + 0.5, text: "t", orderIndex: $0)
        }
    )
    return (store, directory)
}

@Test func aOneToOneCalendarEventGivesAllTheirSentencesOneRemoteSpeaker() throws {
    let (store, directory) = try makeStoreWithCall(speakers: ["me", "them-1", "them-2", "them-3"])
    defer { try? FileManager.default.removeItem(at: directory) }

    try store.setEvent(callID: "c", title: "1:1", eventID: nil, pinned: false, participants: ["anna@a.com"])

    #expect(try store.fetchSegments(callID: "c").map(\.speaker) == ["me", "them-1", "them-1", "them-1"])
}

@Test func segmentsWrittenAfterAOneToOneEventGetOneRemoteSpeaker() throws {
    let (store, directory) = try makeStoreWithCall(speakers: [])
    defer { try? FileManager.default.removeItem(at: directory) }
    try store.setEvent(callID: "c", title: "1:1", eventID: nil, pinned: false, participants: ["anna@a.com"])

    try store.replaceSegments(callID: "c", segments: [
        StoredTranscriptSegment(speaker: "them-1", startSec: 0, endSec: 8, text: "long", orderIndex: 0),
        StoredTranscriptSegment(speaker: "them-2", startSec: 9, endSec: 10, text: "да", orderIndex: 1)
    ])

    #expect(try store.fetchSegments(callID: "c").map(\.speaker) == ["them-1", "them-1"])
}

@Test func aGroupCallKeepsTheDiarizerSpeakersIncludingOneWithOnlyShortSegments() throws {
    let (store, directory) = try makeStoreWithCall(speakers: ["them-1", "them-2", "them-3"])
    defer { try? FileManager.default.removeItem(at: directory) }

    try store.setEvent(callID: "c", title: "Daily", eventID: nil, pinned: false, participants: ["anna@a.com", "bob@a.com"])

    #expect(try store.fetchSegments(callID: "c").map(\.speaker) == ["them-1", "them-2", "them-3"])
}

@Test func aCallWithNoAttendeesKeepsTheDiarizerSpeakers() throws {
    let (store, directory) = try makeStoreWithCall(speakers: ["them-1", "them-2"])
    defer { try? FileManager.default.removeItem(at: directory) }

    try store.setEvent(callID: "c", title: "Untitled", eventID: nil, pinned: false, participants: [])

    #expect(try store.fetchSegments(callID: "c").map(\.speaker) == ["them-1", "them-2"])
}
