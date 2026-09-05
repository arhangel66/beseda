import Foundation
import Testing

@testable import Podushka

private func makeSegment(_ text: String, words: [(Double, Double, String)]) -> TranscriptSegment {
    TranscriptSegment(
        start: words.first?.0 ?? 0,
        end: words.last?.1 ?? 0,
        text: text,
        confidence: 1,
        words: words.map { TranscriptWord(start: $0.0, end: $0.1, text: $0.2) }
    )
}

@Test func aCleanTurnSwitchGivesOneTurnPerSpeaker() {
    let segments = [
        makeSegment("Ready when you are.", words: [(0.0, 0.4, "Ready"), (0.4, 0.8, "when"), (0.8, 1.4, "you are.")]),
        makeSegment("Go ahead.", words: [(2.0, 2.4, "Go"), (2.4, 2.9, "ahead.")])
    ]
    let timeline = [
        SpeakerInterval(speaker: "S2", start: 0, end: 1.5),
        SpeakerInterval(speaker: "S7", start: 1.9, end: 3.0)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns.map(\.speaker) == ["them-1", "them-2"])
    #expect(turns.map(\.text) == ["Ready when you are.", "Go ahead."])
    #expect(turns[1].start == 2.0)
    #expect(turns[1].end == 2.9)
}

@Test func aSentenceSpanningASwitchIsSplitBetweenSpeakers() {
    let segments = [
        makeSegment(
            "So I think yes exactly.",
            words: [(0.0, 0.3, "So"), (0.3, 0.6, "I"), (0.6, 1.0, "think"), (1.6, 1.9, "yes"), (1.9, 2.4, "exactly.")]
        )
    ]
    let timeline = [
        SpeakerInterval(speaker: "S1", start: 0, end: 1.2),
        SpeakerInterval(speaker: "S2", start: 1.5, end: 2.5)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns.map(\.speaker) == ["them-1", "them-2"])
    #expect(turns.map(\.text) == ["So I think", "yes exactly."])
}

@Test func aWordInAGapTakesTheNearestSpeaker() {
    let segments = [makeSegment("Ага", words: [(2.0, 2.2, "Ага")])]
    let timeline = [
        SpeakerInterval(speaker: "S1", start: 0, end: 1.0),
        SpeakerInterval(speaker: "S2", start: 2.5, end: 4.0)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns.map(\.speaker) == ["them-1"])
    #expect(turns[0].text == "Ага")
}

@Test func aWordFarFromEverySpeakerKeepsThePreviousOne() {
    let segments = [
        makeSegment("Hi", words: [(0.1, 0.4, "Hi")]),
        makeSegment("Ага", words: [(9.0, 9.2, "Ага")])
    ]
    let timeline = [
        SpeakerInterval(speaker: "S1", start: 0, end: 1.0),
        SpeakerInterval(speaker: "S2", start: 20.0, end: 22.0)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns.map(\.speaker) == ["them-1", "them-1"])
    #expect(turns.map(\.text) == ["Hi", "Ага"])
}

@Test func aMonologueStaysOneLinePerSentence() {
    let segments = (0..<4).map { index in
        makeSegment(
            "Sentence \(index).",
            words: [(Double(index) * 10, Double(index) * 10 + 3, "Sentence"), (Double(index) * 10 + 3, Double(index) * 10 + 5, "\(index).")]
        )
    }
    let timeline = [SpeakerInterval(speaker: "S1", start: 0, end: 40)]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns.count == 4)
    #expect(turns.allSatisfy { $0.speaker == "them-1" })
    #expect(turns[2].text == "Sentence 2.")
}

@Test func aWordBeforeAnySpeakerIntervalTakesTheFirstSpeaker() {
    let segments = [makeSegment("Hey guys", words: [(0.0, 0.3, "Hey"), (0.3, 0.7, "guys")])]
    let timeline = [
        SpeakerInterval(speaker: "S4", start: 5.0, end: 8.0),
        SpeakerInterval(speaker: "S1", start: 2.0, end: 4.0)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns.map(\.speaker) == ["them-1"])
    #expect(turns[0].text == "Hey guys")
}

@Test func segmentsWithoutWordsStillProduceTurns() {
    let segments = [
        TranscriptSegment(start: 0, end: 1.0, text: "Раз", confidence: 1, words: nil),
        TranscriptSegment(start: 2.0, end: 3.0, text: "Два", confidence: 1, words: nil)
    ]
    let timeline = [
        SpeakerInterval(speaker: "S1", start: 0, end: 1.2),
        SpeakerInterval(speaker: "S2", start: 1.8, end: 3.2)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns.map(\.speaker) == ["them-1", "them-2"])
    #expect(turns.map(\.text) == ["Раз", "Два"])
}

@Test func anEmptyTimelineProducesNoTurns() {
    let segments = [makeSegment("Hi", words: [(0.0, 0.3, "Hi")])]

    #expect(SpeakerAssignment.remoteTurns(segments: segments, timeline: []).isEmpty)
}
