---
type: Decision Record
title: Speaker accuracy, local
description: How to make Beseda tell speakers apart and transcribe the remote side better, all on the Mac — proposed; part measured, part waiting for the benchmark.
status: proposed
tags: [asr, diarization, research]
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
sources:
  - id: harness
    title: Eval set, scorer and rerun command
    resource: ../../untracked/epics/speaker-accuracy/README.md
  - id: baseline
    title: Beseda's current pipeline and its numbers
    resource: ../../untracked/epics/speaker-accuracy/baseline/README.md
  - id: diarization
    title: Diarization and me/them alternatives
    resource: ../../untracked/epics/speaker-accuracy/diarization/README.md
  - id: asr
    title: Remote-speech ASR alternatives
    resource: ../../untracked/epics/speaker-accuracy/asr/README.md
---

# Speaker accuracy, local

**Status: proposed; the two no-model fixes (echo gate, diarizer timeline) are implemented** in the app
(BESEDA-45, see [ASR](../architecture/asr.md)), not rescored through the app pipeline yet. Part of the table is measured, the rest waits for the benchmark rerun
(`untracked/epics/speaker-accuracy/run_all.sh`); the Mac was overloaded when this was written.
A manual merge of two remote speakers exists in the call view (BESEDA-80, see [Storage](../architecture/storage.md)).
Everything stays local, the benchmark included. Direction E in [development directions](development-directions.md).

## Today's pipeline

Read from the code at `03dae95`.[^baseline]

- **Diarization:** FluidAudio 0.15.6 offline (pyannote community-1 + WeSpeaker + VBx, 21 MB, threshold 0.70),
  on the **system channel only**, after ASR. Speaker labels are given **per ASR word** (overlap, else nearest
  within 0.4 s, else previous word), so a speaker exists only where ASR produced words.
- **Me/them:** the channel and nothing else — mic is "me", system is "them". **No echo cancellation, no
  bleed handling, no dedup between channels**: remote speech leaking into the mic is transcribed again as "me".
- **ASR:** Parakeet v3 (485 MB, language autodetect) or GigaAM v3 RNNT (274 MB, Russian), via transcribe.cpp.

## Eval set and its limits

28 min, 13 recordings:[^harness] 5 real (3 VoxConverse, 2 AMI crops; system channel only, no reference text)
and 8 synthetic two-channel calls mixed from FLEURS (mostly Russian, 3 mixed ru-en), degraded like a call
(100–7000 Hz, libopus 20 kbps, noise), with the system channel echoed into the mic at −20 dB, 60 ms late.

- Synthetic turns are short (1–6 s), shorter than real calls; this penalises the diarizer's 1 s embedding minimum.
- The synthetic echo is one pure delay and gain, which the echo gate fits exactly: **its gain here is an upper
  bound**; a real room smears and distorts echo.
- **WER only on the 8 synthetic calls (~5 min): differences under ~2 points are noise.** No English-only call.
- Speed was measured on a shared, overloaded Mac: ±30 %.

## Metrics

DER (pyannote.metrics, collar 0.25 s, overlap scored; also with overlap excluded and system channel only),
speaker-count error (mean |Δ| per file), WER/CER (system channel, normalized), me/them error (share of speech
time on the wrong channel), bleed (echo words transcribed twice as "me", per remote word), × realtime, model
size.[^harness]

## Candidates and why

Diarization and me/them:[^diarization]

| candidate | why |
|---|---|
| echo gate on the mic | cheapest cross-channel fix, no model: cut mic segments to where the mic beats the predicted echo |
| diarizer timeline instead of per-word labels | no model: the diarizer alone is twice as good as what the app shows |
| FluidAudio 0.17.4, thresholds 0.5–0.8 | same models, newer library; lower threshold for the undercounted speakers |
| embedding minimum 0.3 s | short turns are skipped by the 1 s minimum |
| known speaker count | oracle upper bound for the count error, not a product setting |
| Sortformer (NVIDIA), LS-EEND | end-to-end diarizers FluidAudio already ships in CoreML, handle overlap |
| dropped: pyannote in Python | gated weights, same pipeline as FluidAudio, would need a Python runtime in the app |
| dropped: Apple voice-processing AEC | only on live I/O, cannot run on recorded files; to try in the app |

Remote-speech ASR:[^asr]

