import Foundation
import Testing

@testable import Podushka

private func tokens(_ items: [(String, Double, Double)]) -> [WordAssembler.Token] {
    items.map { WordAssembler.Token(start: $0.1, end: $0.2, text: $0.0) }
}

@Test func sentencePiecesBecomeWords() {
    let words = WordAssembler.words(from: tokens([
        ("\u{2581}При", 0.0, 0.04),
        ("вет", 0.08, 0.12),
        ("\u{2581}мир", 0.20, 0.28)
    ]))

    #expect(words.map(\.text) == ["Привет", "мир"])
    #expect(words[0].start == 0.0)
    #expect(words[0].end == 0.12)
    #expect(words[1].start == 0.20)
}

@Test func aBareMarkerStillOpensAWord() {
    // GigaAM emits the marker on its own before a piece that carries no prefix
    let words = WordAssembler.words(from: tokens([
        ("\u{2581}", 0.0, 0.04),
        ("ря", 0.08, 0.12),
        ("да", 0.16, 0.20)
    ]))

    #expect(words.map(\.text) == ["ряда"])
    #expect(words[0].start == 0.0)
    #expect(words[0].end == 0.20)
}

@Test func aTranscriptOpeningWithoutTheMarkerKeepsItsFirstWord() {
    let words = WordAssembler.words(from: tokens([
        ("Да", 0.0, 0.04),
        ("\u{2581}нет", 0.10, 0.20)
    ]))

    #expect(words.map(\.text) == ["Да", "нет"])
}

@Test func noTokensMeanNoWords() {
    #expect(WordAssembler.words(from: []).isEmpty)
}
