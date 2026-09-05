# System Audio Capture Spike

Date: 2026-05-10

## Decision

Use native Core Audio process taps as the preferred MVP capture path on this machine.

Keep BlackHole 2ch as a fallback path, but do not route through it by default. The native path successfully captured system audio without switching the default output device.

## Environment

- macOS: 26.2
- Xcode: 26.4.1
- SDK: MacOSX26.4.sdk
- Default input: `MacBook Pro Microphone`
- Default output before and after tests: `MacBook Pro Speakers`
- Existing fallback devices found: `BlackHole 2ch`, `Multi-Output Device`, `Microsoft Teams Audio`

## Implementation

Spike code lives in `spikes/CaptureSpike`.

Build the app bundle:

```bash
cd /Users/mikhail/w/learning/podushka
./scripts/build_capture_spike_app.sh
```

List audio devices:

```bash
spikes/CaptureSpike/.build/CaptureSpike.app/Contents/MacOS/CaptureSpike list-devices
```

Record both channels:

```bash
spikes/CaptureSpike/.build/CaptureSpike.app/Contents/MacOS/CaptureSpike record \
  --duration 30 \
  --output-dir untracked/custom/capture-spike/manual-run
```

The app bundle includes:

- `NSMicrophoneUsageDescription`
- `NSAudioCaptureUsageDescription`

## Native Capture Path

The spike uses:

- `CATapDescription(stereoGlobalTapButExcludeProcesses:)`
- `AudioHardwareCreateProcessTap`
- A private aggregate device with `kAudioAggregateDeviceTapListKey`
- `AudioDeviceCreateIOProcIDWithBlock`
- `AVAudioEngine` microphone tap

Files written:

- `system.raw.wav`: stereo 48 kHz Float32 WAV from the process tap.
- `mic.raw.wav`: mono 48 kHz Float32 WAV from the default microphone.
- `session.json`: start/end timestamps and basic file metadata.

## Verification Results

### Device Listing

The spike successfully read Core Audio devices. Relevant output:

```text
MacBook Pro Microphone BuiltInMicrophoneDevice [default-input]
MacBook Pro Speakers BuiltInSpeakerDevice [default-output, system-output]
BlackHole 2ch BlackHole2ch_UID
```

### System-Only Test

Command pattern:

```bash
(sleep 1; afplay untracked/custom/capture-spike/test-tone.wav) &
spikes/CaptureSpike/.build/CaptureSpike.app/Contents/MacOS/CaptureSpike record \
  --duration 7 \
  --skip-mic \
  --output-dir untracked/custom/capture-spike/system-test
```

Result:

- `system.raw.wav`
- Format: `pcm_f32le`, stereo, 48 kHz
- Duration: `5.952s`
- Volume: `mean_volume -24.8 dB`, `max_volume -21.1 dB`

The first attempt started `afplay` before the tap was active and produced no frames. Starting test audio after the tap begins works.

### Microphone-Only Test

Result:

- `mic.raw.wav`
- Format: `pcm_f32le`, mono, 48 kHz
- Duration: `2.900s`
- Volume: `mean_volume -43.2 dB`, `max_volume -30.3 dB`

The first microphone run included permission handoff time in `session.json`; the actual audio file duration matched the requested recording window.

### Dual Test

Result:

- `system.raw.wav`: `pcm_f32le`, stereo, 48 kHz, `6.122667s`, `mean_volume -25.0 dB`
- `mic.raw.wav`: `pcm_f32le`, mono, 48 kHz, `7.100s`, `mean_volume -39.0 dB`

The default output device remained `MacBook Pro Speakers` after recording.

## Gaps Before Phase 1

- Test native tap with a real call app: Zoom, Telegram, Slack, or browser audio.
- Confirm behavior after granting permissions through normal app launch, not only direct bundle executable invocation.
- Decide whether Phase 1 should keep this spike as a separate target or fold the useful pieces into `Audio/SystemAudioTap.swift` and `Audio/DualCapture.swift`.
- Add normalization from Float32 WAV to 16 kHz mono ASR WAV in the Swift pipeline or call the existing Python worker normalization path.

## Follow-Up Risk

Native taps work for generated system audio on macOS 26.2. A real call app may still behave differently, especially if it uses a private audio driver or changes output devices internally. If real call capture fails, use the already-installed `BlackHole 2ch` fallback path.

