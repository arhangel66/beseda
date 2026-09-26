# Remote-speech ASR alternatives

Epic BESEDA-6, second reading: how well the other participants' speech (system channel, band-limited,
libopus 20 kbps) is transcribed, Russian and mixed Russian-English. Local alternatives to Beseda's two
engines, scored on the 8 synthetic calls of the eval set ([../README.md](../README.md)) against the
baseline of [../baseline/README.md](../baseline/README.md). Research only, no app code.

## Rerun

```
cd untracked/epics/speaker-accuracy/asr && nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock uv run run.py
```

Builds the eval set if absent, runs every engine in `ENGINES` one after another on the system channel of
each call, writes `../hyp/<engine>/` (unique names, `asr-*`), and writes the table to
[results.md](results.md). To run one engine, change the list in `main(...)` at the bottom of `run.py`;
`transcribe=False` only rescores. First run downloads ~5 GB of models into the Hugging Face / GigaAM caches.

## Alternatives

| name | what | aimed at |
|---|---|---|
| `asr-whisper-turbo` | Whisper large-v3-turbo (MLX, fp16), whole file, language auto-detected once | multilingual model |
| `asr-whisper-turbo-per-chunk` | same model, but on silero-VAD chunks (≤ 20 s), language detected per chunk | mixed calls |
| `asr-gigaam-ctc` | GigaAM v3 `e2e_ctc` (PyTorch, CPU) on the same VAD chunks — the other decoding of the app's GigaAM | Russian |
| `asr-gigaam-ctc-loudnorm` | the same, after ffmpeg `loudnorm` (EBU R128) of the call audio | cheap front-end trick |
| `asr-route-gigaam-ru-parakeet-en` | Whisper-turbo language ID per VAD chunk → GigaAM CTC for `ru`, Parakeet v3 (MLX) for `en` | mixed calls |

## Results (M2 Max)

| alternative | WER ru | CER ru | WER mixed | CER mixed | Δ WER ru vs GigaAM app | Δ WER mixed vs Parakeet app | × realtime (system channel) |
|---|---|---|---|---|---|---|---|
| Parakeet v3 (app) | 0.128 | 0.077 | 0.389 | 0.327 | | | — |
| GigaAM v3 RNNT (app) | 0.100 | 0.063 | 0.448 | 0.262 | | | — |
| asr-whisper-turbo | not measured | | | | | | |
| asr-whisper-turbo-per-chunk | not measured | | | | | | |
| asr-gigaam-ctc | not measured | | | | | | |
| asr-gigaam-ctc-loudnorm | not measured | | | | | | |
| asr-route-gigaam-ru-parakeet-en | not measured | | | | | | |

**Not measured yet (2026-09-26):** the Mac was overloaded (load average 150–400) for the whole task and the
rules forbid inference then. Every row is filled by the rerun command above; one engine at a time:
set e.g. `main(["asr-gigaam-ctc"], transcribe=True)`.

- WER/CER come from 8 short calls (5 ru, 3 mixed, ~5 min): **differences under ~2 points are noise.**
  The set has no English-only call, so English is only measured inside the mixed calls.
- × realtime is the system channel alone (VAD + ASR, models warm), with other agents on the Mac; the
  baseline's speed covers both channels plus diarization, so it is not in the same column.
- The CTC/Parakeet engines here are the PyTorch / MLX weights, not the app's gguf quantizations
  (GigaAM `e2e-rnnt-Q8_0`, Parakeet `Q4_K_M`), so a small gap to the app is expected either way.

| name | model on disk | licence | into the Swift app |
|---|---|---|---|
| Whisper large-v3-turbo | ~1.6 GB (fp16) | MIT | native: WhisperKit (CoreML) or whisper.cpp (Metal); transcribe.cpp does not ship Whisper |
| GigaAM v3 e2e CTC | not checked (downloaded on first run) | MIT | transcribe.cpp already runs GigaAM v3 (the RNNT gguf); CTC needs a gguf or sherpa-onnx; else a Python worker |
| loudnorm | 0 | — | a few lines of vDSP gain in `AudioNormalizer` before ASR |
| routing | Whisper (LID only) + both current engines | MIT + CC BY 4.0 | both engines already in transcribe.cpp; LID from WhisperKit (tiny/turbo encoder) per VAD chunk |
| silero VAD (chunking) | 2 MB | MIT | FluidAudio already ships a CoreML silero VAD |

## Dropped

- **T-one** (T-Bank, Russian telephony): its package pins numpy < 2 through pyctcdecode, GigaAM needs
  numpy ≥ 2, so it needs a separate env; it is an 8 kHz narrow-band model, throwing away the 4–7 kHz our
  call channel keeps, and Russian-only, so it cannot help the mixed calls where the baseline is worst.
- **whisper.cpp / WhisperKit** as separate rows: same weights as the MLX Whisper here, so the same
  WER; they matter only for the Swift integration (table above).
- **Forcing Parakeet's language**: Parakeet v3 has no language prompt (transcribe.cpp's language argument
  is ignored for it); the routing row is the way to "force" it per chunk.
- **Punctuation model on GigaAM CTC**: the scorer strips punctuation, so it cannot change WER.
- `docs/asr-bakeoff.md` measured only parakeet-mlx on two clean Russian voice notes: nothing to reuse for
  call audio or mixed speech.

## Notes

- Expected, to be checked: per-chunk language ID should recover the sentences Parakeet drops on
  `call_mix_4spk`; loudnorm is likely noise-level because the eval audio is already at a steady level.
