---
type: Architecture
title: ASR
description: How Beseda turns the two channel files into a timestamped, speaker-labelled transcript on the Mac.
---
# ASR

## How it works

Speech recognition runs in-process, on the Mac, through transcribe.cpp (`CTranscribe` binary target plus
the vendored Swift wrapper in `Vendor/TranscribeCpp`). No audio leaves the machine.

- **Engines** — `SpeechModel.catalogue` holds two GGUF models, each with a revision-pinned Hugging Face
  URL, size and SHA-256:
  - `parakeet-tdt-0.6b-v3` (default) — 25 languages, auto-detected; the runtime windows long audio itself.
  - `gigaam-v3-e2e-rnnt` — Russian only, with punctuation; `maxUtteranceSec: 25`, because past its
    ~25 s window it silently drops speech.
- **Runtime installer** — `RuntimeInstaller` (`@MainActor`) runs two resumable stages: `speechModel`
  downloads beside the target and moves the file in only after the hash matches; `warmUp` loads the model
  once and writes a marker naming the model. Switching models re-runs both. Models live in
  `Application Support/Beseda/runtime/models`.
- **Transcription** — `LocalTranscriber` loads the selected model on its serial queue, reads the 16 kHz
  mono file as Float32, cuts it with `UtteranceSplitter` (at the quietest moment in the window tail;
  GigaAM windows, 120 s pieces otherwise just to move the progress bar), and runs each piece with word
  timestamps. The model is unloaded after 10 minutes idle and on quit (`shutdown`).
- **Timestamps** — Parakeet returns word times; GigaAM only token times, so `WordAssembler` rebuilds
  words from SentencePiece tokens (U+2581 starts a word). Piece offsets are added back to absolute time.
  `SentenceBuilder` groups words into sentence segments (punctuation or a long pause).
- **Diarization** — only the system channel is diarized. `Diarizer` wraps FluidAudio's
  `OfflineDiarizerManager` (clustering threshold 0.70); its CoreML models download and compile on first
  use. `SpeakerAssignment.remoteTurns` maps words onto the speaker timeline and yields `them-1`,
  `them-2`… turns. Diarization failure is logged and skipped: the transcript falls back to one `them`.
- **Merge** — `DualTranscriptResult.speakerSegments` interleaves `me` segments with the remote turns by
  start time. `TranscriptMerger.writeDualTranscript` writes `transcript.md` with a `## Dialogue` block
  and a `## Channels` block (per-channel text and segments). `SpeakerNaming` turns keys into display
  names; renames rewrite only the dialogue block (`rewriteDialogue`).

## Main files

`Transcription/LocalTranscriber.swift`, `SpeechModel.swift`, `UtteranceSplitter.swift`,
`WordAssembler.swift`, `SentenceBuilder.swift`, `Diarizer.swift`, `SpeakerAssignment.swift`,
`SpeakerNaming.swift`, `TranscriptMerger.swift`, `TranscriptModels.swift`; `Runtime/RuntimeInstaller.swift`;
the pipeline order is in `AppController.transcribeDualCall`.

## Data flow

In: `me.asr.wav`, `them.asr.wav` from [audio capture](audio-capture.md).

Out, per channel: `ASRTranscription` saved as `me.asr.json` / `them.asr.json` and a `transcript_jobs`
row; per call: `transcript.md` and the `transcript_segments` rows (see [storage](storage.md)).

## Constraints

- **Thread safety rests on the caller.** `LocalTranscriber` is `@unchecked Sendable`: its model state is
  touched on its queue, but `progressHandler`/`diagnosticsHandler` are plain vars. `Diarizer` is
  `@unchecked Sendable` with an unguarded `modelsReady` flag. Both are safe only because the
  `@MainActor` `AppController` runs one call's pipeline at a time and awaits each step.
- **`rewriteDialogue` depends on literal headers.** It finds `"## Dialogue\n\n"` and `"## Channels"` in
  `transcript.md` and silently does nothing if either is missing. Changing those headers in
  `writeDualTranscript` breaks renaming for every existing call.
- The model file must exist before `start()`; otherwise it throws `BesedaError.runtimeMissing`.
