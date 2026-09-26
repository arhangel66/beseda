---
type: Decision Record
title: Refactor for quality and load
description: Which incidental decisions are worth refactoring for better quality or lower CPU/RAM/disk — proposed, awaiting Mikhail's approval.
status: proposed
tags: [refactor, performance, research]
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
---

# Refactor for quality and load

**Status: proposed.** Mikhail (2026-09-26) called [separate channels](separate-channels.md),
[SwiftUI](native-menubar-app.md) and [raw SQLite3](sqlite-storage.md) incidental and asked whether refactoring
them buys quality or load. [Local ASR](local-asr.md) is deliberate and stays. Numbers come from
[speaker accuracy](speaker-accuracy.md) (synthetic calls, speed ±30 %) and [architecture](../architecture/index.md).

## Separate channels

- **Today:** mic and system audio are recorded apart; me/them comes from the channel. Me/them error
  0.04–0.08; the echo of the remote side is transcribed twice as "me" (bleed 0.62–0.68). Cost in load:
  each channel is transcribed on its own, so ASR runs on echo too.
- **Option: keep the channels, add the echo gate** from speaker accuracy (~60 lines, vDSP). A mixed track
  would lose the only free me/them signal and push everything onto the diarizer (DER synthetic 0.77+).
- **Gain:** bleed 0.68 → 0.01, me/them 0.08 → 0.03 (0.001 with the diarizer timeline); gated mic
  segments are not sent to ASR, so less ASR work.
- **Cost / risk:** small; the gain is measured on pure-delay echo, an upper bound — must be checked on real
  room echo before trusting it.

## Capture memory (`PCMFloatRecorder`) — done

- **Was:** the whole call was a `[Float]` in RAM until stop (~2 GB for a one-hour call); a crash mid-call
  lost the recording.
- **Now:** `PCMFloatRecorder` opens the raw WAV at start and writes every buffer with `AVAudioFile.write`;
  a crash leaves every sample on disk, and the next launch rewrites the header sizes
  (`repairWAVHeader`) so the file plays and the call can be retried. RAM is flat whatever the call length.
- **Left:** a write error mid-call is only printed to stderr by the capture callbacks; the audio of that
  buffer is dropped without telling the user.

## ASR / diarization pipeline

- **Today:** raw WAV → 16 kHz `asr.wav` per channel → ASR → diarizer on the system channel → per-word
  labels. Parakeet 13×, GigaAM 48× realtime whole pipeline; 485 / 274 MB models + 21 MB diarizer, unloaded
  after 10 min idle. Per-word labels double DER (real 0.262 vs 0.119–0.130 for the diarizer's own timeline).
- **Option: diarizer timeline instead of per-word labels** (a few dozen lines, no model).
- **Gain:** DER real 0.262 → 0.130, no extra compute.
- **Cost / risk:** low; model swaps (FluidAudio 0.17.4, Sortformer, Whisper) wait for the benchmark.
- **Disk:** raw 48 kHz WAVs are ~6× the 16 kHz files; retention already handles it (`StorageJanitor`) —
  **keep**.

## SwiftUI / app structure

- **Today:** one SwiftPM target, `MenuBarExtra`, system controls. Load sits in ASR, the diarizer and the
  ~5 GB summary model (stopped when idle), not in the UI. Core Audio taps require native code anyway.
- **Option: keep.** No measured UI cost; a rewrite buys nothing in quality or load.

## SQLite storage

- **Today:** raw `sqlite3` behind a serial queue, a fresh connection per call, transcript search by
  `LIKE '%query%'` with no index. Hundreds of calls — both costs are milliseconds.
- **Option: keep.** A wrapper (GRDB) or FTS5 index pays off only if search gets slow on a large archive; the
  one cheap change, a single long-lived connection, is optional.
- **Risk of changing:** the schema is an on-disk contract for later versions.

## Ranked list for approval

1. **Stream capture to disk** — flat RAM, no lost recording on crash; one class.
2. **Echo gate on the mic** — bleed 0.68 → 0.01, less ASR work; verify on real echo first.
3. **Diarizer timeline** — DER real 0.262 → 0.130, no compute.
4. **Keep** SwiftUI and SQLite; revisit SQLite (FTS5) only if search is slow.
