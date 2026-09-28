#!/usr/bin/env bash
# Usage: package_store_summary.sh <unsigned-store-app> <pinned-release.tar.gz> <signing-identity> [macOS-profile]
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ $# == 3 || $# == 4 ]] || { echo 'usage: package_store_summary.sh <app> <archive> <identity> [macOS-profile]' >&2; exit 2; }
APP="$1"
ARCHIVE="$2"
IDENTITY="$3"
if [[ $# == 4 ]]; then
    [[ -f "$4" && "$IDENTITY" =~ ^[[:xdigit:]]{40}$ ]] || { echo 'provisioned mode requires a profile and 40-digit identity fingerprint' >&2; exit 1; }
    PROFILE_COPY="$(mktemp)"
    PROFILE_PLIST="$(mktemp)"
    trap 'rm -f "$PROFILE_COPY" "$PROFILE_PLIST"' EXIT
    cp "$4" "$PROFILE_COPY"
    security cms -D -i "$PROFILE_COPY" > "$PROFILE_PLIST" || { echo 'profile decoding failed' >&2; exit 1; }
    swift "$ROOT/scripts/validate_store_profile.swift" "$PROFILE_PLIST" "$IDENTITY"
    echo 'Provisioned Store mode (static verification only)' >&2
else
    echo 'Ad-hoc/static mode: NOT representative of provisioned Store sandbox behavior' >&2
fi
EXPECTED=8933e736495eadfef0731ae32054acfaa75699bf4a6ccba77cd8475db085ec66
[[ -f "$APP/Contents/Info.plist" && -f "$APP/Contents/MacOS/Beseda" && ! -e "$APP/Contents/Helpers" ]] || {
    echo 'expected an unsigned assembled store app without Helpers' >&2; exit 1;
}
[[ -d "$APP/Contents/Resources/Beseda_Beseda.bundle/Resources/en.lproj" ]] || {
    echo 'store resource bundle missing from Contents/Resources' >&2; exit 1;
}
[[ -f "$APP/Contents/Resources/Beseda_Beseda.bundle/Resources/en.lproj/Menu.strings" ]] || {
    echo 'store localization missing' >&2; exit 1;
}
[[ -z "$(find "$APP" -mindepth 1 -maxdepth 1 ! -name Contents -print -quit)" ]] || {
    echo 'unsealed content in app root' >&2; exit 1;
}
[[ "$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')" == "$EXPECTED" ]] || {
    echo 'llama.cpp archive hash mismatch' >&2; exit 1;
}
# The pinned digest is the trust boundary. Still reject paths outside the single release root
# before extracting: no archive entry may write outside the temporary directory.
while IFS= read -r entry; do
    case "$entry" in
        llama-b10819|llama-b10819/|llama-b10819/*) ;;
        *) echo "unexpected archive entry: $entry" >&2; exit 1 ;;
    esac
    case "/$entry/" in */../*|*/./*) echo "unsafe archive entry: $entry" >&2; exit 1 ;; esac
done < <(tar tzf "$ARCHIVE")
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"; if [[ $# == 4 ]]; then rm -f "$PROFILE_COPY" "$PROFILE_PLIST"; fi' EXIT
tar xzf "$ARCHIVE" -C "$STAGING"
SOURCE="$(realpath "$STAGING/llama-b10819")"
[[ -f "$SOURCE/llama-server" && ! -L "$SOURCE/llama-server" ]] || {
    echo 'llama-server missing' >&2; exit 1;
}
HELPERS="$APP/Contents/Helpers"
mkdir "$HELPERS"
cp "$SOURCE/llama-server" "$HELPERS/"
for file in "$SOURCE"/*.dylib; do
    [[ -f "$file" ]] || { echo "invalid dylib: $file" >&2; exit 1; }
    if [[ -L "$file" ]]; then
        target="$(readlink "$file")"
        resolved="$(realpath "$file")" || { echo "invalid dylib: $file" >&2; exit 1; }
        [[ "$target" != /* && "$resolved" == "$SOURCE/"*.dylib && -f "$resolved" ]] || {
            echo "invalid dylib: $file" >&2; exit 1;
        }
        cp -P "$file" "$HELPERS/"
    else
        cp "$file" "$HELPERS/"
    fi
done
for file in "$HELPERS"/*.dylib; do
    [[ -f "$file" ]] || { echo "invalid dylib: $file" >&2; exit 1; }
done
/usr/libexec/PlistBuddy -c 'Add :BesedaStoreSummary bool true' "$APP/Contents/Info.plist"
for file in "$HELPERS"/*.dylib; do
    [[ -L "$file" ]] || codesign --force --sign "$IDENTITY" "$file"
done
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/scripts/store_summary.entitlements" "$HELPERS/llama-server"
if [[ $# == 4 ]]; then install -m 644 "$PROFILE_COPY" "$APP/Contents/embedded.provisionprofile"; fi
codesign --force --sign "$IDENTITY" --entitlements "$ROOT/scripts/store_summary_app.entitlements" "$APP"
codesign --verify --strict --deep "$APP"
if [[ $# == 4 ]]; then
    codesign --verify --strict "$HELPERS/llama-server"
    ENTITLEMENTS="$(mktemp)"
    trap 'rm -rf "$STAGING"; rm -f "$PROFILE_COPY" "$PROFILE_PLIST" "$ENTITLEMENTS"' EXIT
    codesign -d --entitlements :- "$APP" > "$ENTITLEMENTS" 2>/dev/null
    for key in com.apple.security.app-sandbox com.apple.security.device.audio-input com.apple.security.network.client com.apple.security.files.user-selected.read-write com.apple.security.personal-information.calendars; do
        [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$ENTITLEMENTS" 2>/dev/null)" == true ]] || { echo "signed app missing $key" >&2; exit 1; }
    done
    codesign -d --entitlements :- "$HELPERS/llama-server" > "$ENTITLEMENTS" 2>/dev/null
    for key in com.apple.security.app-sandbox com.apple.security.inherit; do
        [[ "$(/usr/libexec/PlistBuddy -c "Print :$key" "$ENTITLEMENTS" 2>/dev/null)" == true ]] || { echo "signed helper missing $key" >&2; exit 1; }
    done
fi
