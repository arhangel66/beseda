import Foundation
import Testing
@testable import Beseda

struct SettingsLocalizationTests {
    @Test func modelStatesAndLanguageChoices() {
        let english = Locale(identifier: "en_US")
        let russian = Locale(identifier: "ru_RU")
        #expect(SettingsText.get("Готова", locale: english) == "Ready")
        #expect(SettingsText.get("Выбрана · не скачана", locale: english) == "Selected · not downloaded")
        #expect(SettingsText.get("Скачана", locale: russian) == "Скачана")
        #expect(SettingsText.get("25 языков", locale: english) == "25 languages")
        #expect(SettingsText.get("только русский", locale: english) == "Russian only")
    }

    @Test func privacyDestructionAndAccessibility() {
        let english = Locale(identifier: "en_US")
        let russian = Locale(identifier: "ru_RU")
        for key in ["Включить строгий режим?", "Включить и удалять аудио",
                    "Аудио уже расшифрованных записей удалится при следующей очистке, а новое — сразу после расшифровки. Удалённое аудио не вернуть, даже если выключить режим.",
                    "Папка в iCloud Drive: экспорт уходит в облако Apple.", "Скрыть", "Удалить"] {
            #expect(SettingsText.get(key, locale: english) != key)
            #expect(SettingsText.get(key, locale: russian) == key)
        }
        #expect(String(format: SettingsText.get("Download %@", locale: english), "Parakeet v3") == "Download Parakeet v3")
    }
}
