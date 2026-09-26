---
name: ios-kit-starter
description: Generate a standalone iOS app from this kit, then run its explicit-UDID build and test contracts.
---

# Kit starter

**Someone works on this Mac.** Never activate an app, never open Simulator.app (`xcrun simctl boot`,
`simctl io`, XCUITest are all headless), launch Mac apps with `open -g -j`, and keep simulator audio off
the speakers (`scripts/silence-simulators.sh`). See `docs/headless.md` in the kit.

Use the repository generator from its root:

```sh
./new-app.sh MyApp apps/MyApp
cd apps/MyApp
./check.sh
./run.sh <explicit-simulator-udid>
```

`new-app.sh` refuses an existing destination, requires XcodeGen, renders
relative source paths and project settings, and creates `project.yml`, the
Xcode project, `run.sh`, and `check.sh`. XcodeGen 2.46.0 is the measured
winner for this kit; its fresh generation-to-visible-launch repeat was
100.003 seconds. The complete comparison is `docs/comparisons/generation.md`.

`run.sh` accepts an explicit UDID; create and own that simulator for a run.
Do not use `booted` in reusable recipes. `run.sh` retains `.derived-data`,
builds the generic simulator target with arm64-only flags on this Mac,
installs, and launches by bundle ID. `check.sh` does not accept a caller UDID:
it creates its own explicit-UDID simulator, uses that same ID for tests and
for installing the `.app` the test build made (no second build through `run.sh`), verifies the built app contains generated `UILaunchScreen` metadata,
captures a screenshot, then shuts down and deletes the device. Its xcodebuild
test phase is bounded to 1800 seconds by default; set
`IOS_KIT_TEST_TIMEOUT_SECONDS` to a positive integer from 1 through 3600 for a
suite-specific bound. Invalid values fail before simulator setup, timeouts
return status 124, and raw logs are retained. Only the existing bounded
exit-70 destination setup retry is eligible for retry; test assertions and
other failures are not retried. Generated apps include a representative asset
catalog; the check requires an installed simulator runtime matching the active
SDK and prints `DEVELOPER_DIR`/runtime remediation when it is absent.

The current host's Xcode 26.6 reports an iOS 26.5 SDK while installed runtimes
are 26.2 and 26.4. The official runtime download reports iOS 26.5 is unavailable,
so the current asset-enabled check is blocked until a matching runtime or Xcode
is selected. The earlier FAB-13 no-asset generated check passed its unit/UI and
run/launch integration in 86 seconds; its raw output and launch screen remain
in `docs/evidence/skills-validation-FAB-13-generated-check.log` and
`docs/evidence/skills-validation-FAB-13-generated-launch.png`. Destination
resolution remains flaky, so rerun with an idle matching runtime when validating
another generated app.
