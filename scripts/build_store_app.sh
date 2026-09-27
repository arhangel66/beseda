#!/usr/bin/env bash
# Private store artifact; requires the pinned llama.cpp archive and a signing identity.
# Usage: build_store_app.sh <verified-release.tar.gz> <signing-identity>
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BESEDA_STORE=1 swift build --jobs 2 --scratch-path .build/store
APP="$ROOT/.build/Beseda-store.app"
scripts/lib/bundle_app.sh "$ROOT/.build/store/debug" "$APP" store
codesign --force --sign "$2" "$APP/Contents/Frameworks/CTranscribe.framework"
scripts/package_store_summary.sh "$APP" "$1" "$2"
echo "$APP"
