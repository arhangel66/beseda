import Foundation
import Observation

/// Onboarding's ten-second check: opens both channels, shows their levels, writes nothing.
@MainActor
@Observable
final class LevelMonitor {
    private(set) var microphoneLevel: Double = 0
    private(set) var systemAudioLevel: Double = 0
    private(set) var isRunning = false
    private(set) var heardMicrophone = false
    private(set) var heardSystemAudio = false
    private(set) var failure: String?

    @ObservationIgnored private var microphone: MicrophoneCapture?
    @ObservationIgnored private var tap: AnyObject?
    @ObservationIgnored private var microphoneTracker = AudioActivityTracker()
    @ObservationIgnored private var systemTracker = AudioActivityTracker()
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var stopTask: Task<Void, Never>?

    /// anything above this counts as "we heard you", well over room noise
    private static let heardThreshold = 0.06

    func start(duration: TimeInterval = 10) {
        stop()
        failure = nil
        heardMicrophone = false
        heardSystemAudio = false
        microphoneTracker = AudioActivityTracker()
        systemTracker = AudioActivityTracker()

        let microphone = MicrophoneCapture(activityTracker: microphoneTracker)
        self.microphone = microphone

        if #available(macOS 14.2, *) {
            let tap = SystemAudioTap(activityTracker: systemTracker)
            do {
                try tap.start(expectedDuration: duration)
                self.tap = tap
            } catch {
                tap.cleanup()
                failure = error.localizedDescription
            }
        }

        Task {
            do {
                try await microphone.start(expectedDuration: duration)
                isRunning = true
                startTicking()
                stopTask = Task {
                    try? await Task.sleep(for: .seconds(duration))
                    stop()
                }
            } catch {
                failure = error.localizedDescription
                stop()
            }
        }
    }

    func stop() {
        stopTask?.cancel()
        stopTask = nil
        ticker?.invalidate()
        ticker = nil
        microphone?.stopDiscarding()
        microphone = nil
        if #available(macOS 14.2, *), let tap = tap as? SystemAudioTap {
            tap.cleanup()
        }
        tap = nil
        isRunning = false
        microphoneLevel = 0
        systemAudioLevel = 0
    }

    private func startTicking() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.sample()
            }
        }
    }

    private func sample() {
        let now = Date()
        microphoneLevel = microphoneTracker.currentMeterLevel(referenceDate: now)
        systemAudioLevel = systemTracker.currentMeterLevel(referenceDate: now)
        // "we heard you" stays on the raw amplitude the threshold was picked against
        heardMicrophone = heardMicrophone || microphoneTracker.currentLevel(referenceDate: now) > Self.heardThreshold
        heardSystemAudio = heardSystemAudio || systemTracker.currentLevel(referenceDate: now) > Self.heardThreshold
    }
}
