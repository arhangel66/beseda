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

    var timeRangeDescription: String {
        guard let endSec else {
            return startSec.mmss
        }
        return "\(startSec.mmss)-\(endSec.mmss)"
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

    var canRetry: Bool {
        status == "failed"
    }

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

    /// the badge next to the name: where the name came from
    var titleSource: String {
        isFromCalendar ? "из календаря" : "по теме разговора"
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

    /// the sidebar's leading column: just the start time
    var clockDescription: String {
        startedDate.map { CallFormatting.clock($0) } ?? ""
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
            return "\(appLabel) · \(Self.statusLabels[status] ?? status)"
        }
        return "\(appLabel) · \(isDual ? "два канала" : "микрофон")"
    }

    /// a call left in one of these states by a crash still has to read as Russian
    private static let statusLabels = [
        "recording": "записываю",
        "normalizing": "готовплю запись",
        "transcribing": "расшифровываю"
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
        return "RTF \(String(format: "%.3f", realTimeFactor))× · расшифровка за \(String(format: "%.0f", wallTimeSec)) с"
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

    func prepare() throws {
        try queue.sync {
            try withDatabase { db in
                try execute(db, "PRAGMA foreign_keys = ON")
                try execute(db, "PRAGMA journal_mode = WAL")
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
                if try !columnExists(db, table: "calls", column: "app_name") {
                    try execute(db, "ALTER TABLE calls ADD COLUMN app_name TEXT")
                }
                if try !columnExists(db, table: "calls", column: "event_title") {
                    try execute(db, "ALTER TABLE calls ADD COLUMN event_title TEXT")
                }
                if try !columnExists(db, table: "calls", column: "event_id") {
                    try execute(db, "ALTER TABLE calls ADD COLUMN event_id TEXT")
                }
                if try !columnExists(db, table: "calls", column: "event_pinned") {
                    try execute(db, "ALTER TABLE calls ADD COLUMN event_pinned INTEGER NOT NULL DEFAULT 0")
                }
                if try !columnExists(db, table: "calls", column: "summary_text") {
                    try execute(db, "ALTER TABLE calls ADD COLUMN summary_text TEXT")
                }
                if try columnExists(db, table: "calls", column: "keep_audio") {
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
                if try !columnExists(db, table: "transcript_jobs", column: "model") {
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
        }
    }

    func failInterruptedCalls(reason: String) throws -> Int {
        // a call left mid-flight belongs to a process that is gone: the audio was only
        // buffered in memory, so the row can never move forward on its own
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    UPDATE calls
                    SET status = 'failed', error = ?, updated_at = ?
                    WHERE status IN ('recording', 'normalizing', 'transcribing')
                    """
                return try withStatement(db, sql) { statement in
                    try bind(statement, 1, reason)
                    try bind(statement, 2, Date().iso8601WithFractions)
                    try stepDone(statement, db)
                    return Int(sqlite3_changes(db))
                }
            }
        }
    }

    /// call folders the janitor must leave alone: a running job reads that audio, a failed one retries from it
    func protectedAudioDirectories() throws -> Set<String> {
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    SELECT audio_dir FROM calls
                    WHERE status IN ('recording', 'normalizing', 'transcribing', 'failed')
                    """
                return try withStatement(db, sql) { statement in
                    var directories: Set<String> = []
                    while sqlite3_step(statement) == SQLITE_ROW {
                        if let path = columnString(statement, 0), !path.isEmpty {
                            directories.insert(path)
                        }
                    }
                    return directories
                }
            }
        }
    }

    func deleteCall(id: String) throws {
        try queue.sync {
            try withDatabase { db in
                try execute(db, "PRAGMA foreign_keys = ON")
                try withStatement(db, "DELETE FROM calls WHERE id = ?") { statement in
                    try bind(statement, 1, id)
                    try stepDone(statement, db)
                }
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
        try queue.sync {
            try withDatabase { db in
                let sql = """
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
                    """
                let now = Date().iso8601WithFractions
                try withStatement(db, sql) { statement in
                    try bind(statement, 1, id)
                    try bind(statement, 2, kind)
                    try bind(statement, 3, startedAt.iso8601WithFractions)
                    try bind(statement, 4, endedAt?.iso8601WithFractions)
                    try bind(statement, 5, durationSec)
                    try bind(statement, 6, status)
                    try bind(statement, 7, transcriptURL?.path)
                    try bind(statement, 8, audioDirectoryURL.path)
                    try bind(statement, 9, error)
                    try bind(statement, 10, appName)
                    try bind(statement, 11, now)
                    try bind(statement, 12, now)
                    try stepDone(statement, db)
                }
            }
        }
    }

    func replaceSegments(callID: String, segments: [StoredTranscriptSegment]) throws {
        try queue.sync {
            try withDatabase { db in
                try execute(db, "BEGIN IMMEDIATE TRANSACTION")
                do {
                    try withStatement(db, "DELETE FROM transcript_segments WHERE call_id = ?") { statement in
                        try bind(statement, 1, callID)
                        try stepDone(statement, db)
                    }
                    // a retry renumbers the speakers, so names pinned to the old keys are gone
                    try withStatement(db, "DELETE FROM call_speakers WHERE call_id = ?") { statement in
                        try bind(statement, 1, callID)
                        try stepDone(statement, db)
                    }

                    let insertSQL = """
                        INSERT INTO transcript_segments (
                            id, call_id, speaker, start_sec, end_sec, text, order_idx
                        )
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """
                    for segment in segments {
                        try withStatement(db, insertSQL) { statement in
                            try bind(statement, 1, "\(callID)-\(segment.orderIndex)")
                            try bind(statement, 2, callID)
                            try bind(statement, 3, segment.speaker)
                            try bind(statement, 4, segment.startSec)
                            try bind(statement, 5, segment.endSec)
                            try bind(statement, 6, segment.text)
                            try bind(statement, 7, Int64(segment.orderIndex))
                            try stepDone(statement, db)
                        }
                    }
                    try execute(db, "COMMIT")
                } catch {
                    try? execute(db, "ROLLBACK")
                    throw error
                }
            }
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
        try queue.sync {
            try withDatabase { db in
                let sql = """
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
                    """
                let now = Date().iso8601WithFractions
                try withStatement(db, sql) { statement in
                    try bind(statement, 1, id)
                    try bind(statement, 2, callID)
                    try bind(statement, 3, speaker)
                    try bind(statement, 4, status)
                    try bind(statement, 5, audioURL.path)
                    try bind(statement, 6, asrJSONURL?.path)
                    try bind(statement, 7, audioDurationSec)
                    try bind(statement, 8, wallTimeSec)
                    try bind(statement, 9, realTimeFactor)
                    try bind(statement, 10, model)
                    try bind(statement, 11, error)
                    try bind(statement, 12, now)
                    try bind(statement, 13, now)
                    try stepDone(statement, db)
                }
            }
        }
    }

    func fetchRecentCalls(limit: Int = 10) throws -> [StoredCallSummary] {
        try fetchCalls(limit: limit)
    }

    func fetchCalls(limit: Int = 200) throws -> [StoredCallSummary] {
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    SELECT c.id, c.kind, c.started_at, c.ended_at, c.duration_sec, c.status,
                           c.transcript_path, c.audio_dir, c.error, c.app_name, c.summary_text,
                           (SELECT group_concat(text, '. ') FROM
                             (SELECT text FROM transcript_segments
                               WHERE call_id = c.id ORDER BY order_idx LIMIT 5)),
                           c.event_title, c.event_id, c.event_pinned
                    FROM calls c
                    ORDER BY c.started_at DESC
                    LIMIT ?
                    """
                return try withStatement(db, sql) { statement in
                    try bind(statement, 1, Int64(limit))

                    var calls: [StoredCallSummary] = []
                    while true {
                        let status = sqlite3_step(statement)
                        if status == SQLITE_DONE {
                            break
                        }
                        guard status == SQLITE_ROW else {
                            throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
                        }

                        calls.append(makeSummary(statement))
                    }
                    return calls
                }
            }
        }
    }

    func fetchCall(id: String) throws -> StoredCallSummary? {
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    SELECT c.id, c.kind, c.started_at, c.ended_at, c.duration_sec, c.status,
                           c.transcript_path, c.audio_dir, c.error, c.app_name, c.summary_text,
                           (SELECT group_concat(text, '. ') FROM
                             (SELECT text FROM transcript_segments
                               WHERE call_id = c.id ORDER BY order_idx LIMIT 5)),
                           c.event_title, c.event_id, c.event_pinned
                    FROM calls c
                    WHERE c.id = ?
                    LIMIT 1
                    """
                return try withStatement(db, sql) { statement in
                    try bind(statement, 1, id)

                    let status = sqlite3_step(statement)
                    if status == SQLITE_DONE {
                        return nil
                    }
                    guard status == SQLITE_ROW else {
                        throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
                    }

                    return makeSummary(statement)
                }
            }
        }
    }

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
            eventPinned: sqlite3_column_int64(statement, 14) != 0
        )
    }

    /// nil title clears the link, so "Без события" is stored rather than left to the matcher
    func setEvent(callID: String, title: String?, eventID: String?, pinned: Bool) throws {
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    UPDATE calls
                    SET event_title = ?, event_id = ?, event_pinned = ?, updated_at = ?
                    WHERE id = ?
                    """
                try withStatement(db, sql) { statement in
                    try bind(statement, 1, title)
                    try bind(statement, 2, eventID)
                    try bind(statement, 3, Int64(pinned ? 1 : 0))
                    try bind(statement, 4, Date().iso8601WithFractions)
                    try bind(statement, 5, callID)
                    try stepDone(statement, db)
                }
            }
        }
    }

    /// nil wipes the stored summary, so a failed regeneration does not leave the old text behind
    func setSummary(callID: String, text: String?) throws {
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    UPDATE calls
                    SET summary_text = ?, updated_at = ?
                    WHERE id = ?
                    """
                try withStatement(db, sql) { statement in
                    try bind(statement, 1, text)
                    try bind(statement, 2, Date().iso8601WithFractions)
                    try bind(statement, 3, callID)
                    try stepDone(statement, db)
                }
            }
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
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    INSERT INTO webhook_deliveries
                        (id, call_id, call_title, attempt, event, url, state, created_at, next_retry_at)
                    VALUES (?, ?, ?, ?, ?, ?, 'queued', ?, ?)
                    """
                try withStatement(db, sql) { statement in
                    try bind(statement, 1, id)
                    try bind(statement, 2, callID)
                    try bind(statement, 3, callTitle)
                    try bind(statement, 4, Int64(attempt))
                    try bind(statement, 5, event)
                    try bind(statement, 6, url)
                    try bind(statement, 7, Date().iso8601WithFractions)
                    try bind(statement, 8, nextRetryAt.iso8601WithFractions)
                    try stepDone(statement, db)
                }
            }
        }
    }

    /// the url is written again here: the user may have fixed the address since the row was queued
    func markWebhookSending(id: String, url: String) throws {
        try queue.sync {
            try withDatabase { db in
                let sql = "UPDATE webhook_deliveries SET state = 'sending', sent_at = ?, url = ? WHERE id = ?"
                try withStatement(db, sql) { statement in
                    try bind(statement, 1, Date().iso8601WithFractions)
                    try bind(statement, 2, url)
                    try bind(statement, 3, id)
                    try stepDone(statement, db)
                }
            }
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
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    UPDATE webhook_deliveries
                    SET state = ?, http_status = ?, response_action = ?, response_body = ?, error = ?, finished_at = ?
                    WHERE id = ?
                    """
                try withStatement(db, sql) { statement in
                    try bind(statement, 1, state)
                    try bind(statement, 2, httpStatus.map(Int64.init))
                    try bind(statement, 3, responseAction)
                    try bind(statement, 4, responseBody)
                    try bind(statement, 5, error)
                    try bind(statement, 6, Date().iso8601WithFractions)
                    try bind(statement, 7, id)
                    try stepDone(statement, db)
                }
            }
        }
    }

    func fetchWebhookDeliveries(callID: String) throws -> [StoredWebhookDelivery] {
        try queue.sync {
            try withDatabase { db in
                let sql = "SELECT \(Self.webhookColumns) FROM webhook_deliveries WHERE call_id = ? ORDER BY attempt DESC"
                return try withStatement(db, sql) { statement in
                    try bind(statement, 1, callID)
                    return try readWebhookDeliveries(statement, db)
                }
            }
        }
    }

    func fetchRecentWebhookDeliveries(limit: Int = 20) throws -> [StoredWebhookDelivery] {
        try queue.sync {
            try withDatabase { db in
                let sql = "SELECT \(Self.webhookColumns) FROM webhook_deliveries ORDER BY created_at DESC LIMIT ?"
                return try withStatement(db, sql) { statement in
                    try bind(statement, 1, Int64(limit))
                    return try readWebhookDeliveries(statement, db)
                }
            }
        }
    }

    func fetchDueWebhookDeliveries(now: Date) throws -> [StoredWebhookDelivery] {
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    SELECT \(Self.webhookColumns) FROM webhook_deliveries
                    WHERE state = 'queued' AND next_retry_at <= ?
                    ORDER BY next_retry_at ASC
                    """
                return try withStatement(db, sql) { statement in
                    try bind(statement, 1, now.iso8601WithFractions)
                    return try readWebhookDeliveries(statement, db)
                }
            }
        }
    }

    func webhookAttemptCount(callID: String) throws -> Int {
        try queue.sync {
            try withDatabase { db in
                try withStatement(db, "SELECT COUNT(*) FROM webhook_deliveries WHERE call_id = ?") { statement in
                    try bind(statement, 1, callID)
                    guard sqlite3_step(statement) == SQLITE_ROW else {
                        throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
                    }
                    return Int(sqlite3_column_int64(statement, 0))
                }
            }
        }
    }

    /// rows the app was quit in the middle of; returned so the caller can queue the next attempt
    func failInterruptedWebhookDeliveries(reason: String) throws -> [StoredWebhookDelivery] {
        try queue.sync {
            try withDatabase { db in
                let interrupted = try withStatement(
                    db, "SELECT \(Self.webhookColumns) FROM webhook_deliveries WHERE state = 'sending'"
                ) { statement in
                    try readWebhookDeliveries(statement, db)
                }
                let sql = "UPDATE webhook_deliveries SET state = 'failed', error = ?, finished_at = ? WHERE state = 'sending'"
                try withStatement(db, sql) { statement in
                    try bind(statement, 1, reason)
                    try bind(statement, 2, Date().iso8601WithFractions)
                    try stepDone(statement, db)
                }
                return interrupted
            }
        }
    }

    private static let webhookColumns = """
        id, call_id, call_title, attempt, event, url, state, http_status, response_action, response_body, \
        error, created_at, sent_at, finished_at, next_retry_at
        """

    private func readWebhookDeliveries(_ statement: OpaquePointer, _ db: OpaquePointer) throws -> [StoredWebhookDelivery] {
        var rows: [StoredWebhookDelivery] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE {
                break
            }
            guard status == SQLITE_ROW else {
                throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
            }
            rows.append(
                StoredWebhookDelivery(
                    id: columnString(statement, 0) ?? "",
                    callID: columnString(statement, 1) ?? "",
                    callTitle: columnString(statement, 2) ?? "",
                    attempt: Int(sqlite3_column_int64(statement, 3)),
                    event: columnString(statement, 4) ?? "",
                    url: columnString(statement, 5) ?? "",
                    state: columnString(statement, 6) ?? "",
                    httpStatus: columnInt(statement, 7),
                    responseAction: columnString(statement, 8),
                    responseBody: columnString(statement, 9),
                    error: columnString(statement, 10),
                    createdAt: columnString(statement, 11) ?? "",
                    sentAt: columnString(statement, 12),
                    finishedAt: columnString(statement, 13),
                    nextRetryAt: columnString(statement, 14)
                )
            )
        }
        return rows
    }

    /// the honest counter under the calendar switch in settings
    func eventCoverage() throws -> (matched: Int, total: Int) {
        try queue.sync {
            try withDatabase { db in
                let sql = "SELECT COUNT(event_title), COUNT(*) FROM calls"
                return try withStatement(db, sql) { statement in
                    guard sqlite3_step(statement) == SQLITE_ROW else {
                        return (matched: 0, total: 0)
                    }
                    return (
                        matched: Int(sqlite3_column_int64(statement, 0)),
                        total: Int(sqlite3_column_int64(statement, 1))
                    )
                }
            }
        }
    }

    func fetchJobStats(callID: String) throws -> StoredJobStats? {
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    SELECT SUM(wall_time_sec), AVG(real_time_factor), MAX(model)
                    FROM transcript_jobs
                    WHERE call_id = ? AND status = 'ready'
                    """
                return try withStatement(db, sql) { statement in
                    try bind(statement, 1, callID)
                    guard sqlite3_step(statement) == SQLITE_ROW,
                          let wallTime = columnDouble(statement, 0) else {
                        return nil
                    }
                    return StoredJobStats(
                        wallTimeSec: wallTime,
                        realTimeFactor: columnDouble(statement, 1),
                        model: columnString(statement, 2)
                    )
                }
            }
        }
    }

    /// call ids whose transcript contains the query; the sidebar search reaches inside
    /// transcripts without loading every segment of every call
    func searchCallIDs(matching query: String) throws -> Set<String> {
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    SELECT DISTINCT call_id FROM transcript_segments
                    WHERE text LIKE ? ESCAPE '\\'
                    """
                return try withStatement(db, sql) { statement in
                    try bind(statement, 1, "%\(query.sqliteLikeEscaped)%")

                    var ids: Set<String> = []
                    while true {
                        let status = sqlite3_step(statement)
                        if status == SQLITE_DONE {
                            break
                        }
                        guard status == SQLITE_ROW else {
                            throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
                        }
                        if let id = columnString(statement, 0) {
                            ids.insert(id)
                        }
                    }
                    return ids
                }
            }
        }
    }

    private func columnExists(_ db: OpaquePointer, table: String, column: String) throws -> Bool {
        try withStatement(db, "PRAGMA table_info(\(table))") { statement in
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE {
                    return false
                }
                guard status == SQLITE_ROW else {
                    throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
                }
                if columnString(statement, 1) == column {
                    return true
                }
            }
        }
    }

    func setSpeakerName(callID: String, speakerKey: String, displayName: String?) throws {
        try queue.sync {
            try withDatabase { db in
                guard let displayName, !displayName.isEmpty else {
                    return try withStatement(
                        db,
                        "DELETE FROM call_speakers WHERE call_id = ? AND speaker_key = ?"
                    ) { statement in
                        try bind(statement, 1, callID)
                        try bind(statement, 2, speakerKey)
                        try stepDone(statement, db)
                    }
                }

                let sql = """
                    INSERT INTO call_speakers (call_id, speaker_key, display_name)
                    VALUES (?, ?, ?)
                    ON CONFLICT(call_id, speaker_key) DO UPDATE SET display_name = excluded.display_name
                    """
                try withStatement(db, sql) { statement in
                    try bind(statement, 1, callID)
                    try bind(statement, 2, speakerKey)
                    try bind(statement, 3, displayName)
                    try stepDone(statement, db)
                }
            }
        }
    }

    func fetchSpeakerNames(callID: String) throws -> [String: String] {
        try queue.sync {
            try withDatabase { db in
                let sql = "SELECT speaker_key, display_name FROM call_speakers WHERE call_id = ?"
                return try withStatement(db, sql) { statement in
                    try bind(statement, 1, callID)

                    var names: [String: String] = [:]
                    while true {
                        let status = sqlite3_step(statement)
                        if status == SQLITE_DONE {
                            break
                        }
                        guard status == SQLITE_ROW else {
                            throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
                        }
                        if let key = columnString(statement, 0), let name = columnString(statement, 1) {
                            names[key] = name
                        }
                    }
                    return names
                }
            }
        }
    }

    func fetchSegments(callID: String) throws -> [StoredTranscriptSegment] {
        try queue.sync {
            try withDatabase { db in
                let sql = """
                    SELECT speaker, start_sec, end_sec, text, order_idx
                    FROM transcript_segments
                    WHERE call_id = ?
                    ORDER BY order_idx ASC
                    """
                return try withStatement(db, sql) { statement in
                    try bind(statement, 1, callID)

                    var segments: [StoredTranscriptSegment] = []
                    while true {
                        let status = sqlite3_step(statement)
                        if status == SQLITE_DONE {
                            break
                        }
                        guard status == SQLITE_ROW else {
                            throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
                        }

                        segments.append(
                            StoredTranscriptSegment(
                                speaker: columnString(statement, 0) ?? "",
                                startSec: columnDouble(statement, 1) ?? 0,
                                endSec: columnDouble(statement, 2),
                                text: columnString(statement, 3) ?? "",
                                orderIndex: Int(sqlite3_column_int64(statement, 4))
                            )
                        )
                    }
                    return segments
                }
            }
        }
    }

    private func withDatabase<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: dbURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(dbURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open SQLite database"
            if let db {
                sqlite3_close(db)
            }
            throw CallStoreError.sqlite(message)
        }

        defer {
            sqlite3_close(db)
        }

        return try body(db)
    }

    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        guard status == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw CallStoreError.sqlite(message)
        }
    }

    private func withStatement<T>(_ db: OpaquePointer, _ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        defer {
            sqlite3_finalize(statement)
        }
        return try body(statement)
    }

    private func stepDone(_ statement: OpaquePointer, _ db: OpaquePointer) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CallStoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: String?) throws {
        if let value {
            let status = sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
            guard status == SQLITE_OK else {
                throw CallStoreError.sqlite("Could not bind string at index \(index)")
            }
        } else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw CallStoreError.sqlite("Could not bind null at index \(index)")
            }
        }
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Double?) throws {
        if let value {
            guard sqlite3_bind_double(statement, index, value) == SQLITE_OK else {
                throw CallStoreError.sqlite("Could not bind double at index \(index)")
            }
        } else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw CallStoreError.sqlite("Could not bind null at index \(index)")
            }
        }
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Int64) throws {
        guard sqlite3_bind_int64(statement, index, value) == SQLITE_OK else {
            throw CallStoreError.sqlite("Could not bind integer at index \(index)")
        }
    }

    private func bind(_ statement: OpaquePointer, _ index: Int32, _ value: Int64?) throws {
        if let value {
            try bind(statement, index, value)
        } else {
            guard sqlite3_bind_null(statement, index) == SQLITE_OK else {
                throw CallStoreError.sqlite("Could not bind null at index \(index)")
            }
        }
    }

    private func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: pointer)
    }

    private func columnDouble(_ statement: OpaquePointer, _ index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return sqlite3_column_double(statement, index)
    }

    private func columnInt(_ statement: OpaquePointer, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return Int(sqlite3_column_int64(statement, index))
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension Date {
    /// the one timestamp format in the index; webhook retry times are compared as these strings
    var iso8601WithFractions: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}

private extension String {
    var sqliteLikeEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }
}

private extension Double {
    var mmss: String {
        let totalSeconds = Int(self.rounded())
        return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}
