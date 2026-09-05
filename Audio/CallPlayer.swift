import AVFAudio
import Foundation
import Observation

/// Plays a recorded call back. A dual call has two files, so both play together and are
/// kept on the same clock.
@MainActor
@Observable
final class CallPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var isAvailable = false
    private(set) var rate: Float = 1

    @ObservationIgnored private var players: [AVAudioPlayer] = []
    @ObservationIgnored private var ticker: Timer?

    private static let speeds: [Float] = [1, 1.5, 2]

    func load(_ call: StoredCallSummary?) {
        stop()
        players = []
        currentTime = 0
        duration = 0
        isAvailable = false

        guard let call else {
            return
        }
        let urls = Self.audioURLs(in: call.audioDirectoryURL)
        guard !urls.isEmpty else {
            return
        }

        players = urls.compactMap { url in
            guard let player = try? AVAudioPlayer(contentsOf: url) else {
                return nil
            }
            player.enableRate = true
            player.rate = rate
            player.prepareToPlay()
            return player
        }
        guard !players.isEmpty else {
            return
        }

        duration = players.map(\.duration).max() ?? 0
        isAvailable = duration > 0
    }

    func togglePlay() {
        if isPlaying {
            pause()
        } else {
            play(from: currentTime >= duration ? 0 : currentTime)
        }
    }

    func seek(to time: TimeInterval) {
        let target = min(max(0, time), duration)
        currentTime = target
        if isPlaying {
            play(from: target)
        } else {
            players.forEach { $0.currentTime = min(target, $0.duration) }
        }
    }

    func cycleSpeed() {
        let next = Self.speeds.firstIndex(of: rate).map { (($0 + 1) % Self.speeds.count) } ?? 0
        rate = Self.speeds[next]
        players.forEach { $0.rate = rate }
    }

    var speedLabel: String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(rate)×"
    }

    var clockLabel: String {
        "\(CallFormatting.mmss(currentTime)) / \(CallFormatting.mmss(duration))"
    }

    func stop() {
        players.forEach { $0.stop() }
        isPlaying = false
        ticker?.invalidate()
        ticker = nil
    }

    private func play(from time: TimeInterval) {
        // both files have to start on the same tick, otherwise the two speakers drift apart
        let startTime = (players.first?.deviceCurrentTime ?? 0) + 0.05
        for player in players {
            player.currentTime = min(time, player.duration)
            player.rate = rate
            player.play(atTime: startTime)
        }
        isPlaying = true
        startTicking()
    }

    private func pause() {
        players.forEach { $0.pause() }
        isPlaying = false
        ticker?.invalidate()
        ticker = nil
    }

    private func startTicking() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let longest = players.max(by: { $0.duration < $1.duration }) else {
            return
        }
        currentTime = min(longest.currentTime, duration)
        if !longest.isPlaying {
            currentTime = duration
            pause()
        }
    }

    /// raw audio first, the normalized copies when the sweep already took the originals
    static func audioURLs(in directory: URL) -> [URL] {
        let candidates = [
            ["me.raw.wav", "them.raw.wav"],
            ["me.asr.wav", "them.asr.wav"],
            ["mic.raw.wav"],
            ["mic.16k-mono.wav"]
        ]
        for group in candidates {
            let urls = group
                .map { directory.appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            if !urls.isEmpty {
                return urls
            }
        }
        return []
    }
}
