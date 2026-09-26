---
type: Decision Record
title: Local on-device ASR
status: accepted
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
sources:
  - id: mikhail
    title: Mikhail, 2026-09-26
---

# Local on-device ASR

**Status: accepted.**

## Context
The first plan ([MVP phase plan](../archive/mvp-phase-plan.md)) fixed the scope as "a personal local call
recorder and transcriber": local speech recognition, local-only storage, cloud sync deferred. Local ASR was
chosen on purpose (Mikhail, 2026-09-26): it now works well enough and fast enough, and private calls —
a psychologist's session, for example — can be processed without worry because nothing leaves the Mac.

## Decision
Speech is transcribed on the Mac. Today through transcribe.cpp (`import TranscribeCpp` in
`Transcription/LocalTranscriber.swift`) with a model the app downloads; see [ASR engine](asr-engine.md).
No code path sends audio to a remote ASR service.

## Consequences
- Audio and transcripts stay on the machine; the app needs a model download and Apple Silicon time per call.
- Quality is bounded by what runs locally; the [speaker accuracy](speaker-accuracy.md) record keeps that
  constraint ("everything stays local").
