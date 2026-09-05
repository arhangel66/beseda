import Foundation
import Testing

@testable import Podushka

private func makeSegment(_ speaker: String, _ start: Double, _ end: Double, _ index: Int) -> StoredTranscriptSegment {
    StoredTranscriptSegment(speaker: speaker, startSec: start, endSec: end, text: "…", orderIndex: index)
}

@Test func lanesSplitTheCallBetweenTheTwoSides() {
    let segments = [
        makeSegment("me", 0, 30, 0),
        makeSegment("them", 30, 60, 1),
        makeSegment("me", 60, 100, 2)
    ]

    let lanes = SpeakerLane.build(from: segments, duration: 100, names: [:])

    #expect(lanes.map(\.speaker) == ["me", "them"])
    #expect(lanes[0].share == 0.7)
    #expect(lanes[1].share == 0.3)
}

@Test func sharesStillAddUpOnACallWithHundredsOfShortLines() {
    let segments = (0..<400).map { index in
        makeSegment(index.isMultiple(of: 2) ? "me" : "them", Double(index) * 5, Double(index) * 5 + 4, index)
    }

    let lanes = SpeakerLane.build(from: segments, duration: 2000, names: [:])
    let total = lanes.reduce(0) { $0 + $1.share }

    #expect(abs(total - 1) < 0.01)
}

@Test func aCallWithOnlyOneChannelDrawsOneLane() {
    let lanes = SpeakerLane.build(from: [makeSegment("me", 0, 10, 0)], duration: 10, names: [:])

    #expect(lanes.count == 1)
}

@Test func everyRemoteSpeakerGetsItsOwnLane() {
    let segments = [
        makeSegment("me", 0, 20, 0),
        makeSegment("them-1", 20, 50, 1),
        makeSegment("them-2", 50, 100, 2)
    ]

    let lanes = SpeakerLane.build(from: segments, duration: 100, names: ["them-2": "Ира"])

    #expect(lanes.map(\.speaker) == ["me", "them-1", "them-2"])
    #expect(lanes.map(\.label) == ["Вы", "Собеседник 1", "Ира"])
}

@Test func backToBackLinesOfOneSpeakerMergeIntoOneBar() {
    let segments = [
        makeSegment("me", 0, 10, 0),
        makeSegment("me", 10, 20, 1),
        makeSegment("them", 20, 30, 2),
        makeSegment("me", 30, 40, 3)
    ]

    let lanes = SpeakerLane.build(from: segments, duration: 40, names: [:])

    #expect(lanes[0].bars.map(\.start) == [0, 0.75])
    #expect(lanes[0].bars.map(\.width) == [0.5, 0.25])
    #expect(lanes[0].initial == "В")
}
