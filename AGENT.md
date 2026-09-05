# 📄 AGENT.md: Podushka Project Overview

Этот файл предназначен для быстрой ориентации ИИ-агентов в проекте **Podushka**.

## 🎯 Проект: Podushka
**Тип:** Local macOS Call Recorder & Transcriber (PoC)
**Основная задача:** Автоматическая запись (микрофон + системный звук), нормализация аудио, транскрибация через ASR-воркер и управление архивом записей.

---

## 🛠 Технологический стек

### Client (macOS App)
*   **Language:** Swift (SwiftUI)
*   **Frameworks:** SwiftUI, AVFoundation (Audio Engine), CoreAudio, AppKit (Menu Bar).
*   **Data:** SQLite (локальный индекс вызовов).
*   **Audio Processing:** AVAudioConverter для нормализации (16kHz, mono, Int16); внешних бинарников нет.

### Речевой движок (ASR)
*   **Library:** [transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) (ggml + Metal), слинкована в приложение через `Vendor/TranscribeCpp` и xcframework из релиза v0.2.3.
*   **Модели:** GGUF, каталог в `Transcription/SpeechModel.swift` — Parakeet v3 (25 языков, 485 МБ) и GigaAM v3 от Сбера (только русский, 261 МБ). Скачиваются в `~/Library/Application Support/Podushka/runtime/models` и сверяются по sha256.
*   **Task:** Speech-to-Text в том же процессе; отдельного воркера и Python больше нет.

---

## 📂 Архитектура проекта (High-Level)

```text
.
├── App/               # Код macOS приложения (SwiftUI/Swift)
│   ├── Views/         # UI: Окно разговоров, плеер, настройки, выбор модели, Menu Bar
│   └── ...            # AppController, AppSettings и др.
├── Audio/             # Захват звука (System Audio + Mic), детекция вызовов
├── Storage/           # Работа с SQLite и файлами записей
├── Transcription/     # Распознавание: каталог моделей, движок, сборка фраз, нарезка длинного аудио
├── Runtime/           # Установка модели: скачивание с проверкой хеша → прогрев, состояние по файлам на диске
├── Vendor/            # Swift-обёртка transcribe.cpp (MIT, скопирована из тега v0.2.3)
├── Webhooks/          # Отправка готовой расшифровки на URL (payload, sender, очередь с повторами)
├── scripts/           # Сборка (build_podushka_app.sh) и упаковка в zip (package_podushka.sh)
├── spikes/            # Прототипы/тесты
├── docs/              # Техническая документация и планы
├── untracked/         # Черновики, спайки, дизайн (данные приложения живут в Application Support)
└── MVP_PHASE_PLAN.md # План развития проекта
```

---

## 🔄 Рабочие процессы (Data Flow)

1.  **Detection:** `CallDetector` обнаруживает активность (микрофон + системный звук).
2.  **Recording:** `PCMFloatRecorder` пишет два потока (Mic + System) в RAW WAV.
3.  **Normalization:** После завершения `AudioNormalizer` пережимает аудио в 16kHz mono.
4.  **ASR Task:** `LocalTranscriber` читает нормализованный WAV, режет его на куски, гоняет модель и собирает фразы из слов (`SentenceBuilder`).
5.  **Storage:** Транскрипты сохраняются в Markdown, метаданные — в SQLite.

---

## 🚦 Текущее состояние и важные файлы

### Ключевые компоненты для изучения:
*   **`App/AppController.swift`**: Сердце приложения, связывающее аудио и UI.
*   **`Transcription/LocalTranscriber.swift`**: Реализация логики распознавания.
*   **`untracked/calls.sqlite`**: Основная база данных с историей вызовов.
*   **`MVP_PHASE_PLAN.md`**: Документ, определяющий вектор разработки.

### Команды запуска:
*   **Тесты:** `swift test`
*   **Сборка приложения:** `./scripts/build_podushka_app.sh`

---

## 📝 Инструкции для Агента
*   **При правке UI:** Смотри в `App/Views` и `App/DesignSystem.swift`.
*   **При проблемах с аудио:** Исследуй `Audio/`.
*   **При работе с данными:** Используй `Storage/` или `App/Storage`.
*   **При анализе логов:** Проверяй `untracked/podushka-app.log`.

---
