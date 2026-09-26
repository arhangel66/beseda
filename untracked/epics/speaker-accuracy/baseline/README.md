# Baseline: what Beseda does today, and its numbers

Beseda's current speaker and ASR pipeline, read from the code at commit `03dae95` (branch native-ui) and run
on the eval set of [../README.md](../README.md). Line references are to that commit.

## What the app does

### Recording and "me" vs "them"

- Two separate captures: the microphone through a plain `AVAudioEngine` input tap
  (`Audio/MicrophoneCapture.swift:22,50`) and every other process's output through a Core Audio process
  tap that excludes Beseda itself (`Audio/SystemAudioTap.swift:45-51`).
- "Me" vs "them" is the channel and nothing else: every mic segment is speaker `me`, every system segment
  is `them` or a diarized `them-N` (`Transcription/TranscriptModels.swift:131-155`).
- **No echo cancellation, no bleed handling, no dedup between channels.** The mic tap does not enable
  voice processing (no `setVoiceProcessingEnabled`), and nothing compares the two transcripts. When the
  remote side leaks from speakers into the mic, it is transcribed a second time as "me".

### Preprocessing and ASR (both channels, one after the other)

- Each raw channel is resampled to 16 kHz mono int16 with `AVAudioConverter`, quality `.max`
  (`Audio/AudioNormalizer.swift:7,28`; both channels in parallel, `App/AppController.swift:751-758`).
- The selected model runs in-process through transcribe.cpp v0.2.3 on Metal
  (`Transcription/LocalTranscriber.swift:99-128`), mic first, then system (`App/AppController.swift:853-869`):
  - **Parakeet v3** (`parakeet-tdt-0.6b-v3-Q4_K_M.gguf`, 485 MB): language `nil` = automatic detection
    (`Transcription/SpeechModel.swift:24-36`), audio fed in 120 s pieces only for the progress bar.
  - **GigaAM v3** (`gigaam-v3-e2e-rnnt-Q8_0.gguf`, 274 MB): language `ru`, audio cut at ≤ 25 s at the
    quietest 100 ms in the last fifth of the window (`Transcription/SpeechModel.swift:38-50`,
    `Transcription/UtteranceSplitter.swift`); words rebuilt from SentencePiece tokens
    (`Transcription/WordAssembler.swift`).
- Word timestamps are grouped into sentence segments: break on `.?!`, on a pause ≥ 1 s, or at 40 words
  (`Transcription/SentenceBuilder.swift:7-31`).

### Diarization (system channel only, after ASR)

- FluidAudio 0.15.6 `OfflineDiarizerManager` (pyannote community-1 segmentation + WeSpeaker embeddings +
  VBx clustering, CoreML, ~21 MB), config `community` with `clusteringThreshold: 0.70` instead of 0.6, no
  min/max/number of speakers (`Transcription/Diarizer.swift:6`, `Tests/BesedaTests/DiarizerTests.swift`).
  Segmentation windows 10 s with step 0.2, embeddings skip segments < 1 s and overlapped speech,
  exclusive (non-overlapping) output.
- Runs on the normalized system file after both ASR passes (`App/AppController.swift:870-875,989-1015`).
  The mic channel is never diarized. A diarizer error falls back to a single `them`.
- Speaker labels are given per **word**, not per diarizer segment: each ASR word takes the diarizer speaker
  it overlaps most, else the nearest within 0.4 s, else the previous word's speaker
  (`Transcription/SpeakerAssignment.swift:20-47,60-81`). Consecutive words of one speaker inside a sentence
  merge into a turn; turns are renamed `them-1`, `them-2`… in order of first appearance. What the user sees
  (and what this baseline scores) is these turns, so a speaker exists only where ASR produced words.

## The adapter

`Package.swift` + `Sources/Baseline/` — a SwiftPM executable. The app's target is an executable, so it
cannot be imported; instead:

- `Sources/Baseline/AppCopy/` holds eight app files **copied verbatim** at `03dae95`: `Diarizer`,
  `SpeakerAssignment`, `UtteranceSplitter`, `WordAssembler`, `SentenceBuilder`, `TranscriptModels`,
  `SpeechModel`, `AudioNormalizer`. `AppStubs.swift` supplies the two symbols they reference from elsewhere.
- `Sources/TranscribeCpp` is a symlink to the app's `Vendor/TranscribeCpp`; `CTranscribe` and FluidAudio
  are pinned to the app's versions.
- `main.swift` re-types the three small functions of `LocalTranscriber` (`run`, `words(in:)`,
  `readSamples`) without its queue and progress, and follows `transcribeDualCall` step by step: normalize →
  ASR mic → ASR system → diarize system → `SpeakerAssignment.remoteTurns` → the app's own
  `DualTranscriptResult.speakerSegments`.

