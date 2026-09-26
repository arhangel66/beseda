# Auto-update with Sparkle

## Context

Two Macs run Beseda. An update today is `scripts/package_app.sh`, a zip sent by
hand, a drag into `/Applications` and one more «Open Anyway» because the bundle is not
notarised. Goal: publish from Mikhail's Mac with one command; the other Mac picks the
new version up on its own, no dialogs.

Facts that shape the design:

- Signing is Apple Development (team `PRH5UQNC57`), no Developer ID, no notarisation. Sparkle
  does not need either: it verifies its own EdDSA signature on the archive and checks
  that the new bundle carries the same code-signing identity as the running one, and its
  installer clears the quarantine flag, so Gatekeeper never sees the update.
- The app is a menu bar agent (`LSUIElement`) that is rarely quit.
- The app records calls. An update must never relaunch the app mid-recording.
- The source tree is not in git; a separate public repo holds only releases.
- `build_app.sh` is a dev-loop script: debug build, `pkill -x Beseda`, then
  relaunch. `package_app.sh` calls it, so today every zip for the other Mac kills
  the app on Mikhail's Mac, mid-recording if one is running. The release build must not
  go through that script.
- Sparkle with `SUAutomaticallyUpdate` downloads in the background but installs on
  quit; when the app never quits, its standard UI eventually shows an "update ready"
  alert. So the silent path is not the default one: the app has to ask for the
  immediate install itself.

## Design

### Hosting

Public GitHub repo `arhangel66/beseda`:

```
appcast.xml                  committed, served as
                             https://raw.githubusercontent.com/arhangel66/beseda/main/appcast.xml
Releases/v0.2.1              asset Beseda-0.2.1.zip
```

The appcast entry's `enclosure url` points at the release asset. Raw GitHub caches for
up to five minutes, which is fine for an hourly check.

### Bundle

```
Beseda.app/Contents/Frameworks/Sparkle.framework   copied from the SwiftPM bin path
                                                       like CTranscribe.framework
Info.plist
  SUFeedURL                  the appcast URL
  SUPublicEDKey              public key from generate_keys
  SUEnableAutomaticChecks    true
  SUAutomaticallyUpdate      true      download + install without asking
  SUScheduledCheckInterval   3600      Sparkle's minimum
```

`codesign --deep` with the Apple Development identity covers Sparkle's nested
`Autoupdate`, `Updater.app` and XPC services; no hardened runtime, so `--deep` is fine.

The `SU*` keys go in only for the release bundle. The dev build on Mikhail's Mac has no
feed URL, otherwise Sparkle would replace it with the published version an hour later.

### In the app

`Runtime/AppUpdater.swift`, one class around `SPUStandardUpdaterController` with an
`SPUUpdaterDelegate`. The "is recording" fact comes in as a closure so the rules are
testable without Sparkle:

- Silent path. `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` fires
  once the update is downloaded and staged. The class keeps the block and invokes it
  right away when nothing is being recorded, otherwise when the controller reports
  `recordingDidStop()`. Invoking it installs and relaunches the agent without any UI.
- Manual path («Обновления»). `updater(_:shouldPostponeRelaunchForUpdate:untilInvokingBlock:)`
  returns true while recording and invokes the block on `recordingDidStop()`, so a
  person clicking "Install and relaunch" cannot cut a call either.
- `checkForUpdates()` calls `NSApp.activate` first: an `LSUIElement` agent otherwise
  shows Sparkle's panel behind other windows.
- `version` string for the popover footer.
- The controller owns the updater the way it owns the other services; wired in
  `AppDelegate`.

Menu bar popover: «Обновления» next to «Настройки», and the version in the
footer so the second Mac can be checked at a glance.

### Release script

`scripts/release.sh`, one command:

1. `swift build -c release`; bundle exactly like the dev script but without `pkill`,
   without touching `~/Applications`; `CFBundleShortVersionString` from `VERSION`,
   `CFBundleVersion` from a timestamp with seconds (Sparkle orders by it; the current
   minute-resolution stamp would make two builds in one minute indistinguishable).
2. `ditto` into `dist/Beseda-<version>.zip`.
3. `generate_appcast dist/` from Sparkle's `bin/` — signs the zip with the key in the
   Keychain and rewrites `dist/appcast.xml` with a per-version entry.
4. `gh release create v<version> dist/Beseda-<version>.zip` in the releases repo,
   copy `appcast.xml` there, commit and push.

