import Foundation
import Testing

@testable import Beseda

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-privacy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func permissions(_ url: URL) throws -> Int {
    try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int
}

@Test func deletingACallLeavesNothingOfItOnDisk() throws {
    let root = try temporaryDirectory()
    let exportFolder = root.appendingPathComponent("export", isDirectory: true)
    let callFolder = root.appendingPathComponent("calls/20260926-101500", isDirectory: true)
    try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: callFolder, withIntermediateDirectories: true)
    for name in ["me.raw.wav", "them.raw.wav", "me.asr.wav", "them.asr.wav", "me.asr.json", "session.json", "transcript.md"] {
        try Data("secret".utf8).write(to: callFolder.appendingPathComponent(name))
    }
    let store = CallStore(dbURL: root.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    try store.upsertCall(
        id: "20260926-101500", kind: "dual", startedAt: Date(), endedAt: Date(), durationSec: 60, status: "ready",
        transcriptURL: callFolder.appendingPathComponent("transcript.md"), audioDirectoryURL: callFolder,
        error: nil, appName: "Zoom"
    )
    try store.replaceSegments(callID: "20260926-101500", segments: [
        StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 2, text: "секретныйпланрелиза", orderIndex: 0)
    ])
    try store.setSummary(callID: "20260926-101500", text: "итоги")
    let call = try #require(try store.fetchCall(id: "20260926-101500"))
    let exportCopy = exportFolder.appendingPathComponent(CallExport.fileName(call))
    try Data("copy".utf8).write(to: exportCopy)

    try store.deleteCallAndFiles(id: "20260926-101500", exportFolder: exportFolder)

    #expect(try store.fetchCall(id: "20260926-101500") == nil)
    #expect(try store.fetchSegments(callID: "20260926-101500").isEmpty)
    #expect(!FileManager.default.fileExists(atPath: callFolder.path))
    #expect(!FileManager.default.fileExists(atPath: exportCopy.path))
    for name in ["calls.sqlite", "calls.sqlite-wal"] {
        let bytes = (try? Data(contentsOf: root.appendingPathComponent(name))) ?? Data()
        #expect(bytes.range(of: Data("секретныйпланрелиза".utf8)) == nil)
    }
}

@Test func protectedStorageIsOwnerOnlyForOldAndNewFiles() throws {
    let root = try temporaryDirectory()
    let oldFolder = root.appendingPathComponent("calls/old", isDirectory: true)
    try FileManager.default.createDirectory(at: oldFolder, withIntermediateDirectories: true)
    let oldFile = oldFolder.appendingPathComponent("transcript.md")
    try Data("old".utf8).write(to: oldFile)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: oldFolder.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: oldFile.path)

    StorageProtection.apply(to: root)
    let store = CallStore(dbURL: root.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    let newFolder = root.appendingPathComponent("calls/new", isDirectory: true)
    try FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
    try "new".write(to: newFolder.appendingPathComponent("transcript.md"), atomically: true, encoding: .utf8)

    #expect(try permissions(root) == 0o700)
    #expect(try permissions(oldFolder) == 0o700)
    #expect(try permissions(oldFile) == 0o600)
    #expect(try permissions(newFolder) == 0o700)
    #expect(try permissions(newFolder.appendingPathComponent("transcript.md")) == 0o600)
    #expect(try permissions(root.appendingPathComponent("calls.sqlite")) == 0o600)
}

@Test func renamedCallKeepsOneExportCopyAndDeletionRemovesIt() throws {
    let root = try temporaryDirectory()
    let exportFolder = root.appendingPathComponent("export", isDirectory: true)
    try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
    let store = CallStore(dbURL: root.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    try store.upsertCall(
        id: "20260926-101500", kind: "dual", startedAt: Date(), endedAt: Date(), durationSec: 60, status: "ready",
        transcriptURL: nil, audioDirectoryURL: root.appendingPathComponent("calls/none"), error: nil, appName: "Zoom"
    )
    func export() throws {
        let call = try #require(try store.fetchCall(id: "20260926-101500"))
        let detail = StoredCallDetail(summary: call, segments: [], speakerNames: [:], markdownText: nil, jobStats: nil)
        let url = try CallExport.write(detail, result: "итоги", type: "Созвон", to: exportFolder)
        try store.replaceExportCopy(callID: call.id, with: url)
    }
    try store.setEvent(callID: "20260926-101500", title: "Синк", eventID: nil, pinned: true)
    try export()

    try store.setEvent(callID: "20260926-101500", title: "Релиз 0.6", eventID: nil, pinned: true)
    try export()
    let copiesAfterRename = try FileManager.default.contentsOfDirectory(atPath: exportFolder.path)
    try store.setEvent(callID: "20260926-101500", title: "Ретро", eventID: nil, pinned: true)
    try store.deleteCallAndFiles(id: "20260926-101500", exportFolder: exportFolder)

    #expect(copiesAfterRename.count == 1 && copiesAfterRename[0].hasSuffix(" Релиз 0.6.md"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: exportFolder.path).isEmpty)
}
