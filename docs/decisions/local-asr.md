---
type: Decision Record
title: Local on-device ASR
status: accepted
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
---

# Local on-device ASR

**Status: accepted.**

## Context
The first plan ([MVP phase plan](../archive/mvp-phase-plan.md)) fixed the scope as "a personal local call
recorder and transcriber": local speech recognition, local-only storage, cloud sync deferred. The plan does not
say why cloud ASR was ruled out; no document records that trade-off.

## Decision
Speech is transcribed on the Mac. Today through transcribe.cpp (`import TranscribeCpp` in
`Transcription/LocalTranscriber.swift`) with a model the app downloads; see [ASR engine](asr-engine.md).
No code path sends audio to a remote ASR service.

## Consequences
- Audio and transcripts stay on the machine; the app needs a model download and Apple Silicon time per call.
- Quality is bounded by what runs locally; the [speaker accuracy](speaker-accuracy.md) record keeps that
  constraint ("everything stays local").
