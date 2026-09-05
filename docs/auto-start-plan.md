# Auto-Start Plan

Goal: stop touching the app by hand. Podushka runs from login, notices a call by itself,
records it, and tells me afterwards. Manual `Listen` stays as a fallback.

Chosen behaviour: record first, notify after (with a "Cancel and delete" action),
not "ask before recording".

## Current State (verified 2026-08-29)

- `Audio/CallDetector.swift` is fully written but wired to nothing: no reference to
  `CallDetector` exists in `App/`. `AppSettings.autoDetectEnabled` and `enabledCallApps`
  are written and never read (`App/AppSettings.swift:18`).
- `AppController.Status.autoRecording(String)` exists and is never assigned
  (`App/AppController.swift:13`).
- The detector's start signal is an output-audio tap probe re-created every ~6.5 s
  (5 s debounce + 1.5 s probe, recursion at `Audio/CallDetector.swift:176`) while an
  allowlisted app runs. Each probe builds and destroys a private aggregate device
  (`Audio/ProcessAudioActivityProbe.swift:66`).
- `scripts/build_podushka_app.sh` never calls `codesign`; the bundle carries the linker's
  ad-hoc signature (`Identifier=Podushka-<content hash>`, `Info.plist=not bound`), so the
  TCC identity changes on every rebuild.
- `Resources/Info.plist` has `LSUIElement=false` and `PodushkaApp` opens a `WindowGroup`
  on launch. No `SMAppService`, no login item.
- `untracked/calls.sqlite` holds 52 calls; exactly one is stuck in `recording`.
- Signing identity available: `Apple Development: ... (QX7LJ7LQ45)`.
- Host is macOS 26.2, so every process-audio API from 14.2 is available.
- Audio is buffered in memory for the whole call and only written on stop
  (`Audio/PCMFloatRecorder.swift:17`, `Audio/DualCapture.swift:106`), and `maxDuration`
  is 4 hours (`App/AppController.swift:166`).

## Stage A: The App Is Always Running

- [x] **A1. Stable code signature.** Sign the whole bundle after the Info.plist is copied:
      `codesign -f -s "Apple Development: ..."` on the `.app`, **without** hardened runtime
      and without entitlements — `--options runtime` would demand
      `com.apple.security.device.audio-input` and turn the mic silent.
      Check: permissions are granted once (they drop one last time on the ad-hoc →
      Development switch), then rebuild, relaunch, record — no new prompt, `them.raw.wav`
      is not silent.
- [x] **A2. Install to a stable location.** Build script installs to
      `~/Applications/Podushka.app` and removes the `.build` copy, so LaunchServices and
      `SMAppService` cannot resolve the same bundle id to a stale duplicate.
      Check: `open ~/Applications/Podushka.app` records end to end; no second Podushka
      bundle remains on disk.
- [x] **A3. Menu-bar-only app.** `LSUIElement=true`, drop the `WindowGroup("control")`
      scene. As an accessory app, windows open unfocused, so call `NSApp.activate()`
      wherever a window is opened (`App/MenuBarView.swift:117,123` already does this for
      the transcript window — the Calls window needs the same).
      Check: launching shows only the menu bar item; `Transcript`, `Calls` and `Settings`
      all open to the front.
- [x] **A4. Launch at login.** `SMAppService.mainApp.register()` behind a
      `Launch at login` toggle in `SettingsView`, state read from
      `SMAppService.mainApp.status`, including `.requiresApproval` (System Settings
      confirmation) shown as text. Only meaningful from the installed bundle.
      Check: enable, log out, log back in, the menu bar item is there.
- [x] **A5. Crash-safe startup.** On launch mark every call left in `recording` /
      `normalizing` / `transcribing` as `failed` with a reason.
      Note: a killed recording leaves no WAV at all (audio is memory-buffered), so these
      rows are not retryable — the point is that the list stops lying.
      Check: kill the app mid-recording, relaunch, the call shows as failed with a
      reason; the existing stuck row is cleaned up too.
- [x] **A6. Stop the idle ASR worker.** The Python worker holds the model in memory
      forever once started (`App/AppController.swift:178` is the only way to kill it).
      For an app that now runs from login, shut it down after ~10 minutes idle.
      Check: transcribe a call, wait, the `uv`/python process is gone; the next call
      starts it again on its own.

## Stage B: Recording Starts By Itself

- [x] **B1. Spike: pick the call signal.** Done — tool at `spikes/CallDetectSpike/main.swift`,
      built by `scripts/build_call_detect_spike.sh`, findings in `docs/call-detection-spike.md`.
      No TCC prompt: reading these properties needs no permission, confirmed against `tccd` logs.
      What it changed in our assumptions:
      - `kAudioProcessPropertyIsRunningInput` **never posts notifications**. Listeners register
        with `noErr` and stay silent. What coreaudiod actually posts is
        `kAudioProcessPropertyDevices` (scope `inpt`/`outp`) within ~40 ms, so a wildcard
        listener per process object plus a re-read of the flags is the working mechanism.
      - Even that only fires when a process attaches or detaches a device. A process that keeps
        the device open and merely starts IO flips the flag silently — `com.apple.CoreSpeech`
        does exactly this. So the detector needs a cheap safety sweep (~2 s property re-read,
        no aggregate devices) on top of the events.
      - Every microphone open is shadowed by `com.apple.CoreSpeech` holding input at the same
        time, which makes the allowlist mandatory rather than a nicety.
      - Identity is per process object: Chrome helpers are separate objects, Safari shows up as
        `com.apple.WebKit.GPU`, CLI processes have no bundle id at all.
