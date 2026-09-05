# Podushka Calls MVP Phase Plan

Goal: build a local macOS menu bar proof of concept that records calls, separates "me" and "them" audio streams, transcribes both locally, and writes a merged Markdown transcript.

Target pace: 5 to 6 focused evenings. Every phase must leave the project in a usable checkpoint state.

## Fixed Product Scope

The MVP is a personal local call recorder and transcriber, not a polished distributed product.

Included:

- macOS menu bar app.
- Manual recording mode from day one.
- Automatic call detection after recording works reliably.
- Local speech recognition through a Python sidecar.
- Separate channels for microphone and remote/system audio.
- Markdown transcript export.
- Small SQLite call index.
- Local-only storage.

Deferred:

- Real-time transcript UI.
- Speaker diarization inside the remote channel.
- Cloud sync.
- Encryption beyond FileVault.
- Auto-update, notarized installer, DMG packaging.
- LLM summaries.
- Full-text search.

## Architecture

```text
SwiftUI menu bar app
        |
        | starts/stops capture
        v
Audio capture layer
        |
        | writes raw WAV files
        v
Normalization step
        |
        | produces 16 kHz mono files for ASR
        v
Python ASR worker over JSONL stdin/stdout
        |
        | returns timestamped segments
        v
Transcript merger
        |
        | writes Markdown and SQLite metadata
        v
Transcript window / recent calls UI
```

Important design choice: keep audio capture and ASR loosely coupled. Capture should produce durable files first; transcription can fail, retry, or switch models without losing the original call.

## Repository Layout

Start with this structure:

```text
podushka/
├── App/
│   ├── PodushkaApp.swift
│   ├── MenuBarView.swift
│   ├── TranscriptWindow.swift
│   ├── SettingsView.swift
│   └── OnboardingView.swift
├── Audio/
│   ├── AudioDeviceCatalog.swift
│   ├── SystemAudioTap.swift
│   ├── BlackHoleInstaller.swift
│   ├── AggregateDevice.swift
│   ├── DeviceRouter.swift
│   ├── DualCapture.swift
│   ├── AudioNormalizer.swift
│   └── CallDetector.swift
├── Transcription/
│   ├── ASRClient.swift
│   ├── TranscriptMerger.swift
│   ├── TranscriptStore.swift
│   └── TranscriptModels.swift
├── Resources/
│   └── README.md
├── python/
│   ├── pyproject.toml
│   └── asr_worker.py
├── docs/
│   ├── capture-spike.md
│   ├── asr-bakeoff.md
│   └── troubleshooting.md
└── README.md
```

Use `SystemAudioTap` as the preferred capture path on macOS versions where it works. Keep `BlackHoleInstaller`, `AggregateDevice`, and `DeviceRouter` as a fallback path.

## Phase 0: ASR Bakeoff

Objective: prove that the transcription model works well enough before writing macOS audio code.

Deliverable: a documented ASR decision in `docs/asr-bakeoff.md`.

Steps:

1. Create the Python sidecar directory.
2. Add a minimal ASR worker dependency set with `uv`.
3. Collect 3 to 5 local test WAV files:
   - Russian speech from your own voice.
   - English speech.
   - Mixed Russian/English.
   - One noisy recording.
   - One short real call-like clip if available.
4. Normalize every test file to 16 kHz mono WAV.
5. Test Parakeet v3 through `parakeet-mlx`.
6. If Russian quality is weak, test a Whisper MLX fallback.
7. Measure:
   - audio duration,
   - transcription wall time,
   - real-time factor,
   - obvious word error patterns,
   - punctuation quality,
   - timestamp quality.
8. Record the chosen default model and fallback model.

Commands:

```bash
cd /Users/mikhail/w/learning/podushka
mkdir -p python docs samples
cd python
uv init --python 3.12
uv add parakeet-mlx
```

Checkpoint:

- `uv run python asr_worker.py --self-test samples/test.wav` returns text and timestamped segments.
- The first model load can be slow, but subsequent jobs reuse the loaded model.
- The chosen ASR path is good enough on Russian speech from your own microphone.

