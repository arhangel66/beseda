import Foundation
import Testing

@testable import Beseda

private func words(_ items: [(String, Double, Double)]) -> [TranscriptWord] {
    items.map { TranscriptWord(start: $0.1, end: $0.2, text: $0.0) }
}

@Test func sentenceEndingWordClosesASegment() {
    let segments = SentenceBuilder.segments(from: words([
        ("Привет,", 0.0, 0.3),
        ("как", 0.3, 0.5),
        ("дела?", 0.5, 0.9),
        ("Нормально.", 1.0, 1.5)
    ]))

    #expect(segments.count == 2)
    #expect(segments[0].text == "Привет, как дела?")
    #expect(segments[1].text == "Нормально.")
}

@Test func longPauseClosesASegmentWithoutPunctuation() {
    let segments = SentenceBuilder.segments(from: words([
        ("раз", 0.0, 0.3),
        ("два", 0.3, 0.6),
        ("три", 4.0, 4.3)
    ]), silenceGap: 1.0)

    #expect(segments.map(\.text) == ["раз два", "три"])
}

@Test func wordLimitClosesASegment() {
    let stream = (0..<7).map { ("сло\($0)", Double($0) * 0.2, Double($0) * 0.2 + 0.1) }
    let segments = SentenceBuilder.segments(from: words(stream), silenceGap: 10, maxWords: 3)

    #expect(segments.map { $0.words?.count } == [3, 3, 1])
}

@Test func segmentBoundsFollowTheFirstAndLastWord() {
    let segments = SentenceBuilder.segments(from: words([
        ("Один", 1.25, 1.5),
        ("два.", 1.5, 2.75)
    ]))

    #expect(segments.count == 1)
    #expect(segments[0].start == 1.25)
    #expect(segments[0].end == 2.75)
    #expect(segments[0].words?.count == 2)
}

@Test func emptyInputYieldsNoSegments() {
    #expect(SentenceBuilder.segments(from: []).isEmpty)
}

@Test func trailingWordsWithoutPunctuationStillBecomeASegment() {
    let segments = SentenceBuilder.segments(from: words([
        ("Готово.", 0.0, 0.5),
        ("а", 0.6, 0.7),
        ("дальше", 0.7, 1.0)
    ]))

    #expect(segments.map(\.text) == ["Готово.", "а дальше"])
}
