import Foundation
import Testing

@testable import Podushka

private let sampleRate = 16_000.0

/// loud everywhere except the requested silent stretch, so the cut has an obvious best answer
private func tone(seconds: Double, silentFrom: Double? = nil, silentTo: Double? = nil) -> [Float] {
    (0..<Int(seconds * sampleRate)).map { index in
        let time = Double(index) / sampleRate
        if let silentFrom, let silentTo, time >= silentFrom, time < silentTo {
            return 0
        }
        return Float(sin(2 * .pi * 220 * time))
    }
}

@Test func audioShorterThanTheLimitIsNotSplit() {
    let samples = tone(seconds: 10)
    let pieces = UtteranceSplitter.split(samples, sampleRate: sampleRate, maxSeconds: 25)

    #expect(pieces.count == 1)
    #expect(pieces[0].offsetSec == 0)
    #expect(pieces[0].samples.count == samples.count)
}

@Test func everyPieceStaysWithinTheLimit() {
    // the quietest frame sits at the very end of every window, which is where a cut
    // computed from the window edge would overshoot the model's limit
    let rising = (0..<Int(90 * sampleRate)).map { index -> Float in
        let time = Double(index) / sampleRate
        return Float(sin(2 * .pi * 220 * time) * (0.2 + 0.8 * (1 - time.truncatingRemainder(dividingBy: 25) / 25)))
    }
    let pieces = UtteranceSplitter.split(rising, sampleRate: sampleRate, maxSeconds: 25)

    #expect(pieces.count > 1)
    #expect(pieces.allSatisfy { Double($0.samples.count) / sampleRate <= 25 })
}

@Test func piecesCoverTheOriginalWithoutGapsOrOverlap() {
    let samples = tone(seconds: 90)
    let pieces = UtteranceSplitter.split(samples, sampleRate: sampleRate, maxSeconds: 25)

    #expect(pieces.map(\.samples.count).reduce(0, +) == samples.count)
    var expectedOffset = 0.0
    for piece in pieces {
        #expect(abs(piece.offsetSec - expectedOffset) < 1e-9)
        expectedOffset += Double(piece.samples.count) / sampleRate
    }
}

@Test func theCutLandsInTheSilenceNotOnTheHardBoundary() {
    // silence sits at 23 s, inside the tail of a 25 s window
    let samples = tone(seconds: 60, silentFrom: 23.0, silentTo: 23.5)
    let pieces = UtteranceSplitter.split(samples, sampleRate: sampleRate, maxSeconds: 25)

    let firstCut = Double(pieces[0].samples.count) / sampleRate
    #expect(firstCut > 23.0)
    #expect(firstCut < 23.5)
}
