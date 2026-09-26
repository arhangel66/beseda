# UI redesign from the Claude Design prototype

Source: `untracked/design/prototype.dc.html` (imported from claude.ai/design project
`46818607-492c-452d-84f4-f0136d039a36`, file `Podushka - Интерактивный прототип.dc.html`).

Scope agreed with Mikhail: build the whole prototype UI, backed by real data and real
local behaviour. Two prototype areas are dropped because nothing in the app produces
their data: the **Итоги** tab (summary / decisions / tasks / topics — needs an LLM) and
the **Модели** settings section (ASR/LLM model manager with downloads). The three
existing windows (`control`, `calls`, `transcript`) collapse into one window
**«Разговоры»**; their views are deleted, not kept as a shim.

UI copy is Russian, as in the prototype. Code, comments and file names stay English.

## Appearance

The prototype specifies every colour as a `light-dark(light, dark)` pair, so the design
is already adaptive. The app follows the system appearance; no forced dark mode.

- [x] `App/DesignSystem.swift`: a `Palette` enum holding the prototype's light/dark
      pairs, the accent `#0a6cff`, the recording red `#e5484d`, the ok green `#34c759`,
      plus the corner radii. Each pair is a *named* dynamic `NSColor` — SwiftUI resolves
      an unnamed one once, in light, and the window never follows the system into dark.
- **Check:** the same screen in Light and Dark matches the two halves of every
  `light-dark()` pair in the prototype; no hard-coded greys outside `DesignSystem`.

## 1. Data the UI needs but the app does not store yet

- [x] `CallStore`: add an `app_name` column (ad-hoc migration next to the existing
      `columnExists` checks) and persist the detected app for auto-started calls;
      manual dual calls get `nil`, mic-only calls get `"Микрофон"`.
- [x] `CallStore.searchCallIDs(matching:)` — SQL `LIKE` over `segments.text`, so the
      sidebar search reaches inside transcripts without loading them all.
- [x] `StoredCallSummary`: derived `displayTitle` from the opening of the transcript —
      the first five lines are read, and the first sentence carrying at least 20
      characters wins, so a call does not end up titled "Hello". Cut at ≤64 chars on a
      word boundary; fallback `"<App> · <date>"`, and `"Заметка с микрофона"` for
      `kind == "mic"`. *(This replaces the prototype's LLM-written titles — it is the
      only real handle we have.)*
- [x] `StoredCallSummary`: `dayGroup` → `Сегодня / Вчера / На этой неделе / Ранее`.
- **Check:** unit tests for title derivation (empty transcript, long first segment,
  mic note) and for day grouping across a day/week boundary.

## 2. Menu bar and popover

- [x] `App/Views/MenuBarPopover.swift` replacing `MenuBarView.swift`, four states driven by
      `AppController.status`:
      - **idle** — «Записать звонок», auto-record toggle, last 3 calls, footer links;
      - **recording** — mm:ss clock, two live level meters (me / собеседник),
        «Остановить» + «Пауза»;
      - **job** — phase title («Готовлю запись» / «Превращаю в текст») and progress;
      - **done** — last call card with «Открыть разговор» and «Итоги» (copies the
        transcript markdown).
- [x] Menu bar label: waveform icon + mm:ss while recording, `···` while processing,
      icon alone when idle.
- [x] `Audio/AudioActivityTracker.swift` publishes a decaying peak level, and
      `DualCapture` now keeps one tracker per channel (the silence stop takes the
      quieter of the two) and exposes both levels. The meters show real audio.
- [x] Pause: `DualCapture.setPaused(_:)` gates both recorders through one flag, so the
      two channels stay aligned.
- [x] Job progress: four steps derived from the status — normalize, worker start,
      transcribe, done. No fake percentage ticking between events.
- **Check:** run a recording — the clock ticks, both meters move when speaking, pause
  freezes them, stop moves the popover to the job state and then to done.

## 3. Window «Разговоры»

- [x] `App/Views/ConversationsWindow.swift` — toolbar: title, search field,
      «Записать», «Поделиться», gear.
- [x] `App/Views/CallSidebar.swift` — live recording row on top, calls grouped
      by day, avatar initials, meta line, duration, search-hit highlighting, the
      «Ничего не нашлось» empty state, and the storage footer
      («Локально · N разговоров · X ГБ аудио», real sizes).
- [x] `App/Views/CallDetailView.swift` — header (title, app, when, duration,
      «два канала» badge), tab strip **Расшифровка / Инфо**, the ffmpeg failure banner
      with «Установить ffmpeg» and «Расшифровать снова», and the Инфо grid + the
      collapsible technical log, which shows the call's own `session.json`. The grid
      drops the prototype's «Модель» row — the model is not recorded per call — and
      keeps «Скорость» from `transcript_jobs`.
