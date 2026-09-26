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
  use. `SpeakerAssignment.remoteTurns` labels each sentence (`them-1`,
  `them-2`…) with the speaker of the diarizer segment it overlaps most, or the nearest one when it lies
  outside diarizer speech; every sentence stays its own line with its own times, so clicking it seeks there.
  Per-word labels, the earlier rule, were twice as wrong ([speaker accuracy](../decisions/speaker-accuracy.md)).
  Diarization failure is logged and skipped: the transcript falls back to one `them`.
  A call whose calendar event has exactly one other attendee is known 1:1: `CallStore` relabels all its
  `them-N` as `them-1` when segments are written or the event is linked
  ([speaker accuracy](../decisions/speaker-accuracy.md)).
- **Echo gate** — remote speech leaking from the speakers into the mic would be transcribed again as
  `me`. `EchoGate` finds the delay (FFT cross-correlation, 0–500 ms) and gain of the system channel
  inside the mic; a 20 ms mic frame is own speech only when its energy beats the predicted echo by 6 dB
  and the noise floor ×10 (gaps up to 200 ms bridged). A mic word is kept when any of its frames is own
  speech; a sentence becomes its kept words with their times, or is dropped. Only the transcript is gated:
  `me.asr.json` keeps everything. One delay and one gain: a real room's smeared echo will get through more
  often. On Mikhail's real calls (headphones) there is no echo to remove and the gate keeps every word
  ([echo gate on real calls](../decisions/speaker-accuracy.md#echo-gate-on-real-calls-beseda-95)).
- **Merge** — `DualTranscriptResult.speakerSegments` interleaves `me` segments with the remote turns by
  start time. `TranscriptMerger.writeDualTranscript` writes `transcript.md` with a `## Dialogue` block
  and a `## Channels` block (per-channel text and segments). `SpeakerNaming` turns keys into display
  names; renames rewrite only the dialogue block (`rewriteDialogue`).

## Main files

`Transcription/LocalTranscriber.swift`, `SpeechModel.swift`, `UtteranceSplitter.swift`,
`WordAssembler.swift`, `SentenceBuilder.swift`, `EchoGate.swift`, `Diarizer.swift`, `SpeakerAssignment.swift`,
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
