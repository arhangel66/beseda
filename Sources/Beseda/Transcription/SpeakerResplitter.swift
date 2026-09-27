import Foundation

/// Re-splits the remote speakers of calls an older diarizer labelled, from the kept `them` audio and
/// its ASR words: the speaker step of «Расшифровать снова» only, no ASR, summary or webhook.
/// `calls.diarizer` is the progress mark, so a quit resumes where it stopped.
final class SpeakerResplitter: @unchecked Sendable {
    typealias Timeline = @Sendable (URL) async throws -> [SpeakerInterval]

    private let store: CallStore
    private let timeline: Timeline
    private let diarizationQueue: DiarizationQueue
    private let isPaused: @Sendable () async -> Bool
    private let log: @Sendable (String) -> Void
    private let progress: @Sendable (_ done: Int, _ total: Int) -> Void
    private let pausePoll: Duration

    init(
        store: CallStore,
        timeline: @escaping Timeline,
        diarizationQueue: DiarizationQueue = DiarizationQueue(),
        isPaused: @escaping @Sendable () async -> Bool,
        log: @escaping @Sendable (String) -> Void,
        progress: @escaping @Sendable (_ done: Int, _ total: Int) -> Void,
        pausePoll: Duration = .seconds(10)
    ) {
        self.store = store
        self.timeline = timeline
        self.diarizationQueue = diarizationQueue
        self.isPaused = isPaused
        self.log = log
        self.progress = progress
        self.pausePoll = pausePoll
    }

    /// the calls it can redo: a call without the `them` audio or its words keeps its speakers
    func pendingCalls() throws -> [StoredCallSummary] {
        try store.fetchCallsSplitByAnotherDiarizer(than: Diarizer.id).filter { call in
            let folder = call.audioDirectoryURL
            return [AppController.DualFiles.systemASR, "them.asr.json"].allSatisfy {
                FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
            }
        }
    }

    func run() async {
        let calls: [StoredCallSummary]
        do {
            calls = try pendingCalls()
        } catch {
            return log("Speaker re-split: could not list calls: \(error.localizedDescription)")
        }
        guard !calls.isEmpty else {
            return
        }
        progress(0, calls.count)
        for (index, call) in calls.enumerated() {
            // ponytail: checked between calls, so a recording started mid-call waits for that one call
            while await isPaused() {
                try? await Task.sleep(for: pausePoll)
            }
            guard !Task.isCancelled else {
                return
            }
            do {
                if try store.hasSpeakerEdits(callID: call.id) {
                    log("Speaker re-split skipped \(call.id): it has manual speaker edits")
                } else {
                    let speakers = try await resplit(call)
                    log("Speaker re-split \(call.id): \(speakers) remote speakers")
                }
            } catch {
                // left as it was: the next launch tries it again
                log("Speaker re-split failed for \(call.id): \(error.localizedDescription)")
            }
            progress(index + 1, calls.count)
        }
    }

    /// the call's remote speakers counted after the re-split
    private func resplit(_ call: StoredCallSummary) async throws -> Int {
        let folder = call.audioDirectoryURL
        let words = try JSONDecoder().decode(
            ASRTranscription.self, from: Data(contentsOf: folder.appendingPathComponent("them.asr.json"))
        )
        let timeline = timeline
        let intervals = try await diarizationQueue.perform(priority: .background) {
            try await timeline(folder.appendingPathComponent(AppController.DualFiles.systemASR))
        }
        let turns = SpeakerAssignment.remoteTurns(segments: words.segments, timeline: intervals)
        guard !turns.isEmpty else {
            // No speech is a completed result, not an error to retry on every launch.
            try store.replaceSegments(callID: call.id, segments: store.fetchSegments(callID: call.id), diarizer: Diarizer.id)
            return 0
        }
        // the mic lines stay as stored: the echo gate already trimmed them
        let mine = try store.fetchSegments(callID: call.id).filter { $0.speaker == TranscriptChannel.microphone.speakerID }
            .map { (speaker: $0.speaker, start: $0.startSec, end: $0.endSec, text: $0.text) }
        let theirs = turns.map { (speaker: $0.speaker, start: $0.start, end: Optional($0.end), text: $0.text) }
        let segments = (mine + theirs)
            .sorted { $0.start == $1.start ? $0.speaker < $1.speaker : $0.start < $1.start }
            .enumerated()
            .map { StoredTranscriptSegment(speaker: $1.speaker, startSec: $1.start, endSec: $1.end, text: $1.text, orderIndex: $0) }
        // file first, row second: a quit between them leaves the old diarizer id, so the call is redone
        if let transcriptURL = call.transcriptURL {
            try TranscriptMerger.rewriteDialogue(in: transcriptURL, segments: segments, names: [:])
        }
        try store.replaceSegments(callID: call.id, segments: segments, diarizer: Diarizer.id)
        try updateExportCopy(of: call, segments: segments)
        return Set(turns.map(\.speaker)).count
    }

    /// the Markdown copy in the export folder, rewritten in place when the call has one
    private func updateExportCopy(of call: StoredCallSummary, segments: [StoredTranscriptSegment]) throws {
        guard let path = try store.exportPath(callID: call.id), FileManager.default.fileExists(atPath: path),
              let fresh = try store.fetchCall(id: call.id), let summaryText = fresh.summaryText else {
            return
        }
        let detail = StoredCallDetail(summary: fresh, segments: segments, speakerNames: [:], markdownText: nil, jobStats: nil)
        let url = try CallExport.write(
            detail, result: summaryText, type: fresh.callType ?? "", to: URL(fileURLWithPath: path).deletingLastPathComponent()
        )
        try store.replaceExportCopy(callID: call.id, with: url)
    }
}
