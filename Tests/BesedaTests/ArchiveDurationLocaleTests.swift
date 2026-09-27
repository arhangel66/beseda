import Foundation
import Testing
@testable import Beseda

@Test func archiveDurationUsesExplicitLocale() {
    let english = Locale(identifier: "en_US")
    let russian = Locale(identifier: "ru_RU")
    for (seconds, ru) in [(42.0, "42 сек"), (214.0, "4 мин"), (3900.0, "1 ч 5 мин")] {
        #expect(CallFormatting.humanDuration(seconds, locale: russian) == ru)
        let en = CallFormatting.humanDuration(seconds, locale: english)
        #expect(!en.isEmpty)
        #expect(!en.contains("сек") && !en.contains("мин") && !en.contains(" ч"))
    }
}
