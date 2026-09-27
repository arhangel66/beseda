#!/usr/bin/env bash
# Private fixtures only: no app launch, signing identity or downloaded executable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/src/llama-b10819" "$TMP/Store.app/Contents"
printf '#!/bin/sh\nexit 0\n' > "$TMP/src/llama-b10819/llama-server"
printf 'stub dylib\n' > "$TMP/src/llama-b10819/libllama.dylib"
tar czf "$TMP/archive.tar.gz" -C "$TMP/src" llama-b10819
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' '<plist version="1.0"><dict/></plist>' > "$TMP/Store.app/Contents/Info.plist"
printf '#!/bin/sh\necho "$*" >> "$SIGN_LOG"\n' > "$TMP/bin/codesign"
chmod +x "$TMP/bin/codesign"
export SIGN_LOG="$TMP/sign.log"
export PATH="$TMP/bin:$PATH"
if bash "$ROOT/scripts/package_store_summary.sh" "$TMP/Store.app" "$TMP/archive.tar.gz" stub >"$TMP/error" 2>&1; then
    echo 'untrusted archive was accepted' >&2; exit 1
fi
grep -q 'archive hash mismatch' "$TMP/error"
test ! -e "$TMP/Store.app/Contents/Helpers/llama-server"
# Only the digest command is stubbed for the happy path; the real rejection above guards the boundary.
printf '#!/bin/sh\necho "8933e736495eadfef0731ae32054acfaa75699bf4a6ccba77cd8475db085ec66  $3"\n' > "$TMP/bin/shasum"
chmod +x "$TMP/bin/shasum"
bash "$ROOT/scripts/package_store_summary.sh" "$TMP/Store.app" "$TMP/archive.tar.gz" stub
cmp "$TMP/src/llama-b10819/llama-server" "$TMP/Store.app/Contents/Helpers/llama-server"
cmp "$TMP/src/llama-b10819/libllama.dylib" "$TMP/Store.app/Contents/Helpers/libllama.dylib"
test "$(/usr/libexec/PlistBuddy -c 'Print :BesedaStoreSummary' "$TMP/Store.app/Contents/Info.plist")" = true
grep -F -- "--entitlements $ROOT/scripts/store_summary.entitlements $TMP/Store.app/Contents/Helpers/llama-server" "$SIGN_LOG"
grep -F -- "--entitlements $ROOT/scripts/store_summary_app.entitlements $TMP/Store.app" "$SIGN_LOG"
grep -F -- "--verify --strict --deep $TMP/Store.app" "$SIGN_LOG"
test ! -e "$TMP/Store.app/Contents/Resources/runtime/llama/llama-server"
echo 'store summary packaging stub passed'
