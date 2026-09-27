import Foundation
import Testing
@testable import Beseda

@Test func deletionFailuresAndOldExportLocation() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let old = root.appendingPathComponent("old")
    let current = root.appendingPathComponent("current")
    let folder = root.appendingPathComponent("calls/id")
    for directory in [old, current, folder] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let original = folder.appendingPathComponent("transcript.md")
    let export = old.appendingPathComponent("export.md")
    let unrelated = current.appendingPathComponent("export.md")
    for url in [original, export, unrelated] { try Data("original".utf8).write(to: url) }
    let db = root.appendingPathComponent("calls.sqlite")
    let store = CallStore(dbURL: db)
    try store.prepare()
    try store.upsertCall(id: "id", kind: "mic", startedAt: Date(), endedAt: nil, durationSec: nil,
                         status: "ready", transcriptURL: original, audioDirectoryURL: folder,
                         error: nil, appName: nil)
    try store.replaceExportCopy(callID: "id", with: export)
    struct Injected: Error {}
    #expect(throws: Injected.self) {
        try store.deleteCallAndFiles(id: "id", exportFolder: old, deleteRow: { _ in throw Injected() })
    }
    #expect(try store.fetchCall(id: "id") != nil)
    #expect(FileManager.default.fileExists(atPath: original.path))
    #expect(FileManager.default.fileExists(atPath: export.path))
    try store.retryPendingCleanup()
    #expect(FileManager.default.fileExists(atPath: export.path))

    #expect(throws: CallStore.ExportDeletionError.self) {
        try store.deleteCallAndFiles(id: "id", exportFolder: old, remove: { url in
            if url == export { throw Injected() }
            try FileManager.default.removeItem(at: url)
        })
    }
    #expect(try store.fetchCall(id: "id") == nil)
    #expect(FileManager.default.fileExists(atPath: export.path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
    let relaunched = CallStore(dbURL: db)
    try relaunched.retryPendingCleanup()
    #expect(!FileManager.default.fileExists(atPath: export.path))
    #expect(FileManager.default.fileExists(atPath: unrelated.path))
}
