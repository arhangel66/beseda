# One remote speaker on known 1:1 calls (BESEDA-93, 2026-09-26)

`app_merge.sh` (now without the 6 s merge: the app's `Diarizer` + `SpeakerAssignment`, t0.70) on copies of the
15 truth calls; `6 s merge` is [app-merge.md](app-merge.md). `this` = t0.70, or 1 when the call is known 1:1.
Signal read from a read-only copy of `calls.sqlite`: no call has a calendar event linked (`participants` empty),
3 dailies carry the user type «Дейли», the rest none. Types are user-named («Другое», «Дейли» only), so no
1:1 type exists; the inferred count (BESEDA-70) is not in the app. So the rule fired on no call.

| call | real | t0.70 | 6 s merge | this | signal |
|---|---|---|---|---|---|
| 20260925-114649 | 1 | 2 | 1 | 2 | none (no event; type none) |
| 20260925-111702 | 1 | 2 | 1 | 2 | none (no event; type none) |
| 20260924-173649 | 1 | 2 | 1 | 2 | none (no event; type none) |
| 20260924-173310 | 1 | 2 | 1 | 2 | none (no event; type none) |
| 20260924-133358 | 1 | 3 | 1 | 3 | none (no event; type none) |
| 20260924-110157 | 1 | 3 | 1 | 3 | none (no event; type none) |
| 20260923-125419 | 1 | 2 | 2 | 2 | none (no event; type none) |
| 20260923-101613 | 1 | 3 | 1 | 3 | none (no event; type none) |
| 20260922-115609 | 1 | 2 | 1 | 2 | none (no event; type none) |
| 20260922-084404 | 1 | 2 | 1 | 2 | none (no event; type none) |
| 20260925-125945 | 3 | 4 | 3 | 4 | none (no event; type Дейли) |
| 20260924-130017 | 4 | 4 | 2 | 4 | none (no event; type Дейли) |
| 20260923-130021 | 4 | 7 | 5 | 7 | none (no event; type Дейли) |
| 20260922-125838 | 4 | 6 | 4 | 6 | none (no event; type none) |
| 20260921-125925 | 4 | 5 | 4 | 5 | none (no event; type none) |
| **total \|Δ\|** | | **20** | **4** | **20** | |

With a linked two-person event the 10 one-to-one calls would each show 1 (|Δ| 20 → 7, the dailies' 7 left).

## Benchmark (real part: VoxConverse ×3 + AMI ×2)

| variant | DER real | speaker-count error real |
|---|---|---|
| t0.70 | 0.119 | 0.60 |
| 6 s merge | 0.118 | 0.80 |
| this | 0.119 | 0.60 |

The benchmark has no call metadata, so no 1:1 signal: the rule lives in `CallStore` and never runs on this
path, and `SpeakerAssignment` is now plain t0.70 — equal to the t0.70 row
([threshold-sweep-benchmark.md](threshold-sweep-benchmark.md)) by construction, not rerun.

**Caveat (critic finding 15):** the real counts are inferred from transcript text by an LLM, not
hand-labelled, and counts cannot show a merge and a split that cancel out.
