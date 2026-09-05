# Speaker diarization for the system-audio channel

## Problem

A call has two audio channels: `me.asr.wav` (microphone) and `them.asr.wav` (system
audio). The speaker label is derived from the channel alone — `TranscriptChannel.speakerID`
in `Transcription/TranscriptModels.swift:98`. Every remote participant is mixed into
one system-audio stream, so a three-person call renders as one undifferentiated
`Собеседник`.

Parakeet does not separate voices; it only transcribes. Splitting remote participants
needs a diarization pass over the system-audio channel and a fusion step that maps the
resulting speaker timeline onto ASR timestamps.

## Approach

Run `FluidAudio.OfflineDiarizerManager` (Swift + CoreML, Apache 2.0, pyannote
Community-1 segmentation → WeSpeaker embeddings → VBx clustering) over `them.asr.wav`,
then assign each ASR word to the speaker whose interval overlaps it most.

Why this over the alternatives:

- It is a Swift package. The Python worker stays a single-purpose ASR process; no new
  responsibility on the most fragile link in the chain.
- Requires macOS 14 / Swift 6. `Package.swift:8` already declares `.macOS(.v14)` with
  tools-version 6.0, and `scripts/build_podushka_app.sh:22` targets 14.0.
- `processComplete(audioFileURL:)` takes a file and converts it internally, so
  `them.asr.wav` (16 kHz mono s16 from `AudioNormalizer`) is consumed as-is.
- Exposes per-speaker embeddings via `result.speakerDatabase`, which is the foundation
  for phase 2 without adding a second model.

The microphone channel is not diarized — it is the owner by construction.

## Scope

In scope: labelling remote participants within a single call as `Собеседник 1 / 2 / 3`,
renaming them by hand, and persisting the result.

Out of scope for this phase:

- Recognising the same voice across different calls (phase 2, built on `speakerDatabase`).
- Separating overlapping speech into two texts, and marking overlap in the UI. When two
  remote voices collide the text goes to the dominant speaker, silently.
- Diarizing the microphone channel for several people in one room.

## Success criterion

On a real three-person call, the transcript shows three distinct remote speakers, each
turn attributed to the correct one, verified by listening. Calls with a single remote
participant must still render exactly one `Собеседник` — no spurious splitting.

## Spike results (step 1, run on 2026-08-29)

`spikes/DiarizeSpike` builds against FluidAudio 0.15.6 and runs. What it showed:

- **Speed is not a concern.** 0.6–0.7 s for 30–47 s of audio on an M2 Max, roughly 50×
  realtime, after a one-off 23 s model compile. Models are 23 files fetched to
  `~/Library/Application Support/FluidAudio/Models`.
- **Times are `Float`**, not `Double`, in `segment.startTimeSeconds` / `endTimeSeconds`.
  The app works in `Double` throughout, so the boundary converts.
- **A silent channel throws `OfflineDiarizationError.noSpeechDetected`.** This is not
  hypothetical — both surviving `them.asr.wav` files are digital silence, so step 7 must
  catch it or such a call gets marked failed.
- **No spurious splitting on one voice**: a 47 s single-speaker microphone channel came
  back as exactly 1 speaker.
- **A genuine two-voice channel split correctly**: on `20260829-183056/me.asr.wav` the
  question «А зачем мне эта запись…» went to one speaker and the answer «Я тебе сделаю…»
  to the other.

### Verdict on the target case: go, with one defect to handle

A 26-minute multi-party team call (32 kbps mono mp3, normalized the same way the app
normalizes) ran in 12.8 s — about 130× realtime — and produced 6 speakers over 225
segments. Fusing that timeline with parakeet words (prototypes in
`untracked/scripts/transcribe_sample.py` and `fuse_sample.py`) gives a transcript whose
attribution is verifiable by content: one speaker consistently talks about soft/hard
limits and miner payouts, another about Grafana and Loki, another about the SDK migration
PR, another about encrypted volumes, another about container creation and SSH timing.
Five real participants, each coherent across 26 minutes.

The sixth, S1, is a phantom: 22.8 s spread over short fragments that are all handovers at
the edges of other people's turns — «uh I think that's all for me. Thank you», «thanks, uh
Mohammed», «yeah, that's that's it for my set». Short boundary fragments cluster together
instead of joining the speaker they belong to.

So the engine works on the target case, and the known failure mode is narrow and
recognisable: a low-total-time cluster made only of short fragments. Step 8 should test
whether raising the minimum segment duration or merging such clusters into their
neighbours removes it, and the fusion of step 3 should be careful not to let a handover
fragment split a turn.

Two details the prototype confirmed: words before the first speaker interval really do
occur (the call opens with «Hello, always. Hey guys» ahead of the timeline), so the
first-word fallback in step 3 is needed; and turn boundaries drift by a word or two
(«here. Uh so I will start» opens with the tail of the previous turn).

