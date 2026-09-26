# Why 1:1 calls show an extra `them` speaker (BESEDA-79, 2026-09-26)

Research only. App pipeline as in `real_calls.sh`: FluidAudio 0.15.6 offline diarizer at t0.70, the app's
per-sentence assignment (`SentenceSpeakerAssignment`) of the stored `them.asr.json`, echo gate on the mic.
`extra_speakers.sh` dumps, per call copy, the t0.70 diarizer segments of both channels with their WeSpeaker
embeddings, the echo gate's own-speech intervals and 100 ms levels (`RealCalls <call> dump`) into `hyp/extra/`
(gitignored, no audio, no text); `extra_speakers.py` replays the assignment and writes the tables below.
Ground truth: [real-calls-truth.md](real-calls-truth.md). Listen-free: timings, levels, embeddings only.

## Mechanism: short replies get their own cluster

Every extra speaker on the 10 one-to-one calls (13 speakers, 431 of 2850 `them` sentence-seconds, 15 %) is the
interlocutor's **short replies**, not another voice and not echo:

| | 13 extra speakers | 10 main speakers |
|---|---|---|
| diarizer segment, median | 1.8 s | 3.9 s |
| longest segment | **≤ 6.2 s on all 13** | ≥ 5.2 s (≥ 10 s on 9 of 10) |
| words per sentence | 4.4 | 8.8 |
| segments starting after ≥ 5 s of system silence | 57 % (76 / 134) | 13 % (52 / 404) |
| diarizer time while Mikhail speaks (echo gate) | 64 % (177 of 276 s) | 38 % |
| cosine to Mikhail's mic voice | ≤ 0.15 | 0.11–0.30 |
| level vs main | −2.7…+1.8 dB (one −8.3 dB, 9 s) | 0 |
| cosine to main (mean embedding) | 0.03–0.73 | 1 |

So the extra speaker is the other person's "да / угу / сейчас" and first words after Mikhail talked: 1–2 s
turns, often over Mikhail's voice (double-talk through their echo canceller/noise suppression), whose
embeddings are too short and too distorted to land in the main cluster. What it is **not**:

- **Mikhail's echo/bleed in the system channel**: cosine to his mic voice ≤ 0.15 on all 13, no higher than
  the main speaker's own 0.11–0.30.
- **Codec/volume change**: level within ±3 dB of the main speaker on 12 of 13.
- **Call start/end, music, notifications**: 30 of 134 extra segments sit in the first/last 30 s, and they
  carry ASR words (4.4 per sentence) — speech, not sounds.
- **Overlap in the diarizer output**: 0 % — the offline timeline has no overlapping segments.

A side effect adds to it: 41 of the extras' 188 sentences have no diarizer speech under them and go to the
nearest segment's speaker, which is often the extra one.

The mean-embedding cosine cannot tell an extra from a new person: extras sit 0.03–0.73 from their main
speaker, while different real people on the benchmark sit 0.02–0.46 apart (below). Any cosine threshold that
merges the extras merges real people. This is also why merging by share (BESEDA-69) glued VoxConverse.

The 20260923-130021 daily (7 shown, 4 real) has the same two short-reply speakers (S1, S2: longest segment
4.0 / 6.0 s, 1.6 s median, 67–76 s) plus five big speakers of 336–513 s each, i.e. one more split among long
turns that segment length does not explain (S6 has the highest cosine to Mikhail's voice of all, 0.42, but
only 8 % of its time over his speech — not echo either).

Caveat: on 20260925-125945 and 20260921-125925 the echo gate marks 57–94 % of every speaker's time as
Mikhail's speech, so "while Mikhail speaks" is unreliable there (loudspeaker, not headphones, most likely).

## Per call: every `them` speaker the app shows

`main` = the speaker with most sentence-seconds. Silence = no system diarizer speech for ≥ 5 s before the
segment. "during mic speech" = share of its diarizer time inside the echo gate's own-speech intervals.

