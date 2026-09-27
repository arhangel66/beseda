#!/usr/bin/env bash
# Builds an isolated Beseda copy for screenshots from this checkout's own .build
# (incremental after the check) and launches it hidden, with a fresh home and its own
# bundle id, so it never touches /Applications/Beseda.app or its data. CFFIXED_USER_HOME does not
# isolate cfprefsd, so each run gets a random bundle id (its own defaults domain), deleted when the copy quits.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/.build/Beseda-shot.app"

nice -n 19 swift build --jobs 2 --package-path "$ROOT" --product Beseda
"$ROOT/scripts/lib/bundle_app.sh" "$(swift build --package-path "$ROOT" --show-bin-path)" "$APP_DIR" screenshot
BUNDLE_ID="app.beseda.shot.$(uuidgen | tr -d - | tr 'A-Z' 'a-z')"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP_DIR/Contents/Info.plist"
codesign --force --timestamp=none --sign - --entitlements "$ROOT/scripts/Beseda.entitlements" "$APP_DIR"
( open -W -n -g -j --env CFFIXED_USER_HOME="$(mktemp -d)" "$APP_DIR"; defaults delete "$BUNDLE_ID" ) >/dev/null 2>&1 &
# wait for the launch before the next run re-bundles the same .app
sleep 2
echo "$APP_DIR"
