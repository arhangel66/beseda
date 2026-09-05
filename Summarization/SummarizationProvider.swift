import Foundation

/// The one thing a summarizer has to do. The mock below and the real model behind an API
/// both fit here, and swapping them is a single line in AppController.
protocol SummarizationProvider: Sendable {
    func summarize(text: String) async throws -> String
}

enum SummarizationError: LocalizedError {
    case emptyTranscript
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyTranscript:
            "В этом разговоре нечего пересказывать: расшифровка пустая."
        case .unavailable(let message):
            message
        }
    }
}

/// Stands in for the model until there is one: waits long enough for the spinner to be
/// worth looking at, then returns the shape a real summary should keep.
struct MockSummarizationProvider: SummarizationProvider {
    /// long enough to see the spinner, short enough not to be annoying; set to 0 when the wait stops teaching anything
    static let thinkingDuration: Duration = .milliseconds(1500)

    let failsOnPurpose: Bool

    func summarize(text: String) async throws -> String {
        try await Task.sleep(for: Self.thinkingDuration)

        if failsOnPurpose {
            throw SummarizationError.unavailable("LM Studio не отвечает на localhost:1235")
        }

        return Self.sample
    }

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
