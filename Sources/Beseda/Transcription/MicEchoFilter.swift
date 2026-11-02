import Foundation

/// the user's voice coming back on the system channel (the other side's speakers into their mic), removed
/// from the remote transcript; the reverse of `EchoGate`. Without it the diarizer makes a phantom person of it.
enum MicEchoFilter {
    /// fewer distinct words repeat by chance ("да да да", "thank you")
    static let minimumDistinctWords = 3
    static let minimumRepeatedShare = 0.8
    /// measured echo lags 0.2–1.3 s; the other person repeating a phrase lags ≥ 2 s,
    /// and the user repeating them gives a negative lag (docs/decisions/speaker-accuracy.md)
    static let echoLag: ClosedRange<Double> = 0.05...1.5

    static func systemSegmentsWithoutMicEcho(_ system: [TranscriptSegment], microphone: [TranscriptSegment]) -> [TranscriptSegment] {
        // compared to the kept mic words only, so a dropped sentence's text always stays in the transcript as "me"
        let micWords = microphone.flatMap { $0.words ?? [] }.compactMap(NormalizedWord.init)
        return system.filter { !isEcho($0, micWords: micWords) }
    }

    private static func isEcho(_ sentence: TranscriptSegment, micWords: [NormalizedWord]) -> Bool {
        // same words in the same order as the mic, each a short constant lag later
        let words = (sentence.words ?? []).compactMap(NormalizedWord.init)
        guard Set(words.map(\.text)).count >= minimumDistinctWords else {
            return false
        }
        let nearby = micWords.filter { $0.start >= sentence.start - 4 && $0.start <= sentence.end + 2 }
        let lags = lagsOfWordsRepeated(words, from: nearby)
        guard Double(lags.count) >= minimumRepeatedShare * Double(words.count) else {
            return false
        }
        return echoLag.contains(lags.sorted()[lags.count / 2])
    }

    /// start-time lags of the system words that line up, in order, with mic words (longest common subsequence)
    private static func lagsOfWordsRepeated(_ words: [NormalizedWord], from mic: [NormalizedWord]) -> [Double] {
        let difference = words.map(\.text).difference(from: mic.map(\.text))
        var removed: Set<Int> = []
        var inserted: Set<Int> = []
        for change in difference {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        let micKept = mic.indices.filter { !removed.contains($0) }
        let wordsKept = words.indices.filter { !inserted.contains($0) }
        return zip(wordsKept, micKept).map { words[$0].start - mic[$1].start }
    }

    private struct NormalizedWord {
        let text: String
        let start: Double

        init?(_ word: TranscriptWord) {
            text = word.text.lowercased().filter { $0.isLetter || $0.isNumber }
            start = word.start
            if text.isEmpty {
                return nil
            }
        }
    }
}
