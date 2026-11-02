# Plan: drop Mikhail's voice echoed back on the system channel

Problem (context audit, README.md): on some calls the other side's speakers return Mikhail's voice into
their mic, so the system channel repeats him ~0.5 s later. The diarizer makes a phantom "Собеседник 2" of it
(20261006-173015: 56+ lines), or old single-`them` calls get his words twice (20260521, 20260525, 20260601…).

Rule (measured on all 123 stored calls, `echo_word_lag.py`, `find_mic_echo_on_system.py`):
a system sentence is echo when it has ≥ 3 distinct words, ≥ 80 % of them repeat the kept mic words in the
same order, and the median per-word lag (system − mic) is 0.05–1.5 s. Real repeats by the other person lag
≥ 2 s (20261008: 2.3 s); Mikhail repeating them gives a negative lag (20261013: −1.9 s).
Compared against the echo-gated mic, so no text is ever lost: a dropped line is always kept as «Вы».

## App

- [ ] `MicEchoFilter.remoteSentencesWithoutMicEcho(system:, microphone:)` in `Transcription/`, word-level rule above.
      Check: unit tests — echo at +0.5 s dropped; repeat at +2.3 s kept; Mikhail repeating at −1.9 s kept;
      "да да да" kept; sentence without words kept.
- [ ] `AppController.transcribeDualCall`: filter `systemAudio.segments` after the echo gate, before diarization
      and the single-`them` fallback. Removed sentences take no diarizer speaker, so no phantom label and
      numbering stays `them-1…N`. Log "Mic echo filter dropped X of Y system sentences".
      Check: `swift test --jobs 2` green.
- [ ] docs: asr.md (pipeline step), speaker-accuracy.md (short section with the numbers).
- [ ] Commit on a branch in my own worktree.

## Your stored calls (one-off script, untracked/scripts/)

- [ ] Backup `calls.sqlite` → `calls.sqlite.before-mic-echo.backup` and each touched `transcript.md`.
- [ ] Calls with word timings (Sep+): same word rule from `them.asr.json` / `me.asr.json`.
      Old May–June calls (no word timings): same rule on stored sentence starts (lag 0–1.5 s).
- [ ] Delete the echo lines, renumber `them-N` so a vanished label leaves no gap, rewrite `order_idx`
      and the `## Dialogue` section of transcript.md. No renames/merges/exports exist on these calls.
      Summaries stay as they are.
- [ ] Dry run first: print what goes per call; you look; then apply.

Expected: ~10 calls, ~240 lines (20261006-173015 loses its phantom them-2, 20261016-113955 its 1-line them-2).
