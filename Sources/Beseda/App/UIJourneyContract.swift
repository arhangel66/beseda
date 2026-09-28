import Foundation

/// Stable names used by the headless accessibility contract and future external UI driver.
enum UIJourneyContract {
    static let seededJourneyEnvironment = "BESEDA_SEEDED_JOURNEY"
    static let seededCallID = "seeded-accessibility-journey"
    static let seededPreviousCallID = "seeded-accessibility-previous"

    enum Identifier {
        static let onboarding = "onboarding.window"
        static let onboardingAdvance = "onboarding.advance"
        static let archive = "archive.sidebar"
        static let search = "archive.search"
        static let summaryTab = "call.summary"
        static let copyTranscript = "call.copy-transcript"
        static let deleteCall = "call.delete"
        static let speakerLinePrefix = "call.speaker-line."
    }

    /// A deterministic call for an isolated copy. It never records, downloads, or requests permission.
    static func seedIfRequested(environment: [String: String], isolated: Bool, paths: AppPaths, store: CallStore) throws {
        guard isolated, environment[seededJourneyEnvironment] != nil,
              try store.fetchCall(id: seededCallID) == nil,
              try store.fetchCall(id: seededPreviousCallID) == nil else { return }

        for (id, time, lines, summary) in [
            (seededPreviousCallID, 1_700_000_000.0,
             ["Example conversation: sketch the lighthouse route.", "Let's check the map next time."],
             "**Договорились**\nUse the paper map for the lighthouse route.\n\n**Что делать**\nCheck the route at the next call."),
            (seededCallID, 1_700_604_800.0,
             ["Example conversation: review the lighthouse route.", "The paper map shows a shorter path."],
             "The shorter route is ready to review; check the map before leaving.")
        ] {
            let directory = paths.callsDirectory.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let transcript = directory.appendingPathComponent("transcript.md")
            try "**Speaker 1:** \(lines[0])\n\n**Speaker 2:** \(lines[1])\n"
                .write(to: transcript, atomically: true, encoding: .utf8)
            let started = Date(timeIntervalSince1970: time)
            try store.upsertCall(
                id: id, kind: "dual", startedAt: started, endedAt: started.addingTimeInterval(60),
                durationSec: 60, status: "ready", transcriptURL: transcript, audioDirectoryURL: directory,
                error: nil, appName: "Example conversation"
            )
            try store.replaceSegments(callID: id, segments: [
                StoredTranscriptSegment(speaker: "them-1", startSec: 0, endSec: 30, text: lines[0], orderIndex: 0),
                StoredTranscriptSegment(speaker: "them-2", startSec: 30, endSec: 60, text: lines[1], orderIndex: 1)
            ])
            try store.setEvent(callID: id, title: id == seededCallID ? "Example conversation: route review" : "Example conversation: route sketch", eventID: nil, pinned: false, seriesID: "synthetic-route")
            try store.setSummary(callID: id, text: summary)
        }
    }
}
