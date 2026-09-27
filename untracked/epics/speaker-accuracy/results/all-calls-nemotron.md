# Nemotron-3 on all of Mikhail's calls (BESEDA-151, 2026-09-27)

`them` speakers on every call that still has `them.asr.wav` + `them.asr.json`: stored now (`Было 0.4.0`: the distinct non-`me` labels in `transcript_segments`, as whichever pre-Nemotron build processed the call left them; `calls.diarizer` is empty on all 123) against Nemotron-3 offline (`all_calls.sh`, the same FluidAudio 0.17.4 preset and weights as `Diarizer.swift`) with the app's per-sentence assignment (`SpeakerAssignment.remoteTurns`, no 6 s rule). The echo gate only trims the mic side, so it does not change the `them` count. Copies only: the store copy and `cp -c` clones, one call at a time.

Real count (`Людей по смыслу`) = people besides Mikhail, read by claude-haiku from the transcript with every remote label replaced by one `other` (prompts and answers in `truth/`, gitignored); the 15 calls of [real-calls-truth.md](real-calls-truth.md) are reused. An LLM reading, not hand labels.

## Calls (123): 70 with audio, 53 without

| reason no audio | calls | ids |
|---|---|---|
| retention (30 d) deleted the audio | 47 | 20260510-191935 20260514-111058 20260515-111126 20260518-110627 20260519-111108 20260520-105926 20260521-110317 20260525-105936 20260527-110059 20260528-110107 20260601-154105 20260602-110021 20260603-130522 20260608-120352 20260610-121020 20260611-120127 20260615-115624 20260616-121650 20260618-120943 20260619-120110 20260622-065841 20260622-120513 20260623-121503 20260624-115939 20260625-123254 20260626-121302 20260629-123646 20260630-093515 20260701-115849 20260702-122244 20260703-120933 20260707-140928 20260708-140834 20260709-141212 20260710-141143 20260713-140005 20260714-141820 20260715-140740 20260716-141012 20260717-141746 20260720-140835 20260727-140647 20260807-210002 20260810-140353 20260817-144708 20260818-190406 20260819-183146 |
| failed: No microphone frames captured | 3 | 20260511-143539 20260513-114225 20260513-114232 |
| mic-only | 1 | 20260511-143601 |
| failed: Interrupted before the app restarted | 1 | 20260514-110031 |
| failed: Missing audio file: me.asr.wav | 1 | 20260906-005056 |

## Summary: calls where the shown count is right

| calls | n | exact 0.4.0 | exact Nemotron | ±1 0.4.0 | ±1 Nemotron |
|---|---|---|---|---|---|
| all | 70 | 12 | 51 | 31 | 64 |
| all, high confidence | 53 | 9 | 44 | 22 | 50 |
| 1:1 | 44 | 5 | 40 | 16 | 43 |
| 1:1, high confidence | 44 | 5 | 40 | 16 | 43 |
| multi-person | 23 | 4 | 8 | 12 | 18 |
| multi-person, high confidence | 6 | 1 | 1 | 3 | 4 |
| nobody else spoke (0) | 3 | 3 | 3 | 3 | 3 |
| nobody else spoke (0), high confidence | 3 | 3 | 3 | 3 | 3 |

## Manual merges

Calls with `call_speaker_merges` rows (a rerun would drop them): none — the store (schema v3, app 0.4.0) has no `call_speaker_merges` table yet.

## Per call

