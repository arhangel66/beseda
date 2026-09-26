---
name: ios-kit-loop
description: Run the measured iOS edit-build-install-launch loop with private retained DerivedData and an explicit simulator or physical-device UDID.
---

# Kit loop

For an existing generated app:

```sh
cd apps/MyApp
./run.sh <explicit-simulator-udid>
```

The script is the proven loop contract: `set -euo pipefail`, app-local
`.derived-data`, generic `xcodebuild -target` compilation, `ARCHS=arm64
ONLY_ACTIVE_ARCH=YES`, `simctl install`, terminate, and launch. It does not
purge caches or choose a shared simulator. Reuse a warm device for edit-to-
screen measurements.

Measured on this Mac: retained arm64 builds were 9.32 seconds cold and
1.12/1.26 seconds warm; a warm visible edit was 7.526 seconds. Initial
creation-to-screen was 118.416 seconds with a cold private simulator. The
comparison and raw evidence are in `docs/comparisons/loop.md`.

Some explicit simulator test/setup attempts return exit 70, including on an
otherwise idle host; the root cause is unknown and is not attributed here to an
SDK/runtime mismatch or simulator contention. Generic target compilation plus
explicit `simctl` remains the measured build/run path. FAB-13's generated-app
integration and the Ledger generated check passed tests, install, launch, and
screenshot; durable logs are in `docs/evidence/skills-validation-FAB-13-generated-check.log`
and `docs/evidence/ledger-generated-check.log`. Prefer deterministic iOS 26.4
and a simulator owned by the run; do not use a shared `booted` device.

## Physical iPhone loop

Use CoreDevice directly. Supply every app- and device-specific value; do not
select the first device or use a device name that can become ambiguous.

```sh
PROJECT=/absolute/path/App.xcodeproj
SCHEME=App
TEAM=ABCDE12345
BUNDLE=com.example.app
DEVICE=00008120-000A6D9E1E84C01E # physical UDID from `details`, not "connected"
DERIVED="$PWD/.device-derived-data"
EVIDENCE="$PWD/.device-loop-evidence"
mkdir -p "$EVIDENCE"

xcrun devicectl list devices --json-output "$EVIDENCE/devices.json"
xcrun devicectl device info details --device "$DEVICE" --timeout 15 \
  --json-output "$EVIDENCE/details.json"
xcrun devicectl device info lockState --device "$DEVICE" --timeout 15 \
  --json-output "$EVIDENCE/lock.json"
```

Before modifying the phone, inspect the JSON and require one physical iPhone
whose state is connected, pairing is paired, Developer Mode is enabled, and
DDI services are available. `lockState` reports whether a passcode is required
and whether the phone has been unlocked since boot; it does not prove that the
screen is unlocked now. Ask the owner to unlock it. Treat a CoreDevice
`Locked` launch error as the definitive gate and stop rather than changing
phone settings.

Build and verify a development-signed app in caller-owned DerivedData. Automatic
signing may contact Apple's service or update a provisioning profile. Do not
add `-allowProvisioningUpdates` unless the owner explicitly permits that.

```sh
rm -rf "$DERIVED"
xcodebuild build -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Debug -sdk iphoneos -destination "id=$DEVICE" \
  -derivedDataPath "$DERIVED" DEVELOPMENT_TEAM="$TEAM" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" CODE_SIGN_STYLE=Automatic
SETTINGS="$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
  -configuration Debug -sdk iphoneos -destination "id=$DEVICE" \
  -derivedDataPath "$DERIVED" DEVELOPMENT_TEAM="$TEAM" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" CODE_SIGN_STYLE=Automatic \
  -showBuildSettings)"
APP="$(printf '%s\n' "$SETTINGS" | awk -F ' = ' \
  '/ TARGET_BUILD_DIR =/{dir=$2} / WRAPPER_NAME =/{name=$2} END{print dir "/" name}')"
test -d "$APP"
codesign --verify --deep --strict "$APP"
```

Install is an update of the same bundle identifier: it preserves the app's data.
Never uninstall, erase, reset, or inspect the data container as part of this
loop.

```sh
xcrun devicectl device install app --device "$DEVICE" --timeout 60 "$APP"
xcrun devicectl device info apps --device "$DEVICE" --bundle-id "$BUNDLE" \
  --timeout 15 --json-output "$EVIDENCE/app.json"

xcrun devicectl device process launch --device "$DEVICE" --timeout 30 \
  --json-output "$EVIDENCE/launch-1.json" "$BUNDLE"
EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Info.plist")"
xcrun devicectl device info processes --device "$DEVICE" --timeout 15 \
  --filter "executable.name == '$EXECUTABLE'" \
  --json-output "$EVIDENCE/process-1.json"
PID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["result"]["runningProcesses"][0]["processIdentifier"])' "$EVIDENCE/process-1.json")"
xcrun devicectl device process terminate --device "$DEVICE" --pid "$PID" --timeout 15
xcrun devicectl device process launch --device "$DEVICE" --timeout 30 \
  --json-output "$EVIDENCE/launch-2.json" "$BUNDLE"
xcrun devicectl device info processes --device "$DEVICE" --timeout 15 \
  --filter "executable.name == '$EXECUTABLE'" \
  --json-output "$EVIDENCE/process-2.json"
xcrun devicectl device info appIcon --device "$DEVICE" --timeout 30 \
  --app-bundle-id "$BUNDLE" --destination "$EVIDENCE/icon.png" \
  --json-output "$EVIDENCE/icon.json"
```

The two process JSON files prove terminate/relaunch only when their PIDs differ.
The generated PNG proves that the installed bundle supplies a rendered icon;
it is not a screenshot or proof that the icon is visible on the Home Screen.

For an optional bounded console sample, use the installed `gtimeout`. This
starts a fresh instance, terminates the existing instance, and interrupts the
new instance when the bound expires, so relaunch normally afterward. It captures
only output attached to the app console, not a complete unified-log history.

```sh
set +e
gtimeout --signal=INT --kill-after=3s 10s \
  xcrun devicectl device process launch --device "$DEVICE" \
  --terminate-existing --console "$BUNDLE" >"$EVIDENCE/console.log" 2>&1
status=$?
set -e
test "$status" -eq 0 || test "$status" -eq 124
xcrun devicectl device process launch --device "$DEVICE" --timeout 30 "$BUNDLE"
```

Delete only the private DerivedData and host evidence when they are no longer
needed. Leave the updated app and its data on the phone. A manual LLDB session
can use `device select "$DEVICE"` and `device process attach -p "$PID"`, but
attach, expression evaluation, and breakpoint behavior are not proved by this
loop. CoreDevice does not expose the physical accessibility tree here; AXe and
`simctl` guidance is simulator-only. Do not claim semantic UI or screenshot
proof from process or icon evidence.
