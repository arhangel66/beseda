import Foundation

/// The shape the transcript lands on the clipboard in. The choice sticks and is what ⌘C uses.
enum TranscriptCopyFormat: String, CaseIterable, Identifiable, Sendable {
    case timestamped
    case clean
    case markdown

    var id: String {
        rawValue
    }

    var title: String { title(locale: .current) }

    func title(locale: Locale) -> String {
        switch self {
        case .timestamped:
            ExportText.get("Диалог с таймкодами", locale: locale)
        case .clean:
            ExportText.get("Чистый диалог", locale: locale)
        case .markdown:
            ExportText.get("Markdown для заметок", locale: locale)
        }
    }

    /// the right-hand hint in the menu: what the first line will look like
    var sample: String { sample(locale: .current) }

    func sample(locale: Locale) -> String {
        switch self {
        case .timestamped:
            "00:41 \(ExportText.get("Вы", locale: locale)): …"
        case .clean:
            "\(ExportText.get("Вы", locale: locale)): …"
        case .markdown:
            ExportText.get("## Разговор", locale: locale)
        }
    }
}

enum TranscriptCopy {
    static func render(_ detail: StoredCallDetail, format: TranscriptCopyFormat, locale: Locale = .current) -> String {
        guard !detail.segments.isEmpty else {
            return detail.markdownText ?? ""
        }
        let names = detail.speakerNames
        func speaker(_ segment: StoredTranscriptSegment) -> String {
            SpeakerNaming.name(for: segment.speaker, overrides: names, locale: locale)
        }

        switch format {
        case .timestamped:
            return detail.segments
                .map { "\(CallFormatting.mmss($0.startSec)) \(speaker($0)): \($0.text)" }
                .joined(separator: "\n")
        case .clean:
            return detail.segments
                .map { "\(speaker($0)): \($0.text)" }
                .joined(separator: "\n")
        case .markdown:
            let summary = detail.summary
            let header = "## \(summary.displayTitle)\n\n\(summary.whenDescription) · \(summary.durationDescription)"
            let body = detail.segments
                .map { "**\(speaker($0))** \(CallFormatting.mmss($0.startSec))  \n\($0.text)" }
                .joined(separator: "\n\n")
            return "\(header)\n\n\(body)"
        }
    }
}