| call | speaker | sentence s | sentences | words | diar s | segments | segment lengths s | in first/last 30 s | after ≥5 s silence | during mic speech | overlapped | level vs main dB | cos main | cos Mikhail | sentences off diar |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 20260925-114649 | main | 92 | 25 | 211 | 69 | 16 | median 5.0, max 10.1 | 6 | 2 | 50% | 0% | 0.0 | 1.00 | 0.24 | 1 |
|  | S2 | 34 | 9 | 41 | 11 | 6 | 1.1, 1.2, 1.5, 1.9, 2.0, 2.9 | 4 | 4 | 48% | 0% | 1.0 | 0.29 | 0.15 | 2 |
| 20260925-111702 | main | 19 | 7 | 36 | 11 | 4 | 1.3, 2.3, 2.5, 5.2 | 4 | 1 | 16% | 0% | 0.0 | 1.00 | 0.11 | 2 |
|  | S1 | 11 | 7 | 19 | 10 | 6 | 1.0, 1.2, 1.4, 1.6, 1.8, 2.8 | 5 | 5 | 54% | 0% | -2.7 | 0.73 | 0.03 | 1 |
| 20260924-173649 | main | 365 | 104 | 809 | 288 | 57 | median 3.2, max 32.1 | 7 | 9 | 26% | 0% | 0.0 | 1.00 | 0.15 | 10 |
|  | S2 | 18 | 12 | 38 | 14 | 7 | median 2.0, max 3.2 | 1 | 3 | 64% | 0% | -1.0 | 0.12 | 0.10 | 3 |
| 20260924-173310 | main | 57 | 17 | 137 | 48 | 8 | median 3.9, max 20.3 | 0 | 1 | 25% | 0% | 0.0 | 1.00 | 0.23 | 4 |
|  | S1 | 36 | 16 | 55 | 19 | 9 | median 1.3, max 5.7 | 5 | 2 | 40% | 0% | -1.7 | 0.22 | 0.10 | 3 |
| 20260924-133358 | main | 150 | 32 | 405 | 153 | 7 | median 17.4, max 60.8 | 1 | 2 | 76% | 0% | 0.0 | 1.00 | 0.13 | 1 |
|  | S3 | 9 | 4 | 14 | 5 | 3 | 1.0, 1.2, 2.6 | 2 | 2 | 90% | 0% | -8.3 | 0.08 | 0.11 | 0 |
|  | S2 | 3 | 1 | 14 | 4 | 1 | 4.3 | 0 | 1 | 98% | 0% | -0.4 | 0.41 | 0.11 | 0 |
| 20260924-110157 | main | 104 | 43 | 268 | 86 | 17 | median 4.3, max 14.9 | 7 | 1 | 29% | 0% | 0.0 | 1.00 | 0.30 | 6 |
|  | S1 | 28 | 8 | 36 | 12 | 6 | 1.1, 1.1, 1.9, 2.2, 2.4, 3.5 | 3 | 4 | 75% | 0% | -2.7 | 0.09 | 0.00 | 3 |
|  | S3 | 25 | 7 | 35 | 15 | 7 | median 2.3, max 3.0 | 1 | 3 | 67% | 0% | 1.8 | 0.41 | 0.06 | 0 |
| 20260923-125419 | main | 46 | 16 | 98 | 44 | 12 | median 3.4, max 6.5 | 3 | 1 | 11% | 0% | 0.0 | 1.00 | 0.11 | 2 |
|  | S1 | 32 | 14 | 57 | 24 | 12 | median 1.7, max 6.2 | 4 | 9 | 63% | 0% | -2.7 | 0.55 | -0.04 | 1 |
| 20260923-101613 | main | 702 | 212 | 1862 | 615 | 127 | median 4.2, max 17.6 | 4 | 11 | 31% | 0% | 0.0 | 1.00 | 0.27 | 17 |
|  | S1 | 75 | 32 | 134 | 45 | 24 | median 1.9, max 3.6 | 1 | 17 | 70% | 0% | -0.5 | 0.03 | 0.02 | 5 |
|  | S2 | 52 | 24 | 122 | 36 | 15 | median 2.1, max 4.0 | 0 | 5 | 51% | 0% | -0.0 | 0.29 | 0.06 | 8 |
| 20260922-115609 | main | 293 | 80 | 794 | 272 | 50 | median 4.0, max 14.8 | 6 | 3 | 68% | 0% | 0.0 | 1.00 | 0.27 | 7 |
|  | S1 | 36 | 17 | 79 | 30 | 17 | median 1.7, max 3.2 | 3 | 9 | 83% | 0% | -0.3 | 0.18 | 0.01 | 3 |
| 20260922-084404 | main | 591 | 172 | 1608 | 524 | 106 | median 3.8, max 18.5 | 4 | 21 | 29% | 0% | 0.0 | 1.00 | 0.26 | 14 |
|  | S2 | 70 | 37 | 179 | 52 | 21 | median 2.0, max 5.6 | 1 | 12 | 63% | 0% | -1.5 | 0.15 | 0.05 | 12 |
| 20260923-130021 | main | 513 | 92 | 1271 | 447 | 88 | median 3.8, max 25.6 | 1 | 3 | 32% | 0% | 0.0 | 1.00 | 0.19 | 6 |
|  | S6 | 503 | 86 | 1566 | 473 | 63 | median 4.6, max 34.1 | 1 | 0 | 8% | 0% | -4.4 | 0.26 | 0.42 | 2 |
|  | S7 | 434 | 90 | 1335 | 411 | 30 | median 6.0, max 83.2 | 0 | 1 | 15% | 0% | -4.9 | 0.19 | 0.12 | 3 |
|  | S4 | 412 | 88 | 1268 | 344 | 79 | median 3.8, max 20.9 | 1 | 1 | 11% | 0% | -4.7 | 0.06 | 0.13 | 5 |
|  | S3 | 336 | 93 | 1124 | 274 | 59 | median 2.8, max 21.1 | 0 | 1 | 12% | 0% | -4.9 | 0.17 | 0.28 | 13 |
|  | S2 | 76 | 20 | 125 | 37 | 18 | median 1.6, max 6.0 | 1 | 6 | 22% | 0% | -2.4 | 0.28 | 0.01 | 6 |
|  | S1 | 67 | 25 | 163 | 53 | 29 | median 1.6, max 4.0 | 6 | 14 | 23% | 0% | -3.3 | 0.22 | 0.01 | 8 |