`build_app.sh` and `package_app.sh` stay for the dev loop; the release
script reuses the bundling by moving it into `scripts/lib/bundle_app.sh` that both call.

## Steps

Each step: RED (build, test or check fails) → GREEN, `swift test` from the repo root.

- [x] **0. Hosting decision** — GitHub public repo `arhangel66/beseda` (2026-09-05) or a
  folder on Mikhail's own server. Everything below assumes GitHub; only the upload part
  of step 5 changes otherwise.

- [x] **1. Sparkle in the bundle** — `Package.swift`: `sparkle-project/Sparkle` ≥ 2.6,
  product `Sparkle`. `scripts/lib/bundle_app.sh`: copy `Sparkle.framework` into
  `Contents/Frameworks`, take a `release` flag that decides whether the `SU*` keys are
  written; both existing scripts call it without the flag. Check: the built app
  launches, `otool -L Contents/MacOS/Beseda` lists `@rpath/Sparkle.framework`,
  `codesign --verify --strict --deep` passes, the dev bundle's plist has no `SUFeedURL`.

- [x] **2. Keys and plist** — the tools ship inside the SwiftPM artifact
  (`.build/artifacts/sparkle/Sparkle/bin/`: `generate_keys`, `sign_update`,
  `generate_appcast`). `generate_keys` once (private key stays in the Keychain of
  Mikhail's Mac; `generate_keys -x` exports a backup to 1Password, never to the repo).
  The five `SU*` keys live in `bundle_app.sh`, not in `Resources/Info.plist`. Check:
  `plutil -lint` on a release bundle, the app starts and logs Sparkle's first scheduled
  check without an error.

- [x] **3. `Runtime/AppUpdater.swift`** — the class above. Tests, with a fake for the
  Sparkle callbacks: the staged-install block runs at once when `isRecording` is false;
  with `isRecording` true it is kept and runs exactly once on `recordingDidStop()`; the
  relaunch-postpone delegate answers true only while recording and its block is also
  replayed on `recordingDidStop()`. Wire into `AppController` and call
  `recordingDidStop()` where the dual capture ends.

- [x] **4. Popover** — «Обновления» button (activates the app first) and the
  version line. Check: the button brings Sparkle's "You're up to date" panel to the
  front against a feed with no newer entry.

- [x] **5. `scripts/release.sh`** — as designed; `docs/release.md` with the
  three-line how-to (bump `VERSION`, run the script, done). Check: run it for 0.2.1,
  `dist/appcast.xml` validates with `xmllint`, the release page shows the zip, the raw
  appcast URL serves the new entry.

- [ ] **6. End-to-end on the second Mac** — *done on Mikhail's Mac 2026-09-05: 0.2.1
  installed by hand updated itself to 0.2.2 with no dialog, quarantine flag absent,
  signature valid, archive intact. Still open: the same on the second Mac, and the
  recording-postpone check.* — install the 0.2.1 build by hand (the last
  manual update) and launch it twice: Sparkle skips the scheduled check on the very
  first launch of a bundle. Publish 0.2.2 with a visible change (the version in the
  popover is enough). Within an hour, or after «Обновления», 0.2.2 is
  running with no dialog at all; no Gatekeeper prompt; microphone and system-audio
  permissions still granted; the archive intact. Then: start a test recording, publish
  0.2.3, confirm the install waits for the recording to stop and happens right after.

## Risks / notes

- The very first Sparkle-enabled version still travels by zip. After that, never.
- Sparkle checks that the new bundle matches the running one's signing requirement
  (team and certificate name). A renewed Apple Development certificate on the same
  Apple ID keeps both; a different team would break updates for installed copies.
- `SUAutomaticallyUpdate` installs updates nobody reviewed on the second Mac. The
  release script is the only gate, so the script must not run from the dev loop by
  accident: it lives under a different name and refuses to run when `VERSION` matches
  the last published tag. Mikhail's own Mac runs the dev build of the same code, so a
  release goes out after it has survived a day there.
- Until step 5 lands, `package_app.sh` still kills the app on Mikhail's Mac: do not
  package while a call is being recorded.
- Sparkle relaunches the app after install; the menu bar agent reappears on its own.
  Auto-recording detection restarts with it; a call that starts during the two-second
  relaunch is caught by the next detection cycle, same as after a reboot.
- Lost private key = no more updates for installed copies (the public key is baked into
  the plist). Hence the exported backup in step 2.
