import Foundation
import SQLite3
import Testing

@testable import Beseda

private func temporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("beseda-safety-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

/// raw SQL on the store file, the way an older release or a broken disk would leave it
private func execute(_ dbURL: URL, _ sql: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open(dbURL.path, &db) == SQLITE_OK else {
        throw CallStoreError.sqlite("open failed")
    }
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
        throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
    }
}

private func userVersion(_ dbURL: URL) -> Int {
    var db: OpaquePointer?
    var statement: OpaquePointer?
    sqlite3_open(dbURL.path, &db)
    defer { sqlite3_finalize(statement); sqlite3_close(db) }
    sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
    sqlite3_step(statement)
    return Int(sqlite3_column_int64(statement, 0))
}

private func columnNames(_ dbURL: URL, table: String) -> Set<String> {
    var db: OpaquePointer?
    var statement: OpaquePointer?
    sqlite3_open(dbURL.path, &db)
    defer { sqlite3_finalize(statement); sqlite3_close(db) }
    sqlite3_prepare_v2(db, "PRAGMA table_info(\(table))", -1, &statement, nil)
    var names: Set<String> = []
    while sqlite3_step(statement) == SQLITE_ROW {
        names.insert(String(cString: sqlite3_column_text(statement, 1)))
    }
    return names
}

private func makeCall(_ store: CallStore, id: String, folder: URL, status: String) throws {
    try store.upsertCall(
        id: id, kind: "dual", startedAt: Date(), endedAt: Date(), durationSec: 60, status: status,
        transcriptURL: nil, audioDirectoryURL: folder, error: nil, appName: "Zoom"
    )
}

// MARK: - 7: a failed index write never marks the call ready

@Test func aFailedSegmentWriteLeavesTheCallNotReady() throws {
    let root = try temporaryDirectory()
    let dbURL = root.appendingPathComponent("calls.sqlite")
    let store = CallStore(dbURL: dbURL)
    try store.prepare()
    try makeCall(store, id: "call", folder: root, status: "transcribing")
    try execute(dbURL, """
        CREATE TRIGGER fail_segments BEFORE INSERT ON transcript_segments
        BEGIN SELECT RAISE(ABORT, 'disk full'); END
        """)

    #expect(throws: CallStoreError.self) {
        try store.markReady(callID: "call", transcriptURL: root.appendingPathComponent("transcript.md"), segments: [
            StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 1, text: "привет", orderIndex: 0)
        ])
    }

    let call = try #require(try store.fetchCall(id: "call"))
    #expect(call.status == "transcribing")
    #expect(call.transcriptPath == nil)
}

@Test func markReadyWritesSegmentsAndStatusTogether() throws {
    let root = try temporaryDirectory()
    let store = CallStore(dbURL: root.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    try makeCall(store, id: "call", folder: root, status: "transcribing")
    let transcriptURL = root.appendingPathComponent("transcript.md")

    try store.markReady(callID: "call", transcriptURL: transcriptURL, segments: [
        StoredTranscriptSegment(speaker: "me", startSec: 0, endSec: 1, text: "привет", orderIndex: 0)
    ])

    let call = try #require(try store.fetchCall(id: "call"))
    #expect(call.status == "ready")
    #expect(call.transcriptPath == transcriptURL.path)
    #expect(try store.fetchSegments(callID: "call").map(\.text) == ["привет"])
}

@Test func markReadyFailsForACallWithNoRow() throws {
    let root = try temporaryDirectory()
    let store = CallStore(dbURL: root.appendingPathComponent("calls.sqlite"))
    try store.prepare()

    #expect(throws: CallStoreError.self) {
        try store.markReady(callID: "gone", transcriptURL: root.appendingPathComponent("transcript.md"), segments: [])
    }
}

// MARK: - 10: deletion is row first, so no half-deleted call survives