The other dailies (same stats, compact): 20260925-125945 S1/S4 (42/64 s, longest 5.5/6.6 s), 20260924-130017
S3/S2 (13/18 s, longest 2.4/2.5 s), 20260922-125838 S1/S5 (45/15 s, longest 4.2/4.4 s), 20260921-125925 S1
(20 s, longest 4.0 s) are the short-reply kind; all other daily speakers have a longest segment of 18–84 s.

## Benchmark (BESEDA-6 set, system channel, same t0.70 run)

Each diarizer speaker mapped to the reference speaker it overlaps most; `real` = the biggest one of that
reference speaker, `split` = a piece of it.

| file | diarizer speaker | reference | real or split | seconds | segments | longest segment s | max cos to another | max cos to a bigger |
|---|---|---|---|---|---|---|---|---|
| ami_ES2004a | S1 | FEE013 | real | 117 | 12 | 24.3 | 0.13 | – |
| ami_ES2004a | S2 | MEO015 | real | 50 | 8 | 14.2 | 0.13 | 0.13 |
| ami_ES2004a | S3 | MEE014 | real | 29 | 4 | 12.9 | 0.10 | 0.10 |
| ami_IS1009a | S1 | FIE088 | real | 142 | 26 | 15.2 | 0.29 | – |
| ami_IS1009a | S3 | FIO089 | real | 53 | 15 | 10.5 | 0.29 | 0.29 |
| ami_IS1009a | S2 | FIO087 | real | 22 | 3 | 17.4 | 0.46 | 0.14 |
| ami_IS1009a | S4 | FIO084 | real | 16 | 2 | 8.7 | 0.46 | 0.46 |
| call_en_me_ru_3spk | S2 | spk2 | real | 6 | 3 | 2.5 | 0.25 | – |
| call_en_me_ru_3spk | S1 | spk3 | real | 5 | 2 | 3.2 | 0.25 | 0.25 |
| call_en_me_ru_3spk | S3 | spk1 | real | 3 | 1 | 2.6 | 0.15 | 0.15 |
| call_mix_2spk | S1 | spk1 | real | 11 | 2 | 5.7 | 0.12 | – |
| call_mix_2spk | S2 | spk2 | real | 8 | 2 | 5.1 | 0.12 | 0.12 |
| call_mix_3spk | S1 | spk2 | real | 11 | 3 | 6.5 | 0.12 | – |
| call_mix_3spk | S2 | spk3 | real | 10 | 2 | 5.3 | 0.37 | 0.12 |
| call_mix_3spk | S3 | spk1 | real | 8 | 2 | 4.2 | 0.37 | 0.37 |
| call_mix_4spk | S1 | spk3 | real | 27 | 6 | 6.6 | – | – |
| call_ru_2spk | S1 | spk1 | real | 8 | 3 | 4.2 | 0.11 | – |
| call_ru_2spk | S3 | spk2 | real | 3 | 1 | 3.1 | 0.29 | 0.06 |
| call_ru_2spk | S2 | spk2 | split | 3 | 1 | 2.8 | 0.29 | 0.29 |
| call_ru_3spk_a | S2 | spk3 | real | 15 | 4 | 4.7 | 0.25 | – |
| call_ru_3spk_a | S1 | spk1 | real | 11 | 2 | 7.1 | 0.25 | 0.25 |
| call_ru_3spk_b | S2 | spk1 | real | 14 | 3 | 7.9 | 0.17 | – |
| call_ru_3spk_b | S1 | spk2 | real | 12 | 4 | 4.3 | 0.17 | 0.17 |
| call_ru_3spk_b | S3 | spk3 | real | 3 | 1 | 2.7 | -0.04 | -0.04 |
| call_ru_4spk | S1 | spk3 | real | 25 | 5 | 9.4 | 0.02 | – |
| call_ru_4spk | S2 | spk2 | real | 2 | 1 | 2.4 | 0.02 | 0.02 |
| vox_asxwr | S1 | spk00 | real | 120 | 4 | 36.2 | 0.19 | – |
| vox_asxwr | S3 | spk02 | real | 75 | 3 | 35.6 | 0.03 | 0.02 |
| vox_asxwr | S2 | spk01 | real | 42 | 1 | 41.7 | 0.19 | 0.19 |
| vox_azisu | S2 | spk00 | real | 71 | 10 | 23.6 | 0.18 | – |
| vox_azisu | S1 | spk03 | real | 61 | 6 | 23.7 | 0.18 | 0.06 |
| vox_azisu | S3 | spk01 | real | 56 | 3 | 36.5 | 0.18 | 0.18 |
| vox_azisu | S4 | spk03 | split | 2 | 1 | 2.0 | 0.18 | 0.18 |
| vox_gzvkx | S3 | spk01 | real | 126 | 3 | 80.6 | 0.23 | – |
| vox_gzvkx | S2 | spk04 | real | 48 | 3 | 20.5 | 0.27 | 0.19 |
| vox_gzvkx | S1 | spk05 | real | 35 | 3 | 29.0 | 0.27 | 0.27 |
| vox_gzvkx | S4 | spk00 | real | 9 | 1 | 8.7 | 0.02 | 0.02 |

