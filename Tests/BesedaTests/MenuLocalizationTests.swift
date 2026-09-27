import Foundation
import Testing
@testable import Beseda

@Test func menuRecordingAndRecoveryCopyFollowsLocale() {
    let english = Locale(identifier: "en_US")
    let russian = Locale(identifier: "ru_RU")
    #expect(MenuText.get("Начать запись", locale: english) == "Start recording")
    #expect(MenuText.get("Начать запись", locale: russian) == "Начать запись")
    #expect(MenuText.get("Продолжить", locale: english) == "Resume")
    #expect(MenuText.get("Остановить", locale: english) == "Stop")
    #expect(MenuText.get("Откройте Настройки → Обработка и скачайте модель", locale: english).contains("download a model"))
    #expect(MenuText.get("Отменить и удалить", locale: english) == "Cancel and delete")
    #expect(MenuText.get("Отменить и удалить", locale: russian) == "Отменить и удалить")
    #expect(MenuText.format("Запись остановлена: %@", "disk full", locale: english) == "Recording stopped: disk full")
    #expect(MenuText.format("Запись остановлена: %@", "диск заполнен", locale: russian) == "Запись остановлена: диск заполнен")
    #expect(MenuText.format("Уровень звука: %@", "microphone", locale: english) == "Audio level: microphone")
    #expect(MenuText.get("Черновик появится примерно через 20 секунд", locale: english).contains("20 seconds"))
}
