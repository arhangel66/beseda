# Showing what happens while a transcript is being made

## Problem

Pressing «Расшифровать снова» on a 26-minute call gives no sign of life for about a
minute. The button greys out, the call row keeps its old status, and nothing says whether
the work started, how far it got, or how long it will take. The same holds for a call that
has just finished recording. This is the worst part of the current experience: the app
looks stuck exactly when it is working hardest.

## What exists today

- `AppController.Status` is rendered in one place only — `App/Views/MenuBarPopover.swift`.
  The conversations window, where the work is actually started from, shows nothing. The
  only feedback is `isBusy` disabling the button.
- The stages are coarse: `startingWorker` → `normalizing` → `transcribing` → `completed`.
  A dual call runs two ASR passes and a diarization pass, and all three report as
  `transcribing`.
- There is no diarization stage at all. The first run also downloads and compiles the
  CoreML models, which takes about twenty seconds, and looks identical to a warm run.
- Status titles are English — «Transcribing», «Starting ASR» — in an otherwise Russian UI.
- Nothing estimates the remaining time, although the data for it is already stored.

## What makes real progress possible

Both slow stages can report a genuine fraction, so nothing here needs to be faked:

- `parakeet_mlx.transcribe(..., chunk_callback=...)` calls back with
  `(end_sample, total_samples)`. `python/asr_worker.py` does not pass it today. The worker
  protocol is already JSONL, so a `job_progress` event sits naturally beside `job_started`
  and `job_done`.
- FluidAudio's `OfflineDiarizerManager.process(_:progressCallback:)` calls back with
  `(chunksProcessed, totalChunks)` after each segmentation chunk — see
  `Sources/FluidAudio/Diarizer/Offline/Core/OfflineDiarizerManager.swift:200`.

An estimate of the remaining time needs no history at all: once a step reports a
fraction, the time its finished part took divides into the time the rest will take. That
self-corrects on a busy machine, which a stored `real_time_factor` would not, so the
`transcript_jobs` columns stay unused here.

## Approach

Show the progress where the work was started, naming the stage and its share of the whole.
A dual call is three passes of known length, so the overall bar is honest, not a spinner.

## Steps

### 1. Progress out of the ASR worker

- [x] Pass `chunk_callback` in `ASRWorker.transcribe` and emit
      `{"type": "job_progress", "id": …, "fraction": …}`.
- [x] Handle the event in `Transcription/ASRClient.swift` and surface it as a callback,
      the way `diagnosticsHandler` already works.

Check: done. The 26-minute system channel of `20260829-194123` reports sixteen rising
fractions over 23 seconds, one about every 1.5 s, and still ends with `job_done`.

### 2. Progress out of the diarizer

- [x] Pass `progressCallback` in `Transcription/Diarizer.swift` and hop the numbers to the
      main actor. It covers segmentation only, so the bar reaches the end of the step a
      second or two before clustering finishes.
- [x] Report the one-off model preparation as its own stage: `prepareModels` moved out of
      `timeline` so the pipeline can name it. A warm run flashes past it.

### 3. A status that can describe a pipeline

- [x] `startingWorker`, `normalizing` and `transcribing` collapsed into one `working(JobStage)`
      case. A `JobStage` is a title, its place in the run, and the share of itself it has
      done; whoever runs the pipeline lists its own steps — five for a fresh call, four for
      a dual retry, two for a microphone note.
- [x] Translate the titles, in `Status` and in the sidebar's `metaDescription`.

### 4. Show it where the work starts

- [x] The call row shows the running step and a bar, keyed on `processingCallID`.
- [x] The detail pane shows a progress banner in place of the failure banner.
- [x] The estimate appears under the title once the step is past a tenth of itself.
- [x] Not in the original list, and the real reason the retry looked dead: a finished retry
      never reached the open pane. `refreshRecentCalls` reloads the selected call when its
      stored status changed, so the transcript now appears without reselecting the call.

Check: pressing «Расшифровать снова» on a 26-minute call shows movement within a second
and never leaves more than a few seconds without a visible change.

## Risks

- **Coarse callbacks.** Measured at sixteen updates on a 26-minute file, about one every
  1.5 s. Smooth enough that interpolating between them was not needed.
- **Progress that lies.** Every step weighs the same in the overall bar, so the silent
  microphone channel of a dual call flies through its fifth of the bar. It jumps forward,
  never back, which is the harmless direction.
- **Loading the model reports nothing.** The first step of a retry can sit at zero for
  several seconds while the worker loads the model. It says its name and spins, which is
  all it can honestly do.