On real recordings (VoxConverse, AMI) the smallest real speaker still has a **longest segment of 8.7 s**
(vox_gzvkx spk00, 9 s total; AMI FIO084 16 s in 2 segments). The synthetic FLEURS calls are cut into 1–6 s turns
by construction (README), so every speaker there is "short" and they cannot judge a segment-length rule.

## Fix candidates

**1. Merge speakers with no long turn (recommended).** A `them` speaker whose longest diarizer segment is
under 7 s is not a speaker: each of its segments is relabelled to the kept speaker of the nearest segment in
time (on a 1:1 call, the main one); if no speaker is kept, the biggest stays. Why 7 s: extras ≤ 6.2 s on
13 of 13, real benchmark speakers ≥ 8.7 s, real daily speakers ≥ 18 s. Counts (`real` from the truth file):

| call | real | now | longest < 4 s merged | longest < 5 s merged | longest < 6 s merged | longest < 7 s merged | longest < 8 s merged |
|---|---|---|---|---|---|---|---|
| 20260925-114649 | 1 | 2 | 1 | 1 | 1 | 1 | 1 |
| 20260925-111702 | 1 | 2 | 1 | 1 | 1 | 1 | 1 |
| 20260924-173649 | 1 | 2 | 1 | 1 | 1 | 1 | 1 |
| 20260924-173310 | 1 | 2 | 2 | 2 | 1 | 1 | 1 |
| 20260924-133358 | 1 | 3 | 2 | 1 | 1 | 1 | 1 |
| 20260924-110157 | 1 | 3 | 1 | 1 | 1 | 1 | 1 |
| 20260923-125419 | 1 | 2 | 2 | 2 | 2 | 1 | 1 |
| 20260923-101613 | 1 | 3 | 1 | 1 | 1 | 1 | 1 |
| 20260922-115609 | 1 | 2 | 1 | 1 | 1 | 1 | 1 |
| 20260922-084404 | 1 | 2 | 2 | 2 | 1 | 1 | 1 |
| 20260925-125945 | 3 | 4 | 4 | 4 | 3 | 2 | 2 |
| 20260924-130017 | 4 | 4 | 2 | 2 | 2 | 2 | 2 |
| 20260923-130021 | 4 | 7 | 7 | 6 | 5 | 5 | 5 |
| 20260922-125838 | 4 | 6 | 6 | 4 | 4 | 4 | 4 |
| 20260921-125925 | 4 | 5 | 4 | 4 | 4 | 4 | 4 |

