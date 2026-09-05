#!/usr/bin/env bash
# Assembles and signs Podushka.app from a SwiftPM bin dir.
# Usage: bundle_app.sh <bin-dir> <app-dir> [release]
# Only a release bundle gets the Sparkle keys: a dev build with a feed URL would
# replace itself with the published version at the next scheduled check.
set -euo pipefail

BIN_DIR="$1"
APP_DIR="$2"
FLAVOR="${3:-dev}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

SU_FEED_URL="https://raw.githubusercontent.com/arhangel66/podushka/main/appcast.xml"
SU_PUBLIC_ED_KEY="tR1eNuK7eLy8yy+rAC+mXLGoQqNlwbj1dXktcF5C64U="

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/Podushka" "$APP_DIR/Contents/MacOS/Podushka"
cp "$ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
PLIST="$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
# Sparkle orders updates by CFBundleVersion, so it has to differ between any two builds
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$PLIST"

if [ "$FLAVOR" = "release" ]; then
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string $SU_FEED_URL" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SU_PUBLIC_ED_KEY" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool true" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 3600" "$PLIST"
fi

# the speech engine and Sparkle ship as dynamic frameworks the binary loads through @rpath
mkdir -p "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources/licenses"
cp -R "$BIN_DIR/CTranscribe.framework" "$APP_DIR/Contents/Frameworks/"
cp -R "$BIN_DIR/Sparkle.framework" "$APP_DIR/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/Podushka"
cp "$ROOT/Vendor/TranscribeCpp/LICENSE" "$APP_DIR/Contents/Resources/licenses/transcribe-cpp-LICENSE-MIT"
cp "$ROOT/.build/artifacts/sparkle/Sparkle/LICENSE" "$APP_DIR/Contents/Resources/licenses/sparkle-LICENSE"
# actool turns the Icon Composer source into both the macOS 26 icon (Assets.car) and the
# plain AppIcon.icns older systems fall back to
xcrun actool "$ROOT/Resources/AppIcon.icon" --compile "$APP_DIR/Contents/Resources" \
    --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
    --output-partial-info-plist "$ROOT/.build/appicon-partial.plist" > /dev/null

IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -n 1)"
if [ -z "$IDENTITY" ]; then
    echo "no Apple Development signing identity in the keychain; run 'security find-identity -v -p codesigning'" >&2
    exit 1
fi

# no --options runtime and no entitlements: the hardened runtime would demand
# com.apple.security.device.audio-input and silently kill microphone capture.
# --deep also signs Sparkle's nested Autoupdate, Updater.app and XPC services.
codesign --force --deep --sign "$IDENTITY" "$APP_DIR"
codesign --verify --strict --deep "$APP_DIR"