@Test func aFailedRowDeleteKeepsTheRowAndTheFiles() throws {
    let root = try temporaryDirectory()
    let dbURL = root.appendingPathComponent("calls.sqlite")
    let folder = root.appendingPathComponent("calls/call", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("audio".utf8).write(to: folder.appendingPathComponent("me.raw.wav"))
    let store = CallStore(dbURL: dbURL)
    try store.prepare()
    try makeCall(store, id: "call", folder: folder, status: "ready")
    try execute(dbURL, "CREATE TRIGGER keep_calls BEFORE DELETE ON calls BEGIN SELECT RAISE(ABORT, 'locked'); END")

    #expect(throws: CallStoreError.self) {
        try store.deleteCallAndFiles(id: "call", exportFolder: nil)
    }

    #expect(try store.fetchCall(id: "call") != nil)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("me.raw.wav").path))
}

@Test func aFailedFileRemovalLeavesNoBrokenCallAndIsCleanedLater() throws {
    let root = try temporaryDirectory()
    let folder = root.appendingPathComponent("calls/call", isDirectory: true)
    let locked = folder.appendingPathComponent("locked", isDirectory: true)
    try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
    try Data("audio".utf8).write(to: locked.appendingPathComponent("me.raw.wav"))
    try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
    let store = CallStore(dbURL: root.appendingPathComponent("calls.sqlite"))
    try store.prepare()
    try makeCall(store, id: "call", folder: folder, status: "ready")

    #expect(throws: (any Error).self) {
        try store.deleteCallAndFiles(id: "call", exportFolder: nil)
    }

    #expect(try store.fetchCall(id: "call") == nil)
    #expect(try store.fetchCalls().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: folder.path))
    // the next launch, with the file no longer stuck
    let stuck = try #require(FileManager.default.enumerator(at: store.trashURL, includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }.first { $0.lastPathComponent == "locked" })
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stuck.path)
    try store.emptyTrash()
    #expect(try FileManager.default.contentsOfDirectory(atPath: store.trashURL.path).isEmpty)
}

// MARK: - 12: versioned migrations with a backup

/// every 0.3.x release (v0.3.0 to v0.3.5) ran the same `prepare`, so this is their one schema
private let schema03 = """
    CREATE TABLE calls (
        id TEXT PRIMARY KEY, kind TEXT NOT NULL, started_at TEXT NOT NULL, ended_at TEXT, duration_sec REAL,
        status TEXT NOT NULL, transcript_path TEXT, audio_dir TEXT NOT NULL, error TEXT, app_name TEXT,
        summary_text TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
        event_title TEXT, event_id TEXT, event_pinned INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE transcript_segments (
        id TEXT PRIMARY KEY, call_id TEXT NOT NULL REFERENCES calls(id) ON DELETE CASCADE, speaker TEXT NOT NULL,
        start_sec REAL NOT NULL, end_sec REAL, text TEXT NOT NULL, order_idx INTEGER NOT NULL
    );
    CREATE INDEX idx_transcript_segments_call_order ON transcript_segments(call_id, order_idx);
    CREATE TABLE transcript_jobs (
        id TEXT PRIMARY KEY, call_id TEXT NOT NULL REFERENCES calls(id) ON DELETE CASCADE, speaker TEXT NOT NULL,
        status TEXT NOT NULL, audio_path TEXT NOT NULL, asr_json_path TEXT, audio_duration_sec REAL,
        wall_time_sec REAL, real_time_factor REAL, model TEXT, error TEXT, created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    CREATE INDEX idx_transcript_jobs_call ON transcript_jobs(call_id, speaker);
    CREATE TABLE call_speakers (
        call_id TEXT NOT NULL REFERENCES calls(id) ON DELETE CASCADE, speaker_key TEXT NOT NULL,
        display_name TEXT NOT NULL, PRIMARY KEY (call_id, speaker_key)
    );
    CREATE TABLE webhook_deliveries (
        id TEXT PRIMARY KEY, call_id TEXT NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
        call_title TEXT NOT NULL, attempt INTEGER NOT NULL, event TEXT NOT NULL, url TEXT NOT NULL,
        state TEXT NOT NULL, http_status INTEGER, response_action TEXT, response_body TEXT, error TEXT,
        created_at TEXT NOT NULL, sent_at TEXT, finished_at TEXT, next_retry_at TEXT
    );
    INSERT INTO calls (id, kind, started_at, status, audio_dir, app_name, summary_text, created_at, updated_at,
                       event_title, event_pinned)
    VALUES ('old', 'dual', '2026-01-10T10:00:00.000Z', 'ready', '/calls/old', 'Zoom', 'итоги',
            '2026-01-10T10:00:00.000Z', '2026-01-10T10:00:00.000Z', 'Планёрка', 1);
    INSERT INTO transcript_segments VALUES ('old-0', 'old', 'them-1', 0, 2, 'старая строка', 0);
    INSERT INTO call_speakers VALUES ('old', 'them-1', 'Анна');
    """

