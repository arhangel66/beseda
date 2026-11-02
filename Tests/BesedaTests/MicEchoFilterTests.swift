import Foundation
import Testing

@testable import Beseda

/// a sentence whose words start `start`, `start + 0.3`, … in order
private func makeSentence(_ text: String, at start: Double) -> TranscriptSegment {
    let words = text.split(separator: " ").enumerated().map { index, word in
        TranscriptWord(start: start + Double(index) * 0.3, end: start + Double(index) * 0.3 + 0.25, text: String(word))
    }
    return TranscriptSegment(start: start, end: words.last!.end, text: text, confidence: nil, words: words)
}

@Test func aSystemSentenceRepeatingTheMicHalfASecondLaterIsDropped() {
    let mic = [makeSentence("Uh, my name is Michael, and uh you", at: 10.0)]
    let system = [makeSentence("Uh, my name is Michael, and you", at: 10.5), makeSentence("Nice to meet you, Michael.", at: 14.0)]

    let kept = MicEchoFilter.systemSegmentsWithoutMicEcho(system, microphone: mic)

    #expect(kept.map(\.text) == ["Nice to meet you, Michael."])
}

@Test func theOtherPersonRepeatingAPhraseTwoSecondsLaterIsKept() {
    let mic = [makeSentence("Hello, yes, can you hear me?", at: 0.4)]
    let system = [makeSentence("Yes, can you hear me fine?", at: 3.4)]

    let kept = MicEchoFilter.systemSegmentsWithoutMicEcho(system, microphone: mic)

    #expect(kept == system)
}

@Test func theUserRepeatingTheOtherPersonIsNotTakenForEcho() {
    let system = [makeSentence("Update the reliability score.", at: 100.0)]
    let mic = [makeSentence("Yes, yes, update the reliability score.", at: 101.3)]

    let kept = MicEchoFilter.systemSegmentsWithoutMicEcho(system, microphone: mic)

    #expect(kept == system)
}

@Test func aShortRepeatedReplyIsKept() {
    let mic = [makeSentence("Да, да, да.", at: 5.0)]
    let system = [makeSentence("Да, да, да.", at: 5.4)]

    let kept = MicEchoFilter.systemSegmentsWithoutMicEcho(system, microphone: mic)

    #expect(kept == system)
}

@Test func aSystemSentenceWithoutWordTimesIsKept() {
    let mic = [makeSentence("I think I will start now", at: 1.0)]
    let system = [TranscriptSegment(start: 1.5, end: 3.0, text: "I think I will start now", confidence: nil, words: nil)]

    let kept = MicEchoFilter.systemSegmentsWithoutMicEcho(system, microphone: mic)

    #expect(kept == system)
}
