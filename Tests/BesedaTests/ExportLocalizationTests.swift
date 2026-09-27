import Foundation
import Testing
@testable import Beseda

@Test func generatedExportLabelsAndNamesFollowExplicitLocale() {
    let english = Locale(identifier: "en_US")
    let russian = Locale(identifier: "ru_RU")
    #expect(ExportText.get("Тип:", locale: english) == "Type:")
    #expect(ExportText.get("Тип:", locale: russian) == "Тип:")
    #expect(SpeakerNaming.defaultName(for: "me", locale: english) == "You")
    #expect(SpeakerNaming.defaultName(for: "them-2", locale: english) == "Other speaker 2")
    #expect(SpeakerNaming.name(for: "them", overrides: ["them": "Ира"], locale: english) == "Ира")
    #expect(SpeakerNaming.defaultName(for: "them", locale: russian) == "Собеседник")
    #expect(TranscriptCopyFormat.clean.title(locale: english) == "Plain transcript")
    #expect(TranscriptCopyFormat.clean.sample(locale: english) == "You: …")
}

@Test func displayDatesFollowLocaleWhileFileDatesRemainStable() {
    let date = Date(timeIntervalSince1970: 1_787_990_880)
    let english = Locale(identifier: "en_US")
    let russian = Locale(identifier: "ru_RU")
    let en = CallFormatting.when(date, now: date, locale: english)
    let ru = CallFormatting.when(date, now: date, locale: russian)
    #expect(en.hasPrefix("today, "))
    #expect(ru.hasPrefix("сегодня, "))
    #expect(en != ru)
    #expect(CallFormatting.when(date.addingTimeInterval(-86_400), now: date, locale: english).hasPrefix("yesterday, "))
}
