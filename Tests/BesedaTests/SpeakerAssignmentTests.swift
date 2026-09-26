import Foundation
import Testing

@testable import Beseda

private func makeSegment(_ text: String, _ start: Double, _ end: Double) -> TranscriptSegment {
    TranscriptSegment(start: start, end: end, text: text, confidence: 1, words: nil)
}

@Test func turnsTakeTheDiarizerSpeakersAndKeepSentenceTimes() {
    let segments = [makeSegment("Ready when you are.", 0.1, 1.4), makeSegment("Go ahead.", 7.0, 7.9)]
    let timeline = [
        SpeakerInterval(speaker: "S7", start: 6.5, end: 13.0),
        SpeakerInterval(speaker: "S2", start: 0, end: 6.0)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns == [
        SpeakerTurn(speaker: "them-1", start: 0.1, end: 1.4, text: "Ready when you are."),
        SpeakerTurn(speaker: "them-2", start: 7.0, end: 7.9, text: "Go ahead.")
    ])
}

@Test func aSentenceTakesTheSpeakerOfTheSegmentItOverlapsMost() {
    let segments = [makeSegment("So I think", 0.0, 1.0), makeSegment("yes exactly.", 1.1, 2.4)]
    let timeline = [
        SpeakerInterval(speaker: "S1", start: 0, end: 2.2),
        SpeakerInterval(speaker: "S2", start: 2.2, end: 2.5)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns == [
        SpeakerTurn(speaker: "them-1", start: 0.0, end: 1.0, text: "So I think"),
        SpeakerTurn(speaker: "them-1", start: 1.1, end: 2.4, text: "yes exactly.")
    ])
}

@Test func aLongSingleSpeakerSegmentKeepsOneLinePerSentence() {
    let segments = [makeSegment("One.", 0.5, 2.0), makeSegment("Two.", 2.5, 4.0), makeSegment("Three.", 4.5, 6.0)]
    let timeline = [SpeakerInterval(speaker: "S3", start: 0, end: 60)]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns.map(\.start) == [0.5, 2.5, 4.5])
    #expect(turns.map(\.speaker) == ["them-1", "them-1", "them-1"])
}

@Test func aSentenceOutsideDiarizerSpeechKeepsItsTimesAndTheNearestSpeaker() {
    let segments = [makeSegment("Hi", 0.1, 0.9), makeSegment("Ага", 7.5, 7.7)]
    let timeline = [
        SpeakerInterval(speaker: "S1", start: 0, end: 6.0),
        SpeakerInterval(speaker: "S2", start: 8.5, end: 15.0)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns == [
        SpeakerTurn(speaker: "them-1", start: 0.1, end: 0.9, text: "Hi"),
        SpeakerTurn(speaker: "them-2", start: 7.5, end: 7.7, text: "Ага")
    ])
}

@Test func anEmptyTimelineProducesNoTurns() {
    #expect(SpeakerAssignment.remoteTurns(segments: [makeSegment("Hi", 0, 0.3)], timeline: []).isEmpty)
}

@Test func aOneSpeakerCallIsUnchanged() {
    let segments = [makeSegment("Hi.", 0, 1), makeSegment("Bye.", 2, 3)]
    let timeline = [SpeakerInterval(speaker: "S4", start: 0, end: 1), SpeakerInterval(speaker: "S4", start: 2, end: 3)]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns == [
        SpeakerTurn(speaker: "them-1", start: 0, end: 1, text: "Hi."),
        SpeakerTurn(speaker: "them-1", start: 2, end: 3, text: "Bye.")
    ])
}