## Both channels can hold several voices

Both surviving test calls have a silent system channel and *two people* in the microphone —
they were in-person conversations, not app calls. So «the microphone is the owner by
construction» does not always hold.

How common is that? Across the 49 calls that still have both `*.asr.json` files, 46 carry
speech in both channels and only 3 are microphone-only. The dominant case is a real app
call, so phase 1 keeps targeting the system channel and leaves the microphone alone.

Worth noting for later: an in-person conversation puts two voices in the microphone, and
telling which one is the owner needs an enrolled voice profile — phase 2 machinery.

## Test material — blocking for calibration

`untracked/calls/` holds 58 calls but only 2 still have `them.asr.wav`: the retention
sweep deletes normalized audio, and everything older is transcripts only. Both survivors
are today's short two-party tests.

So the go/no-go spike (step 1) runs on thin material, and threshold calibration (step 8)
cannot happen until more is recorded. Before step 8:

- [ ] Set normalized-audio retention to `Всегда` in Settings → `Хранение`.
- [ ] Record 10+ real calls, several with three or more participants, noting the actual
      participant count per call.

This is the one part of the plan that depends on calls happening, not on code.

## Steps

### 1. Spike first: does FluidAudio give sane speaker counts?

The load-bearing risk is clustering quality on compressed Zoom/Meet audio, so it gets
tested before any protocol, storage or UI work, and before the main `Package.swift` is
touched. `spikes/CaptureSpike` is the precedent: a spike carries its own manifest.

- [x] `spikes/DiarizeSpike` with its own `Package.swift` depending on FluidAudio.
- [x] Run `OfflineDiarizerManager` over every `them.asr.wav` under `untracked/calls/`,
      printing the detected speaker count and the timeline.
- [x] Verify against `scripts/build_podushka_app.sh`: build the real bundle once with the
      dependency added and confirm nothing but the binary is needed — `cp` at line 17
      copies only the executable, so an SPM resource bundle would be left behind and the
      app would work under `swift run` but not from `~/Applications`. FluidAudio does
      produce `FluidAudio_FluidAudio.bundle`, but it holds only the LuxTTS lexicon, read
      by `TTS/LuxTts/G2p/LuxTtsG2p.swift` and the FluidAudio CLI. Diarization reads its
      models from `~/Library/Application Support/FluidAudio/Models`, so the build script
      stays as it is.

Check: on a known two-party call the detector reports exactly 2 speakers and the turns
line up with what is audible. If it over-splits here, stop and reconsider the engine
before writing anything else.

### 2. Word-level timestamps from the ASR worker

`sentence_to_segment` in `python/asr_worker.py:110` keeps only sentence start/end/text
and drops `AlignedSentence.tokens`. Sentence-level fusion is not good enough: a sentence
can span a speaker change and would be attributed wholesale to one person.

- [x] Group `AlignedToken`s into words (a token whose text starts with a space opens a
      new word) and emit them per segment as `{start, end, text}`.
- [x] Add the optional `words` field to `TranscriptSegment` so older `*.asr.json` files
      still decode. `ASRClient.WorkerEvent.segments` is already `[TranscriptSegment]?`
      and needs no change.
- [x] Add pytest to `python/pyproject.toml` as a dev dependency — the project has no
      test infrastructure on the Python side yet — and one test for token grouping.

Words will also be written into `me.asr.json`, which is unused but harmless; the file
grows by roughly the token count.

Check: `--self-test` prints words with monotonic timings; the pytest covers a word split
across several tokens.

### 3. Fusion of the speaker timeline with ASR words

New `Transcription/SpeakerAssignment.swift`:

- [x] For every word, pick the speaker with the largest time overlap.
- [x] A word touching no speaker interval takes the nearest one within 400 ms; failing
      that it keeps the previous word's speaker, and the first word of a call falls back
      to the first speaker in the timeline. The 400 ms is a guess at segmentation
      boundary slack and is one of the values step 8 calibrates.
- [x] Merge adjacent words of one speaker back into turns, splitting a sentence when the
      speaker changes mid-sentence. A sentence is also the smallest line: merging across
      sentence boundaries collapsed a four-minute monologue into one paragraph and left
      nothing to click for seeking.

Numbering happens here too: the diarizer's own ids are arbitrary, so `them-N` follows the
order people first speak.

Check: unit tests on synthetic timelines — a clean turn switch, a sentence spanning a
switch, a word in a gap, a word far from every interval, a word before any interval, and
segments with no words at all.

### 4. Wiring into the recording flow

