# Diarizer threshold sweep (BESEDA-69, 2026-09-26)

FluidAudio 0.15.6 (the app's), embeddings computed once per file (`prepare`), then clustered at each threshold
(`cluster`). Merge variants: t0.70, then every speaker with under 2 % / 5 % of the diarizer's speech is relabeled
to the bigger speaker whose mean segment embedding is closest by cosine. Every small speaker had embeddings, so
nothing was dropped (total speech seconds are unchanged in every file). Sanity: t0.70 equals BESEDA-65's `new them`
on all 15 calls and the raw-timeline real DER 0.119 of `diarization/README.md`.

## Real calls: `them` speakers (new per-sentence assignment + echo gate)

`real_calls.sh` → `hyp/real-calls.jsonl` (`themByVariant`). Real participant counts are still unknown.

| call | now t0.70 | t0.60 | t0.80 | t0.85 | t0.70 merge <2 % | t0.70 merge <5 % |
|---|---|---|---|---|---|---|
| 20260925-125945 | 4 | 6 | 4 | 4 | 4 | 3 |
| 20260925-114649 | 2 | 3 | 2 | 2 | 2 | 2 |
| 20260925-111702 | 2 | 3 | 2 | 2 | 2 | 2 |
| 20260924-173649 | 2 | 2 | 2 | 2 | 2 | 1 |
| 20260924-173310 | 2 | 2 | 2 | 2 | 2 | 2 |
| 20260924-133358 | 3 | 2 | 2 | 2 | 3 | 1 |
| 20260924-130017 | 4 | 5 | 3 | 3 | 2 | 2 |
| 20260924-110157 | 3 | 3 | 2 | 2 | 3 | 3 |
| 20260923-130021 | 7 | 9 | 6 | 6 | 6 | 5 |
| 20260923-125419 | 2 | 3 | 2 | 1 | 2 | 2 |
| 20260923-101613 | 3 | 3 | 2 | 2 | 3 | 3 |
| 20260922-125838 | 6 | 7 | 5 | 5 | 5 | 4 |
| 20260922-115609 | 2 | 3 | 2 | 2 | 2 | 2 |
| 20260922-084404 | 2 | 3 | 2 | 2 | 2 | 2 |
| 20260921-125925 | 5 | 6 | 5 | 5 | 4 | 4 |

## Benchmark (BESEDA-6 eval set, system channel only, collar 0.25)

`RealCalls <id>.system.wav` → `hyp/sweep/`, scored by `score_sweep.py`. Real = VoxConverse ×3 + AMI ×2
(3–6 speakers, 3–6 min); synthetic = 8 FLEURS calls (2–4 speakers, 30–50 s).

| variant | DER real | speaker-count error real | DER synthetic system | speaker-count error synthetic |
|---|---|---|---|---|
| t0.60 | 0.119 | 0.60 | 0.285 | 0.75 |
| t0.70 | 0.119 | 0.60 | 0.310 | 0.88 |
| t0.80 | 0.120 | 0.60 | 0.310 | 0.75 |
| t0.85 | 0.120 | 0.60 | 0.310 | 0.75 |
| t0.70-merge2% | 0.118 | 0.80 | 0.310 | 0.88 |
| t0.70-merge5% | 0.124 | 1.00 | 0.310 | 0.88 |

Per file: merge <2 % takes `vox_azisu` 4 → 3 speakers (reference 4) and merge <5 % also `vox_gzvkx` 4 → 3
(reference 6): both merge real people. t0.80/0.85 change only `call_ru_2spk` 3 → 2 (reference 2).

## Recommendation

t0.80: one `them` speaker fewer on 6 of 15 calls (the 13:00 dailies 7 → 6, 6 → 5, 4 → 3), benchmark neutral
(real DER 0.119 → 0.120, same count error; synthetic count error 0.88 → 0.75). t0.85 adds nothing over 0.80 but
takes `20260923-125419` to one speaker. Merging by share merges real people on VoxConverse and cuts
`20260924-130017` 4 → 2. Risk of t0.80: unverified until the real participant counts arrive; the benchmark is
short and has no two similar voices, so a real quiet participant may be folded into another at 0.80 unnoticed.
The dailies still show 5–6 speakers at 0.80: the tail is not only a threshold issue.
