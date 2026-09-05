#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPIKE_DIR="$ROOT/spikes/CaptureSpike"

swift build --package-path "$SPIKE_DIR"

BIN_DIR="$(swift build --package-path "$SPIKE_DIR" --show-bin-path)"
APP_DIR="$SPIKE_DIR/.build/CaptureSpike.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/CaptureSpike" "$APP_DIR/Contents/MacOS/CaptureSpike"
cp "$SPIKE_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

echo "$APP_DIR"

