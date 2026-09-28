import Foundation
import Testing
@testable import Beseda

@Test func archiveDetailAndRecoveryLabelsAreLocalized() {
    let english = Locale(identifier: "en_US")
    let russian = Locale(identifier: "ru_RU")
    for (key, expected) in [
        ("Расшифровка", "Transcript"),
        ("Итоги", "Summary"),
        ("Сведения", "Info"),
        ("Отправка на сервис", "Service delivery"),
        ("Скопировать результат", "Copy result"),
        ("Расшифровать снова", "Transcribe again"),
        ("Аудио удалено по правилу хранения", "Audio was deleted under the retention policy"),
        ("Позиция воспроизведения", "Playback position"),
        ("Переименовать участника", "Rename participant"),
        ("Обработка прервалась при перезапуске приложения", "Processing was interrupted when the app restarted"),
        ("Найдена на диске без записи в индексе", "Found on disk but missing from call index")
    ] {
        #expect(ArchiveText.get(key, locale: english) == expected)
        #expect(ArchiveText.get(key, locale: russian) == key)
    }
    let legacy = "Обработка прервалась при перезапуске приложения"
    #expect(ArchiveText.displayError(legacy, locale: english) == "Processing was interrupted when the app restarted")
    #expect(ArchiveText.displayError(legacy, locale: russian) == legacy)
    #expect(ArchiveText.displayError("Движок распознавания не установлен", locale: english) == "Speech recognition engine is not installed")
    #expect(ArchiveText.displayError("User-authored error", locale: english) == "User-authored error")
    #expect(ArchiveText.format("Перейти к %@", "01:23", locale: english) == "Jump to 01:23")
}
