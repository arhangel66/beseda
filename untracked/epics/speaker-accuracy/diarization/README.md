# Diarization and me/them alternatives

BESEDA-15: local alternatives to Beseda's speaker pipeline, on the eval set and scorer of
[../README.md](../README.md), against the baseline of [../baseline/README.md](../baseline/README.md).
Measured on the M2 Max while the Mac was shared and overloaded: the model runs were cut short (see
"Not measured"), timings are rough.

| file | what |
|---|---|
| `Package.swift`, `Sources/Diarize/main.swift` | Swift runner: FluidAudio 0.17.4 diarizers (offline pyannote/VBx at several thresholds, known speaker count, shorter embedding minimum, Sortformer, LS-EEND) on every `<id>.system.wav`, writes `hyp-system/<variant>/` |
| `assemble.py` | the echo gate, the "diarizer timeline" mapping, full hypotheses in `hyp/diar-*`, scores into `../results/diar-*` and `results.md` |
| `results.md` | the table below, as generated |

## Alternatives

1. **Echo gate on the mic (`diar-echo-gate-parakeet`)** — the cheapest cross-channel fix, no model. Per file,
   FFT cross-correlation finds the delay and gain of the system channel inside the mic; a 20 ms mic frame is
   "me" only when its energy beats the predicted echo by 6 dB (and the noise floor). Each ASR mic segment is
   cut down to its runs of own speech (≥ 0.3 s); echo-only segments are dropped. The rest of the app pipeline
   is unchanged. Swift plug-in: ~60 lines with Accelerate (vDSP FFT), native, no model.
2. **Keep the diarizer timeline (`diar-timeline-parakeet`)** — no new model: the system turns are the
   diarizer's own segments, each ASR sentence goes onto the segment it overlaps most (sentences with no
   diarizer speech under them take the nearest segment's speaker). Replaces `SpeakerAssignment`'s per-word
   rule. Native Swift, a few dozen lines.
3. **1 + 2 together (`diar-timeline-echo-gate-parakeet`)** — the recommended combination.
4. **FluidAudio 0.17.4 offline diarizer, threshold 0.5 (`diar-offline-t0.5`)** — same community-1 +
   WeSpeaker + VBx models as the app (21 MB), newer library; with the echo gate and the timeline mapping.
   Native CoreML, a version bump in `Package.swift`.
5. **Sortformer, LS-EEND, other thresholds, known speaker count** — runner written, not measured (see below).

## Results (all 13 files; M2 Max, 2026-09-26)

| hypothesis | DER real | DER real no overlap | DER synthetic both channels | DER synthetic system only | speaker-count error real / synthetic | me/them | bleed | x realtime |
|---|---|---|---|---|---|---|---|---|
| baseline Parakeet (BESEDA-14) | 0.262 | 0.207 | 0.938 | 0.606 | 0.60 / 0.88 | 0.077 | 0.678 | 13 |
| baseline diarizer raw timeline | 0.119 | 0.059 | 0.767 | 0.295 | 0.60 / 0.88 | 0.034 | 0.000 | 13 |
| 1. echo gate | 0.262 | 0.207 | **0.481** | 0.606 | 0.60 / 1.00 | 0.031 | **0.013** | 803 (gate alone) |
| 2. diarizer timeline | **0.130** | 0.073 | 0.772 | 0.295 | 0.60 / 0.88 | 0.029 | 0.678 | no extra work |
| 3. timeline + echo gate | **0.130** | 0.073 | **0.282** | 0.295 | 0.60 / 1.00 | **0.001** | **0.013** | 803 (gate alone) |
| 4. FluidAudio 0.17.4 t=0.5 + 3 | 0.131 | 0.074 | **0.264** | **0.271** | 0.60 / 0.75 | 0.001 | 0.013 | 46 (diarizer alone) |
| Sortformer (4 speakers max) | not measured | | | | | | | | |
| LS-EEND dihard3 / callhome | not measured | | | | | | | | |
| offline t=0.6 / 0.7 / 0.8, min embedding 0.3 s, known speaker count | not measured | | | | | | | | |

