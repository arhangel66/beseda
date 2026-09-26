import Foundation
import Testing

@testable import Beseda

private func makeSegment(_ text: String, _ start: Double, _ end: Double) -> TranscriptSegment {
    TranscriptSegment(start: start, end: end, text: text, confidence: 1, words: nil)
}

@Test func turnsTakeTheDiarizerSegmentsAndTheirTimes() {
    let segments = [makeSegment("Ready when you are.", 0.1, 1.4), makeSegment("Go ahead.", 2.0, 2.9)]
    let timeline = [
        SpeakerInterval(speaker: "S7", start: 1.9, end: 3.0),
        SpeakerInterval(speaker: "S2", start: 0, end: 1.5)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns == [
        SpeakerTurn(speaker: "them-1", start: 0, end: 1.5, text: "Ready when you are."),
        SpeakerTurn(speaker: "them-2", start: 1.9, end: 3.0, text: "Go ahead.")
    ])
}

@Test func aSentenceGoesToTheSegmentItOverlapsMostAndSentencesOnOneSegmentJoin() {
    let segments = [makeSegment("So I think", 0.0, 1.0), makeSegment("yes exactly.", 1.1, 2.4)]
    let timeline = [
        SpeakerInterval(speaker: "S1", start: 0, end: 2.2),
        SpeakerInterval(speaker: "S2", start: 2.2, end: 2.5)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns == [SpeakerTurn(speaker: "them-1", start: 0, end: 2.2, text: "So I think yes exactly.")])
}

@Test func aSentenceOutsideDiarizerSpeechKeepsItsTimesAndTheNearestSpeaker() {
    let segments = [makeSegment("Hi", 0.1, 0.9), makeSegment("Ага", 2.0, 2.2)]
    let timeline = [
        SpeakerInterval(speaker: "S1", start: 0, end: 1.0),
        SpeakerInterval(speaker: "S2", start: 2.5, end: 4.0)
    ]

    let turns = SpeakerAssignment.remoteTurns(segments: segments, timeline: timeline)

    #expect(turns == [
        SpeakerTurn(speaker: "them-1", start: 0, end: 1.0, text: "Hi"),
        SpeakerTurn(speaker: "them-2", start: 2.0, end: 2.2, text: "Ага")
    ])
}

@Test func anEmptyTimelineProducesNoTurns() {
    #expect(SpeakerAssignment.remoteTurns(segments: [makeSegment("Hi", 0, 0.3)], timeline: []).isEmpty)
}
