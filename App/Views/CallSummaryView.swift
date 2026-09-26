import SwiftUI

/// The summary pane in its four states. It takes values rather than the controller, so every
/// state can be looked at from a preview without recording a call to get into it. `controller`
/// is the one exception, needed only to deep-link into Settings from the error card.
struct CallSummaryView: View {
    let text: String?
    let isRunning: Bool
    let error: String?
    let startedAt: Date?
    let recovery: SummaryRecovery?
    let onGenerate: () -> Void
    let onRecover: () -> Void
    let controller: AppController?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error {
                errorCard(error)
            }

            // a regeneration keeps the old text on screen; only a pane with nothing in it
            // gives the whole column to the spinner
            if let text, !text.isEmpty {
                ready(text)
            } else if isRunning {
                running
            } else if error == nil {
                empty
            }
        }
        .frame(maxWidth: 680, alignment: .leading)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Button("Составить итоги", systemImage: "sparkles", action: onGenerate)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

            Text("Коротко: о чём говорили, о чём договорились и что осталось открытым.")
                .font(.callout)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var running: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)

            runningLine("Модель читает расшифровку")

            Button("Составить итоги", systemImage: "sparkles", action: onGenerate)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    /// counts seconds since the request started; swaps to a longer-wait note past 10 s
    private func runningLine(_ base: String) -> some View {
        Group {
            if let startedAt {
                TimelineView(.periodic(from: startedAt, by: 1)) { timeline in
                    let elapsed = Int(timeline.date.timeIntervalSince(startedAt))
                    Text(elapsed >= 10 ? "Модель ещё думает, первый раз это долго…" : "\(base)… \(elapsed) с")
                }
            } else {
                Text("\(base)…")
            }
        }
        .font(.callout)
        .foregroundStyle(Color.secondary)
    }

    private func ready(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Self.rendered(text))
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    runningLine("Итоги составляются заново")
                }
            } else {
                Button("Составить заново", action: onGenerate)
                    .controlSize(.small)
            }
        }
    }

    /// inline-only markdown: `**bold**` and the line breaks survive, `#` headers would not,
    /// which is why the summaries are written without them
    static func rendered(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(Color.red)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 8) {
                Text("Итоги не получились")
                    .font(.body.weight(.semibold))

                Text(message)
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(Color.secondary)
                    .frame(maxWidth: 520, alignment: .leading)

                HStack(spacing: 8) {
                    recoveryButton

                    Button("Повторить", action: onGenerate)
                        .disabled(isRunning)
                }
            }
        }
        .bannerCard(Color.red)
    }

    @ViewBuilder
    private var recoveryButton: some View {
        switch recovery {
        case .startServer:
            Button("Запустить LM Studio", action: onRecover)
                .buttonStyle(.borderedProminent)
        case .downloadModel:
            // the download lives in Settings with its progress bar; a second one here would be a lie
            if let controller {
                SettingsSectionLink(section: "processing", controller: controller) {
                    Text("Скачать модель")
                }
                .buttonStyle(.borderedProminent)
            }
        case .openSettings:
            if let controller {
                SettingsSectionLink(section: "processing", controller: controller) {
                    Text("Открыть настройки")
                }
                .buttonStyle(.borderedProminent)
            }
        case nil:
            EmptyView()
        }
    }
}

/// No `#` headers on purpose: the pane renders inline markdown only and would show them as hashes.
private let sampleSummary = """
    **О чём говорили**
    Обсудили готовность релиза 0.6 и то, что осталось закрыть до выката.

    **Главное**
    — Расшифровка двух каналов работает, осталась разметка говорящих.
    — Договорились не тянуть саммаризацию в релиз, если она не успеет к пятнице.
    — Ира просила заранее прислать заметки по хранению аудио.

    **Что делать**
    — Миша: собрать сборку и прогнать на живом звонке, до четверга.
    — Ира: проверить, как ведут себя старые записи после обновления базы.

    **Открытые вопросы**
    — Не решили, чистить ли сырое аудио сразу после расшифровки.
    """

#Preview("Пусто") {
    CallSummaryView(
        text: nil,
        isRunning: false,
        error: nil,
        startedAt: nil,
        recovery: nil,
        onGenerate: {},
        onRecover: {},
        controller: nil
    )
    .padding(24)
}

#Preview("В работе") {
    CallSummaryView(
        text: nil,
        isRunning: true,
        error: nil,
        startedAt: .now,
        recovery: nil,
        onGenerate: {},
        onRecover: {},
        controller: nil
    )
    .padding(24)
}

#Preview("Готово") {
    CallSummaryView(
        text: sampleSummary,
        isRunning: false,
        error: nil,
        startedAt: nil,
        recovery: nil,
        onGenerate: {},
        onRecover: {},
        controller: nil
    )
    .padding(24)
}

#Preview("Готово, коротко") {
    CallSummaryView(
        text: "**Коротко**\nСозвон на три минуты, ни о чём не договорились.",
        isRunning: false,
        error: nil,
        startedAt: nil,
        recovery: nil,
        onGenerate: {},
        onRecover: {},
        controller: nil
    )
    .padding(24)
}

#Preview("Ошибка") {
    CallSummaryView(
        text: nil,
        isRunning: false,
        error: "LM Studio ответил кодом 500",
        startedAt: nil,
        recovery: .openSettings,
        onGenerate: {},
        onRecover: {},
        controller: nil
    )
    .padding(24)
}

#Preview("Ошибка: сервер не запущен") {
    CallSummaryView(
        text: nil,
        isRunning: false,
        error: "LM Studio не запущен",
        startedAt: nil,
        recovery: .startServer,
        onGenerate: {},
        onRecover: {},
        controller: nil
    )
    .padding(24)
}
