import Foundation
import Testing

@testable import Podushka

@Test func aCallRecordedBeforeDiarizationKeepsTheUnnumberedName() {
    #expect(SpeakerNaming.defaultName(for: "them") == "Собеседник")
    #expect(SpeakerNaming.initial(for: "them", overrides: [:]) == "С")
}

@Test func numberedSpeakersCarryTheirNumberIntoTheAvatar() {
    #expect(SpeakerNaming.defaultName(for: "them-3") == "Собеседник 3")
    #expect(SpeakerNaming.initial(for: "them-3", overrides: [:]) == "3")
}

@Test func aRenameReplacesBothTheNameAndTheAvatarLetter() {
    let overrides = ["them-2": "Игорь"]

    #expect(SpeakerNaming.name(for: "them-2", overrides: overrides) == "Игорь")
    #expect(SpeakerNaming.initial(for: "them-2", overrides: overrides) == "И")
}
