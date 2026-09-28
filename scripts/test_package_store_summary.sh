#!/usr/bin/env bash
# Private fixtures only: no app launch, signing identity or downloaded executable.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/src/llama-b10819" "$TMP/Store.app/Contents/MacOS"
printf 'stub app\n' > "$TMP/Store.app/Contents/MacOS/Beseda"
mkdir -p "$TMP/Store.app/Contents/Resources/Beseda_Beseda.bundle/Resources/en.lproj"
printf 'stub strings\n' > "$TMP/Store.app/Contents/Resources/Beseda_Beseda.bundle/Resources/en.lproj/Menu.strings"
printf '#!/bin/sh\nexit 0\n' > "$TMP/src/llama-b10819/llama-server"
printf 'stub dylib\n' > "$TMP/src/llama-b10819/libllama.dylib"
printf 'second dylib\n' > "$TMP/src/llama-b10819/libggml.0.23.dylib"
ln -s libggml.0.23.dylib "$TMP/src/llama-b10819/libggml.0.dylib"
printf 'unused tool\n' > "$TMP/src/llama-b10819/llama-cli"
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
touch "$TMP/Store.app/stray"
if bash "$ROOT/scripts/package_store_summary.sh" "$TMP/Store.app" "$TMP/archive.tar.gz" stub >"$TMP/error" 2>&1; then
    echo 'stray root content accepted' >&2; exit 1
fi
grep -q 'unsealed content' "$TMP/error"
rm "$TMP/Store.app/stray"
mv "$TMP/Store.app/Contents/Resources/Beseda_Beseda.bundle" "$TMP/Store.app/Contents/Resources/moved"
if bash "$ROOT/scripts/package_store_summary.sh" "$TMP/Store.app" "$TMP/archive.tar.gz" stub >"$TMP/error" 2>&1; then
    echo 'missing resource bundle accepted' >&2; exit 1
fi
grep -q 'resource bundle missing' "$TMP/error"
mv "$TMP/Store.app/Contents/Resources/moved" "$TMP/Store.app/Contents/Resources/Beseda_Beseda.bundle"
printf '#!/bin/sh\necho "8933e736495eadfef0731ae32054acfaa75699bf4a6ccba77cd8475db085ec66  $3"\n' > "$TMP/bin/shasum"
chmod +x "$TMP/bin/shasum"
bash "$ROOT/scripts/package_store_summary.sh" "$TMP/Store.app" "$TMP/archive.tar.gz" stub
cmp "$TMP/src/llama-b10819/llama-server" "$TMP/Store.app/Contents/Helpers/llama-server"
cmp "$TMP/src/llama-b10819/libllama.dylib" "$TMP/Store.app/Contents/Helpers/libllama.dylib"
test "$(readlink "$TMP/Store.app/Contents/Helpers/libggml.0.dylib")" = libggml.0.23.dylib
cmp "$TMP/src/llama-b10819/libggml.0.23.dylib" "$TMP/Store.app/Contents/Helpers/libggml.0.23.dylib"
test "$(find "$TMP/Store.app/Contents/Helpers" -type f | wc -l | tr -d ' ')" = 3
! test -e "$TMP/Store.app/Contents/Helpers/llama-cli"
test "$(/usr/libexec/PlistBuddy -c 'Print :BesedaStoreSummary' "$TMP/Store.app/Contents/Info.plist")" = true
test "$(wc -l < "$SIGN_LOG" | tr -d ' ')" = 5
test "$(head -n 2 "$SIGN_LOG" | grep -c -- '--entitlements')" = 0
test "$(head -n 2 "$SIGN_LOG" | grep -c -- '.dylib$')" = 2
test "$(tail -n 3 "$SIGN_LOG" | head -n 1)" = "--force --sign stub --entitlements $ROOT/scripts/store_summary.entitlements $TMP/Store.app/Contents/Helpers/llama-server"
test "$(tail -n 2 "$SIGN_LOG" | head -n 1)" = "--force --sign stub --entitlements $ROOT/scripts/store_summary_app.entitlements $TMP/Store.app"
grep -F -- "--entitlements $ROOT/scripts/store_summary.entitlements $TMP/Store.app/Contents/Helpers/llama-server" "$SIGN_LOG"
grep -F -- "--entitlements $ROOT/scripts/store_summary_app.entitlements $TMP/Store.app" "$SIGN_LOG"
grep -F -- "--verify --strict --deep $TMP/Store.app" "$SIGN_LOG"
test ! -e "$TMP/Store.app/Contents/Resources/runtime/llama/llama-server"
# Synthetic CMS payload with documented macOS profile keys; no real identity or Keychain access.
python3 - "$TMP" <<'PY'
import datetime, hashlib, pathlib, plistlib, sys
p = pathlib.Path(sys.argv[1]); cert = b'fixture certificate'
(p/'identity').write_text(hashlib.sha1(cert).hexdigest().upper())
profile = dict(TeamIdentifier=['TEAM'], Platform=['OSX'],
    ExpirationDate=datetime.datetime(2099, 1, 1), DeveloperCertificates=[cert],
    Entitlements={'application-identifier':'TEAM.app.beseda.Beseda'})
