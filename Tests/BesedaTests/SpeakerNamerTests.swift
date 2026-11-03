import Foundation
import Testing

@testable import Beseda

private let people = CallPeople("Rustam: Rustan, Mustam\nAnna\n\n  : nobody")

private func lines(_ pairs: [(String, String)]) -> [StoredTranscriptSegment] {
    pairs.enumerated().map { index, pair in
        StoredTranscriptSegment(speaker: pair.0, startSec: Double(index), endSec: nil, text: pair.1, orderIndex: index)
    }
}

@Test func thePeopleListFoldsSpellingsIntoTheNameAndSkipsEmptyLines() {
    #expect(people.canonicalBySpelling == ["rustam": "Rustam", "rustan": "Rustam", "mustam": "Rustam", "anna": "Anna"])
    #expect(people.mentions(in: "ok Rustan, and anna?") == ["Rustan", "anna"])
    #expect(people.canonical(" Mustam. ") == "rustam")
    #expect(people.canonical("None") == StoredSpeakerGuess.unknown)
}

@Test func anAddressNamesTheNextRemoteVoiceAndThanksThePreviousOne() {
    let call = lines([
        ("me", "Rustan, what do you think?"),
        ("them-1", "I think we ship it."),
        ("them-2", "Agreed, the build is green."),
        ("me", "Thanks, Anna."),
        ("them-3", "Hmm."),
    ])

    let guesses = SpeakerNameRules.guesses(for: call, people: people)

    #expect(guesses["them-1"]?.name == "Rustam")
    #expect(guesses["them-1"]?.evidence.contains("addressed, next remote voice them-1") == true)
    #expect(guesses["them-2"]?.name == "Anna")
    #expect(guesses["them-3"]?.name == StoredSpeakerGuess.unknown)
    #expect(guesses["me"] == nil)
}

@Test func aVoiceSayingANameIsNotTakenForThatPerson() {
    let call = lines([
        ("them-1", "Anna, can you share the screen?"),
        ("them-2", "Sure."),
        ("them-1", "Anna, you are muted."),
    ])

    let guesses = SpeakerNameRules.guesses(for: call, people: people)

    #expect(guesses["them-2"]?.name == "Anna")
    #expect(guesses["them-1"]?.name == StoredSpeakerGuess.unknown)
}

@MainActor @Test func theModelFillsOnlyTheLabelsTheRulesLeftOpenAndNeverRepeatsAPlacedPerson() {
    let rules = [
        "them-1": StoredSpeakerGuess(name: "Rustam", source: .rules, evidence: "line 0"),
        "them-2": StoredSpeakerGuess(name: StoredSpeakerGuess.unknown, source: .rules, evidence: "none"),
        "them-3": StoredSpeakerGuess(name: StoredSpeakerGuess.unknown, source: .rules, evidence: "none"),
        "them-4": StoredSpeakerGuess(name: StoredSpeakerGuess.unknown, source: .rules, evidence: "none"),
    ]
    let reply = #"{"them-1": "Anna", "them-2": "anna", "them-3": "Mustam", "them-4": "unknown", "them-9": "Bob"}"#

    let merged = SpeakerNamer.merging(modelReply: reply, into: rules, people: people)

    #expect(merged["them-1"]?.name == "Rustam")
    #expect(merged["them-1"]?.source == .rules)
    #expect(merged["them-2"]?.name == "Anna")
    #expect(merged["them-2"]?.source == .model)
    #expect(merged["them-3"]?.name == StoredSpeakerGuess.unknown)
    #expect(merged["them-4"]?.name == StoredSpeakerGuess.unknown)
    #expect(merged["them-9"] == nil)
    #expect(merged.values.allSatisfy { $0.modelReply == reply })
}

@Test func storedGuessesAreReadBackWithTheirEvidenceAndModelReply() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-guesses-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = CallStore(dbURL: directory.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    try store.upsertCall(
        id: "20261103-101500", kind: "dual", startedAt: Date(), endedAt: nil, durationSec: 180, status: "ready",
        transcriptURL: nil, audioDirectoryURL: directory, error: nil, appName: nil
    )
    let guesses = [
        "them-1": StoredSpeakerGuess(name: "Anna", source: .model, evidence: "the model read the whole call", modelReply: #"{"them-1": "Anna"}"#),
        "them-2": StoredSpeakerGuess(name: "Rustam", source: .rules, evidence: "line 3"),
    ]

    try store.replaceSpeakerGuesses(callID: "20261103-101500", guesses: guesses)
    try store.replaceSpeakerGuesses(callID: "20261103-101500", guesses: guesses)

    #expect(try store.fetchSpeakerGuesses(callID: "20261103-101500") == guesses)
}
