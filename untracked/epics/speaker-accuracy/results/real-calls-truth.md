# Real participant count on the 15 calls of real-calls.md (BESEDA-70, 2026-09-26)

Ground truth for scoring diarizer variants (BESEDA-69). `others` = distinct people besides Mikhail, inferred from content by
claude-haiku on transcripts with the them-N labels replaced by a single `other` (so the labels could not leak), then the
13:00 dailies cross-checked by name against the team roster (Fish, Rustam, Pixel, Mohammed, Gus). Prompts, blind
transcripts and raw answers live in `truth/` (gitignored). `them` = what Beseda's new pipeline shows.

| call | min | others | who | confidence | them |
|---|---|---|---|---|---|
| 20260925-125945 | 29 | 3 | Rustam, Mohammed, Gus (Pixel away, Fish on vacation) | medium | 4 |
| 20260925-114649 | 4 | 1 | one colleague, Loki memory | high | 2 |
| 20260925-111702 | 1 | 1 | one colleague, 2FA setup | high | 2 |
| 20260924-173649 | 9 | 1 | one colleague, GPU strategy | high | 2 |
| 20260924-173310 | 3 | 1 | one colleague, NGT validation | high | 2 |
| 20260924-133358 | 5 | 1 | Gus (GTM/SEO) | high | 3 |
| 20260924-130017 | 33 | 4 | Rustam, Mohammed, Pixel, Gus (Fish absent) | medium | 4 |
| 20260924-110157 | 4 | 1 | one colleague, NGT/Sysbox | high | 3 |
| 20260923-130021 | 51 | 4 | Pixel, Mohammed, Rustam, Gus (Fish absent) | medium | 7 |
| 20260923-125419 | 5 | 1 | one colleague, pricing | high | 2 |
| 20260923-101613 | 26 | 1 | one colleague, PRs/docs | high | 3 |
| 20260922-125838 | 48 | 4 | Fish, Gus, Rustam + one more (Pixel or Mohammed) | low | 6 |
| 20260922-115609 | 13 | 1 | one colleague, pricing epic | high | 2 |
| 20260922-084404 | 23 | 1 | one colleague, WatchTower/rentals | high | 2 |
| 20260921-125925 | 31 | 4 | Fish, Pixel, Rustam + one more | medium | 5 |

Every 1-on-1 call is over-split by exactly one speaker or more; the 13:00 dailies are close except 20260923-130021 (7 vs 4).