(p/'profile').write_bytes(plistlib.dumps(profile))
profile['ExpirationDate'] = datetime.datetime(2000, 1, 1)
(p/'expired').write_bytes(plistlib.dumps(profile))
PY
printf '#!/bin/sh\ncat "$PROFILE_FIXTURE"\nif [ -n "${MUTATE_PROFILE:-}" ]; then cp "$MUTATE_PROFILE" "$ORIGINAL_PROFILE"; fi\n' > "$TMP/bin/security"
# Return the same entitlement plist that a signature made with the requested file would expose.
printf '#!/bin/bash\nif [[ "$1" == -d ]]; then\n  if [[ "$*" == *llama-server* ]]; then cp "$HELPER_ENTITLEMENTS" /dev/stdout; else cp "$APP_ENTITLEMENTS" /dev/stdout; fi\nelse echo "$*" >> "$SIGN_LOG"; fi\n' > "$TMP/bin/codesign"
chmod +x "$TMP/bin/security" "$TMP/bin/codesign"
export APP_ENTITLEMENTS="$ROOT/scripts/store_summary_app.entitlements"
export HELPER_ENTITLEMENTS="$ROOT/scripts/store_summary.entitlements"
identity="$(< "$TMP/identity")"
rm -rf "$TMP/Store.app/Contents/Helpers"
if PROFILE_FIXTURE="$TMP/expired" bash "$ROOT/scripts/package_store_summary.sh" "$TMP/Store.app" "$TMP/archive.tar.gz" "$identity" "$TMP/expired" >"$TMP/error" 2>&1; then
    echo 'expired profile accepted for packaging' >&2; exit 1
fi
grep -q 'invalid macOS provisioning profile' "$TMP/error"
test ! -e "$TMP/Store.app/Contents/embedded.provisionprofile"
/usr/libexec/PlistBuddy -c 'Delete :BesedaStoreSummary' "$TMP/Store.app/Contents/Info.plist"
cp "$TMP/profile" "$TMP/original-profile"
PROFILE_FIXTURE="$TMP/profile" MUTATE_PROFILE="$TMP/expired" ORIGINAL_PROFILE="$TMP/original-profile" bash "$ROOT/scripts/package_store_summary.sh" "$TMP/Store.app" "$TMP/archive.tar.gz" "$identity" "$TMP/original-profile"
cmp "$TMP/profile" "$TMP/Store.app/Contents/embedded.provisionprofile"
cmp "$TMP/expired" "$TMP/original-profile"
test "$(stat -f %Lp "$TMP/Store.app/Contents/embedded.provisionprofile")" = 644
grep -F -- "--verify --strict --deep $TMP/Store.app" "$SIGN_LOG"
grep -F -- "--verify --strict $TMP/Store.app/Contents/Helpers/llama-server" "$SIGN_LOG"
for target in ../outside.dylib missing.dylib /tmp/outside.dylib; do
    rm -rf "$TMP/Store.app/Contents/Helpers"
    ln -sfn "$target" "$TMP/src/llama-b10819/libggml.0.dylib"
    tar czf "$TMP/archive.tar.gz" -C "$TMP/src" llama-b10819
    if bash "$ROOT/scripts/package_store_summary.sh" "$TMP/Store.app" "$TMP/archive.tar.gz" stub >"$TMP/error" 2>&1; then
        echo "unsafe link accepted: $target" >&2; exit 1
    fi
    grep -q 'invalid dylib' "$TMP/error"
done
echo 'store summary packaging stub passed'
