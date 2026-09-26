# Roadmap — September 2026

Context: Beseda runs on two Macs (Mikhail and his wife). Updates are a zip copied by
hand. The review from GPT Astra (2026-09-05) was checked against the code; the items
below are the ones that survived. Public distribution (Developer ID, notarisation,
licence audit) is deliberately out: nobody outside the family runs the app yet.

## Order — open decision

Two candidate orders, both reviewed (Kimi K3, 2026-09-05):

- **1 → 2 → 3 → 4 → 5.** Auto-update first so every later change reaches the second Mac
  on its own. Cost: the rewrite of recording (2) and of the call lifecycle (3) land on
  her Mac automatically, with the release script as the only gate.
- **2 → 3 → 1 → 4 → 5.** Recording stops losing data first, then auto-delivery. The
  first Sparkle-enabled version has to travel by zip anyway; in this order that one zip
  also carries 2 and 3, so there is no extra manual install, and the riskiest changes go
  out only after they have run on Mikhail's Mac for a while.

Decided 2026-09-05 (Mikhail): the first. Auto-update goes out now; the numbering below is the order of work.

## 1. Auto-update via Sparkle

Plan: `docs/auto-update-plan.md`.

Done when: a new version published from Mikhail's Mac installs itself on the second
Mac within about an hour while the app keeps running, with no dialog, no «Open Anyway»
in System Settings, and never during a recording.

## 2. Recording survives a crash

`PCMFloatRecorder` keeps every sample in memory and writes the WAV only on stop
(`Audio/PCMFloatRecorder.swift`). A crash or force-quit loses the whole call; memory
grows with call length.

- Stream PCM to the WAV file from a bounded buffer on a background queue; the audio
  callback never touches the disk.
- The call row is already written at start with `status: "recording"`. On launch, pick
  up rows left in that status: whatever audio was streamed becomes the call, and
  transcription runs on it.

Done when: kill -9 during a 5-minute test recording, relaunch, the call appears with
the audio recorded so far and gets transcribed.

## 3. Recording and processing stop blocking each other

`startCallRecording` returns silently while `status.isBusy`
(`App/AppController.swift`), and `isBusy` covers transcription of the previous call.
Two calls back to back lose the second one.

- Separate recording state from processing state.
- Finished calls go to a persisted processing queue; recording always wins, processing
  can wait or be throttled.

Done when: start a call while the previous one is still transcribing; both end up in
the archive with transcripts.

## 4. Native look

Reference: `untracked/design/review-shots/*.png` (2026-08-29). The window mimics a Mac
app but is drawn by hand: custom toolbar row, custom segmented tabs, a filled blue split
button, chips everywhere, one saturated blue for selection, buttons, avatars and
markers alike. Settings is a hand-built table with a filled sidebar selection, an
English window title and an absolute path in the UI.

- Main window on `NavigationSplitView` + system `.toolbar` + `List` with system
  selection; sidebar width becomes resizable for free.
- Title hierarchy: meeting name first, date · duration · app on the second line.
- Transcript: quieter speaker markers, no chips for technical facts («два канала»,
  model, source of the title move to the Info tab).
- Settings: `Form` with `.formStyle(.grouped)` and toolbar-style tabs, like System
  Settings; Russian window title; folder shown as a name with a «Показать в Finder»
  button; sections «Запись», «Распознавание», «Хранение», «Интеграции».
- Keyboard: ⌘F search, arrows through the list, space toggles playback.

Done when: light and dark screenshots of the main window and settings look like a
Mac app next to Notes and System Settings, and the four keyboard paths work.

## 5. Small fixes from the review

- Empty archive says «Запись начнётся сама» while auto-record is off by default
  (`App/Views/CallSidebar.swift`, `App/AppSettings.swift`): offer «Записать разговор»
  and «Настроить автозапись» instead.
- `updateCallIndex` swallows save errors into the log (`App/AppController.swift`):
  surface them as a banner on the call.
- Onboarding can finish after hearing the microphone only
  (`App/Views/OnboardingWindow.swift`): require both sources or show a limited mode.

## 6. Summary provider picker

Plan: `docs/summary-provider-plan.md`, built 2026-09-06: OpenRouter with a key, the
built-in Gemma 4 E4B behind a downloaded `llama-server`, LM Studio as before. The
quality experiment behind the choice is `docs/summary-model-choice-plan.md`.

Done when: a summary comes out of each of the three providers on this Mac, and the
built-in one leaves no `llama-server` process behind after ten idle minutes.

## Deferred

- Splitting `AppController` (~1700 lines): do it inside items 2 and 3 where the code is
  touched anyway, not as its own project.
- Developer ID, notarisation, Keychain for the webhook secret: only if the app leaves
  the family.
