# Short-reply merge rule: which variant goes into the app (BESEDA-82, 2026-09-26)

Research only, no app code. Follows [extra-speaker-cause.md](extra-speaker-cause.md) (BESEDA-79): the extra
`them` speaker on 1:1 calls is the interlocutor's short replies, so a speaker whose **longest diarizer segment**
is short gets relabelled to a kept speaker. Dumps were redone (BESEDA-79's `hyp/extra/` did not survive its
worktree): `extra_speakers.sh` now stores both the t0.70 (`system`) and t0.80 (`system80`) clusterings of the
same embeddings; t0.70 counts match BESEDA-79 exactly. `short_reply_merge.py` replays the app's per-sentence
assignment (`SentenceSpeakerAssignment`) on each merged timeline, so sentences with no diarizer speech under
them go to the nearest segment, which after the merge is always a kept speaker. Data rules: call copies, one
at a time, `nice -n 19`, memory wait (free ≥ 20 %), no audio out, no cloud.

Truth: [real-calls-truth.md](real-calls-truth.md). Benchmark: the real part of BESEDA-6 (VoxConverse ×3 +
AMI ×2, system channel). **The synthetic FLEURS calls are excluded**: they are cut into 1–6 s turns by
construction, so every speaker there is "short" and they cannot judge a segment-length rule.

## Winner

**After clustering at t0.70 (unchanged), every `them` speaker whose longest diarizer segment is under 6 s is
not a speaker: each of its segments takes the speaker of the nearest-in-time segment of a kept speaker
(distance = gap between segments, 0 when they touch). If no speaker has a segment ≥ 6 s, the one with the most
diarizer seconds is kept. Then `SentenceSpeakerAssignment` as today.**

- Total |Δ| 20 → 4, all 5 dailies fixed or no worse, 9 of 10 1:1 calls exact, no real person glued anywhere.
- Why 6 s and not 7 s: at 7 s 20260925-125945 loses a real person. Its S4 (64 s, longest turn 6.6 s) is a
  distinct voice by the transcript: "do you mind if I go now? I need to jump on a meeting… meeting a guy with
  a data center" — the sales colleague, not a reply of someone else. 7 s fixes one more 1:1 call
  (20260923-125419, extra with one 6.2 s turn) but glues a person; the task says not to glue.
- 6.5 s scores best (|Δ| 3, 10/10) but sits between 6.2 and 6.6 s — fitted to two turns, not recommended.
- Merge target: nearest in time and closest mean embedding give identical counts on every call and file;
  time is simpler (no centroids) and per segment, so it is the one.
- t0.80: no gain on top of the merge (|Δ| 4–5, same 1:1), so the threshold stays 0.70.
- "short AND cosine to target ≥ c": does not save 20260924-130017 — its two short speakers sit at cos 0.11 /
  0.12, the same range as the 1:1 extras (0.03–0.41) — and loses 1:1 calls fast (7 / 4 / 2 of 10 at c
  0.1 / 0.2 / 0.3). Rejected.
- FluidAudio 0.17.4 (newest release; the app has 0.15.6), same offline pyannote/WeSpeaker/VBx models:
  identical counts and DER, the rule behaves the same on it. No reason to bump for this. Sortformer / LS-EEND
  not run: Sortformer's model is a 4-speaker one (dailies have 4 + Mikhail's echo), neither was ever measured
  on the benchmark (BESEDA-15 cut them short), so they are a separate study, not one row.

## 20260924-130017: is 4 → 2 a loss?

No, not caused by the merge. Local transcript (`them.asr.json` copy) around the two small speakers:

- S3 (13 s, 4 sentences) always continues S4 mid-thought: S4 "…and what we can improve." → S3 "So I will
  probably come up with some improvements based on this."; S4 "…you can have fish agent just." → S3 "uh just
  review that as well". It is S4's short replies.
- S2 (18 s, 8 sentences) opens or closes S1's turns: S2 "I can explain that in a few simple words." → S1 "I
  just use my bulk skills…"; S2 "I mean, I again I fully agree with you." → S1 "I'm just… working with one
  hand tied behind my back"; S2 "Yeah, from my perspective." → S1 "Yesterday was launched…". It is S1's.

