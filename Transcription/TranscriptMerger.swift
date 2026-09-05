import Foundation

enum TranscriptMerger {
    static func writeMicrophoneTranscript(_ result: TranscriptResult, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var lines: [String] = []
        lines.append("# Beseda Test Transcript")
        lines.append("")
        lines.append("- Created: \(result.createdAt.formatted(date: .complete, time: .standard))")
        lines.append("- Raw audio: \(result.rawAudioURL.path)")
        lines.append("- Normalized audio: \(result.normalizedAudioURL.path)")
        lines.append("- Audio duration: \(result.audioDurationDescription)")
        lines.append("- ASR: \(result.performanceDescription)")
        lines.append("")
        lines.append("## Transcript")
        lines.append("")
        lines.append(result.text.isEmpty ? "_No text returned._" : result.text)
        lines.append("")
        lines.append("## Segments")
        lines.append("")

        if result.segments.isEmpty {
            lines.append("_No segments returned._")
        } else {
            for segment in result.segments {
                lines.append("- `\(segment.timeRangeDescription)` \(segment.text)")
            }
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func writeDualTranscript(_ result: DualTranscriptResult, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        var lines: [String] = []
        lines.append("# Beseda Dual Transcript")
        lines.append("")
        lines.append("- Created: \(result.createdAt.formatted(date: .complete, time: .standard))")
        lines.append("- Session: \(result.sessionDirectory.path)")
        lines.append("- ASR: \(result.performanceDescription)")
        lines.append("")
        lines.append("## Dialogue")
        lines.append("")

        if result.speakerSegments.isEmpty {
            lines.append("_No timestamped segments returned. Channel transcripts are below._")
        } else {
            for item in result.speakerSegments {
                let name = SpeakerNaming.defaultName(for: item.speaker)
                lines.append("**\(name)** [\(item.segment.startDescription)] \(item.segment.text)")
                lines.append("")
            }
        }

        lines.append("## Channels")
        lines.append("")
        for channel in result.channels {
            appendChannel(channel, to: &lines)
        }

        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    /// Swaps the dialogue block for one rebuilt from the stored lines. Only that block is
    /// touched: the per-channel transcripts and the audio paths below it cannot be recovered
    /// from the database.
    static func rewriteDialogue(in url: URL, segments: [StoredTranscriptSegment], names: [String: String]) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        guard let opening = text.range(of: "## Dialogue\n\n"),
              let channels = text.range(of: "## Channels"),
              opening.upperBound <= channels.lowerBound else {
            return
        }
        let dialogue = segments
            .map { segment in
                let name = SpeakerNaming.name(for: segment.speaker, overrides: names)
                return "**\(name)** [\(CallFormatting.mmss(segment.startSec))] \(segment.text)\n\n"
            }
            .joined()
        try text.replacingCharacters(in: opening.upperBound..<channels.lowerBound, with: dialogue)
            .write(to: url, atomically: true, encoding: .utf8)
    }

    private static func appendChannel(_ channel: ChannelTranscriptResult, to lines: inout [String]) {
        let result = channel.result
        lines.append("## \(channel.channel.title) (\(channel.channel.subtitle))")
        lines.append("")
        lines.append("- Raw audio: \(result.rawAudioURL.path)")
        lines.append("- Normalized audio: \(result.normalizedAudioURL.path)")
        lines.append("- Audio duration: \(result.audioDurationDescription)")
        lines.append("- ASR: \(result.performanceDescription)")
        lines.append("")
        lines.append(result.text.isEmpty ? "_No text returned._" : result.text)
        lines.append("")
        lines.append("### Segments")
        lines.append("")

        if result.segments.isEmpty {
            lines.append("_No segments returned._")
        } else {
            for segment in result.segments {
                lines.append("- `\(segment.timeRangeDescription)` \(segment.text)")
            }
        }

        lines.append("")
    }
}
