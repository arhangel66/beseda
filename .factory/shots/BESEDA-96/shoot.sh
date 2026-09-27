#!/usr/bin/env bash
# Shoots the BESEDA-96 states into .factory/shots/BESEDA-96/<phase>/ the BESEDA-75 way (own bundle id,
# temp home so no model is installed, hidden launch, kit window-shot.swift). Usage: shoot.sh before|after <package dir>
set -euo pipefail
PHASE="$1"
PACKAGE="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
SEED="$HERE/../BESEDA-75/seed.py"
OUT="$HERE/$PHASE"
KIT=/Users/mikhail/w/learning/ios-kit
BUNDLE_ID=dev.beseda96.beseda
APP="$(mktemp -d)/Beseda96.app"
BIN_DIR="$(swift build --package-path "$PACKAGE" --show-bin-path)"
"$PACKAGE/scripts/lib/bundle_app.sh" "$BIN_DIR" "$APP" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
codesign --force --deep --sign "$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development: .*\)"/\1/p' | head -n 1)" "$APP" 2>/dev/null
HOME_DIR="$(mktemp -d)"
DATA="$HOME_DIR/Library/Application Support/Beseda"
rm -rf "$OUT"; mkdir -p "$OUT"

defaults delete "$BUNDLE_ID" 2>/dev/null || true
defaults write "$BUNDLE_ID" beseda.onboardingDone -bool true
defaults write "$BUNDLE_ID" beseda.calendarEnabled -bool false
defaults write "$BUNDLE_ID" beseda.autoDetectEnabled -bool true
defaults write "$BUNDLE_ID" beseda.webhookEnabled -bool false
defaults write "$BUNDLE_ID" beseda.classifyLocally -bool false
defaults write "$BUNDLE_ID" beseda.summaryProvider -string openrouter

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

shot warmup 4
rm -f "$OUT"/warmup*
python3 "$SEED" "$DATA/calls.sqlite" "$DATA/calls"
# a custom prompt's result that happens to have «Открытые вопросы» (item 6)
sqlite3 "$DATA/calls.sqlite" "UPDATE calls SET summary_text = '**Настроение**
Спокойное, без спешки.

**Темы**
— релиз 0.6
— нагрузка на команду
— обучение новичков
— ревью кода

**Открытые вопросы**
— Чистить ли исходное аудио сразу после расшифровки.' WHERE id = 'demo-4'"

shot popover-no-model 4 BESEDA_PREVIEW_POPOVER=idle
shot settings-processing-no-model 5 BESEDA_PREVIEW_SETTINGS=processing
shot previous-call-collapsed 5 BESEDA_PREVIEW_CALL=demo-1
shot previous-call-whole 5 BESEDA_PREVIEW_CALL=demo-1 BESEDA_PREVIEW_WHOLE_SUMMARY=1
defaults write "$BUNDLE_ID" beseda.localOnly -bool true
shot settings-processing-local-only 5 BESEDA_PREVIEW_SETTINGS=processing

defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -rf "$HOME_DIR" "$(dirname "$APP")"
find "$OUT" -name '*-разговоры.png' ! -name 'previous-*' -delete
ls "$OUT"
