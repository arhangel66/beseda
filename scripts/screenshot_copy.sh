#!/usr/bin/env bash
# Builds an isolated Beseda copy for screenshots from this checkout's own .build
# (incremental after the check) and launches it hidden, with a fresh home and its own
# bundle id, so it never touches /Applications/Beseda.app or its data.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/.build/Beseda-shot.app"

nice -n 19 swift build --jobs 2 --package-path "$ROOT" --product Beseda
"$ROOT/scripts/lib/bundle_app.sh" "$(swift build --package-path "$ROOT" --show-bin-path)" "$APP_DIR"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.beseda.shot" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - --entitlements "$ROOT/scripts/Beseda.entitlements" "$APP_DIR"
open -n -g -j --env CFFIXED_USER_HOME="$(mktemp -d)" "$APP_DIR"
echo "$APP_DIR"
