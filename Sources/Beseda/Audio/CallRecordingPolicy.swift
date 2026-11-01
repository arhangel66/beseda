import Foundation

/// Decides when microphone usage by a call app should start and stop an automatic recording.
/// Pure: it never reads the clock or CoreAudio, `CallDetector` feeds it both.
struct CallRecordingPolicy {
    enum Decision: Equatable {
        case start(CallDetector.Detection)
        case stop
    }

    var startDebounce: TimeInterval = 5
    var minimumGapBetweenRecordings: TimeInterval = 60
    /// call apps reopen the microphone for a moment when someone joins; only a longer release ends the call
    var stopDebounce: TimeInterval = 10

    private var candidate: (detection: CallDetector.Detection, since: Date)?
    private var recording: CallDetector.Detection?
    private var lastRecordingEnd: Date?
    /// the app whose recording already ended while it stayed on the microphone: still the same call
    private var finishedHolder: CallDetector.Detection?
    private var releasedSince: Date?

    var isRecording: Bool {
        recording != nil
    }

    /// a recording whose app let go of the microphone, waiting out `stopDebounce`
    var isWaitingToStop: Bool {
        releasedSince != nil
    }

    /// acts on who holds the microphone right now; nil means no allowed app does
    mutating func update(
        holder: CallDetector.Detection?,
        manualRecordingActive: Bool,
        now: Date
    ) -> Decision? {
        guard let holder else {
            candidate = nil
            // the microphone is free, so whoever takes it next is a new call
            finishedHolder = nil
            guard recording != nil else {
                return nil
            }
            let since = releasedSince ?? now
            releasedSince = since
            guard now.timeIntervalSince(since) >= stopDebounce else {
                return nil
            }
            recordingEnded(now: now)
            finishedHolder = nil
            return .stop
        }
        releasedSince = nil
        guard recording == nil, holder != finishedHolder else {
            return nil
        }
        guard !manualRecordingActive else {
            // a manual recording stopped mid-call must not hand straight over to an automatic one
            candidate = nil
            return nil
        }
        if candidate?.detection != holder {
            candidate = (holder, now)
        }
        guard let candidate, now.timeIntervalSince(candidate.since) >= startDebounce else {
            return nil
        }
        if let lastRecordingEnd, now.timeIntervalSince(lastRecordingEnd) < minimumGapBetweenRecordings {
            return nil
        }
        recording = holder
        return .start(holder)
    }

    mutating func recordingEnded(now: Date) {
        finishedHolder = recording
        recording = nil
        candidate = nil
        releasedSince = nil
        lastRecordingEnd = now
    }
}
