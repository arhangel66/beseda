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
    #expect(try store.searchCalls(matching: "маяк путешествия").map(\.id) == [call.id])
    #expect(call.summaryText == "Решили продолжить путешествие.")
    let detail = StoredCallDetail(
        summary: call,
        segments: try store.fetchSegments(callID: call.id),
        speakerNames: [:],
        markdownText: try String(contentsOf: #require(call.transcriptURL), encoding: .utf8),
        jobStats: nil
    )
    #expect(TranscriptCopy.render(detail, format: .clean).contains("\(SpeakerNaming.defaultName(for: "them-1")): Обсудили маяк путешествия"))

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
