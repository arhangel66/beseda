import AVFAudio
import SwiftUI

/// The menu-bar window. Its shape never changes with the app state: status, recording
/// controls, the latest call, then the same commands in the same place.
struct MenuBarPopover: View {
    let controller: AppController
    let openConversations: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modelInstallLine
            statusRow
            controls
            Divider()
            latestCalls
            Divider()
            commands
        }
        .padding(14)
        .frame(width: 340)
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
                Text("Скачивается \(controller.runtime.model.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let fraction {
                    Text("\(Int((fraction * 100).rounded()))%")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
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

    // MARK: - Status

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                statusIcon
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                if controller.isRecording {
                    Text(CallFormatting.mmss(controller.elapsedRecordingSeconds))
                        .font(.title3.monospacedDigit())
                }
            }
            if let stage = controller.jobStage {
                ProgressView(value: stage.overall)
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch controller.status {
        case .recording, .callRecording, .autoRecording:
            if controller.isPaused {
                Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            } else {
                PulsingDot()
            }
        case .working:
            ProgressView().controlSize(.small)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        case .idle, .completed:
            Image(systemName: microphoneDenied ? "mic.slash" : "checkmark.circle")
                .foregroundStyle(microphoneDenied ? .red : .green)
        }
    }

    private var statusTitle: String {
        switch controller.status {
        case .recording, .callRecording:
            controller.isPaused ? "Пауза" : "Идёт запись"
        case .autoRecording(let app):
            controller.isPaused ? "Пауза · \(app)" : "Идёт запись · \(app)"
        case .working(let stage):
            stage.title
        case .failed:
            "Не получилось"
        case .completed where lastCall != nil:
            "Расшифровка готова"
        case .idle, .completed:
            "Готова к записи"
        }
    }

    private var statusSubtitle: String {
        switch controller.status {
        case .recording, .callRecording, .autoRecording:
            if controller.isPaused {
                return "Аудио не пишется"
            }
            return controller.settings.stopOnSilence
                ? "Остановится после минуты тишины"
                : "Остановите вручную"
        case .working(let stage):
            return stage.caption()
        case .failed(let message):
            return message
        case .idle, .completed:
            if microphoneDenied {
                return "Нет доступа к микрофону"
            }
            return controller.settings.autoDetectEnabled
                ? "Автозапись включена, ожидание звонка"
                : "Автозапись выключена"
        }
    }

    /// the only permission that can be read without side effects; system audio is only
    /// known once a tap is opened
    private var microphoneDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        if controller.isRecording {
            VStack(spacing: 8) {
                meterRow(icon: "mic", level: controller.microphoneLevel, color: .green, label: "микрофон")
                meterRow(icon: "speaker.wave.2", level: controller.systemAudioLevel, color: .accentColor, label: "собеседник")
            }
            HStack(spacing: 8) {
                Button(controller.isPaused ? "Продолжить" : "Пауза") {
                    controller.togglePause()
                }
                Button("Остановить") {
                    controller.stopActiveRecording()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut("r", modifiers: .command)
            }
        } else {
            HStack(spacing: 10) {
                Button("Начать запись") {
                    controller.startCallRecording()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(controller.isBusy)
                if controller.isBusy {
                    Text("после расшифровки")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("Автозапись", isOn: Bindable(controller.settings).autoDetectEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if controller.jobStage != nil {
                Text("Разговор уже сохранён. Окно можно закрыть: расшифровка допишется в фоне.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func meterRow(icon: String, level: Double, color: Color, label: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            LevelMeter(level: level, color: color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .trailing)
        }
    }

    // MARK: - Latest calls

    @ViewBuilder
    private var latestCalls: some View {
        if let call = lastCall {
            readyCard(call)
        } else if !controller.recentCalls.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text("Последние")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 2)
                ForEach(controller.recentCalls.prefix(3)) { call in
                    RecentRow(call: call) {
                        controller.selectCall(call)
                        openConversations()
                    }
                }
            }
        } else {
            Text("Разговоров пока нет")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
    }

    private func readyCard(_ call: StoredCallSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(call.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Text("\(call.appLabel) · \(call.durationDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let preview = call.previewText {
                    Text(preview)
                        .font(.callout)
                        .lineLimit(3)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button("Открыть") {
                    controller.selectCall(call)
                    controller.lastReadyCallID = nil
                    openConversations()
                }
                Button("Скопировать расшифровку") {
                    controller.selectCall(call)
                    controller.copyTranscript()
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }

    // MARK: - Commands

    private var commands: some View {
        VStack(spacing: 1) {
            MenuRow(title: "Разговоры…", action: openConversations)
            SettingsLink {
                MenuRowLabel(title: "Настройки…", shortcut: "⌘,")
            }
            .buttonStyle(.plain)
            MenuRow(title: "Завершить Beseda", shortcut: "⌘Q") { controller.quit() }
                .keyboardShortcut("q", modifiers: .command)
        }
    }
}

/// A popover line that behaves like a menu item: full-width, highlighted on hover.
private struct MenuRow: View {
    let title: String
    var shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MenuRowLabel(title: title, shortcut: shortcut)
        }
        .buttonStyle(.plain)
    }
}

private struct MenuRowLabel: View {
    let title: String
    var shortcut: String?

    @State private var isHovering = false

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if let shortcut {
                Text(shortcut)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(.rect)
        .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 5))
        .onHover { isHovering = $0 }
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
                        .lineLimit(1)
                    Text(call.isFailed ? "не расшифрован" : "\(call.whenDescription) · \(call.durationDescription)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(.rect)
            .background(isHovering ? Color.primary.opacity(0.06) : .clear, in: .rect(cornerRadius: 5))
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
            .fill(.red)
            .frame(width: size, height: size)
            .opacity(isPulsing ? 0.35 : 1)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}
