import AppKit
import Foundation
import SwiftUI
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
    let previous = try #require(try store.fetchCall(id: UIJourneyContract.seededPreviousCallID))
    #expect(try store.searchCalls(matching: "shorter path").map(\.id) == [call.id])
    #expect(try store.searchCalls(matching: "sketch the lighthouse").map(\.id) == [previous.id])
    #expect(call.displayTitle != previous.displayTitle)
    #expect(call.startedDate! > previous.startedDate!)
    #expect(try store.previousRelatedCall(toCallID: call.id)?.callID == previous.id)
    #expect(try store.previousRelatedCall(toCallID: previous.id) == nil)
    #expect(call.summaryText == "The shorter route is ready to review; check the map before leaving.")
    #expect(try #require(try store.previousRelatedCall(toCallID: call.id)).digest.contains("**Who does what**\n— You — check the route — next call."))
    let detail = StoredCallDetail(
        summary: call,
        segments: try store.fetchSegments(callID: call.id),
        speakerNames: [:],
        markdownText: try String(contentsOf: #require(call.transcriptURL), encoding: .utf8),
        jobStats: nil
    )
    #expect(TranscriptCopy.render(detail, format: .clean) == "\(SpeakerNaming.defaultName(for: "them-1")): Example conversation: review the lighthouse route.\n\(SpeakerNaming.defaultName(for: "them-2")): The paper map shows a shorter path.")
    let snapshot = try [previous, call].map { try Data(contentsOf: #require($0.transcriptURL)) }
    try UIJourneyContract.seedIfRequested(environment: [UIJourneyContract.seededJourneyEnvironment: "1"], isolated: true, paths: paths, store: store)
    let reread = try [previous.id, call.id].map { try #require(try store.fetchCall(id: $0)) }
    #expect(snapshot == (try reread.map { try Data(contentsOf: #require($0.transcriptURL)) }))
    #expect([previous, call].map(\.startedAt) == reread.map(\.startedAt))
    #expect([previous, call].map(\.summaryText) == reread.map(\.summaryText))

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
    #expect(try store.fetchCall(id: UIJourneyContract.seededPreviousCallID) == nil)
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

@MainActor
@Test func journeyAccessibilityCanBeReadAndActedWithoutAFrontWindow() {
    var presses = 0
    let harness = AccessibilityHarness {
        JourneyHarnessButton(identifier: UIJourneyContract.Identifier.onboardingAdvance) { presses += 1 }
    }

    #expect(harness.window.alphaValue == 0)
    #expect(!harness.window.isKeyWindow)
    #expect(!harness.window.isMainWindow)
    #expect(NSApp.keyWindow !== harness.window)
    #expect(NSApp.mainWindow !== harness.window)
    #expect(harness.element(identifier: UIJourneyContract.Identifier.onboardingAdvance) != nil)
    #expect(harness.element(label: "Продолжить") != nil)
    #expect(harness.performPress(identifier: UIJourneyContract.Identifier.onboardingAdvance))
    #expect(presses == 1)
    #expect(!harness.window.isKeyWindow)
    #expect(!harness.window.isMainWindow)
}

private struct JourneyHarnessButton: NSViewRepresentable {
    let identifier: String
    let action: () -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Продолжить", target: context.coordinator, action: #selector(Coordinator.press))
        button.setAccessibilityIdentifier(identifier)
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        let action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func press() { action() }
    }
}
