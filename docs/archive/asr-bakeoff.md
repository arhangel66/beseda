# ASR Bakeoff

Date: 2026-05-10

> Superseded on 2026-09-05. The engine moved from `parakeet-mlx` to transcribe.cpp
> and the model became a user choice; see `docs/speech-model-choice-plan.md`.

## Decision

Use `parakeet-mlx` with `mlx-community/parakeet-tdt-0.6b-v3` as the default MVP ASR path.

Reasoning:

- Russian speech quality on the provided voice notes is good enough for the MVP.
- Timestamped sentence segments are available through the Python API.
- Warm model load is fast after Hugging Face cache is populated.
- Transcription is comfortably faster than real time on the local Apple Silicon machine.

Keep Whisper MLX as a fallback candidate, but do not implement it before Phase 1 unless broader samples reveal Parakeet failures.

## Environment

- macOS: 26.2
- CPU architecture: arm64
- Python: 3.12.7 via `uv run --python 3.12`
- ASR package: `parakeet-mlx==0.5.1`
- Model: `mlx-community/parakeet-tdt-0.6b-v3`
- Audio normalization: `ffmpeg` to 16 kHz mono WAV, signed 16-bit PCM

## Worker Contract

Implemented in `python/asr_worker.py`.

Events emitted on stdout:

```json
{"type":"ready","model":"parakeet","model_id":"mlx-community/parakeet-tdt-0.6b-v3","version":"0.5.1"}
{"type":"job_started","id":"..."}
{"type":"job_done","id":"...","text":"...","segments":[{"start":0.0,"end":1.4,"text":"...","confidence":0.99}]}
{"type":"job_failed","id":"...","error":"..."}
```

Diagnostics are written to stderr only.

## Samples Tested

| File | Source format | Duration | Normalized output | Result |
|---|---:|---:|---|---|
| `audio_2026-05-10_18-04-35.ogg` | Ogg Opus, mono, 48 kHz | 29.04s | `samples/normalized/audio_2026-05-10_18-04-35.16k-mono.wav` | Good Russian transcript |
| `audio_2026-05-10_18-04-43.ogg` | Ogg Opus, mono, 48 kHz | 56.04s | `samples/normalized/audio_2026-05-10_18-04-43.16k-mono.wav` | Good Russian transcript |

## Measurements

| File | Model load | ASR wall time | Real-time factor | Notes |
|---|---:|---:|---:|---|
| `audio_2026-05-10_18-04-35.ogg` | 165.05s cold load | 3.529s | 0.1215 | First run populated Hugging Face cache |
| `audio_2026-05-10_18-04-43.ogg` | 1.47s warm load | 1.262s | 0.0225 | Cache already populated |
| JSONL re-run of first sample | 1.46s warm load | 1.078s | 0.0371 | Validated stdin/stdout worker protocol |

## Observed Quality

Parakeet produced readable Russian transcripts with punctuation and stable sentence timestamps. The obvious error in the first sample was a place-name spelling variant: `Челябицке` instead of the intended place name. For the MVP transcript use case this is acceptable.

## Remaining Bakeoff Gaps

The current decision is based on two Russian voice-note samples. Before calling Phase 0 fully complete, add and test:

- English speech.
- Mixed Russian/English speech.
- Noisy speech.
- One short real call-like clip with remote audio if available.

If those fail, run a Whisper MLX fallback bakeoff while keeping the Swift JSONL interface unchanged.

