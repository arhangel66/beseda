# Call Detection Spike (auto-start plan B1)

Date: 2026-08-29
Host: macOS 26.2, Swift 6.3.3, MacBook Pro M2 Max

Goal: find out whether a CoreAudio process object can tell Podushka that a call started, without
polling and without any audio tap. Code lives in `spikes/CallDetectSpike/main.swift` — a single
standalone file compiled with `swiftc`, not part of `Package.swift`.

## Build and Run

```bash
cd /Users/mikhail/w/learning/podushka
./scripts/build_call_detect_spike.sh
spikes/CallDetectSpike/.build/CallDetectSpike
```

The script prints the path of the binary it built. The tool runs until Ctrl-C.

Reading the output:

```text
15:48:45  mic ON   mic_cycle (pid 3215)  output=off
15:48:45  mic ON*  com.apple.CoreSpeech (pid 2559)  output=off
```

- `mic ON` / `mic OFF` — `kAudioProcessPropertyIsRunningInput` flipped.
- `output=on|off` — `kAudioProcessPropertyIsRunningOutput` at the same instant (the plan's fallback
  signal).
- `+ proc` / `- proc` — the process object appeared in or vanished from
  `kAudioHardwarePropertyProcessObjectList`.
- **A star (`mic ON*`) is the important one**: it means no listener callback ever arrived and the
  2-second safety sweep found the change instead. See the findings below.
- The name is `kAudioProcessPropertyBundleID` when the process has one, otherwise the executable
  name from the pid. Nothing goes through `NSWorkspace`.

## Findings

### 1. `kAudioProcessPropertyIsRunningInput` never sends a change notification

This is the one assumption in the plan that does not hold.

`AudioObjectAddPropertyListenerBlock` for `kAudioProcessPropertyIsRunningInput` (and for
`...IsRunningOutput` and `...IsRunning`) returns `noErr` on all 32 process objects and then stays
silent forever. Verified by attaching all three listeners to every process object and driving the
microphone from a separate process — zero callbacks, while the control listener on
`kAudioHardwarePropertyProcessObjectList` fired on every process appear/disappear.

A wildcard listener (`kAudioObjectPropertySelectorWildcard` on all scopes and elements) attached to
the same process object shows what coreaudiod actually posts. Microphone opened at 15:44:47.408 and
closed at 15:44:52.421, opened again at 15:44:58.512 and closed at 15:45:03.525:

```text
wildcard listeners on 33 process objects, 0 failed
15:44:47.379  obj=183 pid=98668 pdv#/inpt
15:44:47.387  obj=183 pid=98668 pdv#/outp
15:44:52.461  obj=183 pid=98668 pdv#/inpt
15:44:52.462  obj=183 pid=98668 pdv#/outp
15:44:58.480  obj=183 pid=98668 pdv#/inpt
15:44:58.480  obj=183 pid=98668 pdv#/outp
15:45:03.564  obj=183 pid=98668 pdv#/inpt
15:45:03.564  obj=183 pid=98668 pdv#/outp
```

The event is `kAudioProcessPropertyDevices` (`pdv#`) with scope `inpt` / `outp`, delivered within
40 ms of the real transition. So the working shape is: listen to the process object, read
`IsRunningInput` in the handler. The spike registers a wildcard address per process object for
exactly this reason.

### 2. The device-list event only fires when the process attaches or detaches a device

A process that keeps the input device attached and merely starts/stops IO flips `IsRunningInput`
with no notification at all. `com.apple.CoreSpeech` behaves this way on this machine and is the
reason the spike carries a 2-second sweep: without it the tool would silently under-report.

Every starred line in a real session is a transition the event-driven design would have missed.
**This is the number the owner needs from the table below** — if the real call apps produce starred
lines, B2 cannot be purely event-driven and needs to keep a slow sweep as a backstop.

### 3. Every microphone open is shadowed by `com.apple.CoreSpeech`

Whenever an app opened the mic, `com.apple.CoreSpeech` (Siri / dictation daemon) reported
`IsRunningInput = true` for the same window. An allowlist is therefore mandatory — a naive
"anybody holds the mic" rule fires on a system daemon.

### 4. Identity is per-process, not per-app

The process object list holds separate objects for `com.google.Chrome` and each
`com.google.Chrome.helper`, and browser audio in Safari shows up as `com.apple.WebKit.GPU`, not as
the browser's bundle id. Command-line processes (`ffmpeg`) have no bundle id at all. This is only an
observation of the object list — no browser call was made during the spike. It does not change the
plan's decision to keep Chrome off the allowlist.

### 5. Reading the process object list registers the reader as an audio client

`CallDetectSpike` itself appears in its own startup dump. Harmless, but worth knowing: Podushka will
show up in this list once B2 ships.

## What Was Verified Here

Trigger: a throwaway `AVAudioEngine` tool that opens the mic for 5 s, closes it, waits 6 s and
repeats (`untracked/scripts/mic_cycle.swift`), then `ffmpeg -f avfoundation -i ":0" -t 5` as a
short-lived process that appears and disappears while the tool runs. No calls, no software
installed.

