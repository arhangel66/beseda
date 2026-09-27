import SwiftUI

/// One speaker's part of the strip in the player: where they talked, and how much of the call that was.
struct SpeakerLane: Identifiable {
    let speaker: String
    let label: String
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
    @State private var renamedSpeaker: String?
    @State private var draftName = ""

    private static let legendGap: CGFloat = 12
    private static let avatarSize: CGFloat = 20

    private var duration: TimeInterval {
        player.duration > 0 ? player.duration : detail.summary.duration
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color(nsColor: .separatorColor))

            HStack(spacing: 16) {
                playButton

                track

                if player.isAvailable {
                    Text(player.clockLabel)
                        .font(.callout.monospaced())
                        .monospacedDigit()
                        .foregroundStyle(Color.secondary)

                    Button(player.speedLabel) {
                        player.cycleSpeed()
                    }
                    .controlSize(.small)
                    .help("Скорость воспроизведения")
                    .accessibilityLabel("Скорость воспроизведения")
                    .accessibilityValue(player.speedLabel)
                } else {
                    missingAudioNote
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(.bar)
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
                .frame(width: 16)
        }
        .help(player.isPlaying ? "Пауза" : "Воспроизвести")
        .accessibilityLabel(player.isPlaying ? "Пауза" : "Воспроизвести")
        .disabled(!player.isAvailable)
    }

    /// the strip is decoration under a real slider: the slider owns the drag, the keyboard and VoiceOver
    private var track: some View {
        HStack(spacing: Self.legendGap) {
            ZStack {
                if lanes.isEmpty {
                    // a failed call still has audio but no lines to draw the strip from
                    ProgressRail(progress: progress)
                } else {
                    SpeakerStrip(lanes: lanes, progress: progress)
                }
                Slider(value: position, in: 0...max(duration, 1))
                    .controlSize(.mini)
                    .opacity(player.isAvailable ? 0.85 : 0)
                    .disabled(!player.isAvailable)
                    .accessibilityLabel("Позиция воспроизведения")
                    .accessibilityValue(player.clockLabel)
            }
            if !lanes.isEmpty {
                legend
            }
        }
        .frame(height: Self.avatarSize)
    }

    private var position: Binding<Double> {
        Binding(
            get: { min(player.currentTime, duration) },
            set: { player.seek(to: $0) }
        )
    }

    /// who is in the call, each a named control: the name beside its colour, rename and merge in its menu
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach(lanes) { lane in
                Menu {
                    Button("Переименовать…") { startRenaming(lane.speaker) }
                    let targets = mergeTargets(for: lane.speaker)
                    if !targets.isEmpty {
                        Menu("Объединить с") {
                            ForEach(targets) { target in
                                Button(target.label) { controller.mergeSpeaker(lane.speaker, into: target.speaker) }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(lane.style.bar)
                            .frame(width: 8, height: 8)
                        Text(lane.label)
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("\(lane.label) · \(Int((lane.share * 100).rounded()))% разговора")
                .accessibilityLabel("\(lane.label), \(Int((lane.share * 100).rounded()))% разговора")
            }
        }
        .alert("Как зовут участника?", isPresented: isRenaming) {
            TextField("Имя", text: $draftName)
            Button("Отмена", role: .cancel) { renamedSpeaker = nil }
            Button("Сохранить") {
                if let renamedSpeaker {
                    controller.renameSpeaker(renamedSpeaker, to: draftName)
                }
                renamedSpeaker = nil
            }
        } message: {
            Text("Имя видно только в этом разговоре.")
        }
    }

    /// `me` is never merged, so only a remote speaker gets the other remote speakers
    private func mergeTargets(for speaker: String) -> [SpeakerLane] {
        guard SpeakerNaming.remoteIndex(of: speaker) != nil else {
            return []
        }
        return lanes.filter { $0.speaker != speaker && SpeakerNaming.remoteIndex(of: $0.speaker) != nil }
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renamedSpeaker != nil }, set: { if !$0 { renamedSpeaker = nil } })
    }

    private func startRenaming(_ speaker: String) {
        draftName = detail.speakerNames[speaker] ?? ""
        renamedSpeaker = speaker
    }

    private var missingAudioNote: some View {
        HStack(spacing: 7) {
            Image(systemName: "speaker.slash")
                .font(.caption)
            Text("Аудио удалено по правилу хранения")
            SettingsSectionLink(section: "storage", controller: controller) {
                Text("Настроить")
            }
            .buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
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
                context.fill(Path(cursor), with: .color(Color.accentColor))
            }
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.08), in: .rect(cornerRadius: Self.height / 2))
        .clipShape(.rect(cornerRadius: Self.height / 2))
    }
}

/// A call with no transcript lines gets one plain rail instead of speaker lanes.
private struct ProgressRail: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Color.accentColor)
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