- [x] `App/Views/PlayerBar.swift` — play/pause, waveform scrubber, clock,
      speed cycle 1×/1.5×/2×.
- [x] `Audio/CallPlayer.swift` — two `AVAudioPlayer`s (me + them) started together and
      kept in sync, falling back to the normalized files when the raw WAVs were swept.
- [x] `Audio/WaveformPeaks.swift` — downsample both channels to 84 bars, take the max.
- [x] Clicking a transcript line seeks; the playing line highlights.
- [x] Delete `App/CallsWindow.swift`, `App/TranscriptWindow.swift`,
      `App/MenuBarView.swift`, `App/OnboardingView.swift`, and `runTestRecording`
      with its «Mic 30s» entry point, which the new UI no longer reaches.
- **Check:** open a real recorded call — the waveform matches the audio, the playhead
  moves, clicking a line jumps there, search highlights hits in titles and lines.

## 4. Settings

Two sections instead of the prototype's three (**Модели** is out of scope).

- [x] `App/Views/SettingsWindow.swift` replacing `SettingsView.swift` — sidebar nav
      **Запись / Хранение**, prototype layout.
- [x] **Запись**: «Включать запись при начале звонка» (+ the per-app list),
      «Останавливать после минуты тишины», «Уведомлять, когда расшифровка готова»,
      launch-at-login, and the green privacy note.
- [x] `AppSettings`: `keepAudio: Bool` is replaced by retention rules
      `rawRetention` / `normalizedRetention` (`Сразу / 30 дней / 90 дней / Всегда`),
      plus `notifyWhenReady` and `stopOnSilence`. The old key is dropped, not migrated
      behind a shim.
- [x] **Хранение**: the three-row table (Исходное аудио / Нормализованное аудио /
      Расшифровки и итоги) with real sizes on disk, the retention segmented control,
      the freed-space hint, «Очистить сейчас», and the calls folder row with «Показать».
- [x] `Storage/StorageJanitor.swift` — measures per-kind sizes and deletes raw /
      normalized WAVs past their retention; runs at launch and once every 24 h; the
      post-transcription cleanup uses the same rule instead of `keepAudio`.
- **Check:** unit tests for the sweep decision (per file kind, age, retention value)
  and for the size roll-up; a manual «Очистить сейчас» removes exactly the expected
  files and the sizes shrink.

## 5. Onboarding

- [x] `App/Views/OnboardingWindow.swift` — three steps with the dotted progress, shown
      as a sheet over the window on first launch.
- [x] Step 1: the three privacy promises.
- [x] Step 2: real permission checks — микрофон (`AVCaptureDevice`), системный звук
      (start and immediately stop a tap), ffmpeg (`ExecutableResolver`). «Установить»
      for ffmpeg runs `brew install ffmpeg` when Homebrew is present; otherwise it
      shows the command to run.
- [x] Step 3: the 10-second check — starts both captures, paints the live meter,
      writes nothing to disk, reports «Оба канала слышны».
- [x] `App/PermissionChecks.swift` holds the three checks; the ffmpeg failure banner in
      the detail pane reuses the same install action.
- **Check:** revoke the microphone permission in System Settings — step 2 shows it as
  not granted and the button opens the right pane; the 10-second check leaves no files
  in `untracked/calls`.

## 6. Notification and toast

- [x] Keep the real `UNUserNotification` for «расшифровка готова» (the prototype's
      in-window banner is a macOS notification in reality); gate it on the new
      `notifyWhenReady` setting.
- [x] `App/ToastOverlay.swift` — the bottom-centre toast for «Итоги разговора
      скопированы», «ffmpeg установлен» and similar, 1.9 s, as in the prototype.
- **Check:** «Поделиться» copies the markdown and shows the toast.

## Out of scope (no data behind them)

- Вкладка **Итоги**: summary, decisions, tasks, topics — needs a local LLM pass over
  the transcript.
- Настройки **Модели**: ASR/LLM picker with download management.
- Participant names and avatars: the app knows the channel and the app, not who spoke.

## Verification

- [x] `swift build` clean, no warnings introduced.
- [x] `swift test` green (existing `CallRecordingPolicyTests` plus the new tests above).
- [x] `./scripts/build_podushka_app.sh` and a manual pass: record a short call end to
      end, browse it, search, play it, run cleanup, walk the onboarding.
- [x] Light and Dark checked on every screen.
