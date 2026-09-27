#!/usr/bin/env bash
# Installs the LaunchAgent that runs scripts/nightly_check.sh at 03:30.
# Uninstall: launchctl bootout gui/$(id -u)/app.beseda.nightly-check
#            rm ~/Library/LaunchAgents/app.beseda.nightly-check.plist
set -euo pipefail

LABEL="app.beseda.nightly-check"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT="/Users/mikhail/w/learning/beseda/scripts/nightly_check.sh"
BB_DIR="$(dirname "$(command -v bb)")"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$LABEL</string>
    <key>ProgramArguments</key><array><string>/bin/bash</string><string>$SCRIPT</string></array>
    <key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>30</integer></dict>
    <key>EnvironmentVariables</key><dict><key>PATH</key><string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$BB_DIR</string></dict>
    <key>Nice</key><integer>19</integer>
    <key>LowPriorityIO</key><true/>
    <key>ProcessType</key><string>Background</string>
    <key>StandardOutPath</key><string>$HOME/Library/Logs/beseda-nightly-check.log</string>
    <key>StandardErrorPath</key><string>$HOME/Library/Logs/beseda-nightly-check.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "loaded $LABEL"
