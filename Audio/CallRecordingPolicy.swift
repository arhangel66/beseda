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

    private var candidate: (detection: CallDetector.Detection, since: Date)?
    private var recording: CallDetector.Detection?
    private var lastRecordingEnd: Date?
    /// the app whose recording already ended while it stayed on the microphone: still the same call
    private var finishedHolder: CallDetector.Detection?

    var isRecording: Bool {
        recording != nil
    }

    /// acts on who holds the microphone right now; nil means no allowed app does
    mutating func update(
        holder: CallDetector.Detection?,
        manualRecordingActive: Bool,
        now: Date
    ) -> Decision? {
        guard let holder else {
            candidate = nil
            let wasRecording = recording != nil
            if wasRecording {
                recordingEnded(now: now)
            }
            // the microphone is free, so whoever takes it next is a new call
            finishedHolder = nil
            return wasRecording ? .stop : nil
        }
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
        lastRecordingEnd = now
    }
}