So the diarizer has only two long-turn voices on this call at t0.70; the other two real people (truth: 4,
medium confidence) are already inside S1/S4 before any merge. The 2 there is a clustering limit, not a merge
loss (FluidAudio 0.17.4 finds 5 clusters, but after assignment still shows 4 → 2 with the rule).

## Real calls: shown `them` speakers

`real` from the truth file; variants are `<longest segment limit>, <merge target>, <threshold>`.

| call | real | now t0.70 | now t0.80 | <6 s, time, t0.70 | <7 s, time, t0.70 | <6 s, time, t0.80 | <7 s, time, t0.80 | <6.5 s, time, t0.70 | <6 s, embedding, t0.70 | <7 s, embedding, t0.70 | <6 s, embedding, t0.80 | <7 s, embedding, t0.80 | <7 s + cos ≥ 0.1, time, t0.70 | <7 s + cos ≥ 0.2, time, t0.70 | <7 s + cos ≥ 0.3, time, t0.70 | 0.17.4 t0.70 | 0.17.4 t0.70 <6 s, time |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 20260925-114649 | 1 | 2 | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 1 |
| 20260925-111702 | 1 | 2 | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 1 |
| 20260924-173649 | 1 | 2 | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 2 | 1 |
| 20260924-173310 | 1 | 2 | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 1 |
| 20260924-133358 | 1 | 3 | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 2 | 3 | 1 |
| 20260924-110157 | 1 | 3 | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 2 | 3 | 1 |
| 20260923-125419 | 1 | 2 | 2 | 2 | 1 | 2 | 1 | 1 | 2 | 1 | 2 | 1 | 1 | 1 | 1 | 2 | 2 |
| 20260923-101613 | 1 | 3 | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 3 | 3 | 1 |
| 20260922-115609 | 1 | 2 | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 2 | 1 |
| 20260922-084404 | 1 | 2 | 2 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 1 | 2 | 2 | 2 | 1 |
| 20260925-125945 | 3 | 4 | 4 | 3 | 2 | 3 | 2 | 3 | 3 | 2 | 3 | 2 | 2 | 3 | 3 | 4 | 3 |
| 20260924-130017 | 4 | 4 | 3 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 2 | 4 | 4 | 4 | 2 |
| 20260923-130021 | 4 | 7 | 6 | 5 | 5 | 6 | 5 | 5 | 5 | 5 | 6 | 5 | 5 | 5 | 6 | 7 | 5 |
| 20260922-125838 | 4 | 6 | 5 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 5 | 6 | 6 | 4 |
| 20260921-125925 | 4 | 5 | 5 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 4 | 5 | 5 | 5 | 4 |
| **total \|Δ\|** | | **20** | **16** | **4** | **4** | **5** | **4** | **3** | **4** | **4** | **5** | **4** | **7** | **9** | **14** | **20** | **4** |

## Benchmark (real part, system channel)

DER with a 0.25 s collar; "real people glued" = reference speakers whose own biggest diarizer speaker ended up
merged with another reference speaker's. vox_azisu 4 → 3 in every merge row is its 2 s split of spk03 folding
back (the count error rises only because that split had made the count accidentally right).


| variant | DER real | speaker-count error real | real people glued | per file: shown / real |
|---|---|---|---|---|
| now t0.70 | 0.119 | 0.60 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 4/4, vox_gzvkx 4/6 |
| now t0.80 | 0.120 | 0.60 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 4/4, vox_gzvkx 4/6 |
| <6 s, time, t0.70 | 0.118 | 0.80 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 3/4, vox_gzvkx 4/6 |
| <7 s, time, t0.70 | 0.118 | 0.80 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 3/4, vox_gzvkx 4/6 |
| <6 s, time, t0.80 | 0.119 | 0.80 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 3/4, vox_gzvkx 4/6 |
| <7 s, time, t0.80 | 0.119 | 0.80 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 3/4, vox_gzvkx 4/6 |
| <6.5 s, time, t0.70 | 0.118 | 0.80 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 3/4, vox_gzvkx 4/6 |
| <6 s, embedding, t0.70 | 0.118 | 0.80 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 3/4, vox_gzvkx 4/6 |
| <7 s, embedding, t0.70 | 0.118 | 0.80 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 3/4, vox_gzvkx 4/6 |
| <6 s, embedding, t0.80 | 0.119 | 0.80 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 3/4, vox_gzvkx 4/6 |
| <7 s, embedding, t0.80 | 0.119 | 0.80 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 3/4, vox_gzvkx 4/6 |
| <7 s + cos ≥ 0.1, time, t0.70 | 0.118 | 0.80 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 3/4, vox_gzvkx 4/6 |
| <7 s + cos ≥ 0.2, time, t0.70 | 0.119 | 0.60 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 4/4, vox_gzvkx 4/6 |
| <7 s + cos ≥ 0.3, time, t0.70 | 0.119 | 0.60 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 4/4, vox_gzvkx 4/6 |
| 0.17.4 t0.70 | 0.119 | 0.60 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 4/4, vox_gzvkx 4/6 |
| 0.17.4 t0.70 <6 s, time | 0.118 | 0.80 | 0 | ami_ES2004a 3/4, ami_IS1009a 4/4, vox_asxwr 3/3, vox_azisu 3/4, vox_gzvkx 4/6 |

