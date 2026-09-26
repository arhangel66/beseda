import Foundation
import Testing

@testable import Beseda

private let openRouter = URL(string: "https://openrouter.ai/api/v1")!

@Test func theRequestCarriesTheKeyAsABearerHeaderWhenThereIsOne() throws {
    let request = try ChatCompletionsProvider.request(
        baseURL: openRouter, model: "google/gemini-3.8-flash", prompt: "п", text: "т",
        apiKey: "sk-or-v1-secret", timeout: 60
    )

    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-or-v1-secret")
    #expect(request.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
}

@Test func theRequestGoesOutWithoutAnAuthorizationHeaderToALocalServer() throws {
    let request = try ChatCompletionsProvider.request(
        baseURL: URL(string: "http://127.0.0.1:8734/v1")!, model: "gemma-4-e4b", prompt: "п", text: "т",
        apiKey: nil, timeout: 60
    )

    #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
}

@Test func theRequestAsksForTheWholeSummaryAtOnce() throws {
    let request = try ChatCompletionsProvider.request(
        baseURL: openRouter, model: "m", prompt: "инструкция", text: "Вы: привет", apiKey: nil, timeout: 60
    )
    let body = try #require(request.httpBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(json["max_tokens"] as? Int == ChatCompletionsProvider.maxTokens)
    #expect(json["stream"] as? Bool == false)
    #expect(json["temperature"] as? Double == 0.3)
    let messages = try #require(json["messages"] as? [[String: String]])
    #expect(messages.map { $0["role"] } == ["system", "user"])
    #expect(messages.first?["content"] == "инструкция")
}

@Test func parseReturnsTrimmedContentFromANormalAnswer() throws {
    let json = Data("""
        {"choices": [{"message": {"content": "  саммари готово  "}}]}
        """.utf8)

    #expect(try ChatCompletionsProvider.parse(json, status: 200, serviceName: "OpenRouter") == "саммари готово")
}

@Test func parseThrowsTheServerMessageOnAnErrorBody() {
    let json = Data("""
        {"error": {"message": "что-то пошло не так"}}
        """.utf8)

    do {
        _ = try ChatCompletionsProvider.parse(json, status: 500, serviceName: "OpenRouter")
        Issue.record("ожидалась ошибка unavailable")
    } catch SummarizationError.unavailable(let message) {
        #expect(message == "что-то пошло не так")
    } catch {
        Issue.record("неожиданная ошибка: \(error)")
    }
}

@Test func parseTreatsEmptyChoicesAsAnUnavailableModel() {
    let json = Data("""
        {"choices": []}
        """.utf8)

    do {
        _ = try ChatCompletionsProvider.parse(json, status: 200, serviceName: "OpenRouter")
        Issue.record("ожидалась ошибка unavailable")
    } catch SummarizationError.unavailable(let message) {
        #expect(message == "Модель вернула пустой ответ")
    } catch {
        Issue.record("неожиданная ошибка: \(error)")
    }
}

@Test func parseTellsARefusedKeyApartFromAnyOtherFailure() {
    for status in [401, 402, 403] {
        do {
            let response = Data("""
                {"error": {"message": "remote implementation detail"}}
                """.utf8)
            _ = try ChatCompletionsProvider.parse(response, status: status, serviceName: "OpenRouter")
            Issue.record("ожидалась ошибка unauthorized для \(status)")
        } catch SummarizationError.unauthorized(let message) {
            #expect(message == "Ключ OpenRouter не принят")
        } catch {
            Issue.record("неожиданная ошибка: \(error)")
        }
    }
}

@Test func aServerThatDoesNotAnswerIsReportedAsDownAndNamed() async {
    let provider = ChatCompletionsProvider(
        baseURL: URL(string: "http://127.0.0.1:8734/v1")!,
        model: "gemma-4-e4b",
        prompt: "п",
        serviceName: "Встроенная модель",
        transport: { _ in throw URLError(.cannotConnectToHost) }
    )

    do {
        _ = try await provider.summarize(text: "Вы: привет")
        Issue.record("ожидалась ошибка serverDown")
    } catch SummarizationError.serverDown(let message) {
        #expect(message == "Встроенная модель не отвечает")
    } catch {
        Issue.record("неожиданная ошибка: \(error)")
    }
}

@Test func theErrorCardOffersTheWayOutThatMatchesTheFailure() {
    #expect(AppController.recovery(for: SummarizationError.emptyTranscript, provider: .builtIn, isLMStudioInstalled: true) == nil)
    #expect(AppController.recovery(for: SummarizationError.modelMissing, provider: .builtIn, isLMStudioInstalled: true) == .downloadModel)
    #expect(AppController.recovery(for: SummarizationError.unauthorized("нет ключа"), provider: .openRouter, isLMStudioInstalled: true) == .openSettings)
    #expect(AppController.recovery(for: SummarizationError.serverDown("молчит"), provider: .lmStudio, isLMStudioInstalled: true) == .startServer)
    #expect(AppController.recovery(for: SummarizationError.serverDown("молчит"), provider: .lmStudio, isLMStudioInstalled: false) == .openSettings)
    #expect(AppController.recovery(for: SummarizationError.serverDown("молчит"), provider: .builtIn, isLMStudioInstalled: true) == .openSettings)
}
