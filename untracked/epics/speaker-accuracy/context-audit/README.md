# Context audit of speaker labels (2026-11-02)

16 real calls labelled by Nemotron-3, judged by meaning (LLM agents, `RUBRIC.md`), no audio, no ground truth.
Inputs: `transcripts/<call-id>.tsv` from `calls.sqlite`; verdicts: `judgments/<call-id>.json`.

| | result |
|---|---|
| remote people count exact | 14 / 16 (all 12 dailies, 3–5 people) |
| them-segments on the wrong person, without the echo call | 10 / 3070 (0.3 %) |
| them-segments not decidable (backchannel) | 200 / 3070 |

Both count errors are one extra label made of Mikhail's own voice coming back on the system channel:
- 20261006-173015 (Google Meet, 1:1): them-2 is 115 lines repeating Mikhail ~0.5 s late — far-end echo
  from the other side's speakers.
- 20261016-113955 (Discord, 1:1): them-2 is 2 lines repeating Mikhail while the other side shared a screen
  with sound.

The echo gate only guards the mic against the system channel, not the reverse. The 10 real mistakes are
turn boundaries: a short reply or the first words of the next person glued to the previous speaker.

## Fix (mic-echo-filter, 2026-11-02)

`MicEchoFilter` in the app (rule in docs/architecture/asr.md). Plan: `mic-echo-plan.md`; the final rule moved
the lag window to 0.3–1.5 s and added the whole-speaker drop (≥ 25 % echo words).
`remove_mic_echo_from_stored_calls.py` applied it to the stored calls: 20261006-173015 −115 lines,
20261016-113955 −2 lines, each now one remote speaker; nothing else matched. Backups:
`calls.sqlite.before-mic-echo.backup` and `transcript.md.before-mic-echo.backup` in both call folders.
May–June calls were left: no word times and no echo gate yet, so the direction of a duplicate is unknown.
`transcripts/` and `judgments/` are not committed: they hold call content.
