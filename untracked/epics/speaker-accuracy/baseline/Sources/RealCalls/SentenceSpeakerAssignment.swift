import Foundation

// Transcription/SpeakerAssignment.swift at native-ui HEAD, renamed: speaker per sentence by diarizer-segment overlap

enum SentenceSpeakerAssignment {
    static func remoteTurns(segments: [TranscriptSegment], timeline: [SpeakerInterval]) -> [SpeakerTurn] {
        // speakers come from the diarizer's own segments: per-word labels were twice as wrong (DER 0.262 vs 0.130,
        // docs/decisions/speaker-accuracy.md). Each sentence stays its own line, so clicking it seeks there.
        let intervals = timeline.sorted { $0.start < $1.start }
        guard !intervals.isEmpty else {
            // diarization gave nothing; the caller keeps its single-speaker path
            return []
        }
        let turns = segments.map { segment in
            let overlaps = intervals.map { min($0.end, segment.end) - max($0.start, segment.start) }
            let best = overlaps.indices.max { overlaps[$0] < overlaps[$1] }!
            // no diarizer speech under the words: keep them, as the nearest segment's speaker
            let speaker = overlaps[best] > 0 ? intervals[best].speaker : intervals.min {
                gap($0, segment) < gap($1, segment)
            }!.speaker
            return SpeakerTurn(speaker: speaker, start: segment.start, end: segment.end, text: segment.text)
        }
        return relabelled(turns.sorted { $0.start < $1.start })
    }

    private static func gap(_ interval: SpeakerInterval, _ segment: TranscriptSegment) -> Double {
        min(abs(interval.start - segment.end), abs(segment.start - interval.end))
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
