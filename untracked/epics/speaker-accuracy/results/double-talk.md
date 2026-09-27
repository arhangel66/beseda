# Double-talk removed from the system channel before diarizing (BESEDA-121, 2026-09-27)

Research only, no app change. [extra-speaker-cause.md](extra-speaker-cause.md) found that 64 % of the extra speakers'
time on 1:1 calls falls while Mikhail talks: the interlocutor's overlapped short «да/угу». Question: if the frames
where Mikhail speaks are taken out of the system channel before diarizing, do those replies join the main voice?

**No.** Both variants leave 1:1 calls at 0 of 10 correct (as today) and make the total worse (|Δ| 20 → 23); on top
of the 6 s rule of [short-reply-merge.md](short-reply-merge.md) they lose calls it already fixed (|Δ| 4 → 7 and 13).
The overlap is not what splits the voice. Variant 3 (AEC / spectral subtraction) was skipped: there is nothing to
cancel ([echo-gate-real.md](echo-gate-real.md): no echo of Mikhail on the system channel, he is on headphones),
and removing the double-talk frames outright, the upper bound of what AEC could do here, did not help.

## How

- `double_talk.sh` (copies of `me.asr.wav` + `them.asr.wav`, one call at a time, `lockf`, `nice -n 19`, memory
  wait, peak 316–705 MB) runs `RealCalls <call> doubletalk` → `hyp/double-talk/*.json`; `double_talk.py` prints
  the tables below. No audio out, no cloud, nothing written to Application Support.
- **Mic VAD** (not the echo gate's mask, which makes breaths "own" on −80 dB floor calls): a 20 ms mic frame is own
  speech when it is within 20 dB of the call's own speech level (90th percentile of the mic's frame levels); gaps
  under 0.3 s filled, runs under 0.1 s dropped. Silero VAD was not used: its model is not in the local cache and
  would have been a download. Check against Mikhail's own ASR: 88–96 % of the masked time lies inside his mic
  sentences and 57–88 % of his sentence time is masked, on every call except 20260923-130021 (54 %: a
  louder room, the mask catches non-speech there).
- **1: zeroed** — the system samples under the mask set to 0, then FluidAudio 0.15.6 offline at t0.70.
- **2: embeddings only** — today's t0.70 segments (audio kept, so segmentation and ASR unchanged), each relabelled
  with the speaker of the most-overlapping segment of the zeroed run, else the nearest in time. The zeroed frames
  are silent to the segmentation model, so their mask weight is 0 in that run's embeddings: it is the same
  clustering with the double-talk frames out of the embeddings. FluidAudio's `PreparedDiarization` does not let
  a caller mask frames directly, so this is the closest the public API gets.
- Counts go through the app's per-sentence assignment (`assigned_speakers`); `now` and `6 s rule` match
  short-reply-merge.md exactly, which checks the harness.

## Shown `them` speakers

| call | real | now (t0.70) | 6 s rule | 1: zeroed | 1: zeroed + 6 s | 2: embeddings only | 2 + 6 s |
|---|---|---|---|---|---|---|---|
| 20260925-114649 | 1 | 2 | 1 | 2 | 2 | 2 | 2 |
| 20260925-111702 | 1 | 2 | 1 | 2 | 1 | 2 | 1 |
| 20260924-173649 | 1 | 2 | 1 | 3 | 1 | 3 | 1 |
| 20260924-173310 | 1 | 2 | 1 | 2 | 1 | 2 | 1 |
| 20260924-133358 | 1 | 3 | 1 | 2 | 1 | 2 | 1 |
| 20260924-110157 | 1 | 3 | 1 | 2 | 1 | 2 | 2 |
| 20260923-125419 | 1 | 2 | 2 | 3 | 1 | 3 | 3 |
| 20260923-101613 | 1 | 3 | 1 | 3 | 1 | 3 | 3 |
| 20260922-115609 | 1 | 2 | 1 | 3 | 1 | 3 | 1 |
| 20260922-084404 | 1 | 2 | 1 | 2 | 2 | 2 | 2 |
| 20260925-125945 | 3 | 4 | 3 | 5 | 3 | 5 | 4 |
| 20260924-130017 | 4 | 4 | 2 | 4 | 2 | 4 | 2 |
| 20260923-130021 | 4 | 7 | 5 | 7 | 6 | 7 | 7 |
| 20260922-125838 | 4 | 6 | 4 | 6 | 5 | 6 | 4 |
| 20260921-125925 | 4 | 5 | 4 | 6 | 4 | 6 | 4 |
| **1:1 correct (of 10)** | | **0** | **9** | **0** | **8** | **0** | **5** |
| **dailies correct (of 5)** | | **1** | **3** | **1** | **2** | **1** | **2** |
| **total \|Δ\|** | | **20** | **4** | **23** | **7** | **23** | **13** |

