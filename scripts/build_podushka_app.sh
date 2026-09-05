#!/usr/bin/env bash
# Dev loop: debug build, install into ~/Applications, relaunch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pkill -x Podushka 2>/dev/null || true
sleep 0.2

swift build --package-path "$ROOT" --product Podushka

BIN_DIR="$(swift build --package-path "$ROOT" --show-bin-path)"
APP_DIR="$ROOT/.build/Podushka.app"
INSTALL_DIR="$HOME/Applications/Podushka.app"

"$ROOT/scripts/lib/bundle_app.sh" "$BIN_DIR" "$APP_DIR"
codesign -dv --verbose=2 "$APP_DIR"

# never leave a second bundle with the same CFBundleIdentifier on disk:
# LaunchServices and SMAppService could resolve to the stale .build copy
rm -rf "$INSTALL_DIR"
mkdir -p "$HOME/Applications"
mv "$APP_DIR" "$INSTALL_DIR"

# the script killed a possibly running instance at the start; leave it running again
open "$INSTALL_DIR"

echo "$INSTALL_DIR"
