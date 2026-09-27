---
type: Architecture
title: Storage
description: The SQLite call index, the call archive on disk, search and audio retention.
---
# Storage

## How it works

Everything lives under `~/Library/Application Support/Beseda` (`AppPaths`):

```
Beseda/
├── calls.sqlite          # the call index (CallStore)
├── calls/<call-id>/      # one folder per call; id is Date.fileStamp at start
│   ├── me.raw.wav, them.raw.wav   # capture output
│   ├── me.asr.wav, them.asr.wav   # 16 kHz mono for ASR
│   ├── me.asr.json, them.asr.json # ASR result per channel
│   ├── session.json               # capture metadata
│   └── transcript.md              # merged transcript
├── runtime/models/       # speech models
└── beseda-app.log
```

Old single-microphone calls use `mic.raw.wav`, `mic.16k-mono.wav`, `mic.asr.json`. A Podushka-era
folder is moved here once by `LegacyDataMigration`.

- **CallStore** — raw `sqlite3` (system library) behind a serial queue. `prepare()` creates the tables
  `calls`, `transcript_segments`, `transcript_jobs`, `call_speakers` (renames only), `webhook_deliveries`
  with `foreign_keys = ON` and WAL. Migrations are numbered: `CallStore.migrations` is a list, entry *n*
  brings the file to `PRAGMA user_version = n`, each runs in its own transaction with the version bump, so
  a failure rolls back to the last whole version. Version 1 is everything an unversioned file (every 0.3.x
  release ran the same `prepare`) needed: tables, missing columns added with `ALTER TABLE`, the dead
  `keep_audio` dropped. Before any migration on an existing file, `VACUUM INTO` writes
  `calls.sqlite.v<old version>.backup` next to it; a current file is neither migrated nor copied again.
  A new migration is appended to the list, a released one is never edited. Version 2 adds
  `calls.processing_pending` (INTEGER, 0/1): the call waits for auto-processing. `calls.call_type` (nullable TEXT) holds the
  `CallType.name` the call was processed as (`setCallType`, `StoredCallSummary.callType`); null means
  never processed, as for every call older than the column. `calls.event_series_id` (EventKit
  `calendarItemExternalIdentifier` of a recurring event) and `calls.participants` (event attendees except
  the user, lowercased emails, newline-joined) are nullable TEXT written by `setEvent` whenever an event
  is matched or picked; calls linked before them stay null.
  `calls.one_other_person` (nullable INTEGER) is the classifier's «exactly one other person» answer
  (`setOneOtherPerson`, BESEDA-104), a measurement that relabels nothing (BESEDA-107); null means never answered.
- **Writes throw** — every index write in the recording and retry pipeline (`saveCall`,
  `upsertTranscriptJob`) throws into the job's error path, which shows the failure in the status line. A
  finished transcript goes in through `markReady`: segments and `status = 'ready'` in one transaction; only
  after it commits does `AppController.finishCall` clean audio, enqueue the webhook and start
  auto-processing. A failed write leaves the call not ready with its audio, so retry still works. They feed [related calls](related-calls.md).
- **Launch recovery** — `AppController.init` takes `AppPaths` (and settings) by injection, default the real
  folder, so tests run a whole controller over a temp one. After `prepare()`:
  `failInterruptedCalls` marks calls left in `recording`/`normalizing`/`transcribing` as failed; every
  folder under `calls/` with `me.raw.wav`/`them.raw.wav` (or `mic.raw.wav`) and no row gets a failed row
  («Найдена на диске без записи в индексе»), times from `session.json`, else folder creation and last file
  modification; both kinds get their WAVs repaired and checked (see [Audio capture](audio-capture.md)),
  a failure appended to `calls.error`. So a folder whose index write never landed shows in the archive with
  «Расшифровать снова». If the index cannot be opened, the status line says «Индекс звонков недоступен».
  Then pending auto-processing resumes ([Summarization](summarization.md)).
