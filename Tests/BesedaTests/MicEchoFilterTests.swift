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

    let echo = MicEchoFilter.echoSentences(system, microphone: mic)

    #expect(echo == [system[0]])
}

@Test func theOtherPersonRepeatingAPhraseTwoSecondsLaterIsKept() {
    let mic = [makeSentence("Hello, yes, can you hear me?", at: 0.4)]
    let system = [makeSentence("Yes, can you hear me fine?", at: 3.4)]

    let echo = MicEchoFilter.echoSentences(system, microphone: mic)

    #expect(echo.isEmpty)
}

@Test func theUserRepeatingTheOtherPersonIsNotTakenForEcho() {
    let system = [makeSentence("Update the reliability score.", at: 100.0)]
    let mic = [makeSentence("Yes, yes, update the reliability score.", at: 101.3)]

    let echo = MicEchoFilter.echoSentences(system, microphone: mic)

    #expect(echo.isEmpty)
}

@Test func aShortRepeatedReplyIsKept() {
    let mic = [makeSentence("Да, да, да.", at: 5.0)]
    let system = [makeSentence("Да, да, да.", at: 5.4)]

    let echo = MicEchoFilter.echoSentences(system, microphone: mic)

    #expect(echo.isEmpty)
}

@Test func aSystemSentenceWithoutWordTimesIsKept() {
    let mic = [makeSentence("I think I will start now", at: 1.0)]
    let system = [TranscriptSegment(start: 1.5, end: 3.0, text: "I think I will start now", confidence: nil, words: nil)]

    let echo = MicEchoFilter.echoSentences(system, microphone: mic)

    #expect(echo.isEmpty)
}

@Test func aRemoteVoiceThatAlsoLeaksIntoTheMicIsNotTakenForEcho() {
    let mic = [makeSentence("Так что сейчас она тебе скажет", at: 5.0)]
    let system = [makeSentence("Так что сейчас она тебе скажет", at: 5.2)]

    let echo = MicEchoFilter.echoSentences(system, microphone: mic)

    #expect(echo.isEmpty)
}

@Test func aSpeakerMostlyMadeOfEchoIsDroppedWholeAndTheRestRenumbered() {
    let echoed = makeSentence("my name is Michael", at: 3.0)
    let turns = [
        SpeakerTurn(speaker: "them-1", start: 0.0, end: 1.0, text: "Hello there, Michael."),
        SpeakerTurn(speaker: "them-2", start: 2.0, end: 2.3, text: "Okay."),
        SpeakerTurn(speaker: "them-2", start: echoed.start, end: echoed.end, text: echoed.text),
        SpeakerTurn(speaker: "them-3", start: 6.0, end: 7.0, text: "Nice to meet you.")
    ]

    let kept = MicEchoFilter.turnsWithoutMicEcho(turns, echo: [echoed])

    #expect(kept == [
        SpeakerTurn(speaker: "them-1", start: 0.0, end: 1.0, text: "Hello there, Michael."),
        SpeakerTurn(speaker: "them-2", start: 6.0, end: 7.0, text: "Nice to meet you.")
    ])
}

@Test func aRealSpeakerLosesOnlyItsEchoLine() {
    let echoed = makeSentence("can you see my screen", at: 9.0)
    let turns = [
        SpeakerTurn(speaker: "them-1", start: 0.0, end: 8.0, text: "So the release went fine and the queue is empty now, nothing else from me today."),
        SpeakerTurn(speaker: "them-1", start: echoed.start, end: echoed.end, text: echoed.text)
    ]

    let kept = MicEchoFilter.turnsWithoutMicEcho(turns, echo: [echoed])

    #expect(kept == [turns[0]])
}
