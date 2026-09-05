import Foundation

struct TranscriptWord: Codable, Hashable {
    let start: Double
    let end: Double
    let text: String
}

struct TranscriptSegment: Codable, Hashable, Identifiable {
    let start: Double
    let end: Double
    let text: String
    let confidence: Double?
    /// absent in transcripts recorded before speaker attribution needed word times
    let words: [TranscriptWord]?

    var id: String {
        "\(start)-\(end)-\(text)"
    }

    var timeRangeDescription: String {
        "\(start.mmss)-\(end.mmss)"
    }

    var startDescription: String {
        start.mmss
    }
}

struct ASRReadyEvent: Equatable {
    let model: String
    let version: String
}

struct ASRTranscription: Codable {
    let id: String
    let text: String
    let segments: [TranscriptSegment]
    let audioDurationSec: Double?
    let wallTimeSec: Double?
    let realTimeFactor: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case text
        case segments
        case audioDurationSec = "audio_duration_sec"
        case wallTimeSec = "wall_time_sec"
        case realTimeFactor = "real_time_factor"
    }
}

struct TranscriptResult: Identifiable {
    let id: String
    let createdAt: Date
    let sessionDirectory: URL
    let rawAudioURL: URL
    let normalizedAudioURL: URL
    let markdownURL: URL
    let text: String
    let segments: [TranscriptSegment]
    let audioDurationSec: Double?
    let wallTimeSec: Double?
    let realTimeFactor: Double?

    var audioDurationDescription: String {
        guard let audioDurationSec else {
            return "unknown"
        }
        return "\(audioDurationSec.oneDecimal)s"
    }

    var performanceDescription: String {
        let wall = wallTimeSec.map { "\($0.oneDecimal)s" } ?? "unknown"
        let rtf = realTimeFactor.map { "\($0.threeDecimals)x" } ?? "unknown"
        return "\(wall), RTF \(rtf)"
    }
}

enum TranscriptChannel: String, Codable, Hashable, Identifiable {
    case microphone
    case systemAudio

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .microphone:
            "Me"
        case .systemAudio:
            "Them"
        }
    }

    var subtitle: String {
        switch self {
        case .microphone:
            "microphone"
        case .systemAudio:
            "system audio"
        }
    }

    var speakerID: String {
        switch self {
        case .microphone:
            "me"
        case .systemAudio:
            "them"
        }
    }
}

struct ChannelTranscriptResult: Identifiable {
    let channel: TranscriptChannel
    let result: TranscriptResult

    var id: String {
        channel.rawValue
    }
}

struct DualTranscriptResult: Identifiable {
    let id: String
    let createdAt: Date
    let sessionDirectory: URL
    let markdownURL: URL
    let microphone: TranscriptResult
    let systemAudio: TranscriptResult
    /// system-audio turns split per remote speaker; empty when diarization did not run
    let remoteTurns: [SpeakerTurn]

    var channels: [ChannelTranscriptResult] {
        [
            ChannelTranscriptResult(channel: .microphone, result: microphone),
            ChannelTranscriptResult(channel: .systemAudio, result: systemAudio)
        ]
    }

    var speakerSegments: [SpeakerTranscriptSegment] {
        let mine = microphone.segments.map { segment in
            SpeakerTranscriptSegment(speaker: TranscriptChannel.microphone.speakerID, segment: segment)
        }
        let theirs = remoteTurns.isEmpty
            ? systemAudio.segments.map { segment in
                SpeakerTranscriptSegment(speaker: TranscriptChannel.systemAudio.speakerID, segment: segment)
            }
            : remoteTurns.map { turn in
                SpeakerTranscriptSegment(
                    speaker: turn.speaker,
                    segment: TranscriptSegment(
                        start: turn.start,
                        end: turn.end,
                        text: turn.text,
                        confidence: nil,
                        words: nil
                    )
                )
            }
        return (mine + theirs).sorted { lhs, rhs in
            if lhs.segment.start == rhs.segment.start {
                return lhs.speaker < rhs.speaker
            }
            return lhs.segment.start < rhs.segment.start
        }
    }

    var text: String {
        if speakerSegments.isEmpty {
            return channels.map { channel in
                "\(channel.channel.title):\n\(channel.result.text)"
            }
            .joined(separator: "\n\n")
        }

        return speakerSegments.map { item in
            "\(item.speaker) [\(item.segment.startDescription)] \(item.segment.text)"
        }
        .joined(separator: "\n")
    }

    var performanceDescription: String {
        "Me \(microphone.performanceDescription), Them \(systemAudio.performanceDescription)"
    }
}

struct SpeakerTranscriptSegment: Identifiable {
    let speaker: String
    let segment: TranscriptSegment

    var id: String {
        "\(speaker)-\(segment.id)"
    }
}

private extension Double {
    var mmss: String {
        let totalSeconds = Int(self.rounded())
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    var oneDecimal: String {
        String(format: "%.1f", self)
    }

    var threeDecimals: String {
        String(format: "%.3f", self)
    }
}
