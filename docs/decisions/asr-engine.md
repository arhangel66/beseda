---
type: Decision Record
title: ASR engine: transcribe.cpp with Parakeet or GigaAM
status: accepted
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
---

# ASR engine: transcribe.cpp with Parakeet or GigaAM

**Status: accepted** (2026-09-05). Supersedes the 2026-05-10 choice of `parakeet-mlx`.

## Context
The [ASR bakeoff](../archive/asr-bakeoff.md) picked `parakeet-mlx` with `parakeet-tdt-0.6b-v3` in a Python
sidecar: good Russian on two voice notes, sentence timestamps, faster than real time. The
[speech model choice plan](../archive/speech-model-choice-plan.md) measured transcribe.cpp on three real
call excerpts and found:
- Q4_K_M Parakeet drifts 2.9–6.8% from F16 with no systematic loss: 485 MB instead of 2.51 GB.
- GigaAM v3 (261 MB) is a usable Russian model when fed ≤20 s chunks, but silently drops audio on long
  input and cannot write Latin script (`SSH` → `сей`).
- GigaAM has no MLX port; `parakeet-mlx` 0.5.1 cannot load quantized weights; the Python/`uv` stage broke the
  clean-machine install with an unparseable progress.

## Decision
Replace the Python/MLX path with transcribe.cpp through its Swift bindings, and let the user pick the model:
Parakeet (default for mixed and technical speech) or GigaAM (Russian without English jargon). Rejected:
patching `parakeet-mlx` for quantization — it saves disk and nothing else.

## Consequences
- No Python, `uv` or venv; disk drops from 3.6 GB to one model file.
- GigaAM input must be split into short chunks by the app.
- transcribe.cpp gives Parakeet one segment per file, so sentences are rebuilt from word timestamps
  (`Transcription/SentenceBuilder.swift`).
