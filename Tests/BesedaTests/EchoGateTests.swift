import Foundation
import Testing

@testable import Beseda

private let sampleRate = 16_000

/// 4 s: the remote side talks for 0–2 s, "me" for 2.5–3.5 s; the mic hears the remote side at −20 dB, 60 ms late
private func makeCall() -> (mic: [Float], system: [Float]) {
    var generator = SystemRandomNumberGenerator()
    let count = 4 * sampleRate
    let system = (0..<count).map { index in
        index < 2 * sampleRate ? Float.random(in: -0.5...0.5, using: &generator) : Float.random(in: -0.0005...0.0005, using: &generator)
    }
    let delay = 960
    let mic = (0..<count).map { index in
        let echo = index >= delay ? 0.1 * system[index - delay] : 0
        let own: Float = (40_000..<56_000).contains(index) ? 0.3 * sin(Float(index) * 0.2) : 0
        return echo + own + Float.random(in: -0.0005...0.0005, using: &generator)
    }
    return (mic, system)
}

@Test func theEchoLagIsFound() {
    let call = makeCall()

    #expect(EchoGate.echoLag(mic: call.mic, system: call.system) == 960)
}

@Test func echoOnlySentencesAreDroppedAndOwnSpeechIsKept() {
    let call = makeCall()
    let segments = [
        TranscriptSegment(start: 0.2, end: 1.8, text: "echo of them", confidence: 1, words: nil),
        TranscriptSegment(start: 2.4, end: 3.6, text: "me", confidence: 1, words: nil)
    ]

    let kept = EchoGate.ownSpeechSegments(segments, mic: call.mic, system: call.system)

    #expect(kept.map(\.text) == ["me"])
    #expect(abs(kept[0].start - 2.4) < 0.15)
    #expect(abs(kept[0].end - 3.6) < 0.15)
}

@Test func aSentenceGluingEchoAndOwnSpeechIsCutToTheOwnSpeech() {
    let call = makeCall()
    let segments = [TranscriptSegment(start: 1.0, end: 3.8, text: "them and me", confidence: 1, words: nil)]

    let kept = EchoGate.ownSpeechSegments(segments, mic: call.mic, system: call.system)

    #expect(kept.count == 1)
    #expect(kept[0].start > 2.2 && kept[0].start < 2.6)
    #expect(kept[0].end > 3.4 && kept[0].end < 3.8)
}
