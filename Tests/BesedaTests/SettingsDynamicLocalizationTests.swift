import Foundation
import Testing
@testable import Beseda

struct SettingsDynamicLocalizationTests {
    @Test func dynamicFailuresAndPrivacy() {
        let en = Locale(identifier: "en_US")
        let ru = Locale(identifier: "ru_RU")
        let keys = [
            "Другое", "Встроенная модель", "Выбранный календарь не найден — выберите другой",
            "Нет доступа к календарю", EndpointRefusal.plainHTTP.rawValue,
            "Секрет не подошёл (401)", "Файл модели повреждён при скачивании",
            "в очереди", "ошибка", "Подготовка",
            "В приложении отсутствует движок итогов",
            "Работает без интернета. Называет исполнителей, но может пропустить одну договорённость или мелкое поручение."
        ]
        for key in keys {
            #expect(SettingsText.get(key, locale: en) != key)
            #expect(SettingsText.get(key, locale: ru) == key)
        }
        #expect(SettingsText.get("Нужен https: по http секрет и расшифровка идут открытым текстом (http — только для localhost)", locale: en).contains("secret and transcript"))
        #expect(SettingsText.get("Выбранный календарь не найден — выберите другой", locale: en).contains("Choose another"))
    }
}
