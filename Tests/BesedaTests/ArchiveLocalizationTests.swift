import Foundation
import Testing
@testable import Beseda

@Test func archiveSearchDeletionAndAccessibilityCopyAreLocalized() {
    let english = Locale(identifier: "en_US")
    let russian = Locale(identifier: "ru_RU")
    for (key, expected) in [
        ("Искать в разговорах", "Search calls"),
        ("Разговоров пока нет", "No calls yet"),
        ("Удалить разговор", "Delete call"),
        ("Остановить запись", "Stop recording"),
        ("Запись, расшифровка, итоги и копия в папке экспорта удалятся с этого Mac. Вернуть их не получится.", "The recording, transcript, summary, and copy in the export folder will be deleted from this Mac. They cannot be recovered.")
    ] {
        #expect(ArchiveText.get(key, locale: english) == expected)
        #expect(ArchiveText.get(key, locale: russian) == key)
    }
    #expect(String(format: ArchiveText.get("Удалить «%@»?", locale: english), "My call") == "Delete “My call”?")
    #expect(String(format: ArchiveText.get("Удалить «%@»?", locale: russian), "My call") == "Удалить «My call»?")
}
