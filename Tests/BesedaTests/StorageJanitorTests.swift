import Foundation
import Testing

@testable import Beseda

private let day: TimeInterval = 24 * 60 * 60

@Test func fileNamesMapToTheThreeStorageKinds() {
    #expect(StorageJanitor.kind(ofFileNamed: "me.raw.wav") == .rawAudio)
    #expect(StorageJanitor.kind(ofFileNamed: "them.raw.wav") == .rawAudio)
    #expect(StorageJanitor.kind(ofFileNamed: "me.asr.wav") == .normalizedAudio)
    #expect(StorageJanitor.kind(ofFileNamed: "mic.16k-mono.wav") == .normalizedAudio)
    #expect(StorageJanitor.kind(ofFileNamed: "transcript.md") == .text)
    #expect(StorageJanitor.kind(ofFileNamed: "session.json") == .text)
    #expect(StorageJanitor.kind(ofFileNamed: "notes.txt") == nil)
}

@Test func immediateRuleExpiresAFreshFile() {
    let rules = RetentionRules(rawAudio: .immediately, normalizedAudio: .forever)

    #expect(StorageJanitor.isExpired(kind: .rawAudio, age: 0, rules: rules))
    #expect(!StorageJanitor.isExpired(kind: .normalizedAudio, age: 365 * day, rules: rules))
}

@Test func datedRuleExpiresOnlyPastItsDeadline() {
    let rules = RetentionRules(rawAudio: .days30, normalizedAudio: .days90)

    #expect(!StorageJanitor.isExpired(kind: .rawAudio, age: 29 * day, rules: rules))
    #expect(StorageJanitor.isExpired(kind: .rawAudio, age: 31 * day, rules: rules))
    #expect(!StorageJanitor.isExpired(kind: .normalizedAudio, age: 60 * day, rules: rules))
    #expect(StorageJanitor.isExpired(kind: .normalizedAudio, age: 91 * day, rules: rules))
}

@Test func textIsNeverSweptWhateverTheAudioRulesSay() {
    let rules = RetentionRules(rawAudio: .immediately, normalizedAudio: .immediately)

    #expect(!StorageJanitor.isExpired(kind: .text, age: 10 * 365 * day, rules: rules))
}

@Test func sweepRemovesExpiredAudioAndKeepsTheTranscript() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-janitor-\(UUID().uuidString)", isDirectory: true)
    let callDirectory = directory.appendingPathComponent("20260601-120000", isDirectory: true)
    try FileManager.default.createDirectory(at: callDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let old = Date().addingTimeInterval(-45 * day)
    try write("raw", to: callDirectory.appendingPathComponent("me.raw.wav"), modifiedAt: old)
    try write("normalized", to: callDirectory.appendingPathComponent("me.asr.wav"), modifiedAt: old)
    try write("# transcript", to: callDirectory.appendingPathComponent("transcript.md"), modifiedAt: old)

    let janitor = StorageJanitor(callsDirectory: directory)
    let freed = janitor.sweep(rules: RetentionRules(rawAudio: .days30, normalizedAudio: .days90))

    #expect(freed > 0)
    #expect(!FileManager.default.fileExists(atPath: callDirectory.appendingPathComponent("me.raw.wav").path))
    #expect(FileManager.default.fileExists(atPath: callDirectory.appendingPathComponent("me.asr.wav").path))
    #expect(FileManager.default.fileExists(atPath: callDirectory.appendingPathComponent("transcript.md").path))
}

@Test func sweepLeavesTheAudioOfAProtectedCallAlone() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-janitor-\(UUID().uuidString)", isDirectory: true)
    let sweptCall = directory.appendingPathComponent("20260601-120000", isDirectory: true)
    let protectedCall = directory.appendingPathComponent("20260601-140000", isDirectory: true)
    try FileManager.default.createDirectory(at: sweptCall, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: protectedCall, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let now = Date()
    try write("raw", to: sweptCall.appendingPathComponent("me.raw.wav"), modifiedAt: now)
    try write("raw", to: protectedCall.appendingPathComponent("me.raw.wav"), modifiedAt: now)

    let janitor = StorageJanitor(callsDirectory: directory)
    let rules = RetentionRules(rawAudio: .immediately, normalizedAudio: .immediately)
    let expired = janitor.expiredBytes(rules: rules, protecting: [protectedCall.path], now: now)
    let freed = janitor.sweep(rules: rules, protecting: [protectedCall.path], now: now)

    #expect(!FileManager.default.fileExists(atPath: sweptCall.appendingPathComponent("me.raw.wav").path))
    #expect(FileManager.default.fileExists(atPath: protectedCall.appendingPathComponent("me.raw.wav").path))
    #expect(freed == 3)
    #expect(expired == 3)
}

@Test func measureSplitsTheFolderByKind() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-measure-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try write(String(repeating: "a", count: 100), to: directory.appendingPathComponent("me.raw.wav"), modifiedAt: Date())
    try write(String(repeating: "b", count: 40), to: directory.appendingPathComponent("me.asr.wav"), modifiedAt: Date())
    try write(String(repeating: "c", count: 10), to: directory.appendingPathComponent("transcript.md"), modifiedAt: Date())

    let usage = StorageJanitor(callsDirectory: directory).measure()

    #expect(usage.rawAudioBytes == 100)
    #expect(usage.normalizedAudioBytes == 40)
    #expect(usage.textBytes == 10)
    #expect(usage.audioBytes == 140)
}

private func write(_ contents: String, to url: URL, modifiedAt: Date) throws {
    try contents.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: url.path)
}
