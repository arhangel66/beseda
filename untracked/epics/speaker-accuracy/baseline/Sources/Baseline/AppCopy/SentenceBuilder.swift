import Foundation

/// Turns the engine's word stream into the sentence segments the rest of the app stores and
/// draws. `parakeet-mlx` used to hand us sentences and we derived words from them; transcribe.cpp
/// is the other way round, so the split lives here.
enum SentenceBuilder {
    /// a pause this long reads as a sentence break even without punctuation
    static let defaultSilenceGap: Double = 1.0
    /// a model that emits no punctuation must not produce one segment per call
    static let defaultMaxWords = 40

    static func segments(
        from words: [TranscriptWord],
        silenceGap: Double = defaultSilenceGap,
        maxWords: Int = defaultMaxWords
    ) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var current: [TranscriptWord] = []

        for (index, word) in words.enumerated() {
            current.append(word)
            let isLast = index == words.count - 1
            let endsSentence = word.text.hasSuffix(".") || word.text.hasSuffix("?") || word.text.hasSuffix("!")
            let hitWordLimit = current.count >= maxWords
            let longPause = !isLast && words[index + 1].start - word.end >= silenceGap

            if isLast || endsSentence || hitWordLimit || longPause {
                segments.append(makeSegment(current))
                current.removeAll()
            }
        }
        return segments
    }

    private static func makeSegment(_ words: [TranscriptWord]) -> TranscriptSegment {
        TranscriptSegment(
            start: words[0].start,
            end: words[words.count - 1].end,
            text: words.map(\.text).joined(separator: " "),
            confidence: nil,
            words: words
        )
    }
}