Go/no-go:

- If Parakeet is acceptable, use it as the default.
- If Parakeet is fast but poor on Russian, switch the worker implementation to Whisper MLX while keeping the Swift interface unchanged.
- If both are poor, stop and improve the audio normalization/test data before building the app.

## Phase 0.5: System Audio Capture Spike

Objective: decide whether the MVP can avoid BlackHole by using native macOS system audio capture.

Deliverable: `docs/capture-spike.md` with the selected capture path.

Steps:

1. Create a tiny Swift/Xcode experiment, separate from the main app if faster.
2. Add `NSMicrophoneUsageDescription`.
3. Add `NSAudioCaptureUsageDescription`.
4. Request or trigger microphone capture permission.
5. Try native system/process audio capture using Core Audio taps on the local macOS version.
6. Record 30 seconds of:
   - microphone,
   - system output,
   - both at the same time.
7. Verify whether the remote/system audio can be recorded without switching the default output device.
8. Test with:
   - Safari or Chrome playing YouTube,
   - Zoom test meeting if available,
   - Slack or Telegram call if available.
9. Document failures, permissions, and macOS version.

Checkpoint:

- A 30-second mic WAV and a 30-second remote/system WAV exist and line up roughly in time.
- The app can cleanly start and stop recording twice in a row.

Decision:

- Prefer Core Audio taps if they reliably capture remote audio.
- Use BlackHole fallback if taps are unavailable, unstable, or too slow to implement.
- Keep manual recording regardless of the automatic detection approach.

## Phase 1: Swift App to Python Pipeline

Objective: create the real menu bar app and prove Swift can record a short mic clip, send it to Python, and receive text.

Deliverable: menu bar app with a "Test Record 30s" action.

Steps:

1. Create a macOS SwiftUI app target.
2. Replace the default window entry point with a menu bar app entry point.
3. Add a simple menu:
   - current status,
   - "Test Record 30s",
   - "Open Calls Folder",
   - "Quit".
4. Implement microphone permission handling.
5. Record microphone audio to a durable raw WAV.
6. Normalize the raw file to 16 kHz mono WAV.
7. Spawn the Python worker as a long-lived `Process`.
8. Communicate with the worker through JSONL:
   - Swift writes one JSON object per job to stdin.
   - Python writes one JSON object per event to stdout.
   - Python writes diagnostics to stderr only.
9. Show the returned transcript in the Xcode console or a temporary transcript window.
10. Add worker crash handling:
   - detect process exit,
   - show failed state,
   - allow restart.

Worker protocol:

```json
{"type":"ready","model":"parakeet","version":"..."}
{"type":"job_started","id":"..."}
{"type":"job_done","id":"...","text":"...","segments":[{"start":0.0,"end":1.4,"text":"..."}]}
{"type":"job_failed","id":"...","error":"..."}
```

Checkpoint:

- Click "Test Record 30s".
- Speak into the microphone.
- Within a short time after recording stops, the transcript appears.
- Repeat the flow without restarting the app.

## Phase 2: Dual Capture

Objective: capture "me" and "them" into separate files.

Deliverable: "Test Dual 30s" records two files and transcribes both.

Preferred path:

1. Use the native system audio tap selected in Phase 0.5.
2. Capture microphone separately.
3. Start both captures from a shared logical session start time.
4. Persist per-file metadata:
   - device UID,
   - sample rate,
   - channel count,
   - start host time if available,
   - file duration.

Fallback path:

1. Install or detect BlackHole 2ch.
2. Create a private aggregate or multi-output route.
3. Switch default output only while recording.
4. Restore the previous default output on stop, app quit, and crash recovery where possible.
5. Capture microphone and BlackHole audio into separate WAV files.

Implementation details:

1. Record raw audio in the device's native format, commonly 48 kHz.
2. Normalize after capture for ASR.
3. Do not force the whole capture graph to 16 kHz.
4. Add drift notes if the two files diverge on longer recordings.
5. Add a visible "Recording" status before attempting ASR.

