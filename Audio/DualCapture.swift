import Foundation

enum DualCaptureStopReason: String, Codable, Hashable {
    case maxDuration
    case manual
    case silence
}

struct DualCaptureOutput {
    let startedAt: Date
    let endedAt: Date
    let sessionDirectory: URL
    let microphoneRawURL: URL
    let systemRawURL: URL
    let metadataURL: URL
    let microphone: AudioFileMetadata
    let system: AudioFileMetadata
    let stopReason: DualCaptureStopReason

    var durationSec: TimeInterval {
        endedAt.timeIntervalSince(startedAt)
    }
}

private struct DualCaptureMetadata: Encodable {
    let startedAt: String
    let endedAt: String
    let durationSec: Double
    let stopReason: DualCaptureStopReason
    let microphone: AudioFileMetadata
    let system: AudioFileMetadata
}

final class DualCapture: @unchecked Sendable {
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private var _sleepTask: Task<Void, Error>?
    private var _silenceTask: Task<Void, Never>?
    private var _stopReason: DualCaptureStopReason?
    private var _microphoneTracker: AudioActivityTracker?
    private var _systemTracker: AudioActivityTracker?
    private var _microphone: MicrophoneCapture?
    private var _systemTap: AnyObject?
    private var _paused = false

    private var sleepTask: Task<Void, Error>? {
        get { lock.withLock { _sleepTask } }
        set { lock.withLock { _sleepTask = newValue } }
    }

    private var silenceTask: Task<Void, Never>? {
        get { lock.withLock { _silenceTask } }
        set { lock.withLock { _silenceTask = newValue } }
    }

    private var stopReason: DualCaptureStopReason? {
        get { lock.withLock { _stopReason } }
        set { lock.withLock { _stopReason = newValue } }
    }

    /// 0…1 loudness of each channel, for the live meters in the menu bar popover
    var microphoneLevel: Double {
        lock.withLock { _microphoneTracker }?.currentMeterLevel() ?? 0
    }

    var systemAudioLevel: Double {
        lock.withLock { _systemTracker }?.currentMeterLevel() ?? 0
    }

    var isPaused: Bool {
        lock.withLock { _paused }
    }

    func setPaused(_ paused: Bool) {
        let (microphone, tap, trackers) = lock.withLock {
            _paused = paused
            return (_microphone, _systemTap, [_microphoneTracker, _systemTracker].compactMap { $0 })
        }
        microphone?.isPaused = paused
        if #available(macOS 14.2, *), let tap = tap as? SystemAudioTap {
            tap.isPaused = paused
        }
        if !paused {
            trackers.forEach { $0.resetActivity() }
        }
    }

    func record(
        duration: TimeInterval,
        sessionDirectory: URL,
        autoStopSilenceDuration: TimeInterval? = nil
    ) async throws -> DualCaptureOutput {
        guard #available(macOS 14.2, *) else {
            throw AudioCaptureError.unsupportedFormat("Native system audio capture requires macOS 14.2 or newer")
        }

        let microphoneRawURL = sessionDirectory.appendingPathComponent("me.raw.wav")
        let systemRawURL = sessionDirectory.appendingPathComponent("them.raw.wav")
        let metadataURL = sessionDirectory.appendingPathComponent("session.json")

        try fileManager.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)

        let microphoneTracker = AudioActivityTracker()
        let systemTracker = AudioActivityTracker()
        let systemTap = SystemAudioTap(activityTracker: systemTracker)
        let microphone = MicrophoneCapture(activityTracker: microphoneTracker)
        lock.withLock {
            _microphoneTracker = microphoneTracker
            _systemTracker = systemTracker
            _microphone = microphone
            _systemTap = systemTap
            _paused = false
        }
        defer {
            lock.withLock {
                _microphoneTracker = nil
                _systemTracker = nil
                _microphone = nil
                _systemTap = nil
                _paused = false
            }
        }

        do {
            stopReason = nil
            try systemTap.start(expectedDuration: duration)
            try await microphone.start(expectedDuration: duration)

            let startedAt = Date()
            let task = Task { try await Task.sleep(for: .seconds(duration)) }
            sleepTask = task
            if let autoStopSilenceDuration {
                let monitor = Task { [weak self, microphoneTracker, systemTracker] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        guard !Task.isCancelled, self?.isPaused == false else {
                            continue
                        }
                        // both channels have to go quiet: one side listening is still a call
                        let silence = min(microphoneTracker.silentDuration(), systemTracker.silentDuration())
                        if silence >= autoStopSilenceDuration {
                            self?.stop(reason: .silence)
                            return
                        }
                    }
                }
                silenceTask = monitor
            }
            _ = try? await task.value
            sleepTask = nil
            silenceTask?.cancel()
            silenceTask = nil
            let endedAt = Date()
            let resolvedStopReason = stopReason ?? .maxDuration
            stopReason = nil

            let systemMetadata = try systemTap.stopAndWrite(to: systemRawURL)
            let microphoneMetadata = try microphone.stopAndWrite(to: microphoneRawURL)

            let output = DualCaptureOutput(
                startedAt: startedAt,
                endedAt: endedAt,
                sessionDirectory: sessionDirectory,
                microphoneRawURL: microphoneRawURL,
                systemRawURL: systemRawURL,
                metadataURL: metadataURL,
                microphone: microphoneMetadata,
                system: systemMetadata,
                stopReason: resolvedStopReason
            )
            try writeMetadata(for: output)
            return output
        } catch {
            silenceTask?.cancel()
            silenceTask = nil
            stopReason = nil
            systemTap.cleanup()
            microphone.stopDiscarding()
            throw error
        }
    }

    func stop(reason: DualCaptureStopReason = .manual) {
        lock.withLock {
            if _stopReason == nil {
                _stopReason = reason
            }
            _sleepTask?.cancel()
        }
    }

    private func writeMetadata(for output: DualCaptureOutput) throws {
        let metadata = DualCaptureMetadata(
            startedAt: output.startedAt.iso8601WithFractions,
            endedAt: output.endedAt.iso8601WithFractions,
            durationSec: output.durationSec,
            stopReason: output.stopReason,
            microphone: output.microphone,
            system: output.system
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: output.metadataURL)
    }
}
