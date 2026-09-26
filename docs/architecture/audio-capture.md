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
  duration (4 h, set in `AppController`), a manual `stop()`, or silence auto-stop. Auto-stop fires when
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
converted to interleaved Float32 by `PCMFloatRecorder`.

Out, into the call folder (see [storage](storage.md)): `me.raw.wav`, `them.raw.wav` at the device
rate and channel count, and `session.json` (start/end, duration, stop reason, file metadata).
`AudioNormalizer` then converts each raw file with `AVAudioConverter` to 16 kHz mono Int16
`me.asr.wav` / `them.asr.wav` — the input of [ASR](asr.md).

## Constraints

- **The whole call lives in memory until stop.** `PCMFloatRecorder` appends every sample to a
  `[Float]` and writes the WAV only in `writeWAV` at the end. A crash or kill mid-call loses the
  recording; on the next launch `CallStore.failInterruptedCalls` marks such rows failed.
- **macOS 14.2 for system audio.** The package targets macOS 14, but process taps need 14.2, so
  `SystemAudioTap` is `@available(macOS 14.2, *)`. `DualCapture.record` throws below 14.2, and
  `DualCapture` / `LevelMonitor` keep the tap as `AnyObject?` (`_systemTap`, `tap`) and cast it back
  with `if #available(macOS 14.2, *), let tap = ... as? SystemAudioTap` — a stored property cannot have
  a type that is only available on a newer OS.
- `MicrophoneProcessWatcher` listens to every property of each process object, not to
  `IsRunningInput`: on macOS 26.2 coreaudiod never posts that change (see the comment in
  `CallDetector.swift`).
