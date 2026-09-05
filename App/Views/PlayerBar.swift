import SwiftUI

/// One speaker's part of the strip in the player: where they talked, and how much of the call that was.
struct SpeakerLane: Identifiable {
    let speaker: String
    let label: String
    let initial: String
    let style: SpeakerStyle
    /// start and width as fractions of the call, ready to draw without touching the segments again
    let bars: [(start: Double, width: Double)]
    let share: Double

    var id: String {
        speaker
    }

    /// A line lasts until the next one starts: the ASR end time is often missing, and a strip
    /// drawn from start times alone reads as a row of dots. Back-to-back lines of one speaker
    /// merge into one bar, so the canvas paints one rectangle instead of a seam per line.
    static func build(
        from segments: [StoredTranscriptSegment],
        duration: TimeInterval,
        names: [String: String]
    ) -> [SpeakerLane] {
        guard duration > 0, !segments.isEmpty else {
            return []
        }
        var order: [String] = []
        var bars: [String: [(start: Double, width: Double)]] = [:]
        var talk: [String: Double] = [:]
        for (index, segment) in segments.enumerated() {
            let end = segments[safe: index + 1]?.startSec ?? segment.endSec ?? duration
            // no floor here: a floor per line would add up to more than the call on a long one
            let width = max(0, min(1, (end - segment.startSec) / duration))
            let start = segment.startSec / duration
            if bars[segment.speaker] == nil {
                order.append(segment.speaker)
            }
            if let last = bars[segment.speaker]?.last, abs(last.start + last.width - start) < 1e-9 {
                bars[segment.speaker]![bars[segment.speaker]!.count - 1].width += width
            } else {
                bars[segment.speaker, default: []].append((start: start, width: width))
            }
            talk[segment.speaker, default: 0] += width
        }
        // the owner first, then the remote speakers by their key, so the rows never reshuffle
        return order
            .sorted { lhs, rhs in
                (lhs == TranscriptChannel.microphone.speakerID ? 0 : 1, lhs)
                    < (rhs == TranscriptChannel.microphone.speakerID ? 0 : 1, rhs)
            }
            .map { speaker in
                SpeakerLane(
                    speaker: speaker,
                    label: SpeakerNaming.name(for: speaker, overrides: names),
                    initial: SpeakerNaming.initial(for: speaker, overrides: names),
                    style: .of(speaker: speaker),
                    bars: bars[speaker] ?? [],
                    share: talk[speaker] ?? 0
                )
            }
    }
}

struct PlayerBar: View {
    let controller: AppController
    let detail: StoredCallDetail
    let player: CallPlayer

    @State private var lanes: [SpeakerLane] = []

    private static let legendGap: CGFloat = 12
    private static let avatarSize: CGFloat = 20
    private static let avatarOverlap: CGFloat = 4

    private var duration: TimeInterval {
        player.duration > 0 ? player.duration : detail.summary.duration
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Palette.separator)

