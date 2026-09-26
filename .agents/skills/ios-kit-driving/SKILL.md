---
name: ios-kit-driving
description: Drive and verify the kit's expense journey with AXe or XCUITest using an explicit simulator UDID and semantic accessibility anchors.
---

# Kit UI driving

**Someone works on this Mac.** Never activate an app, never open Simulator.app (`xcrun simctl boot`,
`simctl io`, XCUITest are all headless), launch Mac apps with `open -g -j`, and keep simulator audio off
the speakers (`scripts/silence-simulators.sh`). See `docs/headless.md` in the kit.

AXe 1.5.2 was the measured shell-driver winner on the earlier Xcode setup.
With Xcode 26.6 on 2026-09-21 it failed before reading the UI because its
private `SimulatorKit` dependency had no compatible architecture. Treat AXe as
unavailable on this setup until an updated release passes a fresh probe. The
retained, bounded recipe is:

```sh
scripts/driving/axe-add-expense.sh <explicit-udid> <evidence-directory>
```

The script builds privately, installs and launches the baseline, retries the
initial accessibility read for up to 30 seconds, taps `expense.add`, fills
`expense.title` and `expense.amount`, reads the final tree, and verifies
`Lunch` plus the localized amount. It uses separate commands and fresh reads;
AXe batch lost the sheet's Save element after typing.

The Save fallback `axe tap -x 360 -y 112` is verified **only on the tested
iPhone 17 Pro**. It is non-portable because Save is absent from that sheet's
AX tree. Prefer semantic IDs in future Ledger UI and do not generalize that
coordinate.

For structural assertions, use the installed-runtime XCUITest path:

```sh
scripts/driving/xcuitest-add-expense.sh <explicit-udid> <evidence-directory>
```

That recipe passed on iOS 26.5 with Xcode 26.6 on 2026-09-21 (one UI test,
12.965 seconds; 28.369-second test operation). It bounds xcodebuild to 300
seconds and screenshot capture to 30 seconds. iOS 26.2 and 26.4 also have
earlier green evidence on this host. Intermittent exit 70 setup failures have
occurred even when the host was otherwise idle; their root cause is unknown and
is not attributed to an SDK/runtime mismatch. `simctl` alone can install,
launch, and screenshot but cannot tap, type, inspect accessibility, or assert
visible text. The full comparison and evidence are in
`docs/comparisons/driving.md`.

## System interruption boundary

Do not infer that a system interruption is gone because an app element exists,
has its expected label, or reports `isHittable`. After HealthKit first-use UI,
XCTest has returned a stale app element whose synthesized hit point was
`{-1, -1}` even after the element was reacquired. An interruption monitor also
has no public completion signal, and XCTest requires another interaction to
invoke it.

A deterministic helper must observe a specific semantic element on the actual
system surface, act on that element, wait for that same surface to disappear,
then query the app control again. Use this sequence only when the system surface
and its stable semantic element are exposed to XCTest. Do not replace a missing
system observable with coordinates, a generic app tap, a sleep, or an action
retry: those can dismiss or outwait an unknown surface while hiding the
assertion being tested.

HealthKit first-use UI on iOS 26.5 did not expose a stable surface through the
app or SpringBoard queries in the investigated ordered-suite failure. The kit
therefore has no proven general HealthKit interruption helper. Isolate or
pre-authorize that permission outside the behavior assertion only when the test
contract permits it; otherwise retain the failing assertion and report the
platform automation limitation. See
`docs/evidence/healthkit-interruption-lifecycle-2026-09-21.md`.

## System banners in evidence screenshots

iOS 26 simulators post a «Ready for Apple Intelligence» notification from
Settings at an unpredictable time after boot; it has landed over an app title
in committed evidence. No `simctl` switch turns it off, and a fresh simulator
often shows nothing for minutes (2026-09-24, iOS 26 runtime, iPhone 16e). Take
evidence on a freshly created simulator, then open every captured PNG and
retake any with a banner, alert or keyboard over the app. Do not crop or
sleep it away: a retake is the only clean shot.

## 9:41 status bar for store screenshots

The simulator inherits the Mac's region and 24-hour clock, which render
`--time "9:41"` as «09:41»; both defaults need a reboot to take effect
(proved in WholeBook `scripts/store-screenshots.sh`; `docs/evidence/fab122-status-bar-941.png`). On a booted `$UDID`:

```bash
xcrun simctl spawn "$UDID" defaults write -g AppleLocale en_US
xcrun simctl spawn "$UDID" defaults write -g AppleICUForce24HourTime -bool false
xcrun simctl shutdown "$UDID" && xcrun simctl boot "$UDID" && xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState discharging --batteryLevel 100 --cellularBars 4 --wifiBars 3
```

## Mockup vs app side-by-side

Compare a screen with its mockup in one command instead of composing PNGs by hand:

```bash
scripts/compare-shot.swift design/reference/library.png shot.png compare.png --crop 54,92,672,1504
```

Mockup left, app right, both scaled to 390 pt at 2x, a label over each half (`--labels "mockup|app"`).
`--crop x,y,w,h` (reference pixels, top-left origin) cuts the phone frame off the mockup.

## Recording simulator audio

The kit's `check.sh` and `run.sh` already route the simulator's own output to BlackHole
(`scripts/silence-simulators.sh`); the Mac's output device is never touched. Record BlackHole with the kit recorder. Never `ffmpeg -f avfoundation`: its capture adds clicks on a 256-sample grid
that are not in the app (proved in WholeBook FAB-81).

```bash
scripts/silence-simulators.sh "$UDID"            # after every boot; never switch the Mac's output
swiftc scripts/record-blackhole.swift -o /tmp/rec && /tmp/rec 25 out.caf   # lossless, default input untouched
python3 scripts/find-clicks.py out.caf           # needs ffmpeg and numpy
```

`find-clicks.py` prints isolated clicks with their times and the 256-grid ratio. A clean voice gives a few
hits in 25 s (plosives) and grid ≈ 1.1×; a capture artefact gives dozens of hits and grid 1.6× or more.
Judge a crackle report only on a recording made this way.
