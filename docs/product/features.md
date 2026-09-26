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
  (`Summarization/`).
- **Calendar.** With calendar access, a call is named after the matching calendar event from the calendars
  picked under Интеграции (`Calendar/CalendarService.swift`).
- **Webhook.** A finished transcript is POSTed as JSON to a URL set under Интеграции, with an optional secret
  in the `Authorization` header, retried on failure, with a delivery log (`Webhooks/`).
- **Onboarding.** A first-run window: welcome, microphone and system audio permissions, speech model
  download, a test recording that shows both channels (`App/Views/OnboardingWindow.swift`).
- **Updates.** Sparkle checks hourly and installs when no call is being recorded; Основные → Обновления
  checks by hand (`Runtime/AppUpdater.swift`).

Not in the code: MCP, cloud sync, real-time transcript.
