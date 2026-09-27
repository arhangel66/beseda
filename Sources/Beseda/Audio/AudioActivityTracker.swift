import Foundation

/// Watches one capture channel: how long it has been silent (auto-stop) and how loud it is
/// right now (the popover meters).
final class AudioActivityTracker: @unchecked Sendable {
    private let peakThreshold: Float
    private let rmsThreshold: Double
    private let lock = NSLock()
    private var lastActivityDate = Date()
    private var level: Double = 0
    private var levelUpdatedAt = Date()

    /// how long a level takes to fall to a twentieth of itself once the callbacks go quiet
    private static let levelDecay: TimeInterval = 0.18

    /// the bottom of the meter scale: quieter than this is room noise and draws as nothing
    private static let meterFloorDBFS: Double = -60

    init(peakThresholdDBFS: Double = -45, rmsThresholdDBFS: Double = -60) {
        self.peakThreshold = Float(Self.amplitude(fromDBFS: peakThresholdDBFS))
        self.rmsThreshold = Self.amplitude(fromDBFS: rmsThresholdDBFS)
    }

    func observe(samples: [Float]) {
        guard !samples.isEmpty else {
            return
        }

        var peak: Float = 0
        var sumSquares = 0.0
        for sample in samples {
            let absolute = abs(sample)
            peak = max(peak, absolute)
            sumSquares += Double(absolute * absolute)
        }

        let rms = sqrt(sumSquares / Double(samples.count))
        let now = Date()
        lock.withLock {
            level = max(Double(peak), decayedLevel(at: now))
            levelUpdatedAt = now
            if peak >= peakThreshold || rms >= rmsThreshold {
                lastActivityDate = now
            }
        }
    }

    /// a paused recording feeds no samples, so resuming must not read as a long silence
    func resetActivity(referenceDate: Date = Date()) {
        lock.withLock {
            lastActivityDate = referenceDate
        }
    }

    func silentDuration(referenceDate: Date = Date()) -> TimeInterval {
        lock.withLock {
            referenceDate.timeIntervalSince(lastActivityDate)
        }
    }

    /// 0…1 peak amplitude, decayed since the last buffer so an idle meter falls to zero
    func currentLevel(referenceDate: Date = Date()) -> Double {
        lock.withLock {
            decayedLevel(at: referenceDate)
        }
    }

    /// the same peak on a decibel scale: speech peaks near -20 dBFS, which a linear meter draws as a flat line
    func currentMeterLevel(referenceDate: Date = Date()) -> Double {
        let amplitude = currentLevel(referenceDate: referenceDate)
        guard amplitude > 0 else {
            return 0
        }
        let dbfs = 20 * log10(amplitude)
        return min(1, max(0, 1 - dbfs / Self.meterFloorDBFS))
    }

    private func decayedLevel(at date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(levelUpdatedAt))
        return level * exp(-elapsed / Self.levelDecay)
    }

    private static func amplitude(fromDBFS value: Double) -> Double {
        pow(10, value / 20)
    }
}
