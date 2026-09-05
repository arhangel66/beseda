# Swift App to Python Pipeline

## Decision

Phase 1 uses a SwiftPM macOS executable target wrapped into a local `.app` bundle
by `scripts/build_podushka_app.sh`. This keeps the proof of concept fast to
iterate without introducing an Xcode project yet.

The app is menu-bar-first through SwiftUI `MenuBarExtra`. It owns one
long-lived Python ASR worker process and sends transcription jobs over JSONL.

## Build and Run

```bash
cd /Users/mikhail/w/learning/podushka
./scripts/build_podushka_app.sh
open .build/Podushka.app
```

If the app is launched outside the repository, set `PODUSHKA_ROOT` to the repo
path. Normal local launches from this checkout should resolve paths from the
compiled `#filePath`.

## Current Flow

1. `Listen` starts a dual recording manually.
2. The app records microphone and native system audio tap streams at the same
   time.
3. Raw files are written as `me.raw.wav` and `them.raw.wav`.
4. `ffmpeg` normalizes the raw WAV files to `me.asr.wav` and `them.asr.wav`.
5. The app starts or reuses the long-lived ASR worker.
6. `ASRClient` sends two `transcribe` JSON jobs to `python/asr_worker.py`.
7. Raw ASR responses are written to `me.asr.json` and `them.asr.json`.
8. Timestamped segments are merged into a speaker-labelled dialogue.
9. A Markdown transcript is written to `untracked/calls/<timestamp>/transcript.md`.
10. `untracked/calls.sqlite` is updated with call status, ASR job metadata, and
    transcript segments.
11. The `Calls` window reads the SQLite index and transcript files back into a
    searchable local browser.

`Mic 30s` keeps the Phase 1 microphone-only path available for diagnostics.

A `Stop` button appears next to `Listen` while a dual recording is in flight.
It cancels the recording sleep, after which the normal normalize → ASR →
transcript pipeline runs on whatever was captured. The same path runs when the
silence monitor stops the recording after 60 seconds without meaningful
microphone or system-audio activity.

## Verification

- `swift build --package-path /Users/mikhail/w/learning/podushka --product Podushka`
  completes without warnings.
- `scripts/build_podushka_app.sh` creates
  `/Users/mikhail/w/learning/podushka/.build/Podushka.app`.
- The app process launches and stays alive for a basic smoke test.
- Launching the app creates or migrates `untracked/calls.sqlite`.
- The `Calls` window opens from the menu bar app and can read the latest indexed
  dual test call.
- The JSONL worker still returns `ready`, `pong`, `job_started`, and `job_done`
  for the existing normalized Russian sample.

## Storage Lifecycle

Settings expose a `Keep audio files` toggle (default off). When off, both raw
WAVs (`*.raw.wav`) and normalized ASR WAVs (`*.asr.wav` /
`mic.16k-mono.wav`) are deleted right after a successful transcript is
written. The call folder still keeps `session.json`, raw ASR JSON outputs
(`me.asr.json`, `them.asr.json`, `mic.asr.json`), and `transcript.md`.

The `calls` SQLite table records `keep_audio` per call so retried jobs and
the Calls browser can tell whether audio is still on disk.

## Retry

The `Calls` window shows a `Retry` toolbar action for any call with status
`failed`. Retry feeds the existing normalized ASR WAVs back to the worker,
overwrites `*.asr.json`, replaces SQLite segments, rewrites `transcript.md`,
and applies the same audio cleanup rule on success. If the audio files were
already deleted (or never produced), retry marks the call `failed` again with
a clear "Missing audio file" error.

## Copy Actions

`Calls` and `Transcript` windows each expose a `Copy` menu with `Copy
Markdown` (the raw `transcript.md` text) and `Copy Plain Text` (segments
joined as `speaker [mm:ss-mm:ss] text`).

## Gaps

- The microphone side may need input-device diagnostics, quiet-signal warnings,
  or a Whisper fallback if Parakeet keeps hallucinating on weak mic audio.
- Auto-start is intentionally disabled for MVP because bundle-ID/app-presence
  triggers were too noisy for always-running apps like Discord.
- Long manual recordings buffer raw audio in memory (~1.4 GB/hour for the dual
  path) until normalization. Streaming-to-disk capture is deferred.
- Storage location is still `<repo>/untracked/calls/`; the plan recommends
  `~/Library/Application Support/Podushka/Calls/` and a folder selector in
  Settings for non-POC use.