Gains against the baseline Parakeet pipeline:

- **Echo** (finding 1): the gate takes echo words transcribed twice from 0.678 to 0.013 and synthetic DER on
  both channels from 0.938 to 0.481; with the timeline, to 0.282. me/them error 0.077 → 0.001. It costs
  ~1 ms per second of audio. Caveat: our echo is one pure delay and gain (−20 dB, 60 ms), which this gate fits
  exactly; a real room smears the echo over ~100 ms and a real speaker/mic adds nonlinearity, so expect less
  on real calls. The next step there is a max over nearby lags or a real AEC (WebRTC AEC3).
- **Per-word assignment** (finding 2): using the diarizer's timeline takes real DER 0.262 → 0.130, almost
  the raw diarizer's 0.119 (the rest is the text-less diarizer segments getting no ASR, and sentences
  outside diarizer speech). No new model.
- **Speaker count** (finding 3): threshold 0.5 on 0.17.4 lowers synthetic count error 1.00 → 0.75 and system
  DER 0.295 → 0.271; it does not fix it. What is left is mostly (a) turns of 1–6 s against the 1 s embedding
  minimum — partly an artefact of our FLEURS-cut set, real call turns are longer — and (b) ASR misses:
  in `call_mix_4spk` Parakeet transcribes none of "me"'s English speech, so "me" disappears whatever the
  diarizer does. Known speaker count and the 0.3 s embedding minimum are the direct tests and are not measured.
  The count error with the gate rises 0.88 → 1.00 only through `call_mix_4spk`: Parakeet's mic segments there
  are all echo, the gate rightly drops them, and "me" (never transcribed) is gone as a speaker.

Model size: FluidAudio diarizer 21 MB on disk (Segmentation 5.7 MB, Embedding 13 MB, FBank, PLDA). Licences:
FluidAudio Apache-2.0; pyannote community-1 weights CC BY 4.0; WeSpeaker Apache-2.0; Sortformer NVIDIA Open
Model License; LS-EEND MIT (per FluidAudio docs, not re-checked). Everything here is native Swift/CoreML.

## Dropped

- **pyannote community-1 / 3.1 in Python on MPS**: gated on Hugging Face, no token on this Mac; community-1
  is the same pipeline FluidAudio runs in CoreML, so the Python run would mostly measure PyTorch vs CoreML.
  And a Python engine inside a Swift app means shipping a Python runtime: a real cost.
- **Apple voice-processing AEC (`setVoiceProcessingEnabled`)**: works only on live AVAudioEngine I/O, it
  cannot run offline on recorded files, so it cannot be measured on this set. It is the obvious product
  counterpart of the echo gate, to try in the app.

## Not measured, and how to rerun

The Mac was overloaded; the model run was killed after `offline-t0.5`. Each rerun, one at a time:

```
cd untracked/epics/speaker-accuracy
(cd baseline && sh run.sh)                                   # hyp/baseline-* (needed by assemble.py)
(cd diarization && swift build -c release)
VARIANTS=sortformer nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock diarization/.build/release/Diarize
VARIANTS=lseend-dihard3,lseend-callhome nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock diarization/.build/release/Diarize
VARIANTS=offline-t0.6,offline-t0.7,offline-t0.8 nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock diarization/.build/release/Diarize
VARIANTS=offline-t0.7-minseg0.3,offline-t0.7-known-count nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock diarization/.build/release/Diarize
nice -n 19 uv run diarization/assemble.py                    # scores every complete hyp-system/<variant>/
```

`assemble.py` picks up every `hyp-system/<variant>/` with all 13 files and adds its row to `results.md`.
The known-count variant reads the speaker count from the reference (an oracle: an upper bound, not a product
setting) and loads the model per file, so its speed is not comparable.

## Recommendation (so far)

Alternatives 1 + 2: native, no model, no download; DER on the synthetic calls 0.938 → 0.282, real 0.262 →
0.130, echo duplicates 0.68 → 0.01. Bumping FluidAudio to 0.17.4 with threshold 0.5 adds a little (0.264).
Sortformer/LS-EEND stay open until measured.
