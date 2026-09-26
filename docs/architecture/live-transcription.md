---
type: Architecture
title: Live transcription
description: The optional preview during a call — me/them lines and «Ключевые моменты» read from the raw files while they are written.
---
# Live transcription

## How it works

Optional (Запись → «Расшифровывать во время звонка», `AppSettings.transcribesDuringCall`, off by default).
While a call records, the menu bar popover shows the last me/them lines and 3–5 key points. It is a
preview: nothing is written to the call folder or the index, and the post-call [pipeline](asr.md) still
produces the transcript.

- **Input** — no second capture path. `GrowingWAVFile` reads `me.raw.wav` / `them.raw.wav` straight from
  disk while the recorder writes them: the header says zero frames until close, so the length comes from
  the file size past the `data` chunk. A chunk is mixed to mono and resampled to 16 kHz with
  `AVAudioConverter`, as `AudioNormalizer` does.
- **Chunks** — transcribe.cpp has no streaming API, so `LiveTranscriptionLoop` cuts fixed chunks of 20 s
  with 2 s overlap (`LiveBackoff.chunkSeconds`/`overlapSeconds`; under GigaAM's 25 s window) and runs them
  through the same `LocalTranscriber` (`transcribe(samples:)`), one model in memory. The loop runs in a
  detached `.utility` task. `LiveChunkMerge` cuts each overlap at its middle by absolute word times, so no
  word appears twice; `LiveLine.lines` turns both channels' words into sentences by start time. No
  diarization, no echo gate.
- **Back-off** — `LiveBackoff`: a chunk is taken only when it is fully on disk; with more than one chunk
  waiting behind it, the backlog is skipped and the newest chunk taken. A chunk that took longer than its
  own audio, or a grown `DualCapture.droppedBufferCount` (buffers `PCMFloatRecorder` failed to write),
  doubles the rest between chunks (10 s, up to 60 s); a clean chunk halves it. The loop never touches the
  capture threads.
- **Key points** — `KeyPointsSchedule`: every 180 s of recorded audio (the clock is the microphone file
  length, so pause stops it), only when the transcript grew, never two rounds at once. `LiveTranscription`
  sends the lines («Я» / «Собеседник») to the summary provider from `makeSummaryProvider` with
  `keyPointsPrompt`; a failure is logged and the old bullets stay.
- **Lifecycle** — `AppController.runDualRecording` starts `LiveTranscription` before the capture and
  stops and awaits it (a chunk in flight finishes) before normalization, so `transcribeDualCall` never
  shares the transcriber with it. Pause drops buffers, so the files stop growing and the loop idles.
- **Preview** — `BESEDA_PREVIEW_POPOVER=live` opens the popover as recording with
  `LiveTranscription.preview()`: canned lines and key points, no capture, model or LLM — for no-focus screenshots.

## Load

Measured 2026-09-26 on the M2 Max, model `parakeet-tdt-0.6b-v3` (Q4_K_M), by the opt-in harness
`liveModeLoadOfATenMinuteCall` (`BESEDA_LIVE_LOAD=1 nice -n 19 swift test --jobs 2 --filter liveModeLoad`):
600 s of `say` speech (Milena on the 48 kHz mono mic file, Samantha on the 48 kHz stereo system file),
written second by second through `PCMFloatRecorder`, the real `LocalTranscriber` on the loop.
Key points were **off**: the built-in model (llama-server + Gemma) is not installed on this Mac, so
llama-server's memory is not measured.

- CPU of the whole test process (`ps %cpu`, every 5 s): mean 16 %, peak 113 % (one core ≈ 100 %).
- RAM (RSS): peak 686 MB, flat over the call — no growth with the transcript.
- Chunks: 66 of 66 possible (both channels), none skipped; one 20 s chunk took 0.20 s mean, 0.29 s max.
- Back-offs: 0, dropped buffers: 0.
- Live text lag behind the recording: mean 3 s, max 7 s (an upper bound: measured to the newest
  sentence's start, and a chunk waits until its 20 s are on disk).

Raw samples (seconds since start, CPU %, RSS MB, llama-server RSS MB):

```
0 49.1 663 0
5 1.9 664 0
10 25.2 664 0
15 19.9 664 0
20 70.8 686 0
25 4.2 685 0
31 1.0 685 0
36 1.9 686 0
41 25.7 686 0
46 6.4 686 0
51 2.4 686 0
57 3.6 686 0
62 9.6 686 0
67 37.2 686 0
72 33.6 630 0
77 23.8 644 0
82 4.3 644 0
88 4.3 644 0
93 14.6 643 0
98 22.9 643 0
103 7.2 643 0
109 1.6 643 0
114 13.2 643 0
119 0.8 643 0
124 7.4 643 0
130 3.0 644 0
135 26.0 643 0
140 12.2 634 0
145 2.7 634 0
151 2.1 645 0
156 21.8 645 0
161 10.5 631 0
166 3.1 645 0
172 1.8 645 0
177 1.7 645 0
182 113.1 652 0
187 25.2 645 0
192 6.1 645 0
198 1.5 645 0
203 7.6 645 0
208 34.0 645 0
213 17.6 631 0
218 92.2 652 0
223 5.9 645 0
229 5.1 645 0
234 37.8 645 0
239 33.8 645 0
244 9.1 645 0
249 3.6 645 0
255 8.7 644 0
260 13.3 644 0
265 10.1 644 0
270 3.6 644 0
276 2.4 644 0
281 13.3 645 0
286 14.1 644 0
291 46.1 644 0
296 3.4 644 0
302 2.3 644 0
307 16.1 632 0
312 22.7 645 0
317 0.1 645 0
322 5.7 645 0
328 1.9 645 0
333 22.2 645 0
338 21.7 645 0
343 69.6 651 0
348 7.2 644 0
353 2.3 644 0
359 2.4 644 0
364 7.5 644 0
369 34.1 644 0
374 10.7 644 0
379 49.1 649 0
385 1.5 645 0
390 0.4 644 0
395 37.2 642 0
400 29.0 645 0
405 8.4 645 0
411 4.9 645 0
416 92.1 652 0
421 35.7 645 0
426 5.0 645 0
431 2.5 645 0
437 2.2 645 0
442 13.1 645 0
447 16.2 645 0
452 86.3 652 0
458 3.1 645 0
463 1.9 645 0
468 19.5 635 0
473 10.8 646 0
478 3.0 646 0
484 1.9 646 0
489 72.5 654 0
494 13.8 646 0
499 3.3 646 0
505 1.9 646 0
510 2.1 647 0
515 20.2 646 0
520 15.4 646 0
525 7.5 646 0
530 1.9 646 0
536 1.6 633 0
541 33.8 633 0
546 23.2 646 0
551 15.2 646 0
556 4.7 633 0
562 2.7 646 0
567 3.5 646 0
572 34.4 646 0
577 4.9 633 0
583 1.4 646 0
588 7.1 646 0
593 21.2 646 0
598 5.5 647 0
```

## Main files

`Transcription/LiveTranscriptPolicy.swift` (pure: `LiveLine`, `LiveChunkMerge`, `LiveBackoff`,
`KeyPointsSchedule`), `Transcription/LiveTranscriptionLoop.swift` (`LiveTranscriptionLoop`,
`GrowingWAVFile`), `App/LiveTranscription.swift`, the view in `App/Views/MenuBarPopover.swift`.

## Constraints

- **The transcriber is shared by time, not by lock.** The live loop and the post-call pipeline use the one
  `LocalTranscriber`; only the awaited `stopLiveTranscription` keeps them apart (see [ASR](asr.md)).
- The tail after the last full chunk is never shown live; the final transcript has it.
- A harness can drive `LiveTranscriptionLoop` without capture: write audio through a `PCMFloatRecorder`
  at real-time pace and pass closures for `transcribe`, `droppedBuffers`, `isPaused`, `update`.
