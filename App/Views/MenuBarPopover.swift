import SwiftUI

struct MenuBarPopover: View {
    let controller: AppController
    let openConversations: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modelInstallLine
            Group {
                if controller.isRecording {
                    recording
                } else if let stage = controller.jobStage {
                    job(stage)
                } else if let lastCall {
                    done(lastCall)
                } else {
                    idle
                }
            }
        }
        .padding(14)
        .frame(width: 340)
        .foregroundStyle(Palette.textPrimary)
        .onAppear {
            controller.refreshRecentCalls()
        }
    }

    /// The onboarding step can be skipped while the model is still coming down; without this
    /// the app would look idle and then fail the first call with "модель не установлена".
    @ViewBuilder
    private var modelInstallLine: some View {
        if case .running(let fraction) = controller.runtime.state(of: .speechModel) {
            HStack(spacing: 8) {
                ProgressView(value: fraction ?? 0)
                    .frame(width: 90)
                Text("Скачиваю \(controller.runtime.model.title)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 0)
                if let fraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(Palette.textTertiary)
                }
            }
        }
    }

    private var lastCall: StoredCallSummary? {
        guard let id = controller.lastReadyCallID else {
            return nil
        }
        return controller.recentCalls.first { $0.id == id }
    }

    // MARK: - Idle

    private var idle: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                AppMark(size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Готов записывать")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Микрофон и системный звук на месте")
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            AccentButton(title: "Записать звонок", systemImage: "record.circle", height: 34) {
                controller.startCallRecording()
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                PillToggle(isOn: Bindable(controller.settings).autoDetectEnabled, width: 30)
                Text("Включать запись, когда начинается звонок")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
            }

            divider

            if !controller.recentCalls.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    SectionCaption(text: "Последние")
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)

                    ForEach(controller.recentCalls.prefix(3)) { call in
                        RecentRow(call: call) {
                            controller.selectCall(call)
                            openConversations()
                        }
                    }
                }

                divider
            }

            HStack(spacing: 14) {
                LinkText("Все разговоры", action: openConversations)
                SettingsLink {
                    Text("Настройки")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                }
                .buttonStyle(.plain)
                if controller.updater.isAvailable {
                    LinkText("Обновления") { controller.updater.checkForUpdates() }
                }
                Spacer()
                Text(controller.updater.version)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textTertiary)
                LinkText("Выйти") { controller.quit() }
            }
        }
    }

    // MARK: - Recording

    private var recording: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                PulsingDot()
                Text(controller.isPaused ? "Пауза" : "Записываю звонок")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(CallFormatting.mmss(controller.elapsedRecordingSeconds))
                    .font(.system(size: 20, weight: .medium, design: .monospaced))
                    .monospacedDigit()
            }

            VStack(spacing: 10) {
                meterRow(icon: "mic", level: controller.microphoneLevel, color: Palette.ok, label: "я")
                meterRow(icon: "speaker.wave.2", level: controller.systemAudioLevel, color: Palette.accent, label: "собеседник")
            }

            HStack(spacing: 8) {
                Button {
                    controller.stopActiveRecording()
                } label: {
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white)
                            .frame(width: 9, height: 9)
                        Text("Остановить")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
                    .background(Palette.recording, in: .rect(cornerRadius: 9))
                }
                .buttonStyle(.plain)

                OutlineButton(height: 32) {
                    controller.togglePause()
                } label: {
                    Text(controller.isPaused ? "Продолжить" : "Пауза")
                        .font(.system(size: 13))
                }
            }

            Text(controller.isPaused
                 ? "Пауза. Аудио не пишется."
                 : hintText)
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    private var hintText: String {
        controller.settings.stopOnSilence
            ? "Остановлю сама после минуты тишины · оба канала идут"
            : "Оба канала идут · остановите вручную"
    }

    private func meterRow(icon: String, level: Double, color: Color, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 14)
            LevelMeter(level: level, color: color)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 66, alignment: .trailing)
        }
    }

    // MARK: - Job

    private func job(_ stage: JobStage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(stage.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(stage.caption())
                        .font(.system(size: 11.5))
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            ProgressTrack(value: stage.overall)

            Text("Разговор уже сохранён. Можно закрыть окно — допишу расшифровку в фоне и покажу уведомление.")
                .font(.system(size: 11.5))
                .lineSpacing(2)
                .foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: - Done

    private func done(_ call: StoredCallSummary) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Palette.ok)
                Text("Расшифровка готова")
                    .font(.system(size: 13, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(call.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                Text("\(call.appLabel) · \(call.durationDescription)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textTertiary)
                if let preview = call.previewText {
                    Text(preview)
                        .font(.system(size: 12.5))
                        .lineSpacing(3)
                        .lineLimit(3)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Palette.fillRaised, in: .rect(cornerRadius: 9))

            HStack(spacing: 8) {
                OutlineButton(height: 30) {
                    controller.selectCall(call)
                    controller.lastReadyCallID = nil
                    openConversations()
                } label: {
                    Text("Открыть")
                }

                AccentButton(title: "Скопировать", systemImage: "doc.on.doc", height: 30) {
                    controller.selectCall(call)
                    controller.copyTranscript()
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Palette.separator)
            .frame(height: 0.5)
    }
}

private struct RecentRow: View {
    let call: StoredCallSummary
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Avatar(initials: call.initials, fallbackSymbol: call.fallbackSymbol, size: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text(call.displayTitle)
                        .font(.system(size: 12.5))
                        .lineLimit(1)
                    Text(call.isFailed ? "не расшифрован" : "\(call.whenDescription) · \(call.durationDescription)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Palette.textPrimary.opacity(0.3))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(isHovering ? Palette.fillHover : .clear, in: .rect(cornerRadius: Metrics.controlCorner))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct LinkText: View {
    let title: String
    let action: () -> Void

    @State private var isHovering = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(isHovering ? Palette.accent : Palette.textSecondary)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct PulsingDot: View {
    var size: CGFloat = 10

    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Palette.recording)
            .frame(width: size, height: size)
            .opacity(isPulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

struct AppMark: View {
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: size * 0.55, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [Color(hex: 0x5B6CFF), Color(hex: 0x2A3AD0)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: .rect(cornerRadius: size * 0.27)
            )
    }
}