- [ ] **B1a. Fill the results table with real calls** (owner, during normal work): run the spike
      during a Zoom and a Telegram call and record whether the flag flips at join, clears at
      leave, whether a voice message or dictation raises it, and whether it survives sleep/wake
      with the lid closed mid-call. The open question it settles: whether call apps also flip
      the flag silently, i.e. how much the detector must lean on the sweep instead of events.
- [x] **B2. Rewrite the detector around that signal.** Wildcard property listener per process
      object + list listener + ~2 s safety sweep; keep the allowlist and the debounce, drop the
      recursive re-probe and the aggregate-device probe entirely.
      Delete what dies with it: `minActivePeakDBFS`, `minActiveRMSDBFS`,
      `activityProbeDuration` (`Audio/CallDetector.swift:41`) and
      `Audio/ProcessAudioActivityProbe.swift` if nothing else references it.
      Check: Telegram and Slack idle for 30 minutes — zero starts, zero aggregate devices
      created (`system_profiler SPAudioDataType`), flat CPU.
- [x] **B3. Detector state machine + tests.** Extract the start/stop decision (debounce,
      "manual recording wins", "already recording", minimum gap) into a pure type and add
      the project's first test target for it.
      Check: tests cover start after debounce, no start during a manual recording, stop
      after the mic is released, and a start immediately followed by a stop.
- [x] **B4. Wire it into `AppController`.** Detector start runs the existing call
      recording path with `Status.autoRecording(appName)`; stop ends the capture. Two stop
      conditions: the app released the microphone, or the existing 60 s silence auto-stop.
      Check: real Zoom call — status flips to `Recording Zoom` within ~10 s of joining,
      `transcript.md` appears after leaving, nothing was clicked.
- [x] **B5. Settings UI.** `Record calls automatically` toggle plus the per-app checkbox
      list, both bound to the `AppSettings` fields nothing reads today.
      Check: unchecking Telegram stops Telegram calls from being recorded, no rebuild.
- [x] **B6. Junk guard.** Discard auto-started calls shorter than ~10 s: delete the
      folder, skip ASR, no SQLite row. This is what catches voice messages and dictation.
      Check: a 10-second misfire leaves no call folder and no row.
- [x] **B7. Notify after the fact.** `UNUserNotificationCenter` banner on auto-start
      ("Recording your Zoom call") with a `Cancel and delete` action, and a second banner
      when the transcript is ready. Needs: the delegate set at launch, a registered
      `UNNotificationCategory` for the action, and a small controller-side bridge to open
      the Calls window (no `openWindow` environment inside a notification callback).
      Accepted compromise: the banner lives ~5 s and the action is behind a hover, so the
      menu bar stays the reliable way to cancel.
      Check: both banners appear; `Cancel and delete` stops the capture and removes the
      folder and the row.

## Awaiting Hands-On Verification

Everything in Stage A and Stage B is written, builds clean and passes 8 tests, and the
signed bundle is installed at `~/Applications/Podushka.app`. What no agent could check
without launching the app:

- permissions survive a rebuild (the point of A1), and the mic is not silent;
- the login item registers and comes back after a logout;
- the stale `recording` row is swept on first launch;
- notification authorization is granted, the `Cancel and delete` action appears under the
  banner and really removes folder and row;
- clicking a notification opens the Calls window. Riskiest piece: the bridge that lets a
  notification open that window is wired from `.onAppear` on the menu bar label
  (`App/PodushkaApp.swift:41`). If SwiftUI does not run that before the menu is first
  opened, a notification click will only activate the app and open nothing.

## Stage C: Live Verification

- [ ] One hour-long call watched for memory: the whole recording sits in `[Float]`
      buffers, roughly 1-1.5 GB RSS per hour of dual capture, and auto-start makes long
      unattended recordings likely. If RSS is unacceptable, streaming-to-disk capture
      becomes the next task (out of scope here).
- [ ] A week of real calls with hands off the menu bar.
- [ ] Confirm: no missed call, no false recording, no stuck `recording` row, disk usage
      bounded with `Keep audio files` off.

## Dropped

- Storing `app_bundle_id` / `app_name` in the `calls` table: the app name already shows in
  the status and the notification; a schema migration buys nothing this week.
- Measuring Chrome/Meet in the B1 spike: Chrome is off the allowlist by default
  (`Audio/CallDetector.swift:25`), so it would be work for an unused path.

## Open Questions

- Chrome/Google Meet: mic usage is reported for the whole Chrome process, so any browser
  mic use is indistinguishable from a Meet call. Stays off the allowlist.
- Calls live inside the repo (`untracked/calls/`), and `ProjectPaths` resolves through the
  compiled-in `#filePath` (`App/ProjectPaths.swift:9`) — fine until the repo moves. Moving
  storage to `~/Library/Application Support/Podushka/` is a separate task.
