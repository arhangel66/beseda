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
    static func remoteTurns(segments: [TranscriptSegment], timeline: [SpeakerInterval]) -> [SpeakerTurn] {
        // the diarizer's own segments are the turns: per-word labels were twice as wrong (DER 0.262 vs 0.130,
        // docs/decisions/speaker-accuracy.md). Each sentence goes onto the segment it overlaps most.
        let intervals = timeline.sorted { $0.start < $1.start }
        guard !intervals.isEmpty else {
            // diarization gave nothing; the caller keeps its single-speaker path
            return []
        }
        var texts = [[String]](repeating: [], count: intervals.count)
        var outside: [SpeakerTurn] = []
        for segment in segments {
            let overlaps = intervals.map { min($0.end, segment.end) - max($0.start, segment.start) }
            let best = overlaps.indices.max { overlaps[$0] < overlaps[$1] }!
            if overlaps[best] > 0 {
                texts[best].append(segment.text)
            } else {
                // no diarizer speech under the words: keep them, as the nearest segment's speaker
                let nearest = intervals.min {
                    gap($0, segment) < gap($1, segment)
                }!
                outside.append(SpeakerTurn(speaker: nearest.speaker, start: segment.start, end: segment.end, text: segment.text))
            }
        }
        // a diarizer segment with no words under it has nothing to show in the transcript
        let turns = intervals.indices.compactMap { index in
            texts[index].isEmpty ? nil : SpeakerTurn(
                speaker: intervals[index].speaker,
                start: intervals[index].start,
                end: intervals[index].end,
                text: texts[index].joined(separator: " ")
            )
        }
        return relabelled((turns + outside).sorted { $0.start < $1.start })
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
