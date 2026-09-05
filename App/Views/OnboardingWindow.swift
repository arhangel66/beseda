import SwiftUI

struct OnboardingWindow: View {
    let controller: AppController
    let onFinish: () -> Void

    @State private var step = 1
    private static let stepCount = 4
    @State private var permissions = PermissionsModel()
    @State private var monitor = LevelMonitor()

    private static let texts = [
        ("Ваши разговоры остаются на этом Mac",
         "Podushka записывает звонки и превращает их в текст локально. Ни аудио, ни расшифровки не уходят в сеть."),
        ("Два доступа — и можно записывать",
         "Проверю оба сразу, чтобы первая настоящая встреча не оказалась первой попыткой."),
        ("Движок распознавания",
         "Речь превращается в текст на этом Mac. Для этого нужно один раз скачать Python, библиотеки и модель — около 2,6 ГБ."),
        ("Проверим, что вас слышно",
         "Скажите пару слов: если полоска двигается, микрофон и системный звук пойдут в запись.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(1...Self.stepCount, id: \.self) { index in
                        Capsule()
                            .fill(index <= step ? Palette.accent : Palette.toggleOff)
                            .frame(width: 34, height: 3)
                    }
                }

                Text(Self.texts[step - 1].0)
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.5)
                    .padding(.top, 12)

                Text(Self.texts[step - 1].1)
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(Palette.textSecondary)
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
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textQuaternary)

                Spacer()

                OutlineButton(height: 30) {
                    guard step > 1 else {
                        return
                    }
                    step -= 1
                } label: {
                    Text("Назад").font(.system(size: 13))
                }
                .opacity(step == 1 ? 0.35 : 1)

                AccentButton(
                    title: advanceTitle,
                    height: 30,
                    isEnabled: canAdvance
                ) {
                    advance()
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .frame(width: 640, height: 520)
        .background(Palette.windowBackground)
        .foregroundStyle(Palette.textPrimary)
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
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Palette.ok)
                            .padding(.top, 3)
                        Text(promise)
                            .font(.system(size: 14))
                            .lineSpacing(4)
                    }
                }
            }
        case 3:
            VStack(alignment: .leading, spacing: 16) {
                SpeechModelList(controller: controller)
                Text(runtimeHint)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case 2:
            VStack(spacing: 8) {
                PermissionRow(
                    label: "Микрофон",
                    hint: "Чтобы записывать вас",
                    action: "Разрешить",
                    state: permissions.microphone
                ) {
                    Task { await permissions.requestMicrophone() }
                }
                PermissionRow(
                    label: "Системный звук",
                    hint: "Чтобы записывать собеседника — без этого получится монолог",
                    action: "Проверить",
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
                        color: Palette.ok,
                        barCount: 48,
                        height: 44
                    )

                    HStack(spacing: 14) {
                        AccentButton(title: testButtonTitle, height: 30, isEnabled: !monitor.isRunning) {
                            monitor.start()
                        }
                        Text(testHint)
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
                .background(Palette.fillHover, in: .rect(cornerRadius: Metrics.windowCorner))
            }
        }
    }

    private static let promises = [
        "Аудио и текст лежат в папке на этом компьютере — их видно в Finder.",
        "Расшифровка считается офлайн, моделью на вашем железе.",
        "Аудио можно удалять автоматически, оставляя только текст."
    ]

    private var testButtonTitle: String {
        if monitor.isRunning {
            return "Слушаю…"
        }
        return monitor.heardMicrophone ? "Записать ещё раз" : "Записать 10 секунд"
    }

    private var testHint: String {
        if let failure = monitor.failure {
            return failure
        }
        if monitor.isRunning {
            return "Скажите что-нибудь"
        }
        if monitor.heardMicrophone && monitor.heardSystemAudio {
            return "Оба канала слышны — можно записывать встречи"
        }
        if monitor.heardMicrophone {
            return "Микрофон слышен, системный звук молчал — включите музыку и проверьте ещё раз"
        }
        return "Проверю оба канала сразу"
    }

    private var runtimeHint: String {
        if controller.runtime.isReady {
            return "Всё на месте, расшифровка работает офлайн"
        }
        if controller.runtime.isInstalling {
            return "Можно идти дальше, скачивание не прервётся"
        }
        return "Parakeet понимает 25 языков, GigaAM — только русский, зато вчетверо легче"
    }

    private var footnote: String {
        switch step {
        case 2:
            "Можно пропустить и настроить позже"
        case 3:
            "Без модели записи останутся без текста; скачать можно и потом, в настройках"
        case 4:
            "Эта запись никуда не сохранится"
        default:
            "Шаг \(step) из \(Self.stepCount)"
        }
    }

    private var advanceTitle: String {
        switch step {
        case 3 where !controller.runtime.isReady:
            "Пропустить"
        case Self.stepCount:
            "Готово"
        default:
            "Дальше"
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
                    .font(.system(size: 13.5, weight: .medium))
                Text(detail)
                    .font(.system(size: 12))
                    .lineSpacing(2)
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer(minLength: 0)

            switch state {
            case .granted:
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                    Text("Готово")
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.okText)
            case .checking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Проверяю")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textTertiary)
                }
            case .idle, .denied:
                AccentButton(title: action, height: 26, action: onGrant)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(Palette.fillHover, in: .rect(cornerRadius: Metrics.cardCorner))
    }

    private var detail: String {
        if case .denied(let message) = state {
            return message
        }
        return hint
    }
}