Faithfulness: same engines, models, settings, order and merge code. Differences: the models are loaded
once per engine and warmed up with 1 s of silence before timing (the app loads on the first call and
unloads after 10 idle minutes); the eval audio is already 16 kHz, so normalization does not resample;
`processing_seconds` covers normalize + both ASR passes + diarization. Copies go stale if the app changes
these files; rerun against a newer commit by copying them again.

Models: Parakeet is taken from the app's model cache (`~/Library/Application Support/Beseda/runtime/models`,
only `.gguf` files there, linked read-only after a sha256 check), GigaAM is downloaded into `models/`
(gitignored). The diarizer models are FluidAudio's own cache.

## Rerun

```
untracked/epics/speaker-accuracy/baseline/run.sh
```

Fetches missing models, builds the eval set if absent, builds the adapter, runs it under
`lockf /tmp/beseda-speaker-accuracy.lock` (~4 min for both engines), then `score_baseline.py` scores
`hyp/baseline-parakeet`, `hyp/baseline-gigaam` and `hyp/baseline-diarizer-raw` into `../results/`.

## Results (M2 Max, 2026-09-26)

| | Parakeet v3 | GigaAM v3 | diarizer raw timeline |
|---|---|---|---|
| DER, all 13 | 0.386 | 0.403 | 0.239 |
| DER real (VoxConverse+AMI) | 0.262 | 0.311 | 0.119 |
| DER real, overlap excluded | 0.207 | 0.251 | 0.059 |
| DER synthetic calls, both channels | 0.938 | 0.810 | 0.767 |
| DER synthetic calls, overlap excluded | 0.944 | 0.816 | 0.775 |
| DER synthetic, system channel only | 0.606 | 0.413 | 0.295 |
| speaker-count error (mean \|Δ\|, all) | 0.77 | 0.85 | 0.77 |
| me/them error (share of speech time) | 0.077 | 0.036 | 0.034 |
| echo words transcribed twice (bleed rate) | 0.678 | 0.620 | — |
| WER / CER, synthetic, system channel | 0.259 / 0.202 | 0.275 / 0.162 | — |
| WER / CER, ru calls (5) | 0.128 / 0.077 | 0.100 / 0.063 | — |
| WER / CER, mixed ru-en calls (3) | 0.389 / 0.327 | 0.448 / 0.262 | — |
| × realtime (whole pipeline, all) | 13.3 | 48.1 | — |
| model size on disk | 485 MB + 21 MB diarizer | 274 MB + 21 MB diarizer | 21 MB |

- The "diarizer raw timeline" column is FluidAudio's segments on the system channel as they come, plus the
  Parakeet mic segments as `me` — not what the app shows, but it separates the diarizer's own error from
  what word-level assignment adds. Its WER is meaningless (no text).
- VoxConverse/AMI have no reference text in the set, so English WER is not measured.
- **WER/CER come from 8 short synthetic calls (~5 min of audio): treat differences under ~2 points
  as noise.** Timings vary ±30 % between runs because other agents share the Mac.
- Full tables: [../results/baseline-parakeet.md](../results/baseline-parakeet.md),
  [../results/baseline-gigaam.md](../results/baseline-gigaam.md),
  [../results/baseline-diarizer-raw.md](../results/baseline-diarizer-raw.md),
  [../results/baseline-extra.md](../results/baseline-extra.md) (by language, system-only DER); per-file
  numbers in the `.json` next to them.

## Where it is weakest

1. **Echo on the mic channel.** With the remote side leaking in at −20 dB, 62–68 % of remote words are
   transcribed again as "me", and those long `me` segments over remote speech are most of the synthetic
   DER (0.94 both channels vs 0.61 system-only for Parakeet). Nothing in the app cancels or dedups it.
2. **Word-level assignment roughly doubles the diarizer's error.** On real recordings the diarizer alone
   gets DER 0.119, the app's turns 0.262 (Parakeet) / 0.311 (GigaAM): turns exist only where words are,
   and fallback rules smear a speaker over the next one's words. On the synthetic calls 0.295 → 0.41–0.61.
3. **Parakeet's language detection on mixed ru-en.** Mixed calls have WER 0.39 against 0.13 for Russian;
   in `call_mix_4spk` whole sentences in the "other" language vanish from the system transcript. GigaAM
   is Russian-only and spells English by ear (mixed WER 0.45).
4. **Short turns.** Synthetic turns are 1–6 s and embeddings skip segments < 1 s, so the diarizer undercounts
   speakers (e.g. 2 of 4 in `call_mix_4spk`); speaker-count error is ~0.8 everywhere.
