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
        // speakers come from the diarizer's own segments: per-word labels were twice as wrong (DER 0.262 vs 0.130,
        // docs/decisions/speaker-accuracy.md). Each sentence stays its own line, so clicking it seeks there.
        let intervals = mergingShortReplies(timeline.sorted { $0.start < $1.start })
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

    private static func mergingShortReplies(_ intervals: [SpeakerInterval]) -> [SpeakerInterval] {
        // speakers with no segment of 6 s or more: on real calls they are someone's short replies split off
        // (docs/decisions/speaker-accuracy.md); each segment goes to the nearest-in-time kept speaker
        let bySpeaker = Dictionary(grouping: intervals, by: \.speaker)
        var kept = Set(bySpeaker.filter { $0.value.contains { $0.end - $0.start >= 6 } }.keys)
        if kept.isEmpty, let biggest = bySpeaker.max(by: { seconds($0.value) < seconds($1.value) }) {
            kept = [biggest.key]
        }
        let keptIntervals = intervals.filter { kept.contains($0.speaker) }
        return intervals.map { interval in
            guard !kept.contains(interval.speaker) else {
                return interval
            }
            let nearest = keptIntervals.min {
                distance($0, interval) < distance($1, interval)
            }!
            return SpeakerInterval(speaker: nearest.speaker, start: interval.start, end: interval.end)
        }
    }

    private static func seconds(_ intervals: [SpeakerInterval]) -> Double {
        intervals.reduce(0) { $0 + $1.end - $1.start }
    }

    private static func distance(_ a: SpeakerInterval, _ b: SpeakerInterval) -> Double {
        max(a.start - b.end, b.start - a.end, 0)
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
