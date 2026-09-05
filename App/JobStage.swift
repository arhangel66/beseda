import Foundation

/// One named step of the pipeline that turns a recording into a transcript. Whoever runs the
/// pipeline lists its own steps: a retry of a microphone note has two, a fresh call has five.
struct JobStage: Equatable {
    let title: String
    let index: Int
    let total: Int
    /// how much of this step is done; nil while the step has no way of telling
    var fraction: Double?
    var startedAt = Date()

    var overall: Double {
        (Double(index - 1) + (fraction ?? 0)) / Double(total)
    }

    /// the line under the title: which step this is, and how much of it is left
    func caption(now: Date = Date()) -> String {
        ["Шаг \(index) из \(total)", remainingDescription(now: now)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    /// Seconds left in this step, taken from how long its finished part took. The first
    /// fractions are too small to divide by, so the estimate stays hidden until then.
    func remainingSec(now: Date = Date()) -> Double? {
        guard let fraction, fraction >= 0.1, fraction < 1 else {
            return nil
        }
        let elapsed = now.timeIntervalSince(startedAt)
        return elapsed / fraction - elapsed
    }

    private func remainingDescription(now: Date) -> String? {
        guard let seconds = remainingSec(now: now) else {
            return nil
        }
        if seconds < 60 {
            return "осталось \(max(Int(seconds.rounded()), 1)) сек"
        }
        return "осталось \(Int((seconds / 60).rounded(.up))) мин"
    }
}
