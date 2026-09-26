---
type: Architecture
title: Audio capture
description: How Beseda records the microphone and the system audio as two separate channels.
---
# Audio capture

## How it works

A call is recorded as two independent files: the microphone ("me") and everything the Mac plays
("them"). Keeping them apart is what lets the transcript say who spoke without guessing from one mixed
track.

- **Microphone** — `MicrophoneCapture` installs a tap on `AVAudioEngine.inputNode` at the device's own
  format and asks for microphone permission first.
- **System audio** — `SystemAudioTap` creates a CoreAudio process tap
  (`CATapDescription(stereoGlobalTapButExcludeProcesses:)`, excluding Beseda's own process, private,
  unmuted), wraps it in a private aggregate device and reads it through an IO proc block on its own
  dispatch queue.
- **Both** — `DualCapture.record` starts the tap, then the microphone, sleeps until the maximum
  duration (4 h, set in `AppController`; the 4 GB limit ends a 48 kHz stereo call first, but the formats
  come from the devices, so on a mono or lower-rate one the cap still matters), a manual `stop()`, or silence auto-stop. Auto-stop fires when
  *both* channels have been quiet for the configured time, checked every 2 s. Pause drops buffers on
  both channels so the files stay aligned.
- **Call detection** — `CallDetector` watches which processes hold the microphone
  (`MicrophoneProcessWatcher`, CoreAudio process objects and `kAudioProcessPropertyIsRunningInput`) and
  matches their bundle ids against the user's allowed list (`knownCallApps`: Zoom, Teams, Slack,
  Telegram, Discord, FaceTime, Telemost, Chrome). The pure `CallRecordingPolicy` decides start/stop: a
  5 s debounce, 60 s minimum gap, a manual recording wins, and the same app staying on the microphone
  after a recording ended is still the same call. `AppController` discards an auto-recording shorter
  than 10 s.
- **Levels** — `AudioActivityTracker` observes every buffer: peak/RMS for silence detection and a
  decaying 0…1 meter. `DualCapture.microphoneLevel`/`systemAudioLevel` feed the menu bar meters;
  `LevelMonitor` opens both channels for the onboarding's ten-second check and writes nothing.

## Main files

`Audio/DualCapture.swift`, `Audio/MicrophoneCapture.swift`, `Audio/SystemAudioTap.swift`,
`Audio/PCMFloatRecorder.swift`, `Audio/AudioActivityTracker.swift`, `Audio/CallDetector.swift`,
`Audio/CallRecordingPolicy.swift`, `Audio/LevelMonitor.swift`, `Audio/AudioNormalizer.swift`.

## Data flow

In: microphone buffers (Float32) and tap buffers (Float32 or Int16 PCM, interleaved or not), both
converted to Float32 by `PCMFloatRecorder` and written to the raw WAV as they arrive (`AVAudioFile.write`
per buffer; the level checks pass no file and write nothing).

Out, into the call folder (see [storage](storage.md)): `me.raw.wav`, `them.raw.wav` at the device
rate and channel count, and `session.json` (start/end, duration, stop reason, file metadata).
`AudioNormalizer` then converts each raw file with `AVAudioConverter` to 16 kHz mono Int16
`me.asr.wav` / `them.asr.wav` — the input of [ASR](asr.md). While recording, the optional
[live transcription](live-transcription.md) reads the growing raw files; `PCMFloatRecorder` counts buffers it
failed to write (`droppedBufferCount`) so that loop can back off.

A failed write (disk full, the 4 GB limit below) is not only logged: `PCMFloatRecorder.writeError` keeps
the first one, the live ticker in `AppController` sees it through `DualCapture.writeError`, stops the
recording (`stopReason` `writeFailed`), sets `recordingWarning` (shown in the popover until the next
recording; the 4 GB text is picked by the `AudioCaptureError.fileFull` case) and posts a «Запись
остановлена» notification. What reached the disk is transcribed as usual.

## Constraints

- **A crash keeps the audio.** Every buffer reaches the raw file as it arrives, but AudioFile fills in
  the WAV header sizes only at close, so a killed call leaves `me.raw.wav` / `them.raw.wav` whose header
  says zero frames (and no `session.json`). On the next launch `CallStore.failInterruptedCalls` marks
  the row failed and returns its folder, and `PCMFloatRecorder.repairWAVHeader` rewrites the sizes from
  the file length. The call stays in the archive; its retry normalizes the raw files first when the
  `asr.wav` files are missing.
- **4 GB per raw file.** A WAV header cannot count past 4 GiB, so `PCMFloatRecorder` refuses to grow the
  data past `wavDataLimit` (4·10⁹ bytes, ~2 h 53 min of a 48 kHz stereo Float32 tap) and the recording
  stops there cleanly through the write-error path. Lifting it (RF64/CAF or rolling files) was declined:
  normalization, crash repair and live transcription all read these WAVs.
- **macOS 14.2 minimum.** Process taps need 14.2, so the whole package targets it (`Package.swift`,
  `LSMinimumSystemVersion`, the bundle script) and `SystemAudioTap` needs no availability checks.
- `MicrophoneProcessWatcher` listens to every property of each process object, not to
  `IsRunningInput`: on macOS 26.2 coreaudiod never posts that change (see the comment in
  `CallDetector.swift`).
