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
  with `foreign_keys = ON` and WAL. Migrations are inline in `prepare()`: missing columns are added with
  `ALTER TABLE`, the dead `keep_audio` column is dropped. `calls.call_type` (nullable TEXT) holds the
  `CallType.name` the call was processed as (`setCallType`, `StoredCallSummary.callType`); null means
  never processed, as for every call older than the column. `calls.event_series_id` (EventKit
  `calendarItemExternalIdentifier` of a recurring event) and `calls.participants` (event attendees except
  the user, lowercased emails, newline-joined) are nullable TEXT written by `setEvent` whenever an event
  is matched or picked; calls linked before them stay null. They feed [related calls](related-calls.md). On launch `failInterruptedCalls` marks calls
  left in `recording`/`normalizing`/`transcribing` as failed.
- **Search** — the sidebar filters loaded calls by `StoredCallSummary.searchableText` (title, app, date,
  preview, error). From two characters on, `searchCallIDs` also matches transcript text with an escaped
  `LIKE '%query%'` over `transcript_segments`. No full-text index.
- **StorageJanitor** — classifies files by suffix (`.raw.wav` raw, `.asr.wav`/`.16k-mono.wav`
  normalized, `.md`/`.json` text, kept forever), measures usage, and deletes audio older than the
  retention rule (`immediately`, 30, 90 days, `forever`) by modification date. Folders of calls in
  progress or failed (`protectedAudioDirectories`) are skipped so a retry still has its audio. It runs
  daily, on the settings button, and `cleanupAudioIfNeeded` applies the rules when a call finishes.

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
