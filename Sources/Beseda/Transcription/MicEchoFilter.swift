import Foundation

/// the user's voice coming back on the system channel (the other side's speakers into their mic), removed
/// from the remote transcript; the reverse of `EchoGate`. Without it the diarizer makes a phantom person of it.
enum MicEchoFilter {
    /// fewer distinct words repeat by chance ("да да да", "thank you")
    static let minimumDistinctWords = 3
    static let minimumRepeatedShare = 0.8
    /// echo through the other side's speakers came back 0.4–1.3 s late; the other person repeating a phrase
    /// lags ≥ 2 s, the user repeating them is negative, and a remote voice that also leaks into the user's own
    /// mic lags 0.16–0.24 s (docs/decisions/speaker-accuracy.md)
    static let echoLag: ClosedRange<Double> = 0.3...1.5
    /// a remote speaker this much made of echo is the user's own voice: its leftover short lines go too
    static let echoSpeakerShare = 0.25

    static func echoSentences(_ system: [TranscriptSegment], microphone: [TranscriptSegment]) -> [TranscriptSegment] {
        // compared to the kept mic words only, so a dropped sentence's text always stays in the transcript as "me"
        let micWords = microphone.flatMap { $0.words ?? [] }.compactMap(NormalizedWord.init)
        return system.filter { isEcho($0, micWords: micWords) }
    }

    /// remote turns without echo sentences and without speakers mostly made of them, numbered again
    static func turnsWithoutMicEcho(_ turns: [SpeakerTurn], echo: [TranscriptSegment]) -> [SpeakerTurn] {
        let echoKeys = Set(echo.map { "\($0.start) \($0.text)" })
        let isEchoTurn = { (turn: SpeakerTurn) in echoKeys.contains("\(turn.start) \(turn.text)") }
        let wordCount = { (turn: SpeakerTurn) in turn.text.split(separator: " ").count }
        let echoSpeakers = Set(Dictionary(grouping: turns, by: \.speaker).filter { _, spoken in
            let echoWords = spoken.filter(isEchoTurn).map(wordCount).reduce(0, +)
            return Double(echoWords) >= echoSpeakerShare * Double(spoken.map(wordCount).reduce(0, +))
        }.keys)
        return SpeakerAssignment.relabelled(turns.filter { !isEchoTurn($0) && !echoSpeakers.contains($0.speaker) })
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
