import Foundation
import Testing

@testable import Podushka

@Test func parseReturnsTrimmedContentFromANormalAnswer() throws {
    let json = Data("""
        {"choices": [{"message": {"content": "  саммари готово  "}}]}
        """.utf8)

    #expect(try LocalModelProvider.parse(json, status: 200) == "саммари готово")
}

@Test func parseThrowsTheServerMessageOnAnErrorBody() {
    let json = Data("""
        {"error": {"message": "что-то пошло не так"}}
        """.utf8)

    do {
        _ = try LocalModelProvider.parse(json, status: 500)
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
        _ = try LocalModelProvider.parse(json, status: 200)
        Issue.record("ожидалась ошибка unavailable")
    } catch SummarizationError.unavailable(let message) {
        #expect(message == "Модель вернула пустой ответ")
    } catch {
        Issue.record("неожиданная ошибка: \(error)")
    }
}
