#!/usr/bin/env bash
# Builds the app and zips it for another Mac: dist/Podushka-<version>.zip.
# ditto keeps the signature and resource forks that a plain zip would drop.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$("$ROOT/scripts/build_podushka_app.sh" | tail -n 1)"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
DIST="$ROOT/dist"
ZIP="$DIST/Podushka-$VERSION.zip"

mkdir -p "$DIST"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
codesign --verify --strict --deep "$APP"
ls -lh "$ZIP"
