import Foundation

struct SpeakerInterval: Hashable {
    let speaker: String
    let start: Double
    let end: Double
}

struct SpeakerTurn: Hashable {
    let speaker: String
    let start: Double
    let end: Double
    let text: String
}

enum SpeakerAssignment {
    /// slack around a segmentation boundary, calibrated in step 8 of the diarization plan
    static let nearestWindowSec = 0.4

    static func remoteTurns(segments: [TranscriptSegment], timeline: [SpeakerInterval]) -> [SpeakerTurn] {
        // an empty timeline means diarization gave nothing; the caller keeps its single-speaker path
        guard let firstSpeaker = timeline.sorted(by: { $0.start < $1.start }).first?.speaker else {
            return []
        }

        var turns: [SpeakerTurn] = []
        var previousSpeaker: String?
        for segment in segments {
            // a sentence always opens a line: merging across them would turn a four-minute
            // monologue into one paragraph and leave nothing to click for seeking
            var isOpen = false
            for word in words(in: segment) {
                let speaker = speaker(for: word, in: timeline) ?? previousSpeaker ?? firstSpeaker
                if isOpen, let last = turns.last, last.speaker == speaker {
                    turns[turns.count - 1] = SpeakerTurn(
                        speaker: speaker,
                        start: last.start,
                        end: word.end,
                        text: "\(last.text) \(word.text)"
                    )
                } else {
                    turns.append(SpeakerTurn(speaker: speaker, start: word.start, end: word.end, text: word.text))
                    isOpen = true
                }
                previousSpeaker = speaker
            }
        }
        return relabelled(turns)
    }

    private static func words(in segment: TranscriptSegment) -> [TranscriptWord] {
        // transcripts recorded before step 2 carry no words; the whole segment acts as one
        segment.words ?? [TranscriptWord(start: segment.start, end: segment.end, text: segment.text)]
    }

    private static func speaker(for word: TranscriptWord, in timeline: [SpeakerInterval]) -> String? {
        var bestSpeaker: String?
        var bestOverlap = 0.0
        for interval in timeline {
            let overlap = min(word.end, interval.end) - max(word.start, interval.start)
            if overlap > bestOverlap {
                bestSpeaker = interval.speaker
                bestOverlap = overlap
            }
        }
        if let bestSpeaker {
            return bestSpeaker
        }

        var nearestSpeaker: String?
        var nearestGap = nearestWindowSec
        for interval in timeline {
            let gap = max(interval.start - word.end, word.start - interval.end, 0)
            if gap < nearestGap {
                nearestSpeaker = interval.speaker
                nearestGap = gap
            }
        }
        return nearestSpeaker
    }

    private static func relabelled(_ turns: [SpeakerTurn]) -> [SpeakerTurn] {
        // the diarizer's own ids are arbitrary; numbering follows the order people first speak
        var keys: [String: String] = [:]
        return turns.map { turn in
            let key = keys[turn.speaker] ?? "them-\(keys.count + 1)"
            keys[turn.speaker] = key
            return SpeakerTurn(speaker: key, start: turn.start, end: turn.end, text: turn.text)
        }
    }
}
