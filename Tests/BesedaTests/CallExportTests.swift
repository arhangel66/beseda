import Foundation
import Testing

@testable import Beseda

private func detail(title: String) -> StoredCallDetail {
    StoredCallDetail(
        summary: StoredCallSummary(
            id: "20260829-140800",
            kind: "dual",
            startedAt: "2026-08-29T14:08:00.000Z",
            endedAt: nil,
            durationSec: 214,
            status: "ready",
            transcriptPath: nil,
            audioDirectoryPath: "/tmp/call",
            error: nil,
            appName: "Zoom",
            previewText: nil,
            summaryText: nil,
            eventTitle: title,
            eventID: "event-1",
            eventPinned: false
        ),
        segments: [
            StoredTranscriptSegment(speaker: "me", startSec: 41, endSec: 44, text: "Начнём с релиза.", orderIndex: 0),
            StoredTranscriptSegment(speaker: "them", startSec: 52, endSec: 58, text: "Давай.", orderIndex: 1)
        ],
        speakerNames: [:],
        markdownText: nil,
        jobStats: nil
    )
}

@Test func exportPutsTitleDateTypeResultThenTranscript() {
    let text = CallExport.markdown(detail(title: "Релиз 0.6"), result: "**Итог**\nВыкатываем.\n", type: "Дейли")

    let lines = text.components(separatedBy: "\n")
    #expect(lines[0] == "# Релиз 0.6")
    #expect(lines[2].contains("2026"))
    #expect(lines[3] == "Тип: Дейли")
    #expect(text.hasSuffix("\n\n**Итог**\nВыкатываем.\n\n## Transcript\n\nВы: Начнём с релиза.\nСобеседник: Давай.\n"))
}

@Test func exportFileNameDropsCharactersTheFileSystemRejects() {
    let name = CallExport.fileName(detail(title: "  План: Q3/Q4?\nитоги  ").summary)

    #expect(name.hasSuffix(" План Q3 Q4 итоги.md"))
    #expect(name.hasPrefix("2026-08-"))
    #expect(!name.contains("/") && !name.contains(":"))
}

@Test func exportWritesTheFileAndARerunOverwritesIt() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    _ = try CallExport.write(detail(title: "Синк"), result: "первый", type: "Созвон", to: folder)
    let url = try CallExport.write(detail(title: "Синк"), result: "второй", type: "Созвон", to: folder)

    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [url.lastPathComponent])
    #expect(try String(contentsOf: url, encoding: .utf8).contains("второй"))
}
