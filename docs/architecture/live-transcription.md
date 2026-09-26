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