- Zeroing moves the split, it does not remove it: 3 of 10 1:1 calls go from 3 to 2 speakers, 4 others from 2 to 3
  (a turn cut by a zeroed gap re-clusters as a new voice). With the 6 s rule on top, 1: zeroed is the only variant
  near today's winner and still loses 20260925-114649, 20260922-084404 and 20260923-130021 (6 vs 5).
- Variant 2 is worse with the rule (13): the relabelling spreads the zeroed run's small speakers onto long
  segments, so some short speakers now own a ≥ 6 s segment and survive the merge.
- **Benchmark** (VoxConverse ×3 + AMI ×2, system channel only): there is no mic, so the mask is empty and both
  variants are a no-op — DER and counts are those of today; nothing was run.

## Mask and speech lost

`words under zeroed frames` — system-channel words that the zeroing would silence: a sentence's words counted in
proportion to its time under the mask (the stored ASR has sentence times, not word times). Variant 1 loses them
if ASR ran on the zeroed audio; variant 2 loses none (the audio is kept).

| call | mic speech level dB | own share of call | own inside mic ASR sentences | mic ASR sentence time masked | system diarizer speech masked | system words | words under zeroed frames |
|---|---|---|---|---|---|---|---|
| 20260925-114649 | -14.2 | 57% | 96% | 86% | 16% | 252 | 47 (18.7%) |
| 20260925-111702 | -16.1 | 53% | 95% | 76% | 21% | 55 | 19 (33.7%) |
| 20260924-173649 | -25.0 | 31% | 88% | 57% | 11% | 847 | 110 (13.0%) |
| 20260924-173310 | -25.4 | 37% | 90% | 78% | 15% | 192 | 29 (15.1%) |
| 20260924-133358 | -17.5 | 34% | 88% | 72% | 5% | 433 | 27 (6.3%) |
| 20260924-110157 | -16.1 | 54% | 94% | 69% | 19% | 339 | 87 (25.8%) |
| 20260923-125419 | -15.3 | 68% | 95% | 87% | 22% | 155 | 43 (27.4%) |
| 20260923-101613 | -16.3 | 49% | 92% | 82% | 14% | 2118 | 356 (16.8%) |
| 20260922-115609 | -15.7 | 53% | 94% | 84% | 11% | 873 | 105 (12.1%) |
| 20260922-084404 | -14.6 | 49% | 93% | 84% | 12% | 1787 | 263 (14.7%) |
| 20260925-125945 | -22.1 | 27% | 92% | 83% | 3% | 3038 | 104 (3.4%) |
| 20260924-130017 | -20.9 | 22% | 89% | 81% | 2% | 3680 | 84 (2.3%) |
| 20260923-130021 | -27.1 | 29% | 54% | 88% | 16% | 6852 | 1029 (15.0%) |
| 20260922-125838 | -21.7 | 21% | 92% | 76% | 2% | 5175 | 137 (2.6%) |
| 20260921-125925 | -19.1 | 26% | 88% | 79% | 2% | 3486 | 89 (2.5%) |
| **all** | | | | | | **29282** | **2529 (8.6%)** |

On 1:1 calls the mask takes 6–34 % of the interlocutor's words, 8.6 % over all calls — a real cost for no gain.

## Caveat

The truth ([real-calls-truth.md](real-calls-truth.md)) is inferred by an LLM from transcripts, not hand-labelled;
dailies are medium or low confidence.
