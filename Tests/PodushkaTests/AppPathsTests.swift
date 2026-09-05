import Foundation
import Testing

@testable import Podushka

private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("podushka-paths-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Test func everyFileLivesUnderTheDataDirectory() throws {
    let base = URL(fileURLWithPath: "/tmp/podushka-data", isDirectory: true)
    let paths = AppPaths(dataDirectory: base)

    #expect(paths.callsDirectory.path == "/tmp/podushka-data/calls")
    #expect(paths.callIndexURL.path == "/tmp/podushka-data/calls.sqlite")
    #expect(paths.appLogURL.path == "/tmp/podushka-data/podushka-app.log")
    #expect(paths.runtimeDirectory.path == "/tmp/podushka-data/runtime")
    #expect(paths.modelsDirectory.path == "/tmp/podushka-data/runtime/models")
    #expect(SpeechModel.default.localURL(in: paths.modelsDirectory).path
        == "/tmp/podushka-data/runtime/models/\(SpeechModel.default.filename)")
}

@Test func legacyCallsMoveIntoTheDataDirectoryOnce() throws {
    let legacy = try makeDirectory()
    let data = try makeDirectory().appendingPathComponent("fresh", isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: legacy)
        try? FileManager.default.removeItem(at: data.deletingLastPathComponent())
    }
    try FileManager.default.createDirectory(at: legacy.appendingPathComponent("calls/20260830-101500"), withIntermediateDirectories: true)
    try Data("db".utf8).write(to: legacy.appendingPathComponent("calls.sqlite"))
    try Data("old log\n".utf8).write(to: legacy.appendingPathComponent("podushka-app.log"))
    try Data("wal".utf8).write(to: legacy.appendingPathComponent("calls.sqlite-wal"))
    let paths = AppPaths(dataDirectory: data)
    try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    try Data("new line\n".utf8).write(to: paths.appLogURL)

    let moved = try LegacyDataMigration.run(from: legacy, to: paths)
    let movedAgain = try LegacyDataMigration.run(from: legacy, to: paths)

    #expect(moved == ["calls", "calls.sqlite", "calls.sqlite-wal", "podushka-app.log"])
    #expect(movedAgain.isEmpty)
    #expect(FileManager.default.fileExists(atPath: paths.callsDirectory.appendingPathComponent("20260830-101500").path))
    #expect(try String(contentsOf: paths.callIndexURL, encoding: .utf8) == "db")
    #expect(try String(contentsOf: paths.appLogURL, encoding: .utf8) == "new line\nold log\n")
    #expect(!FileManager.default.fileExists(atPath: legacy.appendingPathComponent("podushka-app.log").path))
    #expect(!FileManager.default.fileExists(atPath: legacy.appendingPathComponent("calls.sqlite").path))
}

@Test func aDataDirectoryWithADatabaseIsLeftAlone() throws {
    let legacy = try makeDirectory()
    let data = try makeDirectory()
    defer {
        try? FileManager.default.removeItem(at: legacy)
        try? FileManager.default.removeItem(at: data)
    }
    try Data("old".utf8).write(to: legacy.appendingPathComponent("calls.sqlite"))
    try Data("new".utf8).write(to: data.appendingPathComponent("calls.sqlite"))
    let paths = AppPaths(dataDirectory: data)

    let moved = try LegacyDataMigration.run(from: legacy, to: paths)

    #expect(moved.isEmpty)
    #expect(try String(contentsOf: paths.callIndexURL, encoding: .utf8) == "new")
}
