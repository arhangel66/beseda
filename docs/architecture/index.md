# Architecture

How Beseda is built, one document per area. Code is the source of current behaviour; these documents
explain how the parts fit and what constrains them.

- [Audio capture](audio-capture.md) — microphone and system audio as separate channels, call detection, levels.
- [ASR](asr.md) — local speech recognition (Parakeet, GigaAM), timestamps, diarization, transcript merge.
- [Storage](storage.md) — the SQLite call index, the archive on disk, search and audio retention.
- [Integrations](integrations.md) — the webhook and other ways calls leave the app.
- [Summarization](summarization.md) — how a call summary is produced, shown on the call screen and exported to Markdown.
- [Related calls](related-calls.md) — the previous related call and a digest of its stored summary, for «В прошлый раз».
- [App structure](app-structure.md) — the menu bar app, `AppController` and the views.
- [Build and release](build-release.md) — scripts, signing, updates and the ios kit.
