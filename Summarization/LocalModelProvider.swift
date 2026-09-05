import Foundation

/// Talks to a locally running LM Studio server over its OpenAI-compatible chat completions API.
struct LocalModelProvider: SummarizationProvider, Sendable {
    let baseURL: URL
    let model: String
    let prompt: String
    var timeout: TimeInterval = 180

    /// no `#` headers on purpose: the pane renders inline markdown only and would show them as hashes
    static let defaultPrompt = """
        Прочитай расшифровку созвона и напиши по-русски краткое саммари. Без вступления и без \
        заголовков `#` — только жирный текст и переносы. Ровно четыре раздела в этом порядке:

        **О чём говорили**
        Пара предложений о теме разговора.

        **Главное**
        — ключевые факты и договорённости, каждый с новой строки

        **Что делать**
        — кто и что должен сделать дальше

        **Открытые вопросы**
        — то, что осталось нерешённым
        """

    func summarize(text: String) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(
            ChatRequestBody(
                model: model,
                messages: [
                    ChatMessage(role: "system", content: prompt),
                    ChatMessage(role: "user", content: text)
                ],
                temperature: 0.3,
                stream: false
            )
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw SummarizationError.unavailable("Модель думает дольше \(Int(timeout)) с")
        } catch {
            throw SummarizationError.unavailable("LM Studio не отвечает на \(Self.hostAndPort(baseURL))")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        return try Self.parse(data, status: status)
    }

    /// the only part of the exchange that touches raw JSON, kept pure so tests can hit it directly
    static func parse(_ data: Data, status: Int) throws -> String {
        if (200..<300).contains(status) {
            let content = (try? JSONDecoder().decode(ChatCompletionResponse.self, from: data))?
                .choices.first?.message.content?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let content, !content.isEmpty else {
                throw SummarizationError.unavailable("Модель вернула пустой ответ")
            }
            return content
        }

        let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error?.message
        throw SummarizationError.unavailable(message ?? "LM Studio ответил кодом \(status)")
    }

    private static func hostAndPort(_ url: URL) -> String {
        "\(url.host ?? "localhost"):\(url.port ?? 1234)"
    }
}

private struct ChatRequestBody: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let stream: Bool
}

private struct ChatMessage: Encodable {
    let role: String
    let content: String
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }
        let message: Message
    }
    let choices: [Choice]
}

private struct ErrorResponse: Decodable {
    struct ErrorPayload: Decodable {
        let message: String?
    }
    let error: ErrorPayload?
}