- **Speaker merge** — the diarizer can split one remote person into several `them-N`. In the call view a
  line's context menu «Объединить с» folds its speaker into another remote one: `mergeSpeaker` rewrites
  `transcript_segments.speaker` and drops the merged key's rename in one transaction, then
  `transcript.md` is rewritten. `me` is never offered. The speaker count is not stored anywhere; lanes and
  names are derived from the segments, so they follow. A retry re-diarizes and undoes the merge.
  Before/after: [evidence/beseda-80-before-merge.png](evidence/beseda-80-before-merge.png), [evidence/beseda-80-after-merge.png](evidence/beseda-80-after-merge.png).
- **Paging** — the sidebar loads 200 calls, newest first; «Показать ещё» fetches the next 200 by offset,
  and refreshes keep however many are loaded.
- **Search** — the sidebar filters loaded calls by `StoredCallSummary.searchableText` (title, app, date,
  preview, error). From two characters on, `searchCalls` adds every call, loaded or not, whose event title,
  app, summary, participants, error or transcript text match an escaped `LIKE '%query%'`; such rows open
  through `fetchCall(id:)`. No full-text index: the scan takes ~0.1 s over 2000 calls × 200 segments.
  SQLite `LIKE` folds case for ASCII only, so Cyrillic metadata beyond the loaded page matches case-exactly.
- **StorageJanitor** — classifies files by suffix (`.raw.wav` raw, `.asr.wav`/`.16k-mono.wav`
  normalized, `.md`/`.json` text, kept forever), measures usage, and deletes audio older than the
  retention rule (`immediately`, 30, 90 days, `forever`) by modification date. Folders of calls in
  progress or failed (`protectedAudioDirectories`) are skipped so a retry still has its audio. It runs
  daily, on the settings button, and `cleanupAudioIfNeeded` applies the rules when a call finishes.

- **Protection** — `StorageProtection.apply` runs at launch: it sets the process umask to 077, so every
  later file and folder is owner-only, and walks the data folder once, dropping group/other bits (owner
  bits kept, so built binaries stay executable) and setting `completeUntilFirstUserAuthentication` file
  protection where the volume supports it.
- **Deletion** — `CallStore.deleteCallAndFiles` moves the call folder to `trash/<uuid>/<call id>` next to
  the index (a rename), deletes the row, then removes the export copies — the one at the stored
  `calls.export_path` (the last written, whatever the title was then) and the one named by
  `CallExport.fileName` (copies written before the path was stored) — and empties the trash. A failed row
  delete moves the folder back; a trash that cannot be emptied is retried at every launch
  (`emptyTrash`), which keeps a folder whose row is still there. So no listed call points at missing files; segments, jobs, speakers and webhook deliveries go by `ON DELETE CASCADE`. `deleteCall` turns on
  `secure_delete` and truncates the WAL, so deleted text is not left in free pages. A call still waiting
  in the processing queue is dropped from it first.

## Main files

`Storage/CallStore.swift` (schema, queries, `StoredCallSummary` and friends), `Storage/StorageJanitor.swift`,
`App/AppPaths.swift`, `Storage/CallFormatting.swift`, `Storage/TranscriptCopy.swift`.

## Data flow

In: `AppController.saveCall` upserts the call row at each status (`recording` → `normalizing` →
`transcribing` → `ready` or `failed`); [ASR](asr.md) adds jobs and segments. Out: the sidebar list, call
detail, search, and the webhook/summary features read rows back.

## Constraints

- **One connection per call.** `CallStore.database` opens a fresh SQLite connection for every method
  and closes it after, serialised on its queue. Simple and one writer, but every query pays an open, and
  a multi-statement change is not one transaction unless the body makes it so.
- **On-disk formats are a compatibility contract.** The SQLite schema and the files in a call folder
  are read back by later versions: `asr.json` uses snake_case keys (`audio_duration_sec`,
  `wall_time_sec`, `real_time_factor`), and file names are what `StorageJanitor` and retry rely on. Do
  not rename or change them without a migration in `prepare()` or a reader for the old shape.
- **Call file names have no single owner.** They are spelled in three places: `AppController.DualFiles`,
  `DualCapture` (which writes `me.raw.wav` and `them.raw.wav`) and the suffix rules in `StorageJanitor`.
  Renaming a file in one place silently breaks retention and retry.
