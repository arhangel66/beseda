---
type: Feature List
---
# Features

What the code does today. Settings tabs are named as in the app: Основные, Запись, Обработка, Хранение,
Интеграции.

- **Menu bar app.** The popover starts and stops a recording, shows progress and the latest calls, and
  copies a transcript (`App/Views/MenuBarPopover.swift`). A separate window lists conversations
  (`App/Views/ConversationsWindow.swift`).
- **Capture.** Microphone and system audio are recorded as two channels (`Audio/DualCapture.swift`,
  `Audio/SystemAudioTap.swift`); system audio needs macOS 14.2. Recording can be paused. After the call
  the audio is normalized to 16 kHz mono (`Audio/AudioNormalizer.swift`).
- **Live transcription.** Optional, under Запись → «Расшифровывать во время звонка» (off by default):
  while recording, the popover shows the last me/them lines, transcribed in 20 s chunks from the files on
  disk, and 3–5 «Ключевые моменты» from the summary provider every 3 minutes. A preview only; it backs
  off when it falls behind (`Transcription/LiveTranscriptionLoop.swift`).
- **Automatic recording.** `Audio/CallDetector.swift` starts recording when an app from the list under
  Запись → Приложения (Zoom, Telegram, Chrome / Google Meet and others) uses the microphone, and posts a
  notification (`App/CallNotifications.swift`).
- **Local transcription.** transcribe.cpp runs in the app process with a GGUF model the user picks under
  Обработка: Parakeet v3 (25 languages) or GigaAM v3 (Russian) — `Transcription/SpeechModel.swift`,
  `Transcription/LocalTranscriber.swift`. Speakers inside the system channel are separated with FluidAudio
  (`Transcription/Diarizer.swift`) and can be renamed.
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
  Mac), else the summary model — and that type's prompt runs; an unsure or unknown pick is «Другое». Processing starts from «Итоги», or by itself after every call when «Обрабатывать созвоны
  автоматически» is on (off by default).
- **Call screen result.** A processed call opens on «Итоги» with its type in the header; a call that was
  only transcribed opens on the transcript. «Тип: …» reruns the call as another configured type (no
  classifier), «Скопировать результат» copies the result (`App/Views/CallDetailView.swift`).
- **В прошлый раз.** The call screen and each upcoming calendar event show the date and stored digest of the
  previous related call (decisions, next steps, open questions) with a link that opens it; nothing when there
  is no related call with a summary.
- **Export.** With a folder picked under Хранение → Экспорт результатов, every stored result (auto, manual
  or rerun) is written there as Markdown: title, date, type, result, then the clean transcript. The file
  is named by date and title, so a rerun overwrites it (`Storage/CallExport.swift`).
- **Privacy.** The data folder is owner-only (0700/0600, platform file protection where the volume
  supports it), tightened on every launch (`StorageProtection` in `Storage/StorageJanitor.swift`).
  «Удалить» in the conversations toolbar or a sidebar row's context menu, after a confirmation, removes the
  call's row and transcript, its folder and its export copy (`CallStore.deleteCallAndFiles`); a call being
  recorded or processed cannot be deleted. Under Обработка, a note says what text goes to OpenRouter when
  summaries or Jev use it.
- **Calendar.** With calendar access, a call is named after the matching calendar event from the calendars
  picked under Интеграции (`Calendar/CalendarService.swift`).
- **Webhook.** A finished transcript is POSTed as JSON to a URL set under Интеграции, with an optional secret
  in the `Authorization` header, retried on failure, with a delivery log (`Webhooks/`).
- **Onboarding.** A first-run window: welcome, microphone and system audio permissions, speech model
  download, a test recording that shows both channels (`App/Views/OnboardingWindow.swift`).
- **Updates.** Sparkle checks hourly and installs when no call is being recorded; Основные → Обновления
  checks by hand (`Runtime/AppUpdater.swift`).

Not in the code: MCP, cloud sync.