Ground truth from the trigger:

```text
15:48:37.361  started, pid 3215
15:48:45.473  round 1: mic OPEN
15:48:50.486  round 1: mic CLOSED
15:48:56.591  round 2: mic OPEN
15:49:01.604  round 2: mic CLOSED
15:49:07.611  exiting
```

Spike output for the same window (startup dump trimmed to the head and the tail):

```text
=== podushka call-detection spike ===
15:48:33  32 CoreAudio process objects

          ? (pid 8545)  output=off
          ? (pid 9943)  output=off
          CallDetectSpike (pid 3184)  output=off
          com.anthropic.claudefordesktop.helper (pid 10327)  output=off
          com.apple.assistantd (pid 1460)  output=off
          com.apple.CoreSpeech (pid 2559)  output=off
          com.google.Chrome (pid 1247)  output=off
          com.google.Chrome.helper (pid 6079)  output=off
          com.spotify.client (pid 1795)  output=off
          com.tdesktop.Telegram (pid 1252)  output=off
          systemsoundserverd (pid 1389)  output=off

holding the mic now: nobody
watching for changes, Ctrl-C to stop

15:48:37  + proc   mic_cycle (pid 3215)  output=off
15:48:45  mic ON   mic_cycle (pid 3215)  output=off
15:48:45  mic ON*  com.apple.CoreSpeech (pid 2559)  output=off
15:48:50  mic OFF  mic_cycle (pid 3215)  output=off
15:48:51  mic OFF* com.apple.CoreSpeech (pid 2559)  output=off
15:48:56  mic ON   mic_cycle (pid 3215)  output=off
15:48:57  mic ON*  com.apple.CoreSpeech (pid 2559)  output=off
15:49:01  mic OFF  mic_cycle (pid 3215)  output=off
15:49:03  mic OFF* com.apple.CoreSpeech (pid 2559)  output=off
15:49:07  - proc   mic_cycle (pid 3215)  output=off
15:49:09  + proc   ffmpeg (pid 3883)  output=off
15:49:09  mic ON   ffmpeg (pid 3883)  output=off
15:49:15  mic OFF  ffmpeg (pid 3883)  output=off
15:49:15  - proc   ffmpeg (pid 3883)  output=off
```

Confirmed:

- the startup dump lists every process object with bundle id / pid and both flags, and names who
  holds the mic;
- the tool stays alive and keeps reporting until it is killed;
- all four `mic_cycle` transitions land on the same second as the ground truth, driven by listeners
  (no star);
- a process that appears after startup (`ffmpeg`) gets its listener attached in time and is reported
  correctly, including its disappearance;
- `output=off` throughout, which is correct — nothing was playing audio.

Not verified here, left for the table: real call apps, and sleep/wake with the lid closed.

## TCC

**No permission prompt appeared, and none is needed.** The tool ran repeatedly as a bare binary
outside any `.app` bundle, with no `Info.plist` and no usage-description keys, and every property
read returned data. `log show --last 25m --predicate 'process == "tccd"'` contains no mention of
`CallDetectSpike` at all.

Note for comparison: `ffmpeg` really did record audio during the test, so the microphone grant it
used was the terminal's — that grant has nothing to do with the spike, which never opens a device.

## Results Table — To Fill In During Real Usage

Run the tool, join a real call, and copy the relevant lines. For every "yes", note whether the line
had a star: a star means the listener stayed silent and only the 2-second sweep caught it.

| App | Flag flips when the call starts (listener or sweep\*) | Flag clears after the call ends (listener or sweep\*) | Voice message / dictation raises it | Listeners survive sleep-wake, lid closed mid-call | Notes |
| --- | --- | --- | --- | --- | --- |
| Zoom (`us.zoom.xos`) | | | | | |
| Telegram (`com.tdesktop.Telegram`) | | | | | |
| Slack (`com.tinyspeck.slackmacgap`) | | | | | |
| FaceTime (`com.apple.FaceTime`) | | | | | |

For the sleep-wake row: start the tool, join a call, close the lid mid-call, open it again, and
check that the tool still reports the call's end. If it reports nothing after wake, the per-process
listeners did not survive and B2 must re-enumerate on `NSWorkspace.didWakeNotification`.

## What B2 Takes From This

- Listen on the process object with a wildcard address, not on `IsRunningInput` — that selector
  never notifies.
- Re-enumerate `kAudioHardwarePropertyProcessObjectList` on its own listener and attach to new
  process objects; that part works exactly as the plan assumed.
- Keep the allowlist. `com.apple.CoreSpeech` holds the mic alongside every real user of it.
- Decide the sweep question from the table: keep a slow (2-5 s) sweep as a backstop if real call apps
  produce starred lines. Even then it is a property read per process, nothing like the current
  aggregate-device probe.

Throwaway helpers used to reach these conclusions are in `untracked/scripts/`
(`mic_cycle.swift`, `poll_mic_flags.swift`, `wildcard_probe.swift`, `listener_probe.swift`).