Checkpoint:

- Start YouTube or a test call.
- Press "Test Dual 30s".
- Speak while remote audio is playing.
- The app writes:
  - `me.raw.wav`,
  - `them.raw.wav`,
  - `me.asr.wav`,
  - `them.asr.wav`,
  - `session.json`.
- Both ASR outputs contain the expected speaker side.

## Phase 3: Storage, Queue, and Markdown Merge

Objective: after a recording ends, transcription runs as a job and produces a merged Markdown transcript.

Deliverable: a call folder and a merged `.md` transcript for each test recording.

Storage location:

Default to:

```text
~/Library/Application Support/Podushka/Calls/
```

Allow export or custom folder selection later. Avoid defaulting to `~/Documents` because it may be synced by iCloud.

SQLite schema:

```sql
create table calls (
  id text primary key,
  app_bundle_id text,
  app_name text,
  started_at text not null,
  ended_at text,
  duration_sec real,
  status text not null,
  transcript_path text,
  audio_dir text,
  keep_audio integer not null default 0,
  created_at text not null,
  updated_at text not null
);

create table transcript_jobs (
  id text primary key,
  call_id text not null,
  model text not null,
  model_version text,
  status text not null,
  error text,
  real_time_factor real,
  created_at text not null,
  updated_at text not null
);

create table transcript_segments (
  id text primary key,
  call_id text not null,
  speaker text not null,
  start_sec real not null,
  end_sec real,
  text text not null,
  order_idx integer not null
);
```

Steps:

1. Create one call folder per recording.
2. Write session metadata before recording starts.
3. Mark calls as `recording`, `transcribing`, `ready`, or `failed`.
4. Send both ASR files to the worker.
5. Save raw ASR JSON outputs.
6. Interleave `me` and `them` segments by timestamp.
7. Write Markdown:

```markdown
# Zoom · 2026-05-10 14:30 · 47 min

**them** [00:00] Hello, can you hear me?

**me** [00:03] Yes, I can hear you.
```

8. Implement "delete raw audio after successful transcription" when `keep_audio` is false.
9. Keep normalized ASR audio only if debugging is enabled.
10. Add a retry path for failed jobs.

Checkpoint:

- Run a real or simulated call recording.
- Wait for transcription to finish.
- Open the generated Markdown and read a coherent dialogue.
- Restart the app and still see the call in SQLite.

## Phase 4: Automatic Call Detection

Objective: start and stop recording automatically for known call apps, while preserving manual control.

Deliverable: app status changes automatically during a test call and creates a recording folder.

Approach:

1. Watch microphone running state where available.
2. Watch running applications through `NSWorkspace`.
3. Match an allowlist of bundle IDs.
4. Debounce start and stop events.
5. Never start auto-recording if manual recording is already active.
6. Always expose manual start/stop as fallback.

Initial allowlist:

```swift
let callApps: Set<String> = [
    "us.zoom.xos",
    "com.microsoft.teams2",
    "com.tinyspeck.slackmacgap",
    "org.telegram.desktop",
    "com.hnc.Discord",
    "com.apple.FaceTime",
    "ru.yandex.mobile.telemost"
]
```

Chrome/Meet handling:

1. Keep Chrome disabled by default for auto-detection.
2. Add a separate setting for browser-based calls.
3. Treat browser support as a small follow-up spike:
   - inspect active tab URL through AppleScript if allowed,
   - match `meet.google.com`,
   - require explicit user opt-in.

Checkpoint:

- Join a Zoom test call.
- Menu bar status changes to recording.
- Leave the call.
- Recording stops.
- Output files and metadata are created.
- The previous audio output device is restored if the fallback routing path is used.

## Phase 5: UI Polish

Objective: make the POC comfortable enough for daily personal use.

Deliverable: a usable menu bar app with recent calls, transcript viewing, and basic settings.

Menu bar:

