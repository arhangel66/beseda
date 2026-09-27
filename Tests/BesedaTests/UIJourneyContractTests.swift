import Foundation
import Testing

@testable import Beseda

@Test func seededHeadlessJourneyCoversArchiveSearchSummaryCopySpeakerMergeAndDelete() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-ui-contract-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppPaths(dataDirectory: root)
    let store = CallStore(dbURL: paths.callIndexURL)
    try FileManager.default.createDirectory(at: paths.callsDirectory, withIntermediateDirectories: true)
    try store.prepare()

    try UIJourneyContract.seedIfRequested(
        environment: [UIJourneyContract.seededJourneyEnvironment: "1"], isolated: true, paths: paths, store: store
    )

    let call = try #require(try store.fetchCall(id: UIJourneyContract.seededCallID))
    #expect(try store.searchCalls(matching: "маяк путешествия").map(\.id) == [call.id])
    #expect(call.summaryText == "Решили продолжить путешествие.")
    let detail = StoredCallDetail(
        summary: call,
        segments: try store.fetchSegments(callID: call.id),
        speakerNames: [:],
        markdownText: try String(contentsOf: #require(call.transcriptURL), encoding: .utf8),
        jobStats: nil
    )
    #expect(TranscriptCopy.render(detail, format: .clean).contains("Собеседник 1: Обсудили маяк путешествия"))

    try store.mergeSpeaker(callID: call.id, speakerKey: "them-2", into: "them-1")
    #expect(Set(try store.fetchSegments(callID: call.id).map(\.speaker)) == ["them-1"])

    try store.deleteCallAndFiles(id: call.id, exportFolder: nil)
    #expect(try store.fetchCall(id: call.id) == nil)
    #expect(!FileManager.default.fileExists(atPath: call.audioDirectoryURL.path))
}

@Test func seededJourneyCannotModifyARealAppRun() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-ui-contract-guard-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = AppPaths(dataDirectory: root)
    let store = CallStore(dbURL: paths.callIndexURL)
    try FileManager.default.createDirectory(at: paths.callsDirectory, withIntermediateDirectories: true)
    try store.prepare()

    try UIJourneyContract.seedIfRequested(
        environment: [UIJourneyContract.seededJourneyEnvironment: "1"], isolated: false, paths: paths, store: store
    )

    #expect(try store.fetchCall(id: UIJourneyContract.seededCallID) == nil)
}

@Test func journeyAccessibilityNamesAreStableAndUnique() {
    let identifiers = [
        UIJourneyContract.Identifier.onboarding,
        UIJourneyContract.Identifier.onboardingAdvance,
        UIJourneyContract.Identifier.archive,
        UIJourneyContract.Identifier.search,
        UIJourneyContract.Identifier.summaryTab,
        UIJourneyContract.Identifier.copyTranscript,
        UIJourneyContract.Identifier.deleteCall,
        UIJourneyContract.Identifier.speakerLinePrefix
    ]
    #expect(Set(identifiers).count == identifiers.count)
    #expect(identifiers.allSatisfy { !$0.isEmpty })
}
