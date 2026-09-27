# Speaker count from existing embeddings (BESEDA-114, 2026-09-27)

Research only, no app change. Question: can better clustering of the embeddings the diarizer already computes
(FluidAudio 0.15.6 offline, WeSpeaker, no new model) get the number of people right — 1 on 1:1 calls, 3–4 on
dailies — without gluing real people on the benchmark?

**Answer: no variant works.** Every setting picked on the benchmark leaves at least 7 of 10 one-to-one calls
over-split. The only thing that fixes all ten is a "one speaker or more" bar picked by looking at these calls,
and the synthetic calls show it glues 2- and 4-person calls. Details below.

## How it was measured

- `embedding_clustering.sh`: `RealCalls <call or wav> chunks` on copies of `them.asr.wav` of the 15 truth calls
  and on every benchmark system channel, one at a time under `lockf /tmp/beseda-speaker-accuracy.lock`,
  `nice -n 19`, memory wait (free ≥ 20 %). It writes `hyp/chunks/*.json` (gitignored; no audio, no text): the
  t0.70 timeline, the **raw per-window embeddings** (`exposeChunkEmbeddings`, one per 10 s window × local
  speaker) and the timelines of FluidAudio's own knobs.
- **Correction to BESEDA-79/82:** the `embedding` a FluidAudio segment carries is its **cluster centroid**,
  the same vector on every segment of a speaker (`OfflineReconstruction.appendSegment`). So the old "segment
  embeddings" in `hyp/extra/` were per-speaker means, not per segment. This task re-clusters the real per-window
  vectors instead.
