#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPIKE_DIR="$ROOT/spikes/CallDetectSpike"
BIN="$SPIKE_DIR/.build/CallDetectSpike"

mkdir -p "$SPIKE_DIR/.build"
swiftc -O -target arm64-apple-macos14.2 -framework CoreAudio -o "$BIN" "$SPIKE_DIR/main.swift"

echo "$BIN"
