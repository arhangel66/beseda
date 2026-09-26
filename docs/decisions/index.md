# Decisions

- [Development directions](development-directions.md) — where Beseda goes next: Mikhail's answers and the phased plan; approved with changes.
- [Speaker accuracy, local](speaker-accuracy.md) — echo gate and diarizer timeline first, models pending the benchmark; proposed.
- [Local on-device ASR](local-asr.md) — speech is transcribed on the Mac, no cloud ASR.
- [Separate microphone and system channels](separate-channels.md) — "me" and "them" recorded to separate files.
- [ASR engine](asr-engine.md) — transcribe.cpp with a user-picked Parakeet or GigaAM model, replacing parakeet-mlx.
- [Summarization runtime](summarization-runtime.md) — built-in llama-server by default, OpenRouter or LM Studio by choice.
- [Native SwiftUI menu-bar app](native-menubar-app.md) — one SwiftPM target, `MenuBarExtra`, system controls.
- [SQLite call index](sqlite-storage.md) — `calls.sqlite` through the system SQLite3 API.
- [Call-type classifier](call-type-classifier.md) — bundled llama-server by default, Jev via OpenRouter as opt-in cloud; proposed.
- [Refactor for quality and load](refactor-for-quality-and-load.md) — which incidental decisions to refactor; proposed.
- [Ponytail cleanup (BESEDA-4)](ponytail-cleanup.md) — what the cleanup removed; no behaviour changed.
