import Foundation
import Testing

@testable import Podushka

@Test func onlyCallsThatStillNeedTheirAudioProtectTheirFolder() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("podushka-protected-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let store = CallStore(dbURL: directory.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    let readyDirectory = directory.appendingPathComponent("20260830-101500", isDirectory: true)
    let failedDirectory = directory.appendingPathComponent("20260830-113000", isDirectory: true)
    let transcribingDirectory = directory.appendingPathComponent("20260830-120000", isDirectory: true)
    try store.upsertCall(
        id: "20260830-101500",
        kind: "dual",
        startedAt: Date(),
        endedAt: nil,
        durationSec: 180,
        status: "ready",
        transcriptURL: nil,
        audioDirectoryURL: readyDirectory,
        error: nil,
        appName: nil
    )
    try store.upsertCall(
        id: "20260830-113000",
        kind: "dual",
        startedAt: Date(),
        endedAt: nil,
        durationSec: 60,
        status: "failed",
        transcriptURL: nil,
        audioDirectoryURL: failedDirectory,
        error: "Interrupted before the app restarted",
        appName: nil
    )
    try store.upsertCall(
        id: "20260830-120000",
        kind: "dual",
        startedAt: Date(),
        endedAt: nil,
        durationSec: 60,
        status: "transcribing",
        transcriptURL: nil,
        audioDirectoryURL: transcribingDirectory,
        error: nil,
        appName: nil
    )

    let protected = try store.protectedAudioDirectories()

    #expect(protected == [failedDirectory.path, transcribingDirectory.path])
}