            HStack(spacing: 16) {
                playButton

                track

                if player.isAvailable {
                    Text(player.clockLabel)
                        .font(.system(size: 12, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textSecondary)

                    OutlineButton(height: 24) {
                        player.cycleSpeed()
                    } label: {
                        Text(player.speedLabel)
                            .font(.system(size: 11.5))
                    }
                } else {
                    missingAudioNote
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(Palette.playerBackground)
        .onAppear { rebuildLanes() }
        .onChange(of: detail.id) { _, _ in rebuildLanes() }
        .onChange(of: detail.speakerNames) { _, _ in rebuildLanes() }
    }

    /// The button stays when the audio is gone: without it the lanes jump 50 pt left
    /// between a call that plays and one that does not.
    private var playButton: some View {
        Button {
            player.togglePlay()
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 14))
                .foregroundStyle(player.isAvailable ? Color.white : Palette.textQuaternary)
                .frame(width: 34, height: 34)
                .background(player.isAvailable ? Palette.accent : Palette.fillSubtle, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!player.isAvailable)
    }

    private var track: some View {
        GeometryReader { geometry in
            let railWidth = geometry.size.width - legendWidth
            Group {
                if lanes.isEmpty {
                    // a failed call still has audio but no lines to draw the strip from
                    ProgressRail(progress: progress)
                } else {
                    HStack(spacing: Self.legendGap) {
                        SpeakerStrip(lanes: lanes, progress: progress)
                        legend
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(.rect)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { seek(at: $0.location.x, railOrigin: 0, railWidth: railWidth) }
                    .onEnded { seek(at: $0.location.x, railOrigin: 0, railWidth: railWidth) }
            )
        }
        .frame(height: Self.avatarSize)
    }

    /// Krisp's row of initials: who is in the call, hover for the name and share.
    private var legend: some View {
        HStack(spacing: -Self.avatarOverlap) {
            ForEach(lanes) { lane in
                Text(lane.initial)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(lane.style.ink)
                    .frame(width: Self.avatarSize, height: Self.avatarSize)
                    .background(lane.style.soft, in: .circle)
                    .overlay {
                        Circle().strokeBorder(Palette.playerBackground, lineWidth: 1.5)
                    }
                    .help("\(lane.label) · \(Int((lane.share * 100).rounded()))%")
            }
        }
    }

    private var legendWidth: CGFloat {
        guard !lanes.isEmpty else {
            return 0
        }
        return Self.legendGap + Self.avatarSize + CGFloat(lanes.count - 1) * (Self.avatarSize - Self.avatarOverlap)
    }

    private func seek(at x: CGFloat, railOrigin: CGFloat, railWidth: CGFloat) {
        guard player.isAvailable, railWidth > 0 else {
            return
        }
        let fraction = (x - railOrigin) / railWidth
        player.seek(to: min(1, max(0, fraction)) * duration)
    }

    private var missingAudioNote: some View {
        HStack(spacing: 7) {
            Image(systemName: "speaker.slash")
                .font(.system(size: 11))
            Text("Аудио удалено по правилу хранения")
            SettingsSectionLink(section: "storage", controller: controller) {
                Text("Настроить")
                    .foregroundStyle(Palette.accent)
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(Palette.textTertiary)
    }

    private var progress: Double {
        guard duration > 0 else {
            return 0
        }
        return min(1, player.currentTime / duration)
    }

    private func rebuildLanes() {
        lanes = SpeakerLane.build(from: detail.segments, duration: duration, names: detail.speakerNames)
    }
}

/// One strip for the whole call, as in Krisp: every line is a flat rectangle butted against
/// the next, so the strip reads as continuous colour rather than dots. Drawn as one canvas:
/// a busy call has thousands of lines, and thousands of views would repaint on every tick.
private struct SpeakerStrip: View {
    let lanes: [SpeakerLane]
    let progress: Double

    private static let height: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            for lane in lanes {
                for bar in lane.bars {
                    let rect = CGRect(
                        x: bar.start * size.width,
                        y: 0,
                        width: max(1, bar.width * size.width),
                        height: size.height
                    )
                    context.fill(
                        Path(rect),
                        with: .color(lane.style.bar.opacity(bar.start <= progress ? 1 : 0.45))
                    )
                }
            }
            if progress > 0 {
                let cursor = CGRect(x: progress * size.width - 0.75, y: 0, width: 1.5, height: size.height)
                context.fill(Path(cursor), with: .color(Palette.accent))
            }
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Palette.laneTrack, in: .rect(cornerRadius: Self.height / 2))
        .clipShape(.rect(cornerRadius: Self.height / 2))
    }
}

/// A call with no transcript lines gets one plain rail instead of speaker lanes.
private struct ProgressRail: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.laneTrack)
                Capsule()
                    .fill(Palette.accent)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 6)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
