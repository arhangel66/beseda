import Foundation
import SQLite3

struct StoredTranscriptSegment: Identifiable, Hashable {
    let speaker: String
    let startSec: Double
    let endSec: Double?
    let text: String
    let orderIndex: Int

    var id: String {
        "\(orderIndex)-\(speaker)"
    }
}

struct StoredCallSummary: Identifiable, Hashable {
    let id: String
    let kind: String
    let startedAt: String
    let endedAt: String?
    let durationSec: Double?
    let status: String
    let transcriptPath: String?
    let audioDirectoryPath: String
    let error: String?
    /// the call app the recording started from; nil for a manual recording
    let appName: String?
    /// the opening lines of the transcript, the only real handle we have on what the call was about
    let previewText: String?
    /// the summary of the call
    let summaryText: String?
    /// the calendar event that was running when the recording started, if the calendar is on
    let eventTitle: String?
    let eventID: String?
    /// set when the event was chosen by hand: the matcher never touches such a call again
    let eventPinned: Bool
    /// the `CallType.name` the call was processed as; nil for a call never processed
    var callType: String? = nil
    /// shared by every occurrence of a recurring calendar event; nil for one-off events
    var eventSeriesID: String? = nil
    /// attendees of the linked calendar event, lowercased emails or names
    var participants: [String] = []

    var isFailed: Bool {
        status == "failed"
    }

    var isDual: Bool {
        kind == "dual"
    }

    var transcriptURL: URL? {
        transcriptPath.map { URL(fileURLWithPath: $0) }
    }

    var audioDirectoryURL: URL {
        URL(fileURLWithPath: audioDirectoryPath, isDirectory: true)
    }

    var startedDate: Date? {
        CallFormatting.parseISO8601(startedAt)
    }

    var duration: TimeInterval {
        durationSec ?? 0
    }

    var appLabel: String {
        if let appName, !appName.isEmpty {
            return appName
        }
        return kind == "mic" ? "Микрофон" : "Звонок"
    }

    var isFromCalendar: Bool {
        eventTitle?.isEmpty == false
    }

    var displayTitle: String {
        if let eventTitle, !eventTitle.isEmpty {
            return eventTitle
        }
        if let previewText, let title = Self.title(fromTranscriptOpening: previewText) {
            return title
        }
        if kind == "mic" {
            return "Заметка с микрофона"
        }
        guard let startedDate else {
            return appLabel
        }
        return "\(appLabel) · \(CallFormatting.when(startedDate))"
    }

    /// nil when we know no app: the row draws an icon rather than a made-up monogram
    var initials: String? {
        appName.flatMap { $0.first.map { String($0).uppercased() } }
    }

    var fallbackSymbol: String {
        kind == "mic" ? "mic" : "waveform"
    }

    var whenDescription: String {
        startedDate.map { CallFormatting.when($0) } ?? startedAt
    }

    /// the detail header's big line: "Сегодня, 18:31 · 31 мин"
    var whenHeadline: String {
        "\(whenDescription.prefix(1).uppercased())\(whenDescription.dropFirst()) · \(durationDescription)"
    }

    /// the sidebar's leading column: the time under «Сегодня» and «Вчера», date and time further back
    var clockDescription: String {
        guard let startedDate else {
            return ""
        }
        return dayGroup <= .yesterday ? CallFormatting.clock(startedDate) : CallFormatting.when(startedDate)
    }

    var durationDescription: String {
        CallFormatting.humanDuration(duration)
    }

    var dayGroup: CallDayGroup {
        startedDate.map { CallDayGroup.of($0) } ?? .earlier
    }

    /// the sidebar's second line: what went wrong, or where the call came from
    var metaDescription: String {
        if isFailed {
            return "не расшифрован · \(error ?? "ошибка")"
        }
        if status != "ready" {
            return "\(appLabel) · \(statusLabel)"
        }
        return "\(appLabel) · \(isDual ? "два канала" : "микрофон")"
    }

    /// the stored status in Russian: a call left mid-way by a crash still has to read as Russian
    var statusLabel: String {
        Self.statusLabels[status] ?? status
    }

    private static let statusLabels = [
        "recording": "записываю",
        "normalizing": "готовлю запись",
        "transcribing": "расшифровываю",
        "ready": "готов",
        "failed": "ошибка"
    ]

    var searchableText: String {
        [displayTitle, appLabel, whenDescription, previewText ?? "", error ?? ""]
            .joined(separator: " ")
            .lowercased()
    }

