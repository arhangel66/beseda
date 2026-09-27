import Foundation

/// One line of the live preview: a sentence of one channel, no diarization, no echo gate.
struct LiveLine: Identifiable, Hashable {
    let channel: TranscriptChannel
    let start: Double
    let text: String

    var id: String {
        "\(channel.rawValue)-\(start)"
    }

    /// both channels' words as sentences, in the order they were said
    static func lines(microphone: [TranscriptWord], system: [TranscriptWord]) -> [LiveLine] {
        let me = SentenceBuilder.segments(from: microphone).map { LiveLine(channel: .microphone, start: $0.start, text: $0.text) }
        let them = SentenceBuilder.segments(from: system).map { LiveLine(channel: .systemAudio, start: $0.start, text: $0.text) }
        return (me + them).sorted { $0.start < $1.start }
    }
}

/// Glues a channel's live words to the next chunk, which starts `overlap` seconds before the
/// previous one ended. Times are absolute, so the overlap is cut at its middle: the earlier
/// chunk keeps what was said before the cut, the later one what came after.
enum LiveChunkMerge {
    static func merge(_ shown: [TranscriptWord], chunk: [TranscriptWord], chunkStart: Double, overlap: Double) -> [TranscriptWord] {
        let cut = chunkStart + overlap / 2
        let kept = shown.filter { $0.start < cut }
        // the same word straddling the cut gets slightly different times in each chunk
        let lastEnd = kept.last?.end ?? 0
        return kept + chunk.filter { $0.start >= cut && ($0.start + $0.end) / 2 >= lastEnd }
    }
}

/// When the live loop takes its next chunk and how long it rests after one. Recording always
/// wins: a loop that falls behind skips audio and rests longer instead of queueing work.
struct LiveBackoff {
    /// ≤ 25 s, GigaAM's window: past it the model silently drops speech
    static let chunkSeconds = 20.0
    static let overlapSeconds = 2.0
    static let maxRestSeconds = 60.0

    private(set) var restSeconds = 0.0
    private var droppedBuffersSeen = 0

    /// the chunk after one that ended at `transcribedUntil`, or nil while less than a chunk is on disk;
    /// with more than one chunk waiting behind it, the backlog is dropped and the newest chunk taken
    static func nextChunkStart(transcribedUntil: Double, recordedSeconds: Double) -> Double? {
        let start = max(0, transcribedUntil - overlapSeconds)
        guard recordedSeconds - start >= chunkSeconds else {
            return nil
        }
        return recordedSeconds - start > 2 * chunkSeconds ? recordedSeconds - chunkSeconds : start
    }

    /// slower than real time or a recorder that dropped a buffer doubles the rest; a clean chunk halves it
    mutating func chunkFinished(wallSeconds: Double, audioSeconds: Double, droppedBuffers: Int) {
        let trouble = wallSeconds > audioSeconds || droppedBuffers > droppedBuffersSeen
        droppedBuffersSeen = droppedBuffers
        if trouble {
            restSeconds = min(Self.maxRestSeconds, max(Self.chunkSeconds / 2, restSeconds * 2))
        } else {
            restSeconds = restSeconds / 2 < 1 ? 0 : restSeconds / 2
        }
    }
}

/// «Ключевые моменты»: a round every few minutes of recorded audio, only when the transcript
/// grew, never two at once. The clock is recorded seconds, so a pause stops it too.
struct KeyPointsSchedule {
    static let intervalSeconds = 180.0

    private(set) var isBusy = false
    private var lastRoundAt = 0.0
    private var lastTextLength = 0

    /// true when a round should start now; the caller must call `roundFinished` after it
    mutating func startRound(recordedSeconds: Double, textLength: Int) -> Bool {
        guard !isBusy,
              recordedSeconds - lastRoundAt >= Self.intervalSeconds,
              textLength > lastTextLength else {
            return false
        }
        isBusy = true
        lastRoundAt = recordedSeconds
        lastTextLength = textLength
        return true
    }

    mutating func roundFinished() {
        isBusy = false
    }
}
