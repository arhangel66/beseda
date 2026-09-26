#!/usr/bin/env bash
# Shoots every Beseda screen into .factory/shots/BESEDA-75/<phase>/ from an isolated copy:
# own bundle id, temp home, hidden launch (open -n -g -j), kit window-shot.swift. Usage: shoot.sh before|after
set -euo pipefail
PHASE="$1"
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HERE="$ROOT/.factory/shots/BESEDA-75"
OUT="$HERE/$PHASE"
KIT=/Users/mikhail/w/learning/ios-kit
BUNDLE_ID=dev.beseda75.beseda
APP="$(mktemp -d)/Beseda75.app"
BIN_DIR="$(swift build --package-path "$ROOT" --show-bin-path)"
"$ROOT/scripts/lib/bundle_app.sh" "$BIN_DIR" "$APP" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force --deep --sign "$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -n 1)" "$APP" 2>/dev/null
HOME_DIR="$(mktemp -d)"
DATA="$HOME_DIR/Library/Application Support/Beseda"
rm -rf "$OUT"; mkdir -p "$OUT"

defaults_reset() {
    defaults delete "$BUNDLE_ID" 2>/dev/null || true
    defaults write "$BUNDLE_ID" beseda.onboardingDone -bool "${1:-true}"
    defaults write "$BUNDLE_ID" beseda.calendarEnabled -bool false
    defaults write "$BUNDLE_ID" beseda.autoDetectEnabled -bool true
    defaults write "$BUNDLE_ID" beseda.webhookEnabled -bool false
    defaults write "$BUNDLE_ID" beseda.summaryProvider -string openRouter
    defaults write "$BUNDLE_ID" beseda.classifyLocally -bool false
}

# shot <name> <seconds> [ENV=value...]: launches, waits, shoots every window, quits
shot() {
    local name="$1" wait="$2"; shift 2
    local envs=(--env CFFIXED_USER_HOME="$HOME_DIR")
    for pair in "$@"; do envs+=(--env "$pair"); done
    open -n -g -j "${envs[@]}" "$APP"
    sleep "$wait"
    local pid; pid="$(pgrep -f "$APP/Contents/MacOS/Beseda" | head -n 1)"
    "$KIT/scripts/window-shot.swift" "$pid" "$OUT" "$name" || true
    kill "$pid"; sleep 1
}

defaults_reset true
# the first launch creates the index; the seed fills it
shot warmup 4
rm -f "$OUT"/warmup*
python3 "$HERE/seed.py" "$DATA/calls.sqlite" "$DATA/calls"

shot popover-idle 4 BESEDA_PREVIEW_POPOVER=idle
shot popover-recording 4 BESEDA_PREVIEW_POPOVER=live
shot popover-processing 4 BESEDA_PREVIEW_POPOVER=processing
shot popover-warning 4 BESEDA_PREVIEW_POPOVER=warning
shot call-summary 5 BESEDA_PREVIEW_CALL=demo-1
shot call-transcript 5 BESEDA_PREVIEW_CALL=demo-2
shot delete-dialog 5 BESEDA_PREVIEW_CALL=demo-2 BESEDA_PREVIEW_DELETE=1
for section in general recording processing storage integrations; do
    shot "settings-$section" 5 BESEDA_PREVIEW_SETTINGS=$section
done
defaults_reset false
for step in 1 2 3 4; do
    shot "onboarding-$step" 4 BESEDA_PREVIEW_ONBOARDING=$step
    defaults write "$BUNDLE_ID" beseda.onboardingDone -bool false
done

defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -rf "$HOME_DIR" "$(dirname "$APP")"
# the conversations window opens at every launch; only the call shots need it
find "$OUT" -name '*-разговоры.png' ! -name 'call-*' ! -name 'delete-*' -delete
ls "$OUT"
