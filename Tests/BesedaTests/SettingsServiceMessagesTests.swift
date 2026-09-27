import Foundation
import Testing
@testable import Beseda

struct SettingsServiceMessagesTests {
    @Test func formattedResponsesAndFailures() {
        let en = Locale(identifier: "en_US")
        let ru = Locale(identifier: "ru_RU")
        #expect(SettingsText.webhookResponse(status: 200, action: "accepted", seconds: "1.2", locale: en) == "Service responded 200 · accepted in 1.2 seconds")
        #expect(SettingsText.webhookResponse(status: 200, action: nil, seconds: "1.2", locale: ru) == "Сервис ответил 200 за 1.2 с")
        #expect(SettingsText.serviceFailure("Сервер ответил 503", locale: en).contains("Check the server"))
        #expect(SettingsText.serviceFailure("Сервер ответил 503", locale: ru).contains("Проверьте сервер"))
        #expect(SettingsText.serviceFailure("Микрофон не доступен", locale: en).contains("System Settings"))
        #expect(SettingsText.serviceFailure("Файл модели повреждён при скачивании", locale: en).contains("Retry"))
        #expect(SettingsText.webhookMessage("Сервис отклонил запрос: HTTP 403", locale: en) == "Service rejected the request: HTTP 403")
        #expect(SettingsText.serviceFailure("upstream diagnostic: xyz", locale: en) == "upstream diagnostic: xyz")
    }
}