1. Show status:
   - idle,
   - recording,
   - transcribing,
   - failed.
2. Show last 10 calls.
3. Add manual "Start Recording" and "Stop Recording".
4. Add "Open Calls Folder".
5. Add "Settings".

Transcript window:

1. Display merged Markdown as readable text.
2. Add "Copy Markdown".
3. Add "Copy Plain Text".
4. Add "Reveal File".
5. Show failed transcription errors when relevant.

Settings:

1. Allowlist call apps with checkboxes.
2. Calls folder selector.
3. "Keep audio files" toggle, default off.
4. ASR model selector:
   - Parakeet default,
   - Whisper fallback if installed.
5. "Re-transcribe failed calls".
6. "Re-transcribe all calls".
7. Optional reminder to enable system-level Voice Isolation, but do not rely on being able to detect its exact state.

Onboarding:

1. Explain local-only recording and storage.
2. Request microphone permission.
3. Request system audio capture permission if using native taps.
4. If using BlackHole fallback, guide installation with clear admin prompt expectations.
5. Run a 10-second test recording.
6. Show success or troubleshooting.

Checkpoint:

- You can run the app for a real call without Xcode console.
- The recent calls list is useful.
- A failed transcription is visible and retryable.
- Manual recording remains one click away.

## Phase 6: Daily-Use Hardening

Objective: fix the rough edges that appear only after several real calls.

Deliverable: a POC that survives normal personal usage.

Steps:

1. Add structured logs under:

```text
~/Library/Logs/Podushka/
```

2. Add a diagnostics export:
   - app version,
   - macOS version,
   - selected capture path,
   - device list,
   - latest errors,
   - no transcript contents by default.
3. Add crash-safe cleanup:
   - restore output device on next launch if fallback routing was interrupted,
   - remove stale private aggregate devices,
   - mark abandoned recordings as failed.
4. Add minimum-duration filtering so accidental short recordings do not trigger ASR.
5. Add silence filtering before ASR to reduce hallucinations.
6. Add model warmup at app start or first idle period.
7. Add tests for:
   - transcript merge ordering,
   - timestamp formatting,
   - JSONL worker protocol parsing,
   - storage state transitions.

Checkpoint:

- Use the app for 3 to 5 real calls.
- Confirm no stuck audio routing.
- Confirm failed jobs are recoverable.
- Confirm disk usage stays bounded when "Keep audio files" is off.

## Implementation Order Summary

1. ASR quality and speed.
2. Native system audio capture spike.
3. Swift menu bar app with manual mic transcription.
4. Dual capture.
5. Persistent queue and Markdown output.
6. Automatic call detection.
7. UI polish.
8. Daily-use hardening.

## Risk Register

| Risk | Impact | Mitigation |
|---|---:|---|
| Native system audio capture is unreliable | High | Keep BlackHole fallback path |
| BlackHole packaging/licensing complicates sharing | High | Treat it as optional local dependency, not bundled default |
| ASR quality on Russian is weak | High | Bakeoff Parakeet vs Whisper before Swift work |
| Auto-detection false positives | Medium | Manual mode, allowlist, debounce, browser opt-in |
| Audio routing is not restored | High | Store previous device, restore on stop/quit/next launch |
| Long recordings drift between channels | Medium | Record metadata, test 30 min calls, add alignment correction later |
| Worker stdout is polluted by logs | Medium | stdout JSONL only, stderr logs only |
| iCloud sync exposes transcripts | Medium | Default to Application Support, not Documents |
| Silent audio causes ASR hallucinations | Medium | Add energy gate/silence filtering |

## Definition of Done for the MVP

The MVP is done when:

1. You can start a real call.
2. The app records microphone and remote audio separately.
3. The app transcribes both sides locally after the call.
4. A merged Markdown transcript appears automatically.
5. The recent calls UI can open and copy that transcript.
6. Failed transcriptions can be retried.
7. The app does not leave system audio routing broken.
8. The project has notes for the chosen ASR and capture paths.

