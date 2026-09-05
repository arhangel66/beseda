import Foundation
import Testing

@testable import Beseda

private func makeDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-paths-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Test func everyFileLivesUnderTheDataDirectory() throws {
    let base = URL(fileURLWithPath: "/tmp/beseda-data", isDirectory: true)
    let paths = AppPaths(dataDirectory: base)

    #expect(paths.callsDirectory.path == "/tmp/beseda-data/calls")
    #expect(paths.callIndexURL.path == "/tmp/beseda-data/calls.sqlite")
    #expect(paths.appLogURL.path == "/tmp/beseda-data/beseda-app.log")
    #expect(paths.runtimeDirectory.path == "/tmp/beseda-data/runtime")
    #expect(paths.modelsDirectory.path == "/tmp/beseda-data/runtime/models")
    #expect(SpeechModel.default.localURL(in: paths.modelsDirectory).path
        == "/tmp/beseda-data/runtime/models/\(SpeechModel.default.filename)")
}

@Test func thePodushkaFolderBecomesTheBesedaFolderOnce() throws {
    let parent = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: parent) }
    let legacy = parent.appendingPathComponent("Podushka", isDirectory: true)
    try FileManager.default.createDirectory(at: legacy.appendingPathComponent("calls/20260830-101500"), withIntermediateDirectories: true)
    try Data("db".utf8).write(to: legacy.appendingPathComponent("calls.sqlite"))
    try Data("old log\n".utf8).write(to: legacy.appendingPathComponent("podushka-app.log"))
    let paths = AppPaths(dataDirectory: parent.appendingPathComponent("Beseda", isDirectory: true))

    let moved = try LegacyDataMigration.run(from: legacy, to: paths)
    let movedAgain = try LegacyDataMigration.run(from: legacy, to: paths)

    #expect(moved)
    #expect(!movedAgain)
    #expect(FileManager.default.fileExists(atPath: paths.callsDirectory.appendingPathComponent("20260830-101500").path))
    #expect(try String(contentsOf: paths.callIndexURL, encoding: .utf8) == "db")
    #expect(try String(contentsOf: paths.appLogURL, encoding: .utf8) == "old log\n")
    #expect(!FileManager.default.fileExists(atPath: legacy.path))
}

@Test func anExistingBesedaFolderIsLeftAlone() throws {
    let parent = try makeDirectory()
    defer { try? FileManager.default.removeItem(at: parent) }
    let legacy = parent.appendingPathComponent("Podushka", isDirectory: true)
    let data = parent.appendingPathComponent("Beseda", isDirectory: true)
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: legacy.appendingPathComponent("calls.sqlite"))
    try Data("new".utf8).write(to: data.appendingPathComponent("calls.sqlite"))
    let paths = AppPaths(dataDirectory: data)

    let moved = try LegacyDataMigration.run(from: legacy, to: paths)

    #expect(!moved)
    #expect(try String(contentsOf: paths.callIndexURL, encoding: .utf8) == "new")
    #expect(FileManager.default.fileExists(atPath: legacy.path))
}