- `embedding_clustering.py`: re-clusters those windows, turns the new labels back into a timeline (each diarizer
  segment takes the new label with most overlap among its own speaker's windows), and counts `them` on the calls
  through the app's per-sentence assignment (`extra_speakers.assigned_speakers`), as BESEDA-82 did.
- One global setting per variant, **picked on the benchmark only** (VoxConverse ×3 + AMI ×2, system channel):
  glues no more people than today, then the lowest speaker-count error, then the lowest DER; on a tie the more
  merging setting. Then applied unchanged to the calls.
- "Glued" = reference speakers whose most-overlapping hypothesis speaker is also another reference speaker's.
  Today's pipeline already scores 4 here (ES2004a 3 of 4 shown, gzvkx 4 of 6), so "no worse" means ≤ 4.
- Speed: Python time per call on top of the diarizer, median of the 15 calls; every variant except the knobs
  reuses embeddings already computed, so it adds milliseconds. `minEmbed` knobs re-run the models (one more
  full diarization); the other knobs re-run only clustering.

## Result

Truth: [real-calls-truth.md](real-calls-truth.md) — 10 one-to-one calls with 1 other person, 5 dailies with
3–4. **Caveat: that truth is a count inferred by an LLM from the transcript text, not hand-labelled audio.**

| approach (setting picked on the benchmark) | 1:1 correct (of 10) | dailies correct (of 5) | total \|Δ\| (15 calls) | benchmark DER | count error | glued | speed, ms/call |
|---|---|---|---|---|---|---|---|
| now: FluidAudio 0.15.6 t0.70 | 0 | 1 | 20 | 0.119 | 0.60 | 4 | — |
| 1. long-only ≥ 1.5 s, AHC avg cos-dist 0.80, short → nearest centroid | 3 | 2 | 12 | 0.127 | 0.60 | 4 | 16 |
| 1. long-only ≥ 2 s, same | 3 | 2 | 12 | 0.127 | 0.60 | 4 | 8 |
| 1. long-only ≥ 3 s, AHC avg cos-dist 0.60 | 4 | 0 | 15 | **0.113** | 0.60 | 3 | 13 |
| 2. eigengap + spectral (one speaker if mean cos ≥ 0.8) | 1 | 0 | 45 | 0.250 | 1.40 | 4 | 63 |
| 3. VBx Fa 0.2 / 0.5 | 0 / 0 | 1 / 1 | 34 / 64 | 0.121 / 0.138 | 1.20 / 2.60 | 3 / 3 | clustering only |
| 3. VBx Fb 0.4 / 2 / 5 | 0 / 0 / 1 | 1 / 0 / 1 | 26 / 18 / 15 | 0.116 / 0.194 / 0.292 | 0.60 / 1.80 / 2.40 | 3 / **9** / **12** | clustering only |
| 3. VBx 1 iteration | 0 | 1 | 43 | 0.134 | 2.40 | 3 | clustering only |
| 3. min embedded span 2 s / 3 s | 0 / 2 | 1 / 0 | 21 / 20 | 0.131 / 0.154 | 0.60 / 0.80 | 4 / 4 | one more diarization |
| 4. AHC average on speaker means, cos-dist 0.55 | 2 | 0 | 14 | 0.119 | 0.60 | 4 | 1 |
| 4. AHC complete on speaker means, cos-dist 0.55 | 2 | 0 | 14 | 0.119 | 0.60 | 4 | 1 |
| *fitted, not a fix:* one speaker if mean cos ≥ 0.65, else now | 10 | 1 | 7 | 0.119 | 0.60 | 4 | 1 |
| *fitted, not a fix:* one speaker if mean cos ≥ 0.65, else long-only ≥ 3 s | 10 | 0 | 9 | 0.113 | 0.60 | 3 | 1 |

Per call counts, every benchmark setting of the sweep and the raw numbers: rerun `uv run embedding_clustering.py`
(prints all three tables in ~25 s once `hyp/chunks/` exists).

## Per variant

1. **Long segments only.** Clustering windows from segments ≥ N s and snapping the rest to the nearest centroid
   helps a little (best: 3–4 of 10 1:1, |Δ| 12–15) but leaves most 1:1 calls at 2 and breaks the dailies
   (20260924-130017 4 → 2, 20260923-130021 stays 7–8). The benchmark picks cos-dist 0.80 for N 1.5/2 s right
   before a cliff: at 0.85 it glues 9 people. N = 3 s is the only setting that improves the benchmark DER
   (0.119 → 0.113) — worth knowing, but not a count fix.
2. **Eigengap + spectral.** Fails. On the short 1:1 calls (27–97 windows) the largest eigengap sits at k 6–9,
   so it shows 6–9 people; on the benchmark it doubles DER. The single-speaker bar on top does not rescue it.
3. **FluidAudio knobs** (0.15.6 exposes Fa, Fb, VBx iterations, min embedded span, min duration on/off; 0.17.4
   adds nothing for this — same models and clustering, BESEDA-82). Fa up and fewer VBx iterations split more.
   Fb up merges, but glues real people first (Fb 2: 9 glued, Fb 5: 12) and still leaves 9 of 10 1:1 calls at 2.
   A 3 s minimum embedded span fixes 2 of 10 and costs DER 0.154. None is usable.
4. **AHC on speaker means.** Any cut under 0.55 changes nothing on the benchmark; 0.55 is the most merging cut
   that glues nobody new, and it fixes 2 of 10 (20260925-111702, 20260923-125419) while taking 20260924-130017
   from 4 to 3. The extras sit too far from their main speaker (as BESEDA-79 found with centroids).

## One speaker or more: the bar that only works on these calls

Mean cosine of every window to the call's overall centroid (a "how much of one voice is this" number):

| set | mean cos to centroid |
|---|---|
| 10 one-to-one calls (1 other person) | **0.668 – 0.806** |
| 5 dailies (3–4 people) | 0.455 – 0.639 |
| real benchmark (3–6 people) | 0.562 – 0.641 |
| synthetic FLEURS calls, 2 people | 0.616, **0.653** |
| synthetic FLEURS calls, 3–4 people | 0.563 – 0.645, **0.671** (call_ru_4spk) |

A bar at 0.65 turns all ten 1:1 calls into 1 (|Δ| 20 → 7) and changes nothing on the benchmark. But it is
**fitted to these 15 calls**: the benchmark has no one-speaker file, so it cannot place the bar; the gap between
the lowest 1:1 call (0.668) and the highest multi-person daily (20260924-130017, 0.639) is 0.03; and two of the
eight synthetic calls — a 2-person one (0.653) and a 4-person one (0.671) — land above the bar and would be shown
as one person. The synthetic calls are short (15–31 windows) and codec-degraded, so they are a rough check,
but they are the only multi-speaker data at that length and they already overlap the 1:1 range. A 2-person 1:1
with two similar voices is exactly what this bar would glue, so it is not a safe default.

## Verdict

None of the four works: nothing picked on the benchmark gets more than 4 of 10 one-to-one calls right, and the
settings that merge more glue real people on the benchmark first. The per-window WeSpeaker embeddings of short
replies are simply not close enough to the same person's long turns for any global clustering setting to pull
them together without also pulling different people together. The single-speaker bar is the one strong signal
(1:1 calls are the most uniform of everything measured), but its margin is 0.03 on real calls and negative on
synthetic ones — fitted, not a fix. By-product: long-only ≥ 3 s lowers benchmark DER 0.119 → 0.113 without
gluing, if DER alone is ever the goal.