| benchmark | real speakers | now | longest < 4 s merged | longest < 5 s merged | longest < 6 s merged | longest < 7 s merged | longest < 8 s merged |
|---|---|---|---|---|---|---|---|
| ami_ES2004a | 4 | 3 | 3 | 3 | 3 | 3 | 3 |
| ami_IS1009a | 4 | 4 | 4 | 4 | 4 | 4 | 4 |
| call_en_me_ru_3spk | 3 | 3 | 1 | 1 | 1 | 1 | 1 |
| call_mix_2spk | 2 | 2 | 2 | 2 | 1 | 1 | 1 |
| call_mix_3spk | 3 | 3 | 3 | 2 | 1 | 1 | 1 |
| call_mix_4spk | 4 | 1 | 1 | 1 | 1 | 1 | 1 |
| call_ru_2spk | 2 | 3 | 1 | 1 | 1 | 1 | 1 |
| call_ru_3spk_a | 3 | 2 | 2 | 1 | 1 | 1 | 1 |
| call_ru_3spk_b | 3 | 3 | 2 | 1 | 1 | 1 | 1 |
| call_ru_4spk | 4 | 2 | 1 | 1 | 1 | 1 | 1 |
| vox_asxwr | 3 | 3 | 3 | 3 | 3 | 3 | 3 |
| vox_azisu | 4 | 4 | 3 | 3 | 3 | 3 | 3 |
| vox_gzvkx | 6 | 4 | 4 | 4 | 4 | 4 | 4 |

At 7 s: all 10 one-to-one calls 2–3 → 1, 20260922-125838 6 → 4 and 20260921-125925 5 → 4 (exact),
20260923-130021 7 → 5 (4 real). Costs: 20260925-125945 4 → 2 (3 real: S4 has one 6.6 s turn, 6 s gives 3) and
20260924-130017 4 → 2 (4 real, medium confidence: the two it drops have 13 and 18 s of speech, 4 and 8
sentences, longest turn 2.5 s — people who said a line each; worth a check of the transcript). Real
benchmark: no real speaker merged (vox_azisu 4 → 3 only folds its 2 s split). 6 s is the safer edge on the
dailies but leaves 20260923-125419 at 2 (its extra has one 6.2 s turn); the 6.2 / 6.6 s margin is thin, so
the next task scores both. A floor that keeps short-turn speakers with enough speech does not help: extras
reach 75 s (20260923-101613 S1), more than the 13–18 s of the two 20260924-130017 speakers it would save.
Rule in one place: after clustering, before `SentenceSpeakerAssignment`, ~15 lines, no model.

**2. Not a fix: cosine or echo filters.** A cosine threshold overlaps (extras 0.03–0.73 vs real pairs up to
0.46); dropping diarizer speech during Mikhail's own speech would remove 64 % of the extras' time but also
38 % of the main speaker's and still leaves their other replies; echo is not the cause (cosine to Mikhail ≤ 0.15).

## Rerun

```
untracked/epics/speaker-accuracy/extra_speakers.sh   # dumps hyp/extra/*.json, ~1 min per call
cd untracked/epics/speaker-accuracy && uv run extra_speakers.py
```
