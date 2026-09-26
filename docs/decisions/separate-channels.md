---
type: Decision Record
title: Separate microphone and system channels
status: accepted
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
---

# Separate microphone and system channels

**Status: accepted.**

## Context
The [MVP phase plan](../archive/mvp-phase-plan.md) set the goal: record calls, "separate 'me' and 'them' audio
streams", transcribe both, write a merged transcript. The [capture spike](../archive/capture-spike.md)
(2026-05-10) wrote `mic.raw.wav` from the microphone and `system.raw.wav` from a Core Audio process tap and chose
native process taps over BlackHole, because the tap captured system audio without switching the default
output device. Separate files mean the channel says who spoke ("me" vs "them")
without diarization.
Rationale: incidental — how it was first built; open to change if a refactor improves quality or
load (Mikhail, 2026-09-26). See [refactor for quality and load](refactor-for-quality-and-load.md).

## Decision
`Audio/DualCapture.swift` records the microphone (`MicrophoneCapture`) and system audio (`SystemAudioTap`)
into separate files; each channel is transcribed on its own and the transcripts are merged by time.

## Consequences
- "Me" vs "them" comes from the channel for free; diarization is only needed inside the remote channel.
- The plan listed channel drift on long recordings as a risk ("add alignment correction later").
- Echo of the remote side in the microphone is a known problem; see [speaker accuracy](speaker-accuracy.md).
