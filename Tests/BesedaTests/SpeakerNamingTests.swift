import Foundation
import Testing

@testable import Beseda

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

@Test func pipelineSpeakerIdsMapToDistinctNamesAndColours() {
    let mic = TranscriptChannel.microphone.speakerID
    let remote = TranscriptChannel.systemAudio.speakerID

    let names = [mic, remote, "them-2"].map { SpeakerNaming.initial(for: $0, overrides: [:]) + SpeakerNaming.defaultName(for: $0) }
    let bars = [mic, remote, "them-2"].map { SpeakerStyle.of(speaker: $0).bar }

    #expect(names == ["ВВы", "ССобеседник", "2Собеседник 2"])
    #expect(bars[0] == SpeakerStyle.mine.bar)
    #expect(Set(bars).count == 3)
}
