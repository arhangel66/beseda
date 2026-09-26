import Foundation

/// Turns a stored call into the text a provider gets, and nothing else: the reader-facing
/// dialogue with renamed speakers already in it.
final class SummarizationService: Sendable {
    private let provider: SummarizationProvider
    /// ≈100k tokens at 3 chars/token, comfortably under a 131k-token context window
    private let characterBudget: Int

    init(provider: SummarizationProvider, characterBudget: Int = 300_000) {
        self.provider = provider
        self.characterBudget = characterBudget
    }

    func summarize(_ detail: StoredCallDetail) async throws -> String {
        // a call with no segments still renders its markdown, so the emptiness check is on the render
        let text = TranscriptCopy.render(detail, format: .clean)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SummarizationError.emptyTranscript
        }

        guard text.count > characterBudget else {
            return try await provider.summarize(text: text)
        }

        let summary = try await provider.summarize(text: Self.truncated(text, to: characterBudget))
        return "Пересказано только начало разговора — целиком в модель не поместилось.\n\n" + summary
    }

    /// cuts at the last newline before the limit so a line doesn't get chopped mid-sentence
    private static func truncated(_ text: String, to budget: Int) -> String {
        let cutoff = text.index(text.startIndex, offsetBy: budget)
        let prefix = text[..<cutoff]
        guard let lastNewline = prefix.lastIndex(of: "\n") else {
            return String(prefix)
        }
        return String(prefix[..<lastNewline])
    }
}

/// The one thing a summarizer has to do; tests put a spy here instead of a real model.
protocol SummarizationProvider: Sendable {
    func summarize(text: String) async throws -> String
}

/// The cases the error card offers a different way out of; everything else is `unavailable`.
enum SummarizationError: LocalizedError {
    case emptyTranscript
    /// the endpoint did not answer at all: LM Studio not started, llama-server not up
    case serverDown(String)
    /// the key was refused or has no credit left
    case unauthorized(String)
    /// the built-in model or its runtime is not downloaded yet
    case modelMissing

    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            "В этом разговоре нечего пересказывать: расшифровка пустая."
        case .modelMissing:
            "Встроенная модель ещё не скачана."
        case .serverDown(let message), .unauthorized(let message), .unavailable(let message):
            message
        }
    }
}

/// The shape a real summary should keep, shown in the summary pane's previews.
enum MockSummarizationProvider {
    /// No `#` headers on purpose: the pane renders inline markdown only and would show them as hashes.
    static let sample = """
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
}