- [x] In `runDualRecording` (`App/AppController.swift:661`) diarize the system channel
      after its ASR job completes, sequentially rather than concurrently: the saving is
      small, and a throwing `async let` beside the fallback of step 7 complicates error
      handling for no gain.
- [x] Fusion must finish before `cleanupAudioIfNeeded` — with retention set to `Сразу`,
      `them.asr.wav` is deleted the moment the transcript is written.
- [x] Same in `runRetry` (`App/AppController.swift:891`).
- [x] Do **not** generalise `DualTranscriptResult` to owner + N speakers. It honestly
      models what exists — two channels, two ASR runs — and reshaping it drags in
      `ChannelTranscriptResult`, `SpeakerTranscriptSegment`, the computed `text` and
      `performanceDescription`, `TranscriptMerger.appendChannel` and
      `lastDualTranscript` in `AppController:199,203`. Add one field holding the fused
      segments and derive `speakerSegments` from it.

Check: a recorded two-person call still produces exactly two speakers end to end.

### 5. Storage

`transcript_segments.speaker` is `TEXT NOT NULL` (`Storage/CallStore.swift:258`) with no
constraint, so `them-1` fits without a migration.

- [x] Write speaker keys as `me` and `them-1`, `them-2`, … .
- [x] Add a `call_speakers` table holding only renames — `(call_id, speaker_key,
      display_name)`. Default names are computed from the key, so unrenamed speakers
      store nothing, and no `order_idx` column is needed since the key carries the order.
      Follow the `CREATE TABLE IF NOT EXISTS` style of `prepare()`.
- [x] `runRetry` replaces segments via `replaceSegments`; it must clear `call_speakers`
      for that call too, otherwise renames from a previous run point at speaker keys that
      no longer exist after a failed diarization falls back to plain `them`.

Check: a call recorded before this change still opens and renders.

### 6. UI

`SpeakerStyle` in `App/DesignSystem.swift:40` hardcodes `mine` and `theirs`, and
`of(speaker:)` maps everything that is not `me` to `theirs`.

- [x] Replace the fixed pair with a palette indexed by speaker number. Three key classes
      must be handled, permanently: `me`, bare `them` (every pre-existing call, plus
      every future call where diarization fell back), and `them-N`. Keep today's blue for
      the owner and today's orange as the first remote colour.
- [x] `SpeakerLane.build` (`App/Views/PlayerBar.swift:30`) iterates the fixed pair
      `["me", "them"]` through `compactMap`, so `them-1` lanes would vanish from the
      player silently. Derive the lanes from the speaker keys present in the segments.
- [x] Show the display name in `CallDetailView` and `PlayerBar`, defaulting to
      `Собеседник N`.
- [x] Allow renaming a speaker from the transcript, applied to the whole call.
- [x] Update `Storage/TranscriptCopy.swift:61` so copied text carries the same names.
- [x] Decide what happens to `transcript.md`: it is written once at the end of a call and
      kept forever (`StorageJanitor` maps `.md` to `.text` → `.forever`), so a rename
      would leave it stale while the database is correct. Rewrite it on rename.
- [x] `SpeakerLaneTests.swift:19` asserts exactly `["me", "them"]` and
      `TranscriptCopyTests` uses the `them` key; both need updating.

Check: a three-speaker call is readable in light and dark, and renaming updates every
line at once.

### 7. Failure handling

- [x] If diarization fails or the models are missing, fall back to today's single `them`
      label, log the reason, and keep the call otherwise intact.
- [x] Call `prepareModels()` on first use. The download itself gets no log line of its
      own: `Diarizer` prepares lazily and the log prints the elapsed time, which is what
      makes a one-off 20 s model compile visible. A dedicated onboarding
      step with progress is deferred — this fallback already prevents a cold cache from
      ruining a call, and onboarding UI is polish until the pipeline works end to end.

Check: with the model cache removed, a call still completes with a usable transcript.

### 8. Calibration on real material

Academic sets (AMI, VoxConverse) differ from compressed Zoom/Meet system audio, so the
public numbers do not settle thresholds.

- [ ] Once the recordings from the section above exist, add an `untracked/scripts/`
      runner reporting detected vs actual speaker count per call.
- [ ] Tune the clustering threshold and the 400 ms fusion window on that set.

Check: no single-participant call is split, and multi-participant calls report the right
count on the clear majority.

## Risks

- **Over-splitting.** One person on a changing headset or connection can cluster as two.
  This is the main quality risk, which is why step 1 comes first and step 8 exists.
- **Thin calibration material.** Only two short recordings survive; everything else needs
  to be recorded from scratch before thresholds mean anything.
- **Short backchannel replies.** «Ага», «да-да» give noisy embeddings; attribution there
  will be unreliable and that is accepted.
- **Speaker numbering is per call.** `Собеседник 1` in two different calls is not the
  same person until phase 2.