## Every short speaker (longest segment < 7 s, t0.70)

`–` = no speaker of the call has a 7 s segment, so the biggest one is kept.

| call or file | short speaker | longest s | seconds | best kept by cosine | cos | nearest-in-time target of most seconds |
|---|---|---|---|---|---|---|
| 20260925-114649 | S2 | 2.9 | 11 | S1 | 0.29 | S1 |
| 20260925-111702 | S1 | 2.8 | 10 | – | nan | S2 |
| 20260925-111702 | S2 | 5.2 | 11 | – | nan | S2 |
| 20260924-173649 | S2 | 3.2 | 14 | S1 | 0.12 | S1 |
| 20260924-173310 | S1 | 5.7 | 19 | S2 | 0.22 | S2 |
| 20260924-133358 | S2 | 4.3 | 4 | S1 | 0.41 | S1 |
| 20260924-133358 | S3 | 2.6 | 5 | S1 | 0.08 | S1 |
| 20260924-110157 | S1 | 3.5 | 12 | S2 | 0.09 | S2 |
| 20260924-110157 | S3 | 3.0 | 15 | S2 | 0.41 | S2 |
| 20260923-125419 | S1 | 6.2 | 24 | – | nan | S2 |
| 20260923-125419 | S2 | 6.5 | 44 | – | nan | S2 |
| 20260923-101613 | S1 | 3.6 | 45 | S3 | 0.03 | S3 |
| 20260923-101613 | S2 | 4.0 | 36 | S3 | 0.29 | S3 |
| 20260922-115609 | S1 | 3.2 | 30 | S2 | 0.18 | S2 |
| 20260922-084404 | S2 | 5.6 | 52 | S1 | 0.15 | S1 |
| 20260925-125945 | S1 | 5.5 | 42 | S2 | 0.13 | S2 |
| 20260925-125945 | S4 | 6.6 | 64 | S2 | 0.33 | S2 |
| 20260924-130017 | S2 | 2.5 | 18 | S1 | 0.12 | S1 |
| 20260924-130017 | S3 | 2.4 | 13 | S1 | 0.11 | S4 |
| 20260923-130021 | S1 | 4.0 | 53 | S5 | 0.22 | S3 |
| 20260923-130021 | S2 | 6.0 | 37 | S7 | 0.58 | S7 |
| 20260922-125838 | S1 | 4.2 | 45 | S2 | 0.12 | S3 |
| 20260922-125838 | S5 | 4.4 | 15 | S2 | 0.25 | S3 |
| 20260921-125925 | S1 | 4.0 | 20 | S5 | 0.14 | S5 |
| 20260921-125925 | S3 | 2.3 | 2 | S5 | 0.04 | S2 |
| bench_vox_azisu | S4 | 2.0 | 2 | S1 | 0.18 | S1 |

## Rerun

```
untracked/epics/speaker-accuracy/extra_speakers.sh   # hyp/extra/*.json, t0.70 + t0.80, ~15 s per call
cd untracked/epics/speaker-accuracy && uv run short_reply_merge.py
```

The FluidAudio 0.17.4 row: `diarization/.build/release/Diarize` with `VARIANTS=offline-t0.7`, `AUDIO_DIR` = a
temp dir holding one copied `them.asr.wav` as `<call>.system.wav`, `OUTPUT_DIR` = a temp dir; the JSONs go to
`hyp/fluid0174/<call>.json` and `hyp/fluid0174/bench_<id>.json`.