    /// Calls open with "Привет" and "Слышно меня?", so the first sentence that carries
    /// something wins over the first sentence there is.
    static func title(fromTranscriptOpening opening: String, limit: Int = 64) -> String? {
        let sentences = opening
            .split(whereSeparator: { ".!?\n".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = sentences.first else {
            return nil
        }

        let carrying = sentences.first { $0.count >= 20 } ?? first
        guard carrying.count > limit else {
            return carrying
        }
        let cut = carrying.prefix(limit)
        guard let lastSpace = cut.lastIndex(of: " ") else {
            return String(cut) + "…"
        }
        return String(cut[cut.startIndex..<lastSpace]) + "…"
    }
}

/// What the ASR run cost for one call, summed over its channels.
struct StoredJobStats: Hashable {
    let wallTimeSec: Double
    let realTimeFactor: Double?
    /// nil for calls transcribed before the model was recorded
    let model: String?

    var description: String {
        guard let realTimeFactor else {
            return "\(String(format: "%.0f", wallTimeSec)) с"
        }
        let wallTime = "расшифровка за \(String(format: "%.0f", wallTimeSec)) с"
        guard realTimeFactor > 0 else {
            return wallTime
        }
        return "\(wallTime) · в \(String(format: "%.0f", 1 / realTimeFactor)) раз быстрее записи"
    }
}

struct StoredCallDetail: Identifiable, Hashable {
    let summary: StoredCallSummary
    let segments: [StoredTranscriptSegment]
    /// renamed speakers only; everyone else falls back to the default name for their key
    let speakerNames: [String: String]
    let markdownText: String?
    let jobStats: StoredJobStats?

    var id: String {
        summary.id
    }
}

/// One attempt to hand a call to the webhook: queued → sending → delivered | failed.
struct StoredWebhookDelivery: Identifiable, Hashable {
    let id: String
    let callID: String
    /// kept from enqueue time so the journal in settings needs no join with calls
    let callTitle: String
    let attempt: Int
    let event: String
    let url: String
    let state: String
    let httpStatus: Int?
    let responseAction: String?
    let responseBody: String?
    let error: String?
    let createdAt: String
    let sentAt: String?
    let finishedAt: String?
    let nextRetryAt: String?

    var isFinished: Bool {
        state == "delivered" || state == "failed"
    }

    var createdDate: Date? {
        CallFormatting.parseISO8601(createdAt)
    }

    var stateLabel: String {
        switch state {
        case "queued":
            "в очереди"
        case "sending":
            "отправляю"
        case "delivered":
            "доставлено"
        default:
            "ошибка"
        }
    }

    /// the one line both journals show next to the state
    var detailLine: String {
        switch state {
        case "queued":
            if let date = nextRetryAt.flatMap(CallFormatting.parseISO8601) {
                return "повтор в \(CallFormatting.clock(date))"
            }
            return ""
        case "delivered":
            return [httpStatus.map { "HTTP \($0)" }, responseAction].compactMap { $0 }.joined(separator: " · ")
        default:
            return error ?? ""
        }
    }
}

enum CallStoreError: LocalizedError {
    case sqlite(String)

    var errorDescription: String? {
        switch self {
        case .sqlite(let message):
            message
        }
    }
}

final class CallStore {
    private let dbURL: URL
    private let queue = DispatchQueue(label: "app.beseda.call-store")

    init(dbURL: URL = AppPaths.current.callIndexURL) {
        self.dbURL = dbURL
    }

    /// one schema version per entry, run in order; append a new one, never edit a released one
    typealias Migration = (OpaquePointer) throws -> Void

    var migrations: [Migration] {
        [createSchemaV1, addProcessingPending]
    }

    func prepare() throws {
        try prepare(migrations: migrations)
    }

    /// brings the file to `migrations.count` in `PRAGMA user_version`, backing it up first
    func prepare(migrations: [Migration]) throws {
        let fileExisted = FileManager.default.fileExists(atPath: dbURL.path)
        try database { db in
            try execute(db, "PRAGMA foreign_keys = ON")
            try execute(db, "PRAGMA journal_mode = WAL")
            let version = try query(db, "PRAGMA user_version") { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
            guard version < migrations.count else {
                return
            }
            if fileExisted {
                // VACUUM INTO writes a consistent copy even with a live WAL, and refuses an existing file
                let backupURL = backupURL(fromVersion: version)
                if FileManager.default.fileExists(atPath: backupURL.path) {
                    try FileManager.default.removeItem(at: backupURL)
                }
                try run(db, "VACUUM INTO ?", backupURL.path)
            }
            for (index, migrate) in migrations.enumerated().dropFirst(version) {
                try transaction(db) {
                    try migrate(db)
                    try execute(db, "PRAGMA user_version = \(index + 1)")
                }
            }
        }
    }

    func backupURL(fromVersion version: Int) -> URL {
        dbURL.deletingLastPathComponent().appendingPathComponent("\(dbURL.lastPathComponent).v\(version).backup")
    }

    /// version 1: whatever an unversioned file (0.3.x and older) holds, brought to one shape
    private func createSchemaV1(_ db: OpaquePointer) throws {
        try execute(db, """
            CREATE TABLE IF NOT EXISTS calls (
                id TEXT PRIMARY KEY,
                kind TEXT NOT NULL,
                started_at TEXT NOT NULL,
                ended_at TEXT,
                duration_sec REAL,
                status TEXT NOT NULL,
                transcript_path TEXT,
                audio_dir TEXT NOT NULL,
                error TEXT,
                app_name TEXT,
                summary_text TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """)
        let callColumns = try columns(db, table: "calls")
        for (column, type) in [
            ("app_name", "TEXT"),
            ("event_title", "TEXT"),
            ("event_id", "TEXT"),
            ("event_pinned", "INTEGER NOT NULL DEFAULT 0"),
            ("summary_text", "TEXT"),
            ("call_type", "TEXT"),
            ("event_series_id", "TEXT"),
            ("participants", "TEXT"),
            ("export_path", "TEXT")
        ] where !callColumns.contains(column) {
            try execute(db, "ALTER TABLE calls ADD COLUMN \(column) \(type)")
        }
        if callColumns.contains("keep_audio") {
            // retention rules replaced the per-call flag, and nothing reads the column now
            try execute(db, "ALTER TABLE calls DROP COLUMN keep_audio")
        }
        try execute(db, """
            CREATE TABLE IF NOT EXISTS transcript_segments (
                id TEXT PRIMARY KEY,
                call_id TEXT NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
                speaker TEXT NOT NULL,
                start_sec REAL NOT NULL,
                end_sec REAL,
                text TEXT NOT NULL,
                order_idx INTEGER NOT NULL
            )
            """)
        try execute(db, """
            CREATE INDEX IF NOT EXISTS idx_transcript_segments_call_order
            ON transcript_segments(call_id, order_idx)
            """)
        try execute(db, """
            CREATE TABLE IF NOT EXISTS transcript_jobs (
                id TEXT PRIMARY KEY,
                call_id TEXT NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
                speaker TEXT NOT NULL,
                status TEXT NOT NULL,
                audio_path TEXT NOT NULL,
                asr_json_path TEXT,
                audio_duration_sec REAL,
                wall_time_sec REAL,
                real_time_factor REAL,
                model TEXT,
                error TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """)
        if try !columns(db, table: "transcript_jobs").contains("model") {
            try execute(db, "ALTER TABLE transcript_jobs ADD COLUMN model TEXT")
        }
        try execute(db, """
            CREATE INDEX IF NOT EXISTS idx_transcript_jobs_call
            ON transcript_jobs(call_id, speaker)
            """)
        // only renames live here: a speaker left with its default name stores nothing
        try execute(db, """
            CREATE TABLE IF NOT EXISTS call_speakers (
                call_id TEXT NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
                speaker_key TEXT NOT NULL,
                display_name TEXT NOT NULL,
                PRIMARY KEY (call_id, speaker_key)
            )
            """)
        try execute(db, """
            CREATE TABLE IF NOT EXISTS webhook_deliveries (
                id TEXT PRIMARY KEY,
                call_id TEXT NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
                call_title TEXT NOT NULL,
                attempt INTEGER NOT NULL,
                event TEXT NOT NULL,
                url TEXT NOT NULL,
                state TEXT NOT NULL,
                http_status INTEGER,
                response_action TEXT,
                response_body TEXT,
                error TEXT,
                created_at TEXT NOT NULL,
                sent_at TEXT,
                finished_at TEXT,
                next_retry_at TEXT
            )
            """)
        try execute(db, """
            CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_call
            ON webhook_deliveries(call_id, attempt)
            """)
        try execute(db, """
            CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_due
            ON webhook_deliveries(state, next_retry_at)
            """)
    }

    /// version 2: a call waiting for auto-processing, so a quit does not drop the job
    private func addProcessingPending(_ db: OpaquePointer) throws {
        try execute(db, "ALTER TABLE calls ADD COLUMN processing_pending INTEGER NOT NULL DEFAULT 0")
    }

    /// audio folders of the calls it marked failed
    func failInterruptedCalls(reason: String) throws -> [String] {
        // a call left mid-flight belongs to a process that is gone, so the row can never move
        // forward on its own; failed keeps its folder and offers retry from the streamed raw audio
        try database { db in
            let paths = try query(db, """
                SELECT audio_dir FROM calls
                WHERE status IN ('recording', 'normalizing', 'transcribing')
                """) { columnString($0, 0) }
            try run(db, """
                UPDATE calls
                SET status = 'failed', error = ?, updated_at = ?
                WHERE status IN ('recording', 'normalizing', 'transcribing')
                """, reason, Date().iso8601WithFractions)
            return paths.compactMap { $0 }
        }
    }

    /// call folders the janitor must leave alone: a running job reads that audio, a failed one retries from it
    func protectedAudioDirectories() throws -> Set<String> {
        try database { db in
            let paths = try query(db, """
                SELECT audio_dir FROM calls
                WHERE status IN ('recording', 'normalizing', 'transcribing', 'failed')
                """) { columnString($0, 0) }
            return Set(paths.compactMap { $0 }.filter { !$0.isEmpty })
        }
    }

    func deleteCall(id: String) throws {
        try database { db in
            try execute(db, "PRAGMA foreign_keys = ON")
            // overwrite the freed pages and fold the WAL back, so no transcript text stays in the file
            try execute(db, "PRAGMA secure_delete = ON")
            try run(db, "DELETE FROM calls WHERE id = ?", id)
            try execute(db, "PRAGMA wal_checkpoint(TRUNCATE)")
        }
    }

    /// the row with its transcript, the call folder and the Markdown copy in the export folder
    func deleteCallAndFiles(id: String, exportFolder: URL?) throws {
        guard let call = try fetchCall(id: id) else {
            return
        }
        // the folder moves to the trash first: a failed row delete puts it back, and a trash that
        // cannot be emptied now is emptied on the next launch, so no row ever points at missing files
        let fileManager = FileManager.default
        let trashedFolder = trashURL.appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
        let folder = call.audioDirectoryPath.isEmpty ? nil : call.audioDirectoryURL
        let folderExists = folder.map { fileManager.fileExists(atPath: $0.path) } ?? false
        if let folder, folderExists {
            try fileManager.createDirectory(at: trashedFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fileManager.moveItem(at: folder, to: trashedFolder)
        }
        // the stored path finds a copy written under an older title; the current name covers
        // copies written before the path was stored
        let looseFiles = [
            call.transcriptURL, exportFolder?.appendingPathComponent(CallExport.fileName(call)),
            try exportPath(callID: id).map { URL(fileURLWithPath: $0) }
        ]
        do {
            try deleteCall(id: id)
        } catch {
            if let folder, folderExists {
                try? fileManager.moveItem(at: trashedFolder, to: folder)
            }
            throw error
        }
        for url in looseFiles.compactMap({ $0 }) where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try emptyTrash()
    }

    /// call folders a deletion moved aside and could not remove
    var trashURL: URL {
        dbURL.deletingLastPathComponent().appendingPathComponent("trash", isDirectory: true)
    }

    /// trash/<uuid>/<call id>; a folder whose row is still there (a restore that failed) is kept
    func emptyTrash() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: trashURL.path) else {
            return
        }
        for batch in try fileManager.contentsOfDirectory(at: trashURL, includingPropertiesForKeys: nil) {
            let callIDs = try fileManager.contentsOfDirectory(atPath: batch.path)
            if try callIDs.allSatisfy({ try fetchCall(id: $0) == nil }) {
                try fileManager.removeItem(at: batch)
            }
        }
    }

    func upsertCall(
        id: String,
        kind: String,
        startedAt: Date,
        endedAt: Date?,
        durationSec: Double?,
        status: String,
        transcriptURL: URL?,
        audioDirectoryURL: URL,
        error: String?,
        appName: String?
    ) throws {
        let now = Date().iso8601WithFractions
        try database { db in
            try run(db, """
                INSERT INTO calls (
                    id, kind, started_at, ended_at, duration_sec, status,
                    transcript_path, audio_dir, error, app_name, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    kind = excluded.kind,
                    started_at = excluded.started_at,
                    ended_at = excluded.ended_at,
                    duration_sec = excluded.duration_sec,
                    status = excluded.status,
                    transcript_path = excluded.transcript_path,
                    audio_dir = excluded.audio_dir,
                    error = excluded.error,
                    app_name = COALESCE(excluded.app_name, calls.app_name),
                    updated_at = excluded.updated_at
                """,
                id, kind, startedAt.iso8601WithFractions, endedAt?.iso8601WithFractions, durationSec, status,
                transcriptURL?.path, audioDirectoryURL.path, error, appName, now, now)
        }
    }

    func setError(callID: String, error: String) throws {
        try database { db in
            try run(db, "UPDATE calls SET error = ?, updated_at = ? WHERE id = ?", error, Date().iso8601WithFractions, callID)
        }
    }

    func setProcessingPending(callID: String, _ pending: Bool) throws {
        try database { db in
            try run(db, "UPDATE calls SET processing_pending = ? WHERE id = ?", pending, callID)
        }
    }

    /// auto-processing jobs the last run queued and never finished, oldest call first
    func fetchProcessingPendingCallIDs() throws -> [String] {
        try database { db in
            try query(db, "SELECT id FROM calls WHERE processing_pending = 1 ORDER BY started_at") { columnString($0, 0) }
                .compactMap { $0 }
        }
    }

    func replaceSegments(callID: String, segments: [StoredTranscriptSegment]) throws {
        try database { db in
            try transaction(db) {
                try writeSegments(db, callID: callID, segments: segments)
            }
        }
    }

    /// the transcript's lines and the ready status land together or not at all
    func markReady(callID: String, transcriptURL: URL, segments: [StoredTranscriptSegment]) throws {
        try database { db in
            try transaction(db) {
                try writeSegments(db, callID: callID, segments: segments)
                try run(db, "UPDATE calls SET status = 'ready', transcript_path = ?, error = NULL, updated_at = ? WHERE id = ?",
                        transcriptURL.path, Date().iso8601WithFractions, callID)
                guard sqlite3_changes(db) == 1 else {
                    throw CallStoreError.sqlite("No call \(callID) to mark ready")
                }
            }
        }
    }

    private func writeSegments(_ db: OpaquePointer, callID: String, segments: [StoredTranscriptSegment]) throws {
        try run(db, "DELETE FROM transcript_segments WHERE call_id = ?", callID)
        // a retry renumbers the speakers, so names pinned to the old keys are gone
        try run(db, "DELETE FROM call_speakers WHERE call_id = ?", callID)
        for segment in segments {
            try run(db, """
                INSERT INTO transcript_segments (id, call_id, speaker, start_sec, end_sec, text, order_idx)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                "\(callID)-\(segment.orderIndex)", callID, segment.speaker,
                segment.startSec, segment.endSec, segment.text, segment.orderIndex)
        }
    }

    func upsertTranscriptJob(
        id: String,
        callID: String,
        speaker: String,
        status: String,
        audioURL: URL,
        asrJSONURL: URL?,
        audioDurationSec: Double?,
        wallTimeSec: Double?,
        realTimeFactor: Double?,
        model: String?,
        error: String?
    ) throws {
        let now = Date().iso8601WithFractions
        try database { db in
            try run(db, """
                INSERT INTO transcript_jobs (
                    id, call_id, speaker, status, audio_path, asr_json_path,
                    audio_duration_sec, wall_time_sec, real_time_factor,
                    model, error, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    call_id = excluded.call_id,
                    speaker = excluded.speaker,
                    status = excluded.status,
                    audio_path = excluded.audio_path,
                    asr_json_path = excluded.asr_json_path,
                    audio_duration_sec = excluded.audio_duration_sec,
                    wall_time_sec = excluded.wall_time_sec,
                    real_time_factor = excluded.real_time_factor,
                    model = excluded.model,
                    error = excluded.error,
                    updated_at = excluded.updated_at
                """,
                id, callID, speaker, status, audioURL.path, asrJSONURL?.path,
                audioDurationSec, wallTimeSec, realTimeFactor, model, error, now, now)
        }
    }

    func fetchCalls(limit: Int = 200) throws -> [StoredCallSummary] {
        try database { db in
            try query(db, "\(Self.callSelect) ORDER BY c.started_at DESC LIMIT ?", limit, row: makeSummary)
        }
    }

    func fetchCall(id: String) throws -> StoredCallSummary? {
        try database { db in
            try query(db, "\(Self.callSelect) WHERE c.id = ? LIMIT 1", id, row: makeSummary).first
        }
    }

    private static let callSelect = """
        SELECT c.id, c.kind, c.started_at, c.ended_at, c.duration_sec, c.status,
               c.transcript_path, c.audio_dir, c.error, c.app_name, c.summary_text,
               (SELECT group_concat(text, '. ') FROM
                 (SELECT text FROM transcript_segments
                   WHERE call_id = c.id ORDER BY order_idx LIMIT 5)),
               c.event_title, c.event_id, c.event_pinned, c.call_type,
               c.event_series_id, c.participants
        FROM calls c
        """

    private func makeSummary(_ statement: OpaquePointer) -> StoredCallSummary {
        StoredCallSummary(
            id: columnString(statement, 0) ?? "",
            kind: columnString(statement, 1) ?? "",
            startedAt: columnString(statement, 2) ?? "",
            endedAt: columnString(statement, 3),
            durationSec: columnDouble(statement, 4),
            status: columnString(statement, 5) ?? "",
            transcriptPath: columnString(statement, 6),
            audioDirectoryPath: columnString(statement, 7) ?? "",
            error: columnString(statement, 8),
            appName: columnString(statement, 9),
            previewText: columnString(statement, 11),
            summaryText: columnString(statement, 10),
            eventTitle: columnString(statement, 12),
            eventID: columnString(statement, 13),
            eventPinned: sqlite3_column_int64(statement, 14) != 0,
            callType: columnString(statement, 15),
            eventSeriesID: columnString(statement, 16),
            participants: columnString(statement, 17)?.split(separator: "\n").map(String.init) ?? []
        )
    }

    /// nil title clears the link, so "Без события" is stored rather than left to the matcher
    func setEvent(
        callID: String,
        title: String?,
        eventID: String?,
        pinned: Bool,
        seriesID: String? = nil,
        participants: [String] = []
    ) throws {
        let joinedParticipants = participants.isEmpty ? nil : participants.joined(separator: "\n")
        try database { db in
            try run(db, """
                UPDATE calls
                SET event_title = ?, event_id = ?, event_pinned = ?, event_series_id = ?, participants = ?,
                    updated_at = ?
                WHERE id = ?
                """, title, eventID, pinned, seriesID, joinedParticipants, Date().iso8601WithFractions, callID)
        }
    }

    /// nil wipes the stored summary, so a failed regeneration does not leave the old text behind
    func setSummary(callID: String, text: String?) throws {
        try database { db in
            try run(db, "UPDATE calls SET summary_text = ?, updated_at = ? WHERE id = ?",
                    text, Date().iso8601WithFractions, callID)
        }
    }

    func setCallType(callID: String, name: String?) throws {
        try database { db in
            try run(db, "UPDATE calls SET call_type = ?, updated_at = ? WHERE id = ?",
                    name, Date().iso8601WithFractions, callID)
        }
    }

    /// where the call's Markdown copy was last written; nil when it was never exported
    func exportPath(callID: String) throws -> String? {
        try database { db in
            try query(db, "SELECT export_path FROM calls WHERE id = ?", callID) { columnString($0, 0) }.first ?? nil
        }
    }

    /// a renamed call is written under a new name: the copy under the old one goes, or it lingers
    func replaceExportCopy(callID: String, with url: URL) throws {
        if let oldPath = try exportPath(callID: callID), oldPath != url.path,
           FileManager.default.fileExists(atPath: oldPath) {
            try FileManager.default.removeItem(atPath: oldPath)
        }
        try database { db in
            try run(db, "UPDATE calls SET export_path = ? WHERE id = ?", url.path, callID)
        }
    }

    // MARK: - Webhook deliveries

    func insertWebhookDelivery(
        id: String,
        callID: String,
        callTitle: String,
        attempt: Int,
        event: String,
        url: String,
        nextRetryAt: Date
    ) throws {
        try database { db in
            try run(db, """
                INSERT INTO webhook_deliveries
                    (id, call_id, call_title, attempt, event, url, state, created_at, next_retry_at)
                VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?)
                """,
                id, callID, callTitle, attempt, event, url,
                Date().iso8601WithFractions, nextRetryAt.iso8601WithFractions)
        }
    }

    /// the url is written again here: the user may have fixed the address since the row was queued
    func markWebhookSending(id: String, url: String) throws {
        try database { db in
            try run(db, "UPDATE webhook_deliveries SET state = 'sending', sent_at = ?, url = ? WHERE id = ?",
                    Date().iso8601WithFractions, url, id)
        }
    }

    func finishWebhookDelivery(
        id: String,
        state: String,
        httpStatus: Int?,
        responseAction: String?,
        responseBody: String?,
        error: String?
    ) throws {
        try database { db in
            try run(db, """
                UPDATE webhook_deliveries
                SET state = ?, http_status = ?, response_action = ?, response_body = ?, error = ?, finished_at = ?
                WHERE id = ?
                """, state, httpStatus, responseAction, responseBody, error, Date().iso8601WithFractions, id)
        }
    }

    func fetchWebhookDeliveries(callID: String) throws -> [StoredWebhookDelivery] {
        try database { db in
            try query(db, "\(Self.webhookSelect) WHERE call_id = ? ORDER BY attempt DESC", callID, row: makeWebhookDelivery)
        }
    }

    func fetchRecentWebhookDeliveries(limit: Int = 20) throws -> [StoredWebhookDelivery] {
        try database { db in
            try query(db, "\(Self.webhookSelect) ORDER BY created_at DESC LIMIT ?", limit, row: makeWebhookDelivery)
        }
    }

    func fetchDueWebhookDeliveries(now: Date) throws -> [StoredWebhookDelivery] {
        try database { db in
            try query(db, "\(Self.webhookSelect) WHERE state = 'queued' AND next_retry_at <= ? ORDER BY next_retry_at ASC",
                      now.iso8601WithFractions, row: makeWebhookDelivery)
        }
    }

    func webhookAttemptCount(callID: String) throws -> Int {
        try database { db in
            try query(db, "SELECT COUNT(*) FROM webhook_deliveries WHERE call_id = ?", callID) {
                Int(sqlite3_column_int64($0, 0))
            }.first ?? 0
        }
    }

    /// rows the app was quit in the middle of; returned so the caller can queue the next attempt
    func failInterruptedWebhookDeliveries(reason: String) throws -> [StoredWebhookDelivery] {
        try database { db in
            let interrupted = try query(db, "\(Self.webhookSelect) WHERE state = 'sending'", row: makeWebhookDelivery)
            try run(db, "UPDATE webhook_deliveries SET state = 'failed', error = ?, finished_at = ? WHERE state = 'sending'",
                    reason, Date().iso8601WithFractions)
            return interrupted
        }
    }

    private static let webhookSelect = """
        SELECT id, call_id, call_title, attempt, event, url, state, http_status, response_action, response_body, \
        error, created_at, sent_at, finished_at, next_retry_at FROM webhook_deliveries
        """

    private func makeWebhookDelivery(_ statement: OpaquePointer) -> StoredWebhookDelivery {
        StoredWebhookDelivery(
            id: columnString(statement, 0) ?? "",
            callID: columnString(statement, 1) ?? "",
            callTitle: columnString(statement, 2) ?? "",
            attempt: Int(sqlite3_column_int64(statement, 3)),
            event: columnString(statement, 4) ?? "",
            url: columnString(statement, 5) ?? "",
            state: columnString(statement, 6) ?? "",
            httpStatus: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 7)),
            responseAction: columnString(statement, 8),
            responseBody: columnString(statement, 9),
            error: columnString(statement, 10),
            createdAt: columnString(statement, 11) ?? "",
            sentAt: columnString(statement, 12),
            finishedAt: columnString(statement, 13),
            nextRetryAt: columnString(statement, 14)
        )
    }

    /// the honest counter under the calendar switch in settings
    func eventCoverage() throws -> (matched: Int, total: Int) {
        try database { db in
            try query(db, "SELECT COUNT(event_title), COUNT(*) FROM calls") {
                (matched: Int(sqlite3_column_int64($0, 0)), total: Int(sqlite3_column_int64($0, 1)))
            }.first ?? (matched: 0, total: 0)
        }
    }

    func fetchJobStats(callID: String) throws -> StoredJobStats? {
        try database { db in
            try query(db, """
                SELECT SUM(wall_time_sec), AVG(real_time_factor), MAX(model)
                FROM transcript_jobs
                WHERE call_id = ? AND status = 'ready'
                """, callID) { statement in
                columnDouble(statement, 0).map {
                    StoredJobStats(wallTimeSec: $0, realTimeFactor: columnDouble(statement, 1), model: columnString(statement, 2))
                }
            }.first ?? nil
        }
    }

    /// call ids whose transcript contains the query; the sidebar search reaches inside
    /// transcripts without loading every segment of every call
    func searchCallIDs(matching query: String) throws -> Set<String> {
        let escaped = query
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
        return try database { db in
            let ids = try self.query(db, "SELECT DISTINCT call_id FROM transcript_segments WHERE text LIKE ? ESCAPE '\\'",
                                     "%\(escaped)%") { columnString($0, 0) }
            return Set(ids.compactMap { $0 })
        }
    }

    func setSpeakerName(callID: String, speakerKey: String, displayName: String?) throws {
        try database { db in
            guard let displayName, !displayName.isEmpty else {
                return try run(db, "DELETE FROM call_speakers WHERE call_id = ? AND speaker_key = ?", callID, speakerKey)
            }
            try run(db, """
                INSERT INTO call_speakers (call_id, speaker_key, display_name)
                VALUES (?, ?, ?)
                ON CONFLICT(call_id, speaker_key) DO UPDATE SET display_name = excluded.display_name
                """, callID, speakerKey, displayName)
        }
    }

    /// relabels every segment of `speakerKey` as `targetKey`; the merged speaker's name goes with it
    func mergeSpeaker(callID: String, speakerKey: String, into targetKey: String) throws {
        try database { db in
            try execute(db, "BEGIN IMMEDIATE TRANSACTION")
            do {
                try run(db, "UPDATE transcript_segments SET speaker = ? WHERE call_id = ? AND speaker = ?",
                        targetKey, callID, speakerKey)
                try run(db, "DELETE FROM call_speakers WHERE call_id = ? AND speaker_key = ?", callID, speakerKey)
                try execute(db, "COMMIT")
            } catch {
                try? execute(db, "ROLLBACK")
                throw error
            }
        }
    }

    func fetchSpeakerNames(callID: String) throws -> [String: String] {
        try database { db in
            let pairs = try query(db, "SELECT speaker_key, display_name FROM call_speakers WHERE call_id = ?", callID) {
                (columnString($0, 0) ?? "", columnString($0, 1) ?? "")
            }
            return Dictionary(pairs, uniquingKeysWith: { _, last in last })
        }
    }

    func fetchSegments(callID: String) throws -> [StoredTranscriptSegment] {
        try database { db in
            try query(db, """
                SELECT speaker, start_sec, end_sec, text, order_idx
                FROM transcript_segments
                WHERE call_id = ?
                ORDER BY order_idx ASC
                """, callID) { statement in
                StoredTranscriptSegment(
                    speaker: columnString(statement, 0) ?? "",
                    startSec: columnDouble(statement, 1) ?? 0,
                    endSec: columnDouble(statement, 2),
                    text: columnString(statement, 3) ?? "",
                    orderIndex: Int(sqlite3_column_int64(statement, 4))
                )
            }
        }
    }

    // MARK: - SQLite

    /// every call opens its own connection on the serial queue, so callers on any thread see one writer
    private func database<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try queue.sync {
            try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var db: OpaquePointer?
            let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
            guard sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK, let db else {
                let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite database"
                sqlite3_close(db)
                throw CallStoreError.sqlite(message)
            }
            defer {
                sqlite3_close(db)
            }
            return try body(db)
        }
    }

    private func transaction(_ db: OpaquePointer, _ body: () throws -> Void) throws {
        try execute(db, "BEGIN IMMEDIATE TRANSACTION")
        do {
            try body()
            try execute(db, "COMMIT")
        } catch {
            try? execute(db, "ROLLBACK")
            throw error
        }
    }

    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw CallStoreError.sqlite(message)
        }
    }

    /// one statement that returns no rows
    private func run(_ db: OpaquePointer, _ sql: String, _ values: Any?...) throws {
        _ = try rows(db, sql, values) { _ in () }
    }

    private func query<T>(_ db: OpaquePointer, _ sql: String, _ values: Any?..., row: (OpaquePointer) throws -> T) throws -> [T] {
        try rows(db, sql, values, row: row)
    }

    private func rows<T>(_ db: OpaquePointer, _ sql: String, _ values: [Any?], row: (OpaquePointer) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer {
            sqlite3_finalize(statement)
        }
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status = switch value {
            case nil: sqlite3_bind_null(statement, index)
            case let text as String: sqlite3_bind_text(statement, index, text, -1, sqliteTransient)
            case let flag as Bool: sqlite3_bind_int64(statement, index, flag ? 1 : 0)
            case let number as Int: sqlite3_bind_int64(statement, index, Int64(number))
            case let number as Double: sqlite3_bind_double(statement, index, number)
            default: preconditionFailure("CallStore cannot bind \(type(of: value!))")
            }
            guard status == SQLITE_OK else {
                throw CallStoreError.sqlite("Could not bind value at index \(index)")
            }
        }
        var rows: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append(try row(statement))
            case SQLITE_DONE:
                return rows
            default:
                throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    private func columns(_ db: OpaquePointer, table: String) throws -> Set<String> {
        Set(try query(db, "PRAGMA table_info(\(table))") { columnString($0, 1) ?? "" })
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
    sqlite3_column_text(statement, index).map { String(cString: $0) }
}

private func columnDouble(_ statement: OpaquePointer, _ index: Int32) -> Double? {
    sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : sqlite3_column_double(statement, index)
}

extension Date {
    /// the one timestamp format in the index; webhook retry times are compared as these strings
    var iso8601WithFractions: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}
