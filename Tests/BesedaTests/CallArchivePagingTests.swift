import Foundation
import Testing

@testable import Beseda

@Test func theOldestOfMoreThanAPageOfCallsIsFoundBySearchAndByPaging() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-archive-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CallStore(dbURL: directory.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    for index in 0..<205 {
        try store.upsertCall(
            id: "call-\(index)", kind: "dual", startedAt: start.addingTimeInterval(Double(index) * 3600),
            endedAt: nil, durationSec: 60, status: "ready", transcriptURL: nil,
            audioDirectoryURL: directory, error: nil, appName: index == 0 ? "Телемост" : "Zoom"
        )
    }
    try store.replaceSegments(callID: "call-0", segments: [
        StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 2, text: "Обсудили архив", orderIndex: 0)
    ])

    let firstPage = try store.fetchCalls(limit: 200)
    let secondPage = try store.fetchCalls(limit: 200, offset: 200)

    #expect(!firstPage.contains { $0.id == "call-0" })
    #expect(secondPage.map(\.id) == ["call-4", "call-3", "call-2", "call-1", "call-0"])
    #expect(try store.searchCalls(matching: "архив").map(\.id) == ["call-0"])
    #expect(try store.searchCalls(matching: "Телемост").map(\.id) == ["call-0"])
    #expect(try store.searchCalls(matching: "АРХИВ").map(\.id) == ["call-0"])
    #expect(try store.searchCalls(matching: "телемост").map(\.id) == ["call-0"])
}
