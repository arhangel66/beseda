---
type: Feature List
---
# Features

What the code does today. Settings tabs are named here in Russian: Основные, Запись, Обработка, Хранение,
Интеграции. First run, menu, settings, archive and export have en/ru string resources in the build bundle;
`scripts/lib/bundle_app.sh` copies that bundle into the app. Packaged lookup is structurally verified,
but the app has not been launched on an English system. This does not establish payment readiness.

- **Menu bar app.** The popover starts and stops a recording, shows progress and the latest calls, and
  copies a transcript. During recording, status and stop stay at the top, recent calls are hidden, and the
  capped live transcript and key points are collapsed by default (`App/Views/MenuBarPopover.swift`). A separate window lists conversations
  (`App/Views/ConversationsWindow.swift`).
- **Capture.** Microphone and system audio are recorded as two channels (`Audio/DualCapture.swift`,
  `Audio/SystemAudioTap.swift`); system audio needs macOS 14.2. Recording can be paused. After the call
  the audio is normalized to 16 kHz mono (`Audio/AudioNormalizer.swift`).
- **Live transcription.** Optional, under Запись → «Расшифровывать во время звонка» (off by default), above
  the per-app recording list. Запись also has «Проверить звук», the same unsaved ten-second two-channel check
  used in onboarding. While recording, the popover shows the last me/them lines, transcribed in 20 s chunks from the files on
  disk, and 3–5 «Ключевые моменты» from the summary provider every 3 minutes. A preview only; it backs
  off when it falls behind (`Transcription/LiveTranscriptionLoop.swift`).
- **Automatic recording.** `Audio/CallDetector.swift` starts recording when an app from the list under
  Запись → Приложения (Zoom, Telegram, Chrome / Google Meet and others) uses the microphone, and posts a
  notification (`App/CallNotifications.swift`).
- **Local transcription.** transcribe.cpp runs in the app process with a GGUF model the user picks under
  Обработка: Parakeet v3 (25 languages) or GigaAM v3 (Russian) — `Transcription/SpeechModel.swift`,
  `Transcription/LocalTranscriber.swift`. Speakers inside the system channel are separated with NVIDIA's
  Nemotron-3 Diarization via FluidAudio (`Transcription/Diarizer.swift`; 199 MB, OpenMDW-1.1, downloaded in the
  background once a speech model is picked; Обработка calls it «Разделение собеседников» and keeps the model
  name and licence under «Подробнее») and can be renamed. One set of state words
  (`SpeechModel.stateLabel`) is shown on the cards in onboarding and Обработка and in the popover: «Выбрана · не
  скачана», «Выбрана · скачана» (on disk, not yet usable), «Скачана» (another model on disk), and «Готова» only
  for the selected, usable model; without a ready model the popover disables «Начать запись» and shows
  the state with a link to Обработка.
- **Archive and search.** Calls are indexed in SQLite with transcripts on disk (`Storage/CallStore.swift`).
  The conversations window groups calls by day, plays the audio (`Audio/CallPlayer.swift`) and searches
  call metadata and transcript text. Under Хранение, retention rules delete raw or normalized audio and
  keep the text (`Storage/StorageJanitor.swift`).
- **Summaries.** A summary of a call is written by one of three providers picked under Обработка: the
  built-in Gemma 4 E4B run by a downloaded llama.cpp server, OpenRouter with the user's key, or LM Studio
  (`Summarization/`). The user defines call types (name, description, prompt) under Обработка; the
  built-in «Другое» always exists, cannot be deleted and holds the general prompt. With another type
  besides it, a classifier first picks the type from the call's weekday and time, duration and the start
  of the transcript — Jev via OpenRouter when a key is set (the time, duration and excerpt leave the
  Mac), else the summary model — and that type's prompt runs; an unsure or unknown pick is «Другое». Processing starts from «Итоги», or by itself after every call when «Обрабатывать звонки
  автоматически» is on (off by default).
- **Call screen result.** A processed call opens on «Итоги» with its type in the header; a call that was
  only transcribed opens on the transcript. «Тип: …» reruns the call as another configured type (no
  classifier), «Скопировать результат» copies the result (`App/Views/CallDetailView.swift`).
- **В прошлый раз.** The call screen and each upcoming calendar event show the date and stored digest of the
  previous related call (decisions, next steps, open questions) with a link that opens it, collapsed on
  the call screen to one line until «Показать полностью»; nothing when there
  is no related call with a summary.
- **Export.** With a folder picked under Хранение → Экспорт результатов → «Папка экспорта», every stored result (auto, manual
  or rerun) is written there as Markdown: title, date, type, result, then the clean transcript. The file
  is named by date and title, so a rerun overwrites it (`Storage/CallExport.swift`). Generated copy/export speaker names and export labels use English or Russian locale resources; authored titles, type names, transcript text, speaker overrides and fixture text remain unchanged. Unknown external summary/provider errors can remain verbatim. Display dates use the system locale; export filenames retain their stable POSIX date.
- **Privacy.** The data folder is owner-only (0700/0600, platform file protection where the volume
  supports it), tightened on every launch (`StorageProtection` in `Storage/StorageJanitor.swift`).
  «Удалить» in the conversations toolbar or a sidebar row's context menu, after a confirmation, removes the
  call's row and transcript, its folder and its export copy (`CallStore.deleteCallAndFiles`); a call being
  recorded or processed cannot be deleted. Under Обработка → «Кто пишет итоги», one note says what leaves the Mac
  (OpenRouter for summaries or Jev, a remote LM Studio host, the webhook) or that nothing does. With
  «Только локально» on and a cloud or remote provider picked, a second note says the built-in model writes
  the summaries and the rows below are that model's, with its «Скачать»; its missing-model error says
  «Скачайте её в Настройках → Обработка».
- **Calendar.** With calendar access, a call is named after the matching calendar event from the calendars
  picked under Интеграции (`Calendar/CalendarService.swift`). A broken link shows as one red row whose button
  fixes it: «Открыть доступ…» without access, «Выбрать календари…» when a picked calendar is gone. When a
  selected calendar is missing, the footer says that new conversations will not receive names until an
  available calendar is selected instead of showing historical coverage.
- **Webhook.** A finished transcript is sent as JSON to the URL under Интеграции → «Свой сервис», retried on
  failure, with a delivery log (`Webhooks/`). The main text names the sent fields and destination; «Подробнее
  для разработчиков» contains POST, `Authorization`, Bearer and protocol restrictions.
- **Onboarding.** A first-run window: welcome (headline «Аудио остаётся на этом Mac», with the exception —
  text goes to the cloud only for features the user turns on — in the same block), «Два источника звука»
  (microphone and system sound, each with its own action; the footer points to Настройки → Запись), speech model
  download, a test recording that shows both channels (`App/Views/OnboardingWindow.swift`).
- **Settings.** Основные uses a compact window height; content-heavy panes retain the full height.
- **Updates.** Sparkle checks hourly and installs when no call is being recorded; Основные → Обновления
  checks by hand (`Runtime/AppUpdater.swift`).

English-system visual first-run and permission recovery are parked under the host-screen incident. After resolution and permission, use `scripts/screenshot_copy.sh` with the kit's `scripts/window-shot.swift` without activating the host session. Source and bundle checks alone are not a pay-ready verdict.

Not in the code: MCP, cloud sync.
