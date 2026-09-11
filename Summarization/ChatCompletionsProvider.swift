import Foundation

/// Talks to an OpenAI-compatible `chat/completions` endpoint. One request shape serves all
/// three providers — LM Studio, the bundled llama-server and OpenRouter — so only the base
/// URL, the model, the key and the name used in error messages differ.
struct ChatCompletionsProvider: SummarizationProvider, Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    let baseURL: URL
    let model: String
    let prompt: String
    /// nil for the local servers, which take any request
    var apiKey: String?
    /// what the error messages call this endpoint, e.g. «OpenRouter» or «LM Studio на localhost:1234»
    var serviceName: String
    var timeout: TimeInterval = 180
    var transport: Transport = { try await URLSession.shared.data(for: $0) }

    /// Bold on the section names only: the earlier «только жирный текст» made small models
    /// write every line bold (docs/summary-model-choice-plan.md). No `#` headers either,
    /// the pane renders inline markdown and would show them as hashes.
    static let defaultPrompt = """
        Прочитай расшифровку созвона и напиши по-русски краткое саммари. Без вступления и без \
        заголовков `#`. Жирным выделяй только названия четырёх разделов, остальной текст обычный. \
        Ровно четыре раздела в этом порядке:

        **О чём говорили**
        Пара предложений о теме разговора.

        **Главное**
        — ключевые факты и договорённости, каждый с новой строки, строка начинается с «—»

        **Что делать**
        — кто и что должен сделать дальше

        **Открытые вопросы**
        — то, что осталось нерешённым
        """

    /// room for the longest four-section summary measured; without a limit OpenRouter spends
    /// the budget on reasoning tokens and cuts the answer off mid-sentence
    static let maxTokens = 4096

    func summarize(text: String) async throws -> String {
        let request = try Self.request(
            baseURL: baseURL, model: model, prompt: prompt, text: text, apiKey: apiKey, timeout: timeout
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError where error.code == .timedOut {
            throw SummarizationError.unavailable("Модель думает дольше \(Int(timeout)) с")
        } catch {
            throw SummarizationError.serverDown("\(serviceName) не отвечает")
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        return try Self.parse(data, status: status, serviceName: serviceName)
    }

    static func request(
        baseURL: URL, model: String, prompt: String, text: String, apiKey: String?, timeout: TimeInterval
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = timeout
        request.httpBody = try JSONEncoder().encode(
            ChatRequestBody(
                model: model,
                messages: [
                    ChatMessage(role: "system", content: prompt),
                    ChatMessage(role: "user", content: text)
                ],
                temperature: 0.3,
                maxTokens: maxTokens,
                stream: false
            )
        )
        return request
    }

    /// the only part of the exchange that touches raw JSON, kept pure so tests can hit it directly
    static func parse(_ data: Data, status: Int, serviceName: String) throws -> String {
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
        // 402 is OpenRouter's «no credit left»; both it and 401 are fixed in the same field
        if [401, 402, 403].contains(status) {
            throw SummarizationError.unauthorized("Ключ \(serviceName) не принят")
        }
        throw SummarizationError.unavailable(message ?? "\(serviceName) ответил кодом \(status)")
    }
}

private struct ChatRequestBody: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
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
