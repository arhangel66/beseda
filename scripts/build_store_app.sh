#!/usr/bin/env bash
# Private store artifact; requires the pinned llama.cpp archive and a signing identity.
# Usage: build_store_app.sh <verified-release.tar.gz> <signing-identity> [macOS-profile]
set -euo pipefail
[[ $# == 2 || $# == 3 ]] || { echo 'usage: build_store_app.sh <archive> <identity> [macOS-profile]' >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ $# == 3 ]]; then
    [[ -f "$3" && "$2" =~ ^[[:xdigit:]]{40}$ ]] || { echo 'profile and identity fingerprint required' >&2; exit 1; }
    PROFILE_PLIST="$(mktemp)"
    trap 'rm -f "$PROFILE_PLIST"' EXIT
    security cms -D -i "$3" > "$PROFILE_PLIST"
    swift scripts/validate_store_profile.swift "$PROFILE_PLIST" "$2"
fi
BESEDA_STORE=1 swift build --jobs 2 --scratch-path .build/store
APP="$ROOT/.build/Beseda-store.app"
scripts/lib/bundle_app.sh "$ROOT/.build/store/debug" "$APP" store
codesign --force --sign "$2" "$APP/Contents/Frameworks/CTranscribe.framework"
bash scripts/package_store_summary.sh "$APP" "$@"
echo "$APP"
