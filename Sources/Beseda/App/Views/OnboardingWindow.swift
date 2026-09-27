import SwiftUI

struct OnboardingWindow: View {
    let controller: AppController
    let onFinish: () -> Void

    #if DEBUG
    // BESEDA_PREVIEW_ONBOARDING opens a given step for screenshots
    @State private var step = Int(ProcessInfo.processInfo.environment["BESEDA_PREVIEW_ONBOARDING"] ?? "") ?? 1
    #else
    @State private var step = 1
    #endif
    private static let stepCount = 4
    @State private var permissions = PermissionsModel()
    @State private var monitor = LevelMonitor()

    private static let texts = [
        (FirstRunText.get("Аудио остаётся на этом Mac"),
         FirstRunText.get("Беседа записывает звонки и превращает их в текст прямо здесь, аудио в сеть не уходит. Текст уходит в облако, только если вы сами включите: итоги через OpenRouter, Jev или живые тезисы с ключом.")),
        (FirstRunText.get("Два источника звука"),
         FirstRunText.get("Микрофон пишет вас, системный звук — собеседника. Проверю оба сразу, чтобы первая настоящая встреча не оказалась первой попыткой.")),
        (FirstRunText.get("Модель распознавания"),
         FirstRunText.get("Речь превращается в текст на этом Mac. Для этого нужно один раз скачать модель распознавания — от 270 до 490 МБ, смотря какую выбрать.")),
        (FirstRunText.get("Проверим, что вас слышно"),
         FirstRunText.get("Скажите пару слов: если полоска двигается, микрофон и системный звук пойдут в запись."))
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(1...Self.stepCount, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? Color.accentColor : Color.primary.opacity(0.16))
                            .frame(width: 34, height: 3)
                    }
                }

                Text(Self.texts[step - 1].0)
                    .font(.title2.weight(.semibold))
                    .padding(.top, 12)

                Text(Self.texts[step - 1].1)
                    .font(.body)
                    .lineSpacing(4)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: 480, alignment: .leading)
            }
            .padding(.horizontal, 40)
            .padding(.top, 34)

            content
                .padding(.horizontal, 40)
                .padding(.top, 24)
                .frame(minHeight: 220, alignment: .top)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                Text(footnote)
                    .font(.callout)
                    .foregroundStyle(.tertiary)

                Spacer()

                Button(FirstRunText.get("Назад")) {
                    step -= 1
                }
                .disabled(step == 1)

                Button(advanceTitle) {
                    advance()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier(UIJourneyContract.Identifier.onboardingAdvance)
                .disabled(!canAdvance)
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .frame(width: 640, height: 520)
        .accessibilityIdentifier(UIJourneyContract.Identifier.onboarding)
        .onAppear {
            permissions.refresh()
        }
        .onDisappear {
            monitor.stop()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 1:
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.promises, id: \.self) { promise in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                            .foregroundStyle(Color.green)
                            .padding(.top, 3)
                        Text(promise)
                            .font(.body)
                            .lineSpacing(4)
                    }
                }
            }
        case 3:
            VStack(alignment: .leading, spacing: 16) {
                SpeechModelList(controller: controller)
                Text(runtimeHint)
                    .font(.callout)
                    .foregroundStyle(Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case 2:
            VStack(spacing: 8) {
                PermissionRow(
                    label: FirstRunText.get("Микрофон"),
                    hint: FirstRunText.get("Чтобы записывать вас"),
                    action: FirstRunText.get("Разрешить доступ"),
                    state: permissions.microphone
                ) {
                    Task { await permissions.requestMicrophone() }
                }
                PermissionRow(
                    label: FirstRunText.get("Системный звук"),
                    hint: FirstRunText.get("Чтобы записывать собеседника — без этого получится монолог"),
                    action: FirstRunText.get("Проверить звук"),
                    state: permissions.systemAudio
                ) {
                    Task { await permissions.checkSystemAudio() }
                }
            }
        default:
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 16) {
                    LevelMeter(
                        level: max(monitor.microphoneLevel, monitor.systemAudioLevel),
                        color: Color.green,
                        barCount: 48,
                        height: 44
                    )

                    HStack(spacing: 14) {
                        Button(testButtonTitle) {
                            monitor.start()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(monitor.isRunning)
                        Text(testHint)
                            .font(.callout)
                            .foregroundStyle(Color.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 12))
            }
        }
    }

    private static let promises = [
        FirstRunText.get("Аудио и текст лежат в папке на этом компьютере — их видно в Finder."),
        FirstRunText.get("Расшифровка делается без интернета, моделью на этом Mac."),
        FirstRunText.get("Аудио можно удалять автоматически, оставляя только текст.")
    ]

    private var testButtonTitle: String {
        if monitor.isRunning {
            return FirstRunText.get("Слушаю…")
        }
        return monitor.heardMicrophone ? FirstRunText.get("Записать ещё раз") : FirstRunText.get("Записать 10 секунд")
    }

    private var testHint: String {
        if let failure = monitor.failure {
            return failure
        }
        if monitor.isRunning {
            return FirstRunText.get("Скажите что-нибудь")
        }
        if monitor.heardMicrophone && monitor.heardSystemAudio {
            return FirstRunText.get("Оба канала слышны — можно записывать встречи")
        }
        if monitor.heardMicrophone {
            return FirstRunText.get("Микрофон слышен, системный звук молчал — включите музыку и проверьте ещё раз")
        }
        return FirstRunText.get("Проверю оба канала сразу")
    }

    private var runtimeHint: String {
        if controller.runtime.isSpeechModelReady {
            return FirstRunText.get("Модель скачана, расшифровка работает без интернета")
        }
        if controller.runtime.isInstalling {
            return FirstRunText.get("Можно идти дальше, скачивание не прервётся")
        }
        return FirstRunText.get("Parakeet понимает 25 языков, GigaAM — только русский, зато почти вдвое легче")
    }

    private var footnote: String {
        switch step {
        case 2:
            FirstRunText.get("Системный звук можно проверить и позже: Настройки → Запись")
        case 3:
            FirstRunText.get("Без модели записи останутся без текста. Скачать её можно и потом: Настройки → Обработка")
        case 4:
            FirstRunText.get("Эта запись никуда не сохранится")
        default:
            String(format: FirstRunText.get("Шаг %d из %d"), step, Self.stepCount)
        }
    }

    private var advanceTitle: String {
        switch step {
        case 3 where !controller.runtime.isSpeechModelReady:
            FirstRunText.get("Пропустить")
        case Self.stepCount:
            FirstRunText.get("Готово")
        default:
            FirstRunText.get("Дальше")
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 2:
            permissions.microphone.isGranted
        case 4:
            monitor.heardMicrophone
        default:
            true
        }
    }

    private func advance() {
        guard canAdvance else {
            return
        }
        if step == Self.stepCount {
            monitor.stop()
            onFinish()
            return
        }
        step += 1
        if step == 2 {
            permissions.refresh()
        }
        if step == 3 {
            controller.runtime.refresh()
        }
    }
}

private struct PermissionRow: View {
    let label: String
    let hint: String
    let action: String
    let state: PermissionState
    let onGrant: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .lineSpacing(2)
                    .foregroundStyle(Color.secondary)
            }

            Spacer(minLength: 0)

            switch state {
            case .granted:
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.callout.weight(.bold))
                    Text(FirstRunText.get("Готово"))
                }
                .font(.callout)
                .foregroundStyle(Color.green)
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(FirstRunText.get("Проверка…"))
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            case .idle, .denied:
                Button(action, action: onGrant)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: Metrics.cardCorner))
    }

    private var detail: String {
        if case .denied(let message) = state {
            return message
        }
        return hint
    }
}
