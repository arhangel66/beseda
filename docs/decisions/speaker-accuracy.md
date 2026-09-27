---
type: Decision Record
title: Speaker accuracy, local
description: How Beseda tells speakers apart and transcribes the remote side, all on the Mac — echo gate, diarizer timeline, and since BESEDA-131 Nemotron-3 as the diarizer without the 6 s rule.
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

**Diarizer since BESEDA-131: Nemotron-3 Diarization (offline preset, FluidAudio 0.17.4), no 6 s rule.**
It gets all ten 1:1 calls right on its own and the benchmark speaker count exactly; the 6 s rule on top of it
glues 9 benchmark people, so it is gone. See [Nemotron-3 as the diarizer](#nemotron-3-as-the-diarizer-beseda-131).
Sections below it are the history that led there.

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

## Echo gate on real calls (BESEDA-95)

On the 15 truth calls ([echo-gate-real.md](../../untracked/epics/speaker-accuracy/results/echo-gate-real.md))
there is no echo: the system channel is 35–69 dB down in the mic and the one-delay model explains none of it
(Mikhail is on headphones), so the gate works as a mic activity detector. The 57–94 % "own speech" of
20260925-125945 and 20260921-125925 is a mic floor near digital silence (−80 dB), where any breath beats floor ×10 —
not a loudspeaker; it never cost transcript words. The real harm was the sentence rule: 364 of 1 583 kept
sentences had bounds off their words, and a few own words went with dropped sentences. The gate now works by
word (kept when any of its frames is own; sentence = kept words and their times): 0 bounds off, 0 own words lost,
echo kept unchanged. "Most frames own" was rejected: it drops up to 38 real words a call. Still unmeasured: real
loudspeaker echo; if it ever shows up, the fallback stays an AEC (VPIO / WebRTC AEC3), not more gate rules.

## Extra speakers on real calls (BESEDA-78)

**Mechanism.** Every extra `them` speaker on the 10 one-to-one calls is the interlocutor's own **short
replies** ("да / угу", first words after Mikhail spoke): 1–2 s turns, often over Mikhail's voice, whose
embeddings are too short and distorted to join the main cluster. Longest diarizer segment ≤ 6.2 s on all 13
extras, ≥ 10 s on 9 of 10 main speakers. Not echo of Mikhail (cosine to his voice ≤ 0.15), not music or
notifications.[^cause]

**Rule: the 6 s merge, interim default (BESEDA-84, restored in BESEDA-120, dropped in BESEDA-131).** A remote speaker whose longest
diarizer segment is under 6 s gives each of its segments to the nearest-in-time kept speaker; if no speaker has
a 6 s segment, the one with the most seconds stays. t0.70 is unchanged. It lives in
`SpeakerAssignment.mergingShortReplies`, before sentences get their speakers.

It is a fitted deletion rule: a real participant who only gives short replies is erased on any call (critic
review, finding 14), and 7 s already erased a real colleague on a daily. BESEDA-93 dropped it for a
"one remote speaker only on known 1:1 calls" variant; on 2026-09-27 Mikhail brought the 6 s rule back as the
default because it cuts the real-call error from 20 to 4 and the 1:1 variant had nothing reliable to fire on:

- the calendar has no event for ad-hoc calls, so none of the 15 stored calls had one linked and the variant
  equalled t0.70;
- the local LLM's «exactly one other person?» answered «один» on 3 of 5 dailies (20260925-125945,
  20260924-130017, 20260922-125838), so relabelling on it erased real people.[^oneToOne]

Both the calendar path and the classifier question are removed (BESEDA-120).

| | t0.70 | 6 s merge (default) |
|---|---|---|
| real calls, total speaker-count error (15 calls) | 20 | 4 |
| 1:1 calls exact (of 10) | 0 | 9 |
| benchmark DER real (VoxConverse + AMI) | 0.119 | 0.118 |
| benchmark speaker-count error real | 0.60 | 0.80 |

The app path gives the same counts as the harness ([app-merge.md][^merge], rerun in BESEDA-120).

**Escape hatch.** When the rule glues or splits wrongly, «Объединить с» in the call view merges two remote
speakers (BESEDA-80). Each merge is stored per call and applied again after «Расшифровать снова»: rerunning
the diarizer on the same audio gives the same keys, checked on the 15 calls in BESEDA-120. There is no split.

