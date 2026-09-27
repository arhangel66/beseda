import Foundation
import Testing

@testable import Beseda

@Test func aCallRecordedBeforeDiarizationKeepsTheUnnumberedName() {
    #expect(SpeakerNaming.defaultName(for: "them", locale: Locale(identifier: "ru_RU")) == "Собеседник")
    #expect(SpeakerNaming.defaultName(for: "them", locale: Locale(identifier: "en_US")) == "Other speaker")
    #expect(SpeakerNaming.initial(for: "them", overrides: [:]) == String(SpeakerNaming.defaultName(for: "them").prefix(1)))
}

@Test func numberedSpeakersCarryTheirNumberIntoTheAvatar() {
    #expect(SpeakerNaming.defaultName(for: "them-3", locale: Locale(identifier: "ru_RU")) == "Собеседник 3")
    #expect(SpeakerNaming.defaultName(for: "them-3", locale: Locale(identifier: "en_US")) == "Other speaker 3")
    #expect(SpeakerNaming.initial(for: "them-3", overrides: [:]) == "3")
}

@Test func aRenameReplacesBothTheNameAndTheAvatarLetter() {
    let overrides = ["them-2": "Игорь"]

    #expect(SpeakerNaming.name(for: "them-2", overrides: overrides) == "Игорь")
    #expect(SpeakerNaming.initial(for: "them-2", overrides: overrides) == "И")
}

@Test func pipelineSpeakerIdsMapToDistinctNamesAndColours() {
    let mic = TranscriptChannel.microphone.speakerID
    let remote = TranscriptChannel.systemAudio.speakerID

    let speakers = [mic, remote, "them-2"]
    let names = speakers.map { SpeakerNaming.defaultName(for: $0, locale: Locale(identifier: "ru_RU")) }
    let englishNames = speakers.map { SpeakerNaming.defaultName(for: $0, locale: Locale(identifier: "en_US")) }
    let bars = [mic, remote, "them-2"].map { SpeakerStyle.of(speaker: $0).bar }

    #expect(names == ["Вы", "Собеседник", "Собеседник 2"])
    #expect(englishNames == ["You", "Other speaker", "Other speaker 2"])
    #expect(SpeakerNaming.initial(for: "them-2", overrides: [:]) == "2")
    #expect(bars[0] == SpeakerStyle.mine.bar)
    #expect(Set(bars).count == 3)
}

@Test func anUnknownSpeakerKeyNeverShowsUpAsItsName() {
    #expect(SpeakerNaming.defaultName(for: "t", locale: Locale(identifier: "ru_RU")) == "Участник")
    #expect(SpeakerNaming.defaultName(for: "t", locale: Locale(identifier: "en_US")) == "Participant")
    #expect(SpeakerNaming.initial(for: "t", overrides: [:]) == String(SpeakerNaming.defaultName(for: "t").prefix(1)))
}
