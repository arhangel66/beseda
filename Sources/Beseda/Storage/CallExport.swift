import Foundation

/// A processed call as one Markdown file in the export folder the user picked.
enum CallExport {
    static func markdown(_ detail: StoredCallDetail, result: String, type: String, locale: Locale = .current) -> String {
        let summary = detail.summary
        return """
            # \(summary.displayTitle)

            \(summary.startedDate.map { dateLine($0, locale: locale) } ?? "—")
            \(ExportText.get("Тип:", locale: locale)) \(type)

            \(result.trimmingCharacters(in: .whitespacesAndNewlines))

            \(ExportText.get("## Transcript", locale: locale))

            \(TranscriptCopy.render(detail, format: .clean, locale: locale))

            """
    }

    /// date + title, so a rerun of the same call overwrites its file
    static func fileName(_ summary: StoredCallSummary) -> String {
        let date = summary.startedDate.map(fileDate) ?? "—"
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.newlines).union(.controlCharacters)
        let title = summary.displayTitle
            .components(separatedBy: forbidden)
            .joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        // leading dots would hide the file; 120 keeps the name well under the 255-byte limit
        let safeTitle = String(title.drop { $0 == "." }.prefix(120))
        return (safeTitle.isEmpty ? date : "\(date) \(safeTitle)") + ".md"
    }

    static func write(_ detail: StoredCallDetail, result: String, type: String, to folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(fileName(detail.summary))
        try markdown(detail, result: result, type: type).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func dateLine(_ date: Date, locale: Locale) -> String {
        date.formatted(Date.FormatStyle(date: .long, time: .shortened).locale(locale))
    }

    private static func fileDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH-mm"
        return formatter.string(from: date)
    }
}
