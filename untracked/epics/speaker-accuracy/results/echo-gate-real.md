# Echo gate on the 15 real calls (BESEDA-95, 2026-09-26)

Critic finding 16: the echo gate kept a whole ASR sentence's text but moved its bounds to the longest own-speech
run, and was measured only on synthetic pure-delay echo. Here it runs on the 15 calls of
[real-calls-truth.md](real-calls-truth.md), Mikhail's mic channel against the system channel, before (sentence text
at the longest run) and after (word-level gate: a word is kept when any of its 20 ms frames is own speech, the
sentence is its kept words and their times). `echo_gate_real.sh` (copies, one call at a time, lockf, nice 19,
peak 1.1 GB) → `hyp/echo-gate/`, `echo_gate_real.py` → this table. Counts only, listen-free.

Columns: `lag`, `echo dB` — the gate's own echo model (delay, 20·log10 gain of the system channel inside the mic);
`echo fit` — share of mic energy that model explains (r²); `own share` — frames the gate calls Mikhail;
`echo repeats` — mic words that repeat a system word within 0.5 s (after the lag), i.e. echo ASR could transcribe;
`echo kept` — such words left under "Я"; `own lost` — dropped mic words that are not a repeat and whose mic energy
is 10 dB over both the predicted echo and the noise floor; `majority` — the rejected rule "a word is own when at
least half of its frames are"; `bounds off` — kept sentences whose start or end is > 0.3 s from their words.

| call | min | lag ms | echo dB | echo fit | mic floor dB | own share | own while system talks | mic words | echo repeats | echo kept before → after | own lost before → majority → after | bounds off before → after |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 20260925-114649 | 3.9 | 170 | -45.6 | 0 | -63.8 | 77% | 58% | 430 | 0 | 0 → 0 | 2 → 3 → 0 | 9 / 42 → 0 / 44 |
| 20260925-111702 | 1.4 | 444 | -35.3 | 0 | -66.6 | 66% | 48% | 136 | 5 | 5 → 5 | 0 → 2 → 0 | 8 / 34 → 0 / 34 |
| 20260924-173649 | 8.9 | 148 | -60 | 0 | -78.2 | 46% | 37% | 445 | 5 | 5 → 5 | 1 → 22 → 0 | 36 / 91 → 0 / 92 |
| 20260924-173310 | 2.6 | 186 | -54.7 | 0 | -76.3 | 46% | 32% | 141 | 1 | 1 → 1 | 0 → 0 → 0 | 12 / 29 → 0 / 29 |
| 20260924-133358 | 4.5 | 28 | -47.5 | 0 | -80.1 | 86% | 77% | 298 | 1 | 1 → 1 | 0 → 0 → 0 | 5 / 31 → 0 / 31 |
| 20260924-110157 | 4.4 | 270 | -46.6 | 0 | -63.8 | 69% | 55% | 418 | 1 | 1 → 1 | 0 → 13 → 0 | 19 / 84 → 0 / 84 |
| 20260923-125419 | 5 | 40 | -46.7 | 0 | -51.8 | 75% | 45% | 608 | 2 | 2 → 2 | 3 → 8 → 0 | 19 / 65 → 0 / 68 |
| 20260923-101613 | 25.6 | 186 | -55.8 | 0 | -61.8 | 62% | 41% | 2223 | 8 | 8 → 8 | 6 → 38 → 0 | 85 / 320 → 0 / 326 |
| 20260922-115609 | 12.8 | 173 | -55.2 | 0 | -66.8 | 85% | 73% | 1192 | 2 | 2 → 2 | 1 → 5 → 0 | 10 / 159 → 0 / 160 |
| 20260922-084404 | 22.7 | 14 | -52.9 | 0 | -69 | 64% | 40% | 2010 | 7 | 7 → 7 | 2 → 17 → 0 | 38 / 255 → 0 / 257 |
| 20260925-125945 | 28.9 | 16 | -69 | 0 | -81.9 | 79% | 72% | 1325 | 1 | 1 → 1 | 0 → 0 → 0 | 6 / 94 → 0 / 94 |
| 20260924-130017 | 32.7 | 131 | -67.4 | 0 | -56.6 | 39% | 24% | 1258 | 1 | 1 → 1 | 0 → 7 → 0 | 27 / 76 → 0 / 77 |
| 20260923-130021 | 50.8 | 360 | -66.3 | 0 | -55.9 | 30% | 18% | 1463 | 0 | 0 → 0 | 1 → 14 → 0 | 30 / 96 → 0 / 97 |
| 20260922-125838 | 47.9 | 14 | -66.7 | 0 | -55.5 | 28% | 11% | 1803 | 6 | 5 → 5 | 1 → 28 → 0 | 58 / 117 → 0 / 119 |
| 20260921-125925 | 31.3 | 108 | -66.3 | 0 | -80.3 | 90% | 86% | 1403 | 1 | 1 → 1 | 1 → 0 → 0 | 2 / 90 → 0 / 91 |

## What it shows

- **There is no echo on these calls.** The system channel sits 35–69 dB under it in the mic and explains 0 % of
  the mic's energy; the lag is the argmax of noise (14–444 ms, no pattern). Mikhail is on headphones. The 0–8
  "repeats" per call are coincidences of short words (не, что, да, пока, спасибо, okay), not echo: the gate keeps
  them before and after, and should.
- **So the gate is a mic activity detector here.** With the echo predicted at ~0, a frame is "own" when the mic is
  10× over its own 10th-percentile floor. On 20260925-125945, 20260921-125925 (and 20260924-133358) that floor is
  −80…−82 dB — near digital silence from a noise suppressor — so any breath or room sound counts, and 79–90 % of
  the call is "Mikhail", 72–86 % of it while others speak. Not a loudspeaker (echo −66…−69 dB there). It does not
  change the transcript — every word ASR found is kept — only the harness's "while Mikhail speaks" (BESEDA-79)
  was unreliable on those calls. No loudspeaker rule: there is no loudspeaker in the data.
- **Before, the gate's harm was bounds, not text.** 2–85 sentences per call (364 of 1 583 in total) got bounds
  off their words — seeking landed on invented times; and 0–6 own words per call were dropped with whole sentences
  whose longest run was < 0.3 s. After: 0 bounds off, 0 own words lost, echo kept unchanged.
- **The "majority of frames" rule loses real speech** (up to 38 own words on 20260923-101613): Parakeet word times
  include pauses, so a real word can sit mostly on quiet frames. "Any own frame" keeps them; echo-only words
  (no own frame at all) are still dropped, as the synthetic tests check.
