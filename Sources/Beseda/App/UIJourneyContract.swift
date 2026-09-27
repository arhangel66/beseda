import Foundation

/// Stable names used by the headless accessibility contract and future external UI driver.
enum UIJourneyContract {
    static let seededJourneyEnvironment = "BESEDA_SEEDED_JOURNEY"
    static let seededCallID = "seeded-accessibility-journey"

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
              try store.fetchCall(id: seededCallID) == nil else { return }

        let directory = paths.callsDirectory.appendingPathComponent(seededCallID, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let transcript = directory.appendingPathComponent("transcript.md")
        try "**Собеседник 1:** Обсудили маяк путешествия.\n\n**Собеседник 2:** Решение принято.\n"
            .write(to: transcript, atomically: true, encoding: .utf8)
        let started = Date(timeIntervalSince1970: 1_700_000_000)
        try store.upsertCall(
            id: seededCallID, kind: "dual", startedAt: started, endedAt: started.addingTimeInterval(60),
            durationSec: 60, status: "ready", transcriptURL: transcript, audioDirectoryURL: directory,
            error: nil, appName: "Headless contract"
        )
        try store.replaceSegments(callID: seededCallID, segments: [
            StoredTranscriptSegment(speaker: "them-1", startSec: 0, endSec: 30, text: "Обсудили маяк путешествия", orderIndex: 0),
            StoredTranscriptSegment(speaker: "them-2", startSec: 30, endSec: 60, text: "Решение принято", orderIndex: 1)
        ])
        try store.setSummary(callID: seededCallID, text: "Решили продолжить путешествие.")
    }
}
