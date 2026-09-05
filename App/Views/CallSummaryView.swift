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
            Button("Сделать саммари", systemImage: "sparkles", action: onGenerate)
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

            runningLine("Читаю расшифровку")

            Button("Сделать саммари", systemImage: "sparkles", action: onGenerate)
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
            Text(rendered(text))
                .font(.body)
                .lineSpacing(5)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    runningLine("Считаю заново")
                }
            } else {
                Button("Заново", action: onGenerate)
                    .controlSize(.small)
            }
        }
    }

    /// inline-only markdown: `**bold**` and the line breaks survive, `#` headers would not,
    /// which is why the summaries are written without them
    private func rendered(_ text: String) -> AttributedString {
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
                Text("Саммари не получилось")
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.red.opacity(0.09), in: .rect(cornerRadius: Metrics.cardCorner))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cardCorner)
                .strokeBorder(Color.red.opacity(0.3), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var recoveryButton: some View {
        switch recovery {
        case .startServer:
            Button("Запустить LM Studio", action: onRecover)
                .buttonStyle(.borderedProminent)
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

#Preview("Считаю") {
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
        text: MockSummarizationProvider.sample,
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
