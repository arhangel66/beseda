# Speaker counts on Mikhail's real calls (BESEDA-65, 2026-09-26)

`real_calls.sh` → `baseline/Sources/RealCalls`: one diarizer run per call (FluidAudio 0.15.6, t=0.70), the call's stored ASR,
old = 0.3.5 per-word labels without echo gate, new = native-ui HEAD per-sentence labels + echo gate. Counts only, no text.
Real participant count: no call has calendar attendees stored (`participants` is empty everywhere), so all are `?`.

## Measured (most recent first)

| call | min | app | real | old them+me | new them+me | diarizer | new them-N seconds |
|---|---|---|---|---|---|---|---|
| 20260925-125945 | 29 | Discord | ? | 4+1 | 4+1 | 4 | [524, 479, 90, 79] |
| 20260925-114649 | 4 | Discord | ? | 2+1 | 2+1 | 2 | [92, 34] |
| 20260925-111702 | 1 | Discord | ? | 2+1 | 2+1 | 2 | [19, 11] |
| 20260924-173649 | 9 | Discord | ? | 2+1 | 2+1 | 2 | [365, 18] |
| 20260924-173310 | 3 | Discord | ? | 2+1 | 2+1 | 2 | [57, 36] |
| 20260924-133358 | 5 |  | ? | 3+1 | 3+1 | 3 | [150, 9, 3] |
| 20260924-130017 | 33 | Discord | ? | 4+1 | 4+1 | 5 | [719, 611, 28, 18] |
| 20260924-110157 | 4 | Discord | ? | 3+1 | 3+1 | 3 | [104, 28, 25] |
| 20260923-130021 | 51 | Discord | ? | 7+1 | 7+1 | 7 | [513, 503, 434, 412, 336, 76, 67] |
| 20260923-125419 | 5 | Discord | ? | 2+1 | 2+1 | 2 | [46, 32] |
| 20260923-101613 | 26 | Discord | ? | 3+1 | 3+1 | 3 | [702, 75, 52] |
| 20260922-125838 | 48 | Discord | ? | 6+1 | 6+1 | 6 | [576, 476, 430, 375, 77, 39] |
| 20260922-115609 | 13 | Discord | ? | 2+1 | 2+1 | 2 | [293, 36] |
| 20260922-084404 | 23 | Discord | ? | 2+1 | 2+1 | 2 | [591, 70] |
| 20260921-125925 | 31 | Discord | ? | 5+1 | 5+1 | 6 | [416, 351, 228, 199, 52] |

## All ready calls with both channels on disk

| call | min | app | title |
|---|---|---|---|
| 20260925-125945 | 29 | Discord |  |
| 20260925-114649 | 4 | Discord |  |
| 20260925-111702 | 1 | Discord |  |
| 20260924-173649 | 9 | Discord |  |
| 20260924-173310 | 3 | Discord |  |
| 20260924-133358 | 5 |  |  |
| 20260924-130017 | 33 | Discord |  |
| 20260924-110157 | 4 | Discord |  |
| 20260923-130021 | 51 | Discord |  |
| 20260923-125419 | 5 | Discord |  |
| 20260923-101613 | 26 | Discord |  |
| 20260922-125838 | 48 | Discord |  |
| 20260922-115609 | 13 | Discord |  |
| 20260922-084404 | 23 | Discord |  |
| 20260921-125925 | 31 | Discord |  |
| 20260918-125857 | 57 | Discord |  |
| 20260918-121954 | 17 | Discord |  |
| 20260917-164259 | 0 | Telegram |  |
| 20260917-125931 | 29 | Discord |  |
| 20260917-122809 | 17 | Discord |  |
| 20260917-105422 | 1 | Discord |  |
| 20260916-172818 | 32 | Discord |  |
| 20260916-143349 | 9 | Discord |  |
| 20260916-140855 | 14 | Discord |  |
| 20260916-103221 | 15 | Discord |  |
| 20260915-173345 | 29 | Discord |  |
| 20260914-172915 | 36 | Discord |  |
| 20260914-104710 | 24 | Discord |  |
| 20260911-195447 | 8 | Discord |  |
| 20260911-185047 | 15 | Discord |  |
| 20260911-175954 | 5 | Discord |  |
| 20260911-172926 | 20 | Discord |  |
| 20260911-104722 | 22 | Discord |  |
| 20260911-085057 | 8 | Discord |  |
| 20260910-172925 | 39 | Discord |  |
| 20260910-170325 | 5 | Discord |  |
| 20260910-164430 | 1 | Discord |  |
| 20260910-152202 | 19 | Discord |  |
| 20260909-172927 | 41 | Discord |  |
| 20260909-153215 | 9 | Discord |  |
| 20260908-173122 | 49 | Discord |  |
| 20260908-172941 | 1 | Discord |  |
| 20260908-141102 | 9 | Discord |  |
| 20260907-172950 | 39 | Discord |  |
| 20260907-115855 | 17 | Discord |  |
| 20260907-115707 | 1 | Discord |  |
| 20260907-113738 | 15 | Discord |  |
| 20260907-113243 | 1 | Telegram |  |
| 20260907-112222 | 9 | Discord |  |
| 20260904-162917 | 36 | Discord |  |
| 20260904-131651 | 20 | Discord |  |
| 20260903-171604 | 15 | Discord |  |
| 20260903-163014 | 15 | Discord |  |
| 20260903-152457 | 27 | Discord |  |
| 20260903-102211 | 33 | Discord |  |
| 20260902-191439 | 10 | Discord |  |
| 20260902-174018 | 58 | Discord |  |
| 20260902-172613 | 13 | Discord |  |
| 20260902-162922 | 42 | Discord |  |
| 20260902-104148 | 27 | Discord |  |
| 20260901-170132 | 31 | Discord |  |
| 20260901-163019 | 27 | Discord |  |
| 20260901-152455 | 20 | Discord |  |
| 20260831-163124 | 32 | Discord |  |
| 20260831-162934 | 1 | Discord |  |
| 20260831-133718 | 6 | Discord |  |
| 20260830-085825 | 0 | Chrome / Google Meet |  |
| 20260829-194123 | 27 | Файл | Team Sync — Weekly Updates & Issues |
| 20260829-183056 | 1 | Chrome / Google Meet |  |
| 20260829-182231 | 1 | Chrome / Google Meet |  |
