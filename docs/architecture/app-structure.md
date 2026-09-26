---
type: Architecture
title: App structure
description: The menu bar app, AppController and its transcription pipeline, the windows, settings and permissions.
---
# App structure

## How it works

Beseda is a SwiftUI menu bar app (`App/BesedaApp.swift`). `AppDelegate` owns the single `AppController`
and keeps the app alive when the last window closes; `applicationWillTerminate` calls
`controller.shutdown()`, which stops the child `llama-server` and unloads the speech model.

**`AppController`** (`App/AppController.swift`, `@MainActor @Observable`) holds the app state
(`status`: idle, recording, working with a `JobStage`, completed, failed) and wires the services: capture,
`CallDetector`, the transcriber and diarizer, `CallStore`, `WebhookService`, `CalendarService`,
`RuntimeInstaller`, `BundledSummaryInstaller`, `LlamaServer`, `AppUpdater`, notifications.

**Transcription pipeline** (dual call):

1. `runDualRecording` creates the call folder and saves the call as `recording`, runs `DualCapture` (with
   the optional [live transcription](live-transcription.md), stopped and awaited when capture ends), then
   normalizes both channels in parallel (`AudioNormalizer`, stage 1 of 5).
2. `transcribeDualCall` starts the transcriber, runs `transcribeChannel` for the microphone and then the
   system audio, diarizes the system channel (`diarizedTurns`; a failure only skips it), and writes
   `transcript.md` with `TranscriptMerger`.
3. `transcribeChannel` transcribes one file, writes its `*.asr.json` and upserts the `transcript_jobs` row.
4. `finishCall` replaces the call's segments in the index, marks it `ready`, applies audio retention and
   enqueues the webhook.

`saveCall` upserts the call row at every status change (`recording`, `normalizing`, `transcribing`,
`ready`, `failed`). `runRetry` reruns a failed call from its saved audio (`mic` or `dual` kind), skipping
capture.

## Windows and views (`App/Views/`)

- **Menu bar popover** — `MenuBarPopover`: status, record/pause/stop, the latest call, commands.
- **Onboarding** — `OnboardingWindow`, four steps (promises, permissions, speech model, finish), opened on
  first launch until `onboardingDone`.
- **Conversations** — `ConversationsWindow` with `CallSidebar` (calls by day, search, upcoming calendar
  events) and `CallDetailView` (tabs «Расшифровка», «Итоги» via `CallSummaryView`, «Сведения»).
  `PreviousCallBlock` («В прошлый раз», [related calls](related-calls.md)) sits above the tab content in
  `CallDetailView` and under each upcoming event in `CallSidebar`; `AppController` looks it up once per
  selected call (`previousCallForSelected`) and per calendar refresh (`previousCallByEventID`).
- **Player** — `PlayerBar` with `CallPlayer` and per-speaker lanes.
- **Settings** — `SettingsWindow`, sections: general, recording, processing, storage, integrations;
  `SpeechModelList` picks the ASR model.

## Settings and permissions

`AppSettings` stores every setting in `UserDefaults` under `beseda.*` keys, each written in `didSet`.
The two secrets, `openRouterAPIKey` and `webhookSecret`, go to the login Keychain instead (`App/Keychain.swift`,
generic password, service = bundle id, account = the same `beseda.*` key). At launch a secret still in
`UserDefaults` is copied to the Keychain, read back, and only then removed from defaults; if the Keychain
refuses, the value stays in defaults and keeps working, and the move is retried at the next launch or edit.
Items are readable by later builds without a prompt as long as they are signed with the same Apple
Development identity: the designated requirement is the bundle id plus the certificate's CN, which survives
certificate renewal (`scripts/lib/bundle_app.sh`).
`PermissionsModel` (`App/PermissionChecks.swift`) checks the microphone (`AVAudioApplication`) and
system audio by actually opening a `SystemAudioTap` for a second, since macOS grants it silently per app;
a denied permission opens the matching Privacy pane. Paths live in `AppPaths`.

## Constraints

- **`AppController` serialises ASR and diarization.** Recording, retry and model switching start only
  when `status.isBusy` is false, and each pipeline step is awaited on the main actor. `LocalTranscriber`
  and `Diarizer` are `@unchecked Sendable` and rely on this (see [ASR](asr.md)).
- `AppController` is about 1,400 lines; the pipeline, calendar, storage and summary actions all live there.
