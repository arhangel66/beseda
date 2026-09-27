#!/usr/bin/env bash
# Shoots the BESEDA-111 states into .factory/shots/BESEDA-111/<phase>/ the BESEDA-75 way (own bundle id,
# temp home so no model is installed, hidden launch, kit window-shot.swift). Usage: shoot.sh before|after <package dir>
set -euo pipefail
PHASE="$1"
PACKAGE="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
SEED="$HERE/../BESEDA-75/seed.py"
OUT="$HERE/$PHASE"
KIT=/Users/mikhail/w/learning/ios-kit
BUNDLE_ID=dev.beseda111.beseda
APP="$(mktemp -d)/Beseda111.app"
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
# copies of the seeded calls so the store holds more than one sidebar page (200)
python3 - "$DATA/calls.sqlite" <<'PY'
import sqlite3, sys
db = sqlite3.connect(sys.argv[1])
columns = [row[1] for row in db.execute("PRAGMA table_info(calls)")]
seeded = db.execute("SELECT COUNT(*) FROM calls").fetchone()[0]
for copy in range(300 - seeded):
    picked = ", ".join(f"'extra-{copy}'" if c == "id" else f"datetime(started_at, '-{copy + 1} days')" if c == "started_at" else c for c in columns)
    db.execute(f"INSERT INTO calls ({', '.join(columns)}) SELECT {picked} FROM calls WHERE id = 'demo-1'")
db.commit()
PY

shot popover-no-model 4 BESEDA_PREVIEW_POPOVER=idle
shot sidebar-300-calls 5

defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -rf "$HOME_DIR" "$(dirname "$APP")"
ls "$OUT"
