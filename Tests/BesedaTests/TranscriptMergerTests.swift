import Foundation
import Testing

@testable import Beseda

@Test func renamingRewritesTheDialogueAndLeavesTheChannelsAlone() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(UUID().uuidString).md")
    let original = """
        # Beseda Dual Transcript

        ## Dialogue

        **Вы** [00:41] Начнём.

        **Собеседник 1** [00:52] Давай.

        ## Channels

        ## Me (microphone)
        """
    try original.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    try TranscriptMerger.rewriteDialogue(
        in: url,
        segments: [
            StoredTranscriptSegment(speaker: "me", startSec: 41, endSec: 44, text: "Начнём.", orderIndex: 0),
            StoredTranscriptSegment(speaker: "them-1", startSec: 52, endSec: 58, text: "Давай.", orderIndex: 1)
        ],
        names: ["them-1": "Ира"]
    )

    let rewritten = try String(contentsOf: url, encoding: .utf8)
    #expect(rewritten.contains("**Ира** [00:52] Давай."))
    #expect(!rewritten.contains("Собеседник 1"))
    #expect(rewritten.hasSuffix("## Channels\n\n## Me (microphone)"))
}

@Test func aTranscriptWithoutADialogueBlockIsLeftUntouched() throws {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("\(UUID().uuidString).md")
    let original = "# Beseda Test Transcript\n\n## Transcript\n\nтекст"
    try original.write(to: url, atomically: true, encoding: .utf8)
    defer { try? FileManager.default.removeItem(at: url) }

    try TranscriptMerger.rewriteDialogue(in: url, segments: [], names: [:])

    #expect(try String(contentsOf: url, encoding: .utf8) == original)
}
