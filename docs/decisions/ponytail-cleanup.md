---
type: Decision Record
title: Ponytail cleanup (BESEDA-4)
status: accepted
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
---

# Ponytail cleanup (BESEDA-4)

**Status: accepted** (2026-09-26, commits `5cf7f61`, `b1b823d`, `8899194`, `5a2f9a3`, `52e17b9`, `556dac5`).

## Context
Before documenting Beseda, the code was cut down to what it uses, after the ponytail rule in `AGENTS.md`:
the best code is the code never written.

## Decision
Removed or folded:
- `spikes/` (CaptureSpike, CallDetectSpike, DiarizeSpike) with `scripts/build_capture_spike_app.sh` and
  `scripts/build_call_detect_spike.sh` — not built by anything; the capture path lives in `Audio/`.
- `ProcessRunner.stream` and `LineSplitter` — no caller once the Python worker was gone.
- `CoreAudioProcessResolver` — folded into `SystemAudioTap`, its only user.
- `MockSummarizationProvider` — its sample text moved into the `CallSummaryView` previews.
- `SummarizationProvider.swift` — merged into `SummarizationService.swift`.
- `ProcessRunner` — moved from `Audio/AudioNormalizer.swift` into `Summarization/LocalModelSupport.swift`,
  where its callers are.
- Dead `AppController` state (`workerDescription`, `lastTranscript`, `lastDualTranscript`, `lastError`,
  `logMessages` and the like).
- Unused `Identifiable` conformances on transcript and runtime types.
- The transcription pipeline — folded into one path: `transcribeDualCall`, `transcribeChannel`, `finishCall`,
  `saveCall` in `AppController`.

## Consequences
No feature, settings key or on-disk format changed.

Open, Mikhail's call: raising the macOS minimum from 14.0 to 14.2 would remove the `AnyObject` storage and
`#available(macOS 14.2, *)` casts around `SystemAudioTap` (`DualCapture`, `LevelMonitor`), but drops 14.0/14.1.
