import Foundation

/// Builds words out of model tokens. Parakeet hands over words directly, but GigaAM only
/// emits token timestamps, and its tokens are SentencePiece pieces where U+2581 marks the
/// start of a word.
enum WordAssembler {
    struct Token {
        let start: Double
        let end: Double
        let text: String
    }

    private static let wordStart: Character = "\u{2581}"

    static func words(from tokens: [Token]) -> [TranscriptWord] {
        var words: [TranscriptWord] = []
        // the marker often arrives as a token of its own, so an open word is not the same
        // as a word with text in it yet
        var isOpen = false
        var text = ""
        var start = 0.0
        var end = 0.0

        func close() {
            if isOpen && !text.isEmpty {
                words.append(TranscriptWord(start: start, end: end, text: text))
            }
        }

        for token in tokens {
            if token.text.first == wordStart {
                close()
                text = String(token.text.dropFirst())
                start = token.start
                isOpen = true
            } else if !isOpen {
                // a transcript that opens without the marker still has to start somewhere
                text = token.text
                start = token.start
                isOpen = true
            } else {
                text += token.text
            }
            end = token.end
        }
        close()
        return words
    }
}