| candidate | why |
|---|---|
| Whisper large-v3-turbo (whole file) | multilingual model for mixed calls |
| Whisper turbo per VAD chunk | language detected per chunk, for sentences Parakeet drops in mixed calls |
| GigaAM v3 CTC | the other decoding of the app's Russian engine |
| GigaAM CTC + loudnorm | cheap front-end trick |
| route: Whisper language ID → GigaAM for ru, Parakeet for en | best engine per language, both already in the app |
| dropped: T-one | 8 kHz Russian-only, conflicting numpy; cannot help mixed calls |
| dropped: whisper.cpp / WhisperKit rows | same weights as MLX Whisper, same WER |
| dropped: forcing Parakeet's language | Parakeet v3 has no language prompt; routing does it |

## Baseline

| | Parakeet v3 | GigaAM v3 | diarizer raw timeline |
|---|---|---|---|
| DER real (VoxConverse+AMI) | 0.262 | 0.311 | 0.119 |
| DER synthetic, both channels | 0.938 | 0.810 | 0.767 |
| DER synthetic, system only | 0.606 | 0.413 | 0.295 |
| speaker-count error, all | 0.77 | 0.85 | 0.77 |
| me/them error | 0.077 | 0.036 | 0.034 |
| echo words transcribed twice | 0.678 | 0.620 | — |
| WER / CER, ru calls (5) | 0.128 / 0.077 | 0.100 / 0.063 | — |
| WER / CER, mixed ru-en (3) | 0.389 / 0.327 | 0.448 / 0.262 | — |
| × realtime, whole pipeline | 13.3 | 48.1 | — |
| model size | 485 MB + 21 MB | 274 MB + 21 MB | 21 MB |

Source: `untracked/epics/speaker-accuracy/results/baseline-*.md`.[^baseline]

## Alternatives

Diarization, against baseline Parakeet (`results/diar-*.md`):[^diarization]

| alternative | DER real | DER synthetic both channels | DER synthetic system only | count error real / synthetic | me/them | bleed | × realtime |
|---|---|---|---|---|---|---|---|
| baseline Parakeet | 0.262 | 0.938 | 0.606 | 0.60 / 0.88 | 0.077 | 0.678 | 13 |
| echo gate | 0.262 | 0.481 | 0.606 | 0.60 / 1.00 | 0.031 | 0.013 | 803 (gate alone) |
| diarizer timeline | 0.130 | 0.772 | 0.295 | 0.60 / 0.88 | 0.029 | 0.678 | no extra work |
| timeline + echo gate | 0.130 | 0.282 | 0.295 | 0.60 / 1.00 | 0.001 | 0.013 | 803 (gate alone) |
| FluidAudio 0.17.4 t=0.5 + both | 0.131 | 0.264 | 0.271 | 0.60 / 0.75 | 0.001 | 0.013 | 46 (diarizer alone) |
| Sortformer | not measured yet | | | | | | |
| LS-EEND dihard3 / callhome | not measured yet | | | | | | |
| thresholds 0.6 / 0.7 / 0.8 | not measured yet | | | | | | |
| embedding minimum 0.3 s | not measured yet | | | | | | |
| known speaker count | not measured yet | | | | | | |

ASR, system channel (`asr/results.md`):[^asr]

| engine | WER ru | WER mixed | × realtime | size |
|---|---|---|---|---|
| Parakeet v3 (app) | 0.128 | 0.389 | — | 485 MB |
| GigaAM v3 RNNT (app) | 0.100 | 0.448 | — | 274 MB |
| Whisper turbo | not measured yet | | | ~1.6 GB |
| Whisper turbo per chunk | not measured yet | | | ~1.6 GB |
| GigaAM CTC | not measured yet | | | not checked |
| GigaAM CTC + loudnorm | not measured yet | | | not checked |
| route GigaAM ru / Parakeet en | not measured yet | | | both engines + Whisper for language ID |

## Recommendation (provisional)

1. **Two no-model fixes first**, native Swift, nothing to download:
   - **echo gate on the mic** — echo words transcribed twice 0.678 → 0.013, me/them 0.077 → 0.031;
     ~60 lines with vDSP. Gain measured on pure-delay echo, an upper bound: **verify on real room echo
     in the app** before trusting it (fallback: Apple voice-processing AEC or WebRTC AEC3).
   - **diarizer timeline instead of per-word labels** — DER real 0.262 → 0.130, a few dozen lines.
   - Together: synthetic DER 0.938 → 0.282, me/them → 0.001.
