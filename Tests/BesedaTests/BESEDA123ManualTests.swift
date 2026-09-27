import Foundation
import Testing

@testable import Beseda

@Test func beseda123SeedOrMutateIsolatedAppDatabase() throws {
    guard let root = ProcessInfo.processInfo.environment["BESEDA123_FIXTURE_ROOT"],
          let operation = ProcessInfo.processInfo.environment["BESEDA123_OPERATION"] else {
        return
    }

    let dataDirectory = URL(fileURLWithPath: root, isDirectory: true)
        .appendingPathComponent("Library/Application Support/Beseda", isDirectory: true)
    let callDirectory = dataDirectory.appendingPathComponent("calls/test-call", isDirectory: true)
    try FileManager.default.createDirectory(at: callDirectory, withIntermediateDirectories: true)
    let store = CallStore(dbURL: dataDirectory.appendingPathComponent("calls.sqlite"))
    try store.prepare()

    let originalSegments = [
        StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 4, text: "Привет! Давай пройдёмся по релизу.", orderIndex: 0),
        StoredTranscriptSegment(speaker: "them-1", startSec: 5, endSec: 12, text: "Привет. Сборка готова, осталось проверить обновление.", orderIndex: 1),
        StoredTranscriptSegment(speaker: "me", startSec: 13, endSec: 15, text: "Хорошо, а что с подписью?", orderIndex: 2),
        StoredTranscriptSegment(speaker: "them-2", startSec: 16, endSec: 17, text: "Угу.", orderIndex: 3),
        StoredTranscriptSegment(speaker: "them-1", startSec: 18, endSec: 29, text: "Подпись проходит, я проверила на чистой машине.", orderIndex: 4),
        StoredTranscriptSegment(speaker: "them-2", startSec: 31, endSec: 32, text: "Да, да.", orderIndex: 5),
        StoredTranscriptSegment(speaker: "me", startSec: 33, endSec: 37, text: "Отлично, тогда выпускаем в пятницу.", orderIndex: 6),
    ]
    let transcriptURL = callDirectory.appendingPathComponent("transcript.md")

    switch operation {
    case "seed":
        try "## Dialogue\n\n## Channels\n".write(to: transcriptURL, atomically: true, encoding: .utf8)
        try store.upsertCall(
            id: "test-call", kind: "dual", startedAt: Date(), endedAt: Date().addingTimeInterval(37),
            durationSec: 37, status: "transcribing", transcriptURL: nil,
            audioDirectoryURL: callDirectory, error: nil, appName: "Zoom"
        )
        try store.markReady(callID: "test-call", transcriptURL: transcriptURL, segments: originalSegments)
    case "merge":
        try store.mergeSpeaker(callID: "test-call", speakerKey: "them-2", into: "them-1")
    case "rerun":
        try store.markReady(callID: "test-call", transcriptURL: transcriptURL, segments: originalSegments)
    default:
        Issue.record("Unknown BESEDA123_OPERATION")
    }
}