| Звонок | Длит. | Людей по смыслу | Уверенность | Было 0.4.0 | Nemotron | merges? |
|---|---|---|---|---|---|---|
| 20260829-182231 2026-08-29 18:22 · Chrome / Google Meet | 1 мин | 0 (only Mikhail speaking, no other participants) | high | 0 | 0 | — |
| 20260829-183056 2026-08-29 18:30 · Chrome / Google Meet | 1 мин | 0 (only Mikhail speaking, no other participants) | high | 0 | 0 | — |
| 20260829-194123 2026-08-29 19:41 · Team Sync — Weekly Updates & Issues · Файл | 27 мин | 7 (team standup: unnamed speaker, Rustam, Pixel, Mohammed, Worris, and others) | high | 6 | 5 | — |
| 20260830-085825 2026-08-30 08:58 · Chrome / Google Meet | 0 мин | 0 (only Mikhail speaking, no other participants) | high | 0 | 0 | — |
| 20260831-133718 2026-08-31 13:37 · Discord | 6 мин | 1 (one colleague discussing code review) | high | 2 | 1 | — |
| 20260831-162934 2026-08-31 16:29 · Discord | 1 мин | 2 (two colleagues, call opening with greetings and discussion about Pixel not joining) | medium | 2 | 1 | — |
| 20260831-163124 2026-08-31 16:31 · Discord | 32 мин | 2 (Rustam and Mohammed) | high | 4 | 3 | — |
| 20260901-152455 2026-09-01 15:24 · Discord | 20 мин | 1 (Rustam) | high | 3 | 1 | — |
| 20260901-163019 2026-09-01 16:30 · Discord | 27 мин | 3 (Pixel, Mohammed, and another technical colleague) | medium | 6 | 4 | — |
| 20260901-170132 2026-09-01 17:01 · Discord | 31 мин | 1 (Mohammed) | high | 3 | 1 | — |
| 20260902-104148 2026-09-02 10:41 · Discord | 27 мин | 1 (Rustam) | high | 3 | 1 | — |
| 20260902-162922 2026-09-02 16:29 · Discord | 42 мин | 4 (Rustam, Pixel, Mohammed, and infrastructure engineer) | medium | 6 | 3 | — |
| 20260902-172613 2026-09-02 17:26 · Discord | 13 мин | 1 (senior team member) | high | 3 | 1 | — |
| 20260902-174018 2026-09-02 17:40 · Discord | 58 мин | 1 (incident response technical lead) | high | 5 | 2 | — |
| 20260902-191439 2026-09-02 19:14 · Discord | 10 мин | 1 (colleague discussing security issues) | high | 3 | 1 | — |
| 20260903-102211 2026-09-03 10:22 · Discord | 33 мин | 1 (engineer discussing deployments and cluster strategy) | high | 3 | 1 | — |
| 20260903-152457 2026-09-03 15:24 · Discord | 27 мин | 1 (developer discussing validation and node accessibility rules) | high | 3 | 1 | — |
| 20260903-163014 2026-09-03 16:30 · Discord | 15 мин | 2 (Pixel and Rustam) | high | 6 | 3 | — |
| 20260903-171604 2026-09-03 17:16 · Discord | 15 мин | 1 (engineer discussing speed test implementation and CDN performance) | high | 3 | 1 | — |
| 20260904-131651 2026-09-04 13:16 · Discord | 20 мин | 1 (engineer reviewing deployment logs and discussing monorepo migration) | high | 3 | 1 | — |
| 20260904-162917 2026-09-04 16:29 · Discord | 36 мин | 3 (unknown colleague, Rustam, Pixel) | medium | 6 | 3 | — |
| 20260907-112222 2026-09-07 11:22 · Discord | 9 мин | 1 (Rustam) | high | 3 | 1 | — |
| 20260907-113243 2026-09-07 11:32 · Telegram | 1 мин | 1 (one person, airport pickup) | high | 1 | 1 | — |
| 20260907-113738 2026-09-07 11:37 · Discord | 15 мин | 1 (one colleague, Lium loop discussion) | high | 3 | 1 | — |
| 20260907-115707 2026-09-07 11:57 · Discord | 1 мин | 1 (one person, adding Pixel to call) | high | 1 | 1 | — |
| 20260907-115855 2026-09-07 11:58 · Discord | 17 мин | 1 (Pixel) | high | 4 | 2 | — |
| 20260907-172950 2026-09-07 17:29 · Discord | 39 мин | 5 (Rustam, Fish, Pixel, Mohammed, and one unidentified team member) | medium | 6 | 4 | — |
| 20260908-141102 2026-09-08 14:11 · Discord | 9 мин | 1 (one colleague, infrastructure/model deployment questions) | high | 4 | 1 | — |
| 20260908-172941 2026-09-08 17:29 · Discord | 1 мин | 1 (one colleague, technical support) | high | 1 | 1 | — |
| 20260908-173122 2026-09-08 17:31 · Discord | 49 мин | 4 (Mohammed, Pixel, Rustam, Fish) | medium | 7 | 5 | — |
| 20260909-153215 2026-09-09 15:32 · Discord | 9 мин | 3 (Mohammed, and two other team members) | medium | 3 | 1 | — |
| 20260909-172927 2026-09-09 17:29 · Discord | 41 мин | 1 (one colleague, technical discussion) | high | 6 | 3 | — |
| 20260910-152202 2026-09-10 15:22 · Discord | 19 мин | 1 (one colleague, platform issues) | high | 3 | 1 | — |
| 20260910-164430 2026-09-10 16:44 · Discord | 1 мин | 1 (one colleague, database migration issue) | high | 3 | 1 | — |
| 20260910-170325 2026-09-10 17:03 · Discord | 5 мин | 1 (one colleague, database technical discussion) | high | 3 | 1 | — |
| 20260910-172925 2026-09-10 17:29 · Discord | 39 мин | 3 (Rustam, Fish, Pixel) | medium | 6 | 3 | — |
| 20260911-085057 2026-09-11 08:50 · Discord | 8 мин | 1 (one colleague, discussing agent technology) | high | 3 | 1 | — |
| 20260911-104722 2026-09-11 10:47 · Discord | 22 мин | 1 (one colleague, technical discussion about release strategy) | high | 3 | 1 | — |
| 20260911-172926 2026-09-11 17:29 · Discord | 20 мин | 2 (Rustam, Fish) | medium | 3 | 2 | — |
| 20260911-175954 2026-09-11 17:59 · Discord | 5 мин | 1 (one colleague, mining operations issue) | high | 2 | 1 | — |
| 20260911-185047 2026-09-11 18:50 · Discord | 15 мин | 1 (one colleague, penalty and executor issue discussion) | high | 3 | 1 | — |
| 20260911-195447 2026-09-11 19:54 · Discord | 8 мин | 1 (one colleague, Dolphin mining and PR automation) | high | 2 | 1 | — |
| 20260914-104710 2026-09-14 10:47 · Discord | 24 мин | 1 (one colleague, discussing penalties) | high | 2 | 1 | — |
| 20260914-172915 2026-09-14 17:29 · Discord | 36 мин | 4 (Muhammad, Pixel, and team members) | high | 5 | 4 | — |
| 20260915-173345 2026-09-15 17:33 · Discord | 29 мин | 4 (Rustam, Pixel, Mohammed, colleagues) | high | 4 | 3 | — |
| 20260916-103221 2026-09-16 10:32 · Discord | 15 мин | 1 (team member, pull request discussion) | high | 3 | 1 | — |
| 20260916-140855 2026-09-16 14:08 · Discord | 14 мин | 1 (colleague, GPU validation discussion) | high | 3 | 1 | — |
| 20260916-143349 2026-09-16 14:33 · Discord | 9 мин | 2 (colleagues, B300 GPU provider discussion) | medium | 3 | 1 | — |
| 20260916-172818 2026-09-16 17:28 · Discord | 32 мин | 5 (Rustam, Pixel, Mohammed, others) | high | 3 | 2 | — |
| 20260917-105422 2026-09-17 10:54 · Discord | 1 мин | 1 (one colleague, security incident) | high | 1 | 1 | — |
| 20260917-122809 2026-09-17 12:28 · Discord | 17 мин | 1 (one colleague, team management discussion) | high | 3 | 1 | — |
| 20260917-125931 2026-09-17 12:59 · Discord | 29 мин | 3 (Rustam, Pixel, others team standup) | medium | 4 | 3 | — |
| 20260917-164259 2026-09-17 16:42 · Telegram | 0 мин | 1 (one colleague with Valeria) | high | 1 | 2 | — |
| 20260918-121954 2026-09-18 12:19 · Discord | 17 мин | 1 (one colleague, GPU capacity discussion) | high | 3 | 1 | — |
| 20260918-125857 2026-09-18 12:58 · Discord | 57 мин | 4 (Rustam, Pixel, Muhammad, and team standup) | medium | 6 | 4 | — |
| 20260921-125925 2026-09-21 12:59 · Discord | 31 мин | 4 (Fish, Pixel, Rustam + one more) | medium | 5 | 5 | — |
| 20260922-084404 2026-09-22 08:44 · Discord | 23 мин | 1 (one colleague, WatchTower/rentals) | high | 2 | 1 | — |
| 20260922-115609 2026-09-22 11:56 · Discord | 13 мин | 1 (one colleague, pricing epic) | high | 2 | 1 | — |
| 20260922-125838 2026-09-22 12:58 · Discord | 48 мин | 4 (Fish, Gus, Rustam + one more (Pixel or Mohammed)) | low | 6 | 4 | — |
| 20260923-101613 2026-09-23 10:16 · Discord | 26 мин | 1 (one colleague, PRs/docs) | high | 3 | 1 | — |
| 20260923-125419 2026-09-23 12:54 · Discord | 5 мин | 1 (one colleague, pricing) | high | 2 | 1 | — |
| 20260923-130021 2026-09-23 13:00 · Discord | 51 мин | 4 (Pixel, Mohammed, Rustam, Gus (Fish absent)) | medium | 7 | 6 | — |
| 20260924-110157 2026-09-24 11:01 · Discord | 4 мин | 1 (one colleague, NGT/Sysbox) | high | 3 | 1 | — |
| 20260924-130017 2026-09-24 13:00 · Discord | 33 мин | 4 (Rustam, Mohammed, Pixel, Gus (Fish absent)) | medium | 4 | 2 | — |
| 20260924-133358 2026-09-24 13:33 | 5 мин | 1 (Gus (GTM/SEO)) | high | 3 | 1 | — |
| 20260924-173310 2026-09-24 17:33 · Discord | 3 мин | 1 (one colleague, NGT validation) | high | 2 | 1 | — |
| 20260924-173649 2026-09-24 17:36 · Discord | 9 мин | 1 (one colleague, GPU strategy) | high | 2 | 1 | — |
| 20260925-111702 2026-09-25 11:17 · Discord | 1 мин | 1 (one colleague, 2FA setup) | high | 2 | 1 | — |
| 20260925-114649 2026-09-25 11:46 · Discord | 4 мин | 1 (one colleague, Loki memory) | high | 2 | 1 | — |
| 20260925-125945 2026-09-25 12:59 · Discord | 29 мин | 3 (Rustam, Mohammed, Gus (Pixel away, Fish on vacation)) | medium | 4 | 3 | — |