2. **Model choices wait for the benchmark**: FluidAudio 0.17.4 t=0.5 adds a little (0.282 → 0.264);
   Sortformer / LS-EEND / other thresholds and all ASR engines are open until `run_all.sh` fills the rows.
   The ASR target is the mixed calls (WER 0.39–0.45 vs 0.10–0.13 Russian).

**Implemented (BESEDA-45):** both fixes as measured, with two differences: text-less pieces are dropped
instead of shown as empty lines (diarizer segments with no words under them, and the shorter own-speech runs
of a mic sentence — its text goes on the longest run, as in the prototype), and the echo delay is found by
8 s blocks instead of one whole-file FFT, to keep memory flat on long calls. Dropping the text-less diarizer
segments leaves that speech unlabelled, so the app's real DER is probably above 0.130 (likely still well under 0.262). Not rescored:
the eval audio is not built in the checkout and scoring the app pipeline means a full ASR run.

Cost of 1: no models, no size, ~1 ms per audio second for the gate. Not done: no cloud engine, no Python
runtime in the app, no app change before Mikhail approves the direction.

## Extra speakers on real calls (BESEDA-78)

**Mechanism.** Every extra `them` speaker on the 10 one-to-one calls is the interlocutor's own **short
replies** ("да / угу", first words after Mikhail spoke): 1–2 s turns, often over Mikhail's voice, whose
embeddings are too short and distorted to join the main cluster. Longest diarizer segment ≤ 6.2 s on all 13
extras, ≥ 10 s on 9 of 10 main speakers. Not echo of Mikhail (cosine to his voice ≤ 0.15), not music or
notifications.[^cause]

**6 s merge dropped (BESEDA-93).** BESEDA-84 merged every `them` speaker whose longest segment was under 6 s.
It fixed 9 of 10 one-to-one calls, but it is a fitted deletion rule: a real participant who only gives short
replies is erased on any call (critic review, finding 14), and 7 s already erased a real colleague on a daily.
Diarization of every call is back to plain t0.70 + sentence assignment.

**Rule (implemented, BESEDA-93).** Only a call known to be 1:1 gets one remote speaker: every `them-N` of its
stored segments becomes `them-1`. `CallStore` applies it whenever segments are written and whenever an event is
linked, so an event matched after diarization relabels too. Signals the app has:

- calendar event with exactly one attendee besides Mikhail (`calls.participants`) — **used**;
- a 1:1 call type — **not there**: the defaults hold only «Другое», Mikhail's own list only adds «Дейли»;
  types are user-defined names with no "1:1" meaning, so a later type change relabels nothing;
- inferred participant count (BESEDA-70) — **not in the app**: it lives only in the research truth file.

Unlinking the event or switching to a group event does not split the speakers back (re-transcribe to undo).

| | t0.70 | 6 s merge (dropped) | this rule |
|---|---|---|---|
| real calls, total speaker-count error (15 calls) | 20 | 4 | 20 |
| 1:1 calls exact (of 10) | 0 | 9 | 0 |
| benchmark DER real (VoxConverse + AMI) | 0.119 | 0.118 | 0.119 |
| benchmark speaker-count error real | 0.60 | 0.80 | 0.60 |

The rule fires on none of the 15 stored calls: none of them has a calendar event linked, so today it equals
t0.70. With a linked two-person event it would give 10 of 10 one-to-one calls exact and leave the dailies as
they are. The benchmark has no call metadata, so it equals t0.70 by construction.[^oneToOne]

**Caveat (critic finding 15).** The real counts are inferred from transcript text by an LLM, not hand-labelled,
and counts cannot show a merge and a split that cancel out.

[^cause]: [results/extra-speaker-cause.md](../../untracked/epics/speaker-accuracy/results/extra-speaker-cause.md)
[^merge]: [results/short-reply-merge.md](../../untracked/epics/speaker-accuracy/results/short-reply-merge.md), [results/app-merge.md](../../untracked/epics/speaker-accuracy/results/app-merge.md)
[^oneToOne]: [results/one-to-one-forced.md](../../untracked/epics/speaker-accuracy/results/one-to-one-forced.md)
[^harness]: [untracked/epics/speaker-accuracy/README.md](../../untracked/epics/speaker-accuracy/README.md)
[^baseline]: [baseline/README.md](../../untracked/epics/speaker-accuracy/baseline/README.md), `results/baseline-*.md`
[^diarization]: [diarization/README.md](../../untracked/epics/speaker-accuracy/diarization/README.md), `diarization/results.md`
[^asr]: [asr/README.md](../../untracked/epics/speaker-accuracy/asr/README.md), `asr/results.md`
