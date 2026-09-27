# Nemotron-3 in the app: final numbers (BESEDA-131, 2026-09-27)

The app moved from FluidAudio 0.15.6 offline (pyannote community-1 + WeSpeaker + VBx, t0.70, plus the 6 s
short-reply rule) to FluidAudio 0.17.4 **Nemotron-3 Diarization, offline preset** (weights `ga-2026-09-23`).
This file is the rerun on the final code: both diarizers, each with and without the 6 s rule, on the 15 truth
calls (copies of `them.asr.wav`, one at a time) and the real benchmark (VoxConverse ×3, AMI ×2).

- `nemotron_switch.sh` runs `diarization/Diarize` (variants `offline-t0.7`, `nemotron3-offline`; the same
  FluidAudio 0.17.4, preset, weights and `Nemotron3Diarizer.segments` defaults as `Diarizer.swift`) under
  `nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock /usr/bin/time -l`, only when ≥ 20 % memory is free.
- `nemotron_switch.py` scores it with `other_diarizers.row`: calls = shown `them` speakers after the app's
  per-sentence assignment; benchmark = DER (collar 0.25 s), speaker-count error, glued people (reference
  speakers whose most-overlapping hypothesis speaker is also another's). The 6 s rule is
  `short_reply_merge.merged_timeline(…, 6, "time")`, the app's former `mergingShortReplies`.
- The `0.4.0 t0.70` column is the same models on FluidAudio 0.17.4; BESEDA-115 found it gives the 0.15.6
  counts.
- Same numbers as BESEDA-115 ([other-diarizers.md](other-diarizers.md)), to the file.
- Truth caveat as before: the call counts are an LLM's reading of the transcripts, not hand labels.

## Summary

| approach | 1:1 correct (of 10) | dailies correct (of 5) | total \|Δ\| calls | benchmark DER / count error / glued | bench shown/real | × realtime |
|---|---|---|---|---|---|---|
| offline-t0.7 | 0 | 1 | 20 | 0.119 / 0.60 / 4 | 3/4, 4/4, 3/3, 4/4, 4/6 | 160 |
| offline-t0.7 + 6 s | 9 | 3 | 4 | 0.118 / 0.80 / 4 | 3/4, 4/4, 3/3, 3/4, 4/6 | 160 |
| nemotron3-offline | 10 | 2 | 5 | 0.127 / 0.00 / 2 | 4/4, 4/4, 3/3, 4/4, 6/6 | 347 |
| nemotron3-offline + 6 s | 10 | 3 | 3 | 0.223 / 1.80 / 9 | 1/4, 1/4, 3/3, 3/4, 4/6 | 347 |

**Decision: the 6 s rule is dropped.** With Nemotron it fixes one daily (20260921-125925, 5 → 4) and costs
the benchmark 7 more glued people (2 → 9), DER 0.127 → 0.223, count error 0 → 1.8: both AMI meetings fall to
one speaker, because AMI people talk in turns shorter than 6 s. Nemotron alone already gets all ten 1:1 calls.

## Per call: shown `them` speakers

| call | real | 0.4.0 t0.70 | 6 s rule (0.4.0 app) | **Nemotron** (app now) | Nemotron + 6 s |
|---|---|---|---|---|---|
| 20260925-114649 | 1 | 2 | 1 | 1 | 1 |
| 20260925-111702 | 1 | 2 | 1 | 1 | 1 |
| 20260924-173649 | 1 | 2 | 1 | 1 | 1 |
| 20260924-173310 | 1 | 2 | 1 | 1 | 1 |
| 20260924-133358 | 1 | 3 | 1 | 1 | 1 |
| 20260924-110157 | 1 | 3 | 1 | 1 | 1 |
| 20260923-125419 | 1 | 2 | 2 | 1 | 1 |
| 20260923-101613 | 1 | 3 | 1 | 1 | 1 |
| 20260922-115609 | 1 | 2 | 1 | 1 | 1 |
| 20260922-084404 | 1 | 2 | 1 | 1 | 1 |
| 20260925-125945 | 3 | 4 | 3 | 3 | 3 |
| 20260924-130017 | 4 | 4 | 2 | 2 | 2 |
| 20260923-130021 | 4 | 7 | 5 | 6 | 5 |
| 20260922-125838 | 4 | 6 | 4 | 4 | 4 |
| 20260921-125925 | 4 | 5 | 4 | 5 | 4 |

Nemotron total error on the 15 calls: 5 (dailies 20260924-130017 4 → 2, 20260923-130021 4 → 6,
20260921-125925 4 → 5); the 0.4.0 app with the 6 s rule: 4.

## Time and peak memory per file (processing seconds / peak RSS of the runner, model load excluded)

| file | min | offline-t0.7 | nemotron3-offline |
|---|---|---|---|
| 20260925-114649 | 4 | 2.2 s / 0.31 GB | 0.9 s / 0.11 GB |
| 20260925-111702 | 1 | 0.8 s / 0.24 GB | 0.4 s / 0.08 GB |
| 20260924-173649 | 9 | 3.9 s / 0.35 GB | 1.6 s / 0.16 GB |
| 20260924-173310 | 3 | 1.3 s / 0.28 GB | 0.5 s / 0.10 GB |
| 20260924-133358 | 5 | 1.9 s / 0.30 GB | 1.0 s / 0.12 GB |
| 20260924-110157 | 4 | 1.8 s / 0.31 GB | 0.8 s / 0.11 GB |
| 20260923-125419 | 5 | 1.7 s / 0.32 GB | 1.0 s / 0.12 GB |
| 20260923-101613 | 26 | 8.4 s / 0.51 GB | 4.3 s / 0.34 GB |
| 20260922-115609 | 13 | 3.9 s / 0.40 GB | 2.2 s / 0.20 GB |
| 20260922-084404 | 23 | 6.8 s / 0.42 GB | 3.8 s / 0.30 GB |
| 20260925-125945 | 29 | 10.3 s / 0.44 GB | 4.9 s / 0.36 GB |
| 20260924-130017 | 33 | 11.9 s / 0.52 GB | 5.7 s / 0.40 GB |
| 20260923-130021 | 51 | 22.2 s / 0.56 GB | 8.3 s / 0.59 GB |
| 20260922-125838 | 48 | 16.6 s / 0.68 GB | 7.8 s / 0.56 GB |
| 20260921-125925 | 31 | 10.8 s / 0.52 GB | 5.1 s / 0.40 GB |
| ami_ES2004a | 6 | 2.2 s / 0.33 GB | 1.1 s / 0.13 GB |
| ami_IS1009a | 6 | 2.2 s / 0.34 GB | 1.1 s / 0.13 GB |
| vox_asxwr | 4 | 2.0 s / 0.32 GB | 0.7 s / 0.11 GB |
| vox_azisu | 3 | 1.6 s / 0.30 GB | 0.6 s / 0.10 GB |
| vox_gzvkx | 4 | 1.8 s / 0.32 GB | 1.0 s / 0.11 GB |

Nemotron runs ~2× faster than the old diarizer (347× against 160× real time over the 5.5 h)
and peaks at 0.59 GB on the longest call (51 min). The model is 199 MB on disk (was 21 MB).