@Test(arguments: [
    schema03,
    // a 0.3.x file first made by a release that still had the per-call keep_audio flag
    schema03.replacingOccurrences(of: "event_pinned INTEGER NOT NULL DEFAULT 0\n",
                                  with: "event_pinned INTEGER NOT NULL DEFAULT 0, keep_audio INTEGER\n")
])
func aReleasedSchemaMigratesToCurrentKeepingItsData(schema: String) throws {
    let root = try temporaryDirectory()
    let dbURL = root.appendingPathComponent("calls.sqlite")
    try execute(dbURL, schema)
    let store = CallStore(dbURL: dbURL)

    try store.prepare()

    let call = try #require(try store.fetchCall(id: "old"))
    #expect(call.summaryText == "итоги")
    #expect(call.eventTitle == "Планёрка")
    #expect(call.eventPinned)
    #expect(call.callType == nil)
    #expect(try store.fetchSegments(callID: "old").map(\.text) == ["старая строка"])
    #expect(try store.fetchSpeakerNames(callID: "old") == ["them-1": "Анна"])
    #expect(userVersion(dbURL) == store.migrations.count)
    #expect(!columnNames(dbURL, table: "calls").contains("keep_audio"))
    #expect(columnNames(dbURL, table: "calls").isSuperset(of: ["call_type", "event_series_id", "participants", "export_path"]))
    let backupURL = store.backupURL(fromVersion: 0)
    #expect(columnNames(backupURL, table: "calls").contains("event_pinned"))
    #expect(!columnNames(backupURL, table: "calls").contains("export_path"))
}

@Test func aCurrentStoreIsNeitherMigratedNorBackedUpAgain() throws {
    let root = try temporaryDirectory()
    let dbURL = root.appendingPathComponent("calls.sqlite")
    let store = CallStore(dbURL: dbURL)
    try store.prepare()
    #expect(!FileManager.default.fileExists(atPath: store.backupURL(fromVersion: 0).path))

    try store.prepare()

    #expect(userVersion(dbURL) == store.migrations.count)
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.hasSuffix(".backup") })
}

@Test func aFailingMigrationRollsBackAndLeavesTheBackup() throws {
    let root = try temporaryDirectory()
    let dbURL = root.appendingPathComponent("calls.sqlite")
    let store = CallStore(dbURL: dbURL)
    try store.prepare()
    try makeCall(store, id: "call", folder: root, status: "ready")
    let current = store.migrations.count
    let failing: CallStore.Migration = { db in
        sqlite3_exec(db, "ALTER TABLE calls ADD COLUMN half_done TEXT", nil, nil, nil)
        throw CallStoreError.sqlite("migration failed")
    }

    #expect(throws: CallStoreError.self) {
        try store.prepare(migrations: store.migrations + [failing])
    }

    #expect(userVersion(dbURL) == current)
    #expect(!columnNames(dbURL, table: "calls").contains("half_done"))
    #expect(try store.fetchCall(id: "call") != nil)
    #expect(FileManager.default.fileExists(atPath: store.backupURL(fromVersion: current).path))
}
