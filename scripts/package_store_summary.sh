#!/usr/bin/env bash
# Embed the pinned llama.cpp release in an unsigned store app, then sign inside-out.
# Usage: package_store_summary.sh <app> <verified-release.tar.gz> <signing-identity>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$1"
ARCHIVE="$2"
IDENTITY="$3"
EXPECTED=8933e736495eadfef0731ae32054acfaa75699bf4a6ccba77cd8475db085ec66
ACTUAL="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
[[ "$ACTUAL" == "$EXPECTED" ]] || { echo 'llama.cpp archive hash mismatch' >&2; exit 1; }
[[ -f "$APP/Contents/Info.plist" ]] || { echo 'app bundle missing' >&2; exit 1; }
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
tar xzf "$ARCHIVE" -C "$STAGING"
SOURCE="$STAGING/llama-b10819"
[[ -f "$SOURCE/llama-server" ]] || { echo 'llama-server missing' >&2; exit 1; }
HELPERS="$APP/Contents/Helpers"
mkdir -p "$HELPERS"
cp "$SOURCE/llama-server" "$HELPERS/"
find "$SOURCE" -maxdepth 1 -type f -name '*.dylib' -exec cp {} "$HELPERS/" \;
/usr/libexec/PlistBuddy -c 'Add :BesedaStoreSummary bool true' "$APP/Contents/Info.plist"
for file in "$HELPERS"/*.dylib "$HELPERS/llama-server"; do
    codesign --force --sign "$IDENTITY" "$file"
done
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/scripts/store_summary.entitlements" "$APP/Contents/Helpers/llama-server"
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/scripts/store_summary_app.entitlements" "$APP"
codesign --verify --strict --deep "$APP"
