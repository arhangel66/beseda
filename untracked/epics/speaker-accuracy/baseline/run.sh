#!/bin/sh
# Rerun the baseline: fetch the two speech models, run the app pipeline on the eval set, score both engines.
set -eu
cd "$(dirname "$0")"
mkdir -p models

# model file, pinned URL, sha256 (Transcription/SpeechModel.swift); the app's own model cache is reused when it matches
fetch() {
    [ -f "models/$1" ] && return
    cached="$HOME/Library/Application Support/Beseda/runtime/models/$1"
    if [ -f "$cached" ] && [ "$(shasum -a 256 "$cached" | cut -d' ' -f1)" = "$3" ]; then
        ln -s "$cached" "models/$1"
    else
        curl -fL -o "models/$1" "$2"
    fi
    [ "$(shasum -a 256 "models/$1" | cut -d' ' -f1)" = "$3" ] || { echo "sha256 mismatch: $1"; exit 1; }
}
fetch parakeet-tdt-0.6b-v3-Q4_K_M.gguf \
    https://huggingface.co/handy-computer/parakeet-tdt-0.6b-v3-gguf/resolve/85ac09ea12fc4b1112fa76810059364bc6adc9de/parakeet-tdt-0.6b-v3-Q4_K_M.gguf \
    b68557be1e3c40207fd7c4bd9d63f1d3316b963f15325bfb0cc16a8bb0ffd181
fetch gigaam-v3-e2e-rnnt-Q8_0.gguf \
    https://huggingface.co/handy-computer/gigaam-v3-e2e-rnnt-gguf/resolve/f719d70812344f4d0fb8c11c0887b190501a7465/gigaam-v3-e2e-rnnt-Q8_0.gguf \
    78d63b47723b7f8d78c6113a6ef983b5a86e2a86f6c273e1f5cb6967b1c4467a

[ -d ../data/audio ] || (cd .. && uv run make_eval.py)
swift build -c release
# other agents share this Mac: heavy model runs go one at a time
lockf /tmp/beseda-speaker-accuracy.lock .build/release/Baseline
cd .. && uv run baseline/score_baseline.py