**Caveat (critic finding 15).** The real counts are inferred from transcript text by an LLM, not hand-labelled,
and counts cannot show a merge and a split that cancel out.

## Nemotron-3 as the diarizer (BESEDA-131)

BESEDA-115 compared other local diarizers ([other-diarizers.md][^other]): only NVIDIA's Nemotron-3
Diarization (offline preset) got the 1:1 calls right with no rule and no threshold fitted to Mikhail's calls.
The app switched to it; rerun on the final code ([nemotron-switch.md][^switch]):

| | 0.4.0 t0.70 | 0.4.0 app (t0.70 + 6 s) | **Nemotron-3 (app now)** | Nemotron-3 + 6 s |
|---|---|---|---|---|
| 1:1 calls exact (of 10) | 0 | 9 | **10** | 10 |
| dailies exact (of 5) | 1 | 3 | 2 | 3 |
| total speaker-count error, 15 calls | 20 | 4 | 5 | 3 |
| benchmark DER real | 0.119 | 0.118 | 0.127 | 0.223 |
| benchmark speaker-count error | 0.60 | 0.80 | **0.00** | 1.80 |
| benchmark people glued | 4 | 4 | **2** | 9 |
| × realtime (diarizer alone) | 160 | 160 | 347 | 347 |
| peak memory, longest call (51 min) | 0.56 GB | | 0.59 GB | |
| model on disk | 21 MB | | 199 MB | |

- **The 6 s rule is dropped.** On Nemotron it fixes one daily and glues 7 more benchmark people: both AMI
  meetings fall to one speaker, whose people talk in turns under 6 s. It was a rule fitted to the old
  diarizer's short-reply splits, which Nemotron does not make.
- The dailies are where it is still wrong: 20260924-130017 4 → 2 (no diarizer measured gets above 3 there),
  20260923-130021 4 → 6, 20260921-125925 4 → 5. «Объединить с» covers the extra people; a glued one has no fix.
- Licence: OpenMDW-1.1 (NVIDIA), commercial use allowed; shown under Обработка → Распознавание речи.
- Download: 199 MB, pinned to one revision of `FluidInference/nemotron-3-diarization-coreml`, into the app's
  models folder with a size and sha256 check per file and a free-space check, on the first diarized call.
- Manual merges name the old model's labels: `calls.diarizer` records which diarizer labelled a call, and a
  rerun with another one drops the call's merges ([storage](../architecture/storage.md)). Calls transcribed
  before the switch are re-split in the background from their kept audio (BESEDA-161,
  [asr](../architecture/asr.md)); calls whose audio is gone keep their stored speakers.
- **Re-split of old calls, measured.** On Mikhail's 123 calls, 70 still have `them.asr.wav` + `them.asr.json`
  (47 lost the audio to retention). Against a count read from each transcript, the shown number of other
  people is exactly right on 51 of 70 with Nemotron against 12 before, within one on 64 against 31; the 1:1
  calls go from 5/44 to 40/44 exact, multi-person from 4/23 to 8/23. No call had manual merges.[^allCalls]

[^allCalls]: [results/all-calls-nemotron.md](../../untracked/epics/speaker-accuracy/results/all-calls-nemotron.md)
[^other]: [results/other-diarizers.md](../../untracked/epics/speaker-accuracy/results/other-diarizers.md)
[^switch]: [results/nemotron-switch.md](../../untracked/epics/speaker-accuracy/results/nemotron-switch.md)
[^cause]: [results/extra-speaker-cause.md](../../untracked/epics/speaker-accuracy/results/extra-speaker-cause.md)
[^merge]: [results/short-reply-merge.md](../../untracked/epics/speaker-accuracy/results/short-reply-merge.md), [results/app-merge.md](../../untracked/epics/speaker-accuracy/results/app-merge.md)
[^oneToOne]: [results/one-to-one-forced.md](../../untracked/epics/speaker-accuracy/results/one-to-one-forced.md)
[^harness]: [untracked/epics/speaker-accuracy/README.md](../../untracked/epics/speaker-accuracy/README.md)
[^baseline]: [baseline/README.md](../../untracked/epics/speaker-accuracy/baseline/README.md), `results/baseline-*.md`
[^diarization]: [diarization/README.md](../../untracked/epics/speaker-accuracy/diarization/README.md), `diarization/results.md`
[^asr]: [asr/README.md](../../untracked/epics/speaker-accuracy/asr/README.md), `asr/results.md`
