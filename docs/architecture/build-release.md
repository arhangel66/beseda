---
type: Architecture
title: Build and release
description: Package.swift, the build/sign/package/release scripts, Sparkle updates, the check and the ios kit.
---
# Build and release

## Package

`Package.swift` (tools 6.0, macOS 14.2) has one executable target, `Beseda`, at the default
`Sources/Beseda` with sources `App`, `Audio`, `Calendar`, `Storage`, `Summarization`, `Transcription`,
`Webhooks`, `Runtime`, plus `Resources`. Dependencies: FluidAudio (diarization), Sparkle (updates), and
transcribe.cpp as the `CTranscribe` binary xcframework (pinned v0.2.3 with checksum) wrapped by the vendored
`Vendor/TranscribeCpp` target. Tests are `Tests/BesedaTests`. With the targets in their own folders SwiftPM
never walks the rest of the checkout, so no `exclude` list is needed and `.factory/`, `untracked/` or a
scratch folder at the root do not slow the build.

## Private store artifact (BESEDA-257)

`BESEDA_STORE=1 swift build --jobs 2 --scratch-path .build/store` selects a manifest without
Sparkle and excludes `Runtime/AppUpdater.swift`. The store compile flag removes update commands
and settings; the direct build (`swift build --jobs 2`) retains them. Keep separate scratch paths:
SwiftPM reuses object paths when only the manifest environment changes.

`scripts/build_store_app.sh <pinned-llama-archive.tar.gz> <signing-identity>` builds and assembles
`.build/Beseda-store.app`, then invokes `package_store_summary.sh` to embed and sign the pinned
helper. This is a private artifact, not an App Store upload. Store assembly omits Sparkle framework,
license, feed and SU keys. The app signature uses `scripts/store_summary_app.entitlements`: sandbox,
network client, microphone, calendars and user-selected read/write only. The helper keeps its own
entitlements. The direct release assembly and feed are unchanged.

Verified locally: both flavor builds with `--jobs 2`; pinned b10819 archive SHA-256
`8933e736495eadfef0731ae32054acfaa75699bf4a6ccba77cd8475db085ec66`.
Private ad-hoc artifact: `.build/Beseda-store.app` (this worktree only). Its resource bundle lives
at `Contents/Resources/Beseda_Beseda.bundle`, with `Resources/en.lproj/Menu.strings` inside.
SwiftPM generates an accessor that looks beside the app root; store calls instead use
`Bundle.besedaResources` to resolve `Bundle.main.resourceURL` while direct calls continue to use
SwiftPM's generated accessor. Shell stubs reject missing resources and stray root content.
The assembled app passes `codesign --verify --strict --deep`; its helper has sandbox inheritance,
and app entitlements include sandbox, network client, microphone, calendars and user-selected
read/write. No Sparkle framework, feed or SU keys are present. Runtime resource lookup remains
parked: no app launch, sandbox capture, Apple provisioning, TestFlight or review was attempted.
A build alone is not proof of sandbox compatibility.

## Check

`swift test --jobs 2` (from `AGENTS.md`) builds the app and runs every test except the heavy ones gated by
`BESEDA_FULL_CHECK=1`. `scripts/full_check.sh` is the full check: all tests with that flag, then the 1 h
synthetic-call memory tests (`BESEDA_LONG_CALL_MEMORY=echo|asr`). Measured 2026-09-27, M2 Max, after the
build: fast 27.2 → 11.0 s, full 102.6 s.
`theInstalledModelTranscribesRealSpeech` is skipped unless the speech model is installed and
`samples/jfk.wav` is present.

## Scripts

- `scripts/build_app.sh` — dev loop: kills Beseda, debug build, bundles, installs to
  `/Applications/Beseda.app` (removing any other copy so LaunchServices sees one bundle id), relaunches.
- `scripts/package_app.sh` — runs `build_app.sh` and zips the app with `ditto` to
  `dist/Beseda-<VERSION>.zip`.
- `scripts/lib/bundle_app.sh <bin-dir> <app-dir> [release]` — assembles `Beseda.app`: `Info.plist` with
  `VERSION` and a timestamp `CFBundleVersion`, `CTranscribe` and `Sparkle` frameworks, licenses, the icon
  compiled by `actool`, then signs inside-out with hardened runtime (see «Developer ID и нотаризация»)
  with the first "Developer ID Application" identity, or the first "Apple Development" one when there is
  none. Only the `release` flavour adds the Sparkle feed, public EdDSA key and hourly automatic checks.
- `scripts/Beseda.entitlements` — the app's hardened-runtime entitlements.
- `scripts/release.sh` — publishes a release (below); runs `full_check.sh` before the release build.
  `scripts/test_release.sh` checks its syntax and exercises the step-6 recovery path with local command stubs.
- `scripts/screenshot_copy.sh` — builds a copy with a random bundle id `app.beseda.shot.<random>` per run from this checkout's own
  `.build` into `.build/Beseda-shot.app` (including Sparkle, ad-hoc signed without a timestamp or keychain access) and uses the kit's copied
  `scripts/macos-isolated-launch.sh` with `--clean-defaults`. The helper opens it hidden with a fresh
  `CFFIXED_USER_HOME`, sets `IOS_KIT_CLEAN_DEFAULTS=1` to prevent import from the old `app.podushka.Podushka`
  domain, and deletes the random defaults domain before and after the run. It never touches
  `/Applications/Beseda.app` or its data.
- `scripts/nightly_check.sh` — the nightly full check: native-ui in its own detached worktree
  `~/Library/Caches/beseda-nightly-check`, `nice -n 19`, skipped when free memory is under 20 % or a
  Beseda call is recording (an open `*.raw.wav`). Log: `~/Library/Logs/beseda-nightly-check.log`. On
  failure only, one `bb notify` (digest, source and dedupe key `beseda-nightly-check`).
- `scripts/install_nightly_check.sh` — writes and loads the LaunchAgent
  `~/Library/LaunchAgents/app.beseda.nightly-check.plist` (03:30 daily, Nice 19, background). Uninstall:
  `launchctl bootout gui/$(id -u)/app.beseda.nightly-check` then
  `rm ~/Library/LaunchAgents/app.beseda.nightly-check.plist`.

## Releasing

1. Bump `VERSION`.
2. Write `docs/release-notes/<version>.md`; it is the update dialog text and the GitHub release description.
3. Run `./scripts/release.sh` on `main`.

The script refuses to run unless it is on `main`, the tree is clean and the notes exist. Then, each step
skipping what an earlier run already did:

1. If `appcast.xml` at `HEAD` already has this version's zip URL, only `git push origin main` is left; it
   pushes and stops.
2. Tags `HEAD` as `v<version>` and pushes the tag. An existing tag (local or on `origin`) is reused only if
   it points at `HEAD`; otherwise the script refuses.
3. If the release has no `Beseda-<version>.zip` yet: `swift test --jobs 2`, release build and bundle, zip
   into `dist/v<version>/`, a draft GitHub release in `arhangel66/beseda` if there is none, upload with
   `--clobber`. An uploaded zip is never rebuilt: a new build would not match it.
4. Downloads the zip back from the release and runs Sparkle's `generate_appcast` on those bytes (EdDSA key
   from the login keychain, notes embedded) into `dist/v<version>/appcast.xml`.
5. Publishes the draft (a draft's download URL is not public), downloads the public URL, compares it byte
   for byte with step 4 and checks the feed's `edSignature` with `sign_update --verify`.
6. Only then copies the feed to `appcast.xml`, commits `Beseda <version>` and pushes `main`.

A failure at any step leaves the feed untouched (or, at step 6, copied but not committed, or committed but
not pushed), so the fix is to rerun; a published release without the feed is finished by the rerun, not
refused. The clean-tree check lets through exactly one leftover: an `appcast.xml`, staged or not, equal to
`dist/v<version>/appcast.xml`; the rerun then only commits and pushes it. Any other change still refuses.

Installed release copies check the feed hourly; `AppUpdater` holds the install until no call is being
recorded. Dev builds carry no feed and never update themselves.

## Developer ID и нотаризация

Gatekeeper opens a downloaded app only when it is signed with Developer ID, has the hardened runtime and
is notarized. Up to 0.4.0 releases were signed with Apple Development (team `PRH5UQNC57`), no hardened
runtime, not notarized. The scripts are ready; what is left is the account's side.

### Signing (in place, works with either identity)

`bundle_app.sh` signs with `--options runtime`, inside-out as Sparkle documents: `Installer.xpc`,
`Downloader.xpc` (`--preserve-metadata=entitlements`), `Autoupdate`, `Updater.app`, `Sparkle.framework`,
`CTranscribe.framework`, then the app with `scripts/Beseda.entitlements`. A Developer ID identity also
gets `--timestamp` (notarization requires a secure timestamp); Apple Development gets `--timestamp=none`.

Entitlements, only what the runtime would otherwise deny:

- `com.apple.security.device.audio-input` — without it the hardened runtime silently records silence.
- `com.apple.security.personal-information.calendars` — calendar names for conversations.
- No `network.client`: it is an App Sandbox entitlement; the app is not sandboxed.
- No `cs.disable-library-validation` / `allow-unsigned-executable-memory` / `allow-jit`: the speech
  engine is `CTranscribe.framework`, signed by the same team in the same pass, so library validation
  passes; the downloaded `llama-server` (ad-hoc signed, with its own dylibs) is a child process with its
  own signature, and the parent's runtime does not apply to it.

Checked on 2026-09-27 with the Apple Development identity: a release bundle with hardened runtime, bundle
id `app.beseda.Beseda.hrcheck`, launched isolated, loaded `CTranscribe` and `Sparkle` (library validation
passed), checked the feed (`SULastCheckTime` set, Sparkle's installer launcher started for the offered
0.4.0). A probe signed the same way ran the installed `llama-server --version` with its dylibs, exit 0.
Microphone/BlackHole capture and a full transcription were not run: a new bundle id triggers a TCC dialog.

### Controlled Developer ID signing check

On 2026-09-27, a throwaway release-flavour bundle in this worktree's ignored
`.build/BESEDA-196-signing.app` built with `swift build -c release --jobs 2` and
`scripts/lib/bundle_app.sh .build/release .build/BESEDA-196-signing.app release` under
`lockf /tmp/beseda-factory-heavy.lock nice -n 19`. Both commands completed without a keychain
prompt (the signing command had a 120-second noninteractive timeout); `.build` used 1.1 GB.
`codesign --verify --strict --deep` passed. The app signature has Developer ID Application
(team `PRH5UQNC57`), a secure timestamp, hardened runtime (`flags=0x10000(runtime)`), and
exactly the audio-input and calendars entitlements above. The bundle was not launched,
installed or submitted for notarization. The separate controlled notarization check is recorded below.

### Private notarization attempt (BESEDA-207)

The read-only `xcrun notarytool history --keychain-profile beseda-notary` check found no Keychain
password item for `beseda-notary`. Stopped before building or submitting, as required for a missing
profile. Submission ID: none; notarization status: not submitted. No bundle was stapled or assessed.
The existing `~/.config/apple/asc.env` was present but was not read or changed; the missing field is
the Keychain profile `beseda-notary` (its individual credential fields cannot be checked until it exists).
This does not establish public release readiness or bypass the Astra gate.

### Private notarization validation (BESEDA-224)

On 2026-09-27, checked the shared `asc.env` (mode `0600`), all four nonempty fields,
`DEVELOPMENT_TEAM=PRH5UQNC57`, and the referenced `.p8` (mode `0600`) without printing credentials.
Stored the existing account's `beseda-notary` profile and verified it with `notarytool history`.
Under the factory heavy lock and `nice -n 19`, built a private release-flavour Developer ID bundle,
verified its strict code signature, and zipped it. Submitted that zip **once** with
`notarytool submit --wait --keychain-profile beseda-notary`.
Submission ID: `3d3a22b0-7b11-499b-8696-196c70e50494`; status: **Accepted**.
Stapling and ticket validation succeeded; `spctl --assess --type execute` returned
`accepted` / `source=Notarized Developer ID`, and `codesign --verify --strict --deep` passed
on the stapled app. The throwaway bundle was not installed, launched, uploaded, or released.
This is private validation only, not Astra approval for App Store review or release.

### One-time setup once the account is active

1. Certificate. developer.apple.com → Certificates → «+» → **Developer ID Application** (G2 Sub-CA).
   Create the CSR in Keychain Access (Certificate Assistant → Request a Certificate From a Certificate
   Authority, saved to disk), upload it, download the `.cer`, double-click: it lands in the **login**
   keychain next to its private key. Check: `security find-identity -v -p codesigning` lists
   `Developer ID Application: … (PRH5UQNC57)`. Export the certificate with its key as `.p12` into
   1Password: it cannot be downloaded again with the key.
2. notarytool credentials, stored in the login keychain under the profile `beseda-notary`
   (`NOTARY_PROFILE` in `release.sh`). Recommended: an **App Store Connect API key** (Users and Access →
   Integrations → Team Keys, role Developer): it is not tied to Mikhail's Apple ID password or 2FA,
   survives a password change, can be revoked alone. An app-specific password works too but breaks
   when the Apple ID password is reset.

   The shared credentials file is `~/.config/apple/asc.env`, mode `0600`. It contains `ASC_KEY_ID`,
   `ASC_ISSUER_ID`, `ASC_KEY_P8_PATH` and `DEVELOPMENT_TEAM`; the key path points to the existing
   mode-`0600` `.p8` file in the same mode-`0700` directory. WholeBook uses the same files, so do not
   move, copy, rewrite or change their permissions. After confirming `DEVELOPMENT_TEAM` is
   `PRH5UQNC57`, load the file without printing it and store the profile with:

   ```
   set -a; source ~/.config/apple/asc.env; set +a
   xcrun notarytool store-credentials beseda-notary \
       --key "$ASC_KEY_P8_PATH" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID"
   xcrun notarytool history --keychain-profile beseda-notary
   ```

   The certificate itself is not in this file: it was created in the account on this Mac.

### Release with notarization

```
REQUIRE_NOTARIZATION=1 ./scripts/release.sh
```

Step 3 of «Releasing» becomes: bundle (signed as above) → if the app's authority is Developer ID: zip →
`xcrun notarytool submit --keychain-profile beseda-notary --wait` → `xcrun stapler staple` the `.app` →
`spctl --assess` → zip again (the shipped zip holds the stapled app) → upload; the EdDSA feed steps are
unchanged. Without Developer ID the build ships as before, unless `REQUIRE_NOTARIZATION=1`: then the
script refuses before tagging (no identity) or before uploading (bundle not Developer ID).

### Installed copies accept the first Developer ID update

Yes. Sparkle 2's `SUUpdateValidator` accepts a bundle update when **either** the EdDSA signature checks
against the old app's public key **or** the new code signature matches the old one; a valid EdDSA
signature explicitly allows a changed code-signing identity, as long as the new signature is itself valid
and the update still carries an EdDSA key. 0.3.5 and 0.4.0 have `SUPublicEDKey`, the key is unchanged,
so the Developer ID build installs. Never rotate the EdDSA key in the same release as the identity:
then neither check would pass.

### Keychain keys survive the identity change

0.4.0 keeps the OpenRouter key and the webhook secret as generic passwords in the login keychain
(service = bundle id). Such an item's ACL trusts the designated requirement of the app that created it,
and that requirement names the certificate: Apple Development pins the leaf's CN, Developer ID pins the
Developer ID CA and team OU. The same team id does not help (only the data-protection keychain uses team
access groups, and that needs a provisioning profile). So the first Developer ID build gets a macOS
prompt per item («Beseda wants to use … in your keychain»); seen on this Mac with a differently signed
copy. To make that the only prompt: since this change the keys live under the service
`<bundle id>.keys`; a key missing there is read once from the old service (the prompt, «Allow» is
enough) and saved into the new one, owned by the new signature, so later launches are silent. The old
item stays for a rollback. «Deny» leaves the key empty until it is entered again in Settings. The read
runs off the main thread (`AppSettings.loadSecrets`), so the menu bar and windows work while the prompt is
up; the keys read "" until it returns, and recording never needs them.

## Constraints

- The tag points at the commit before the appcast commit: the feed is not part of the build. A new
  commit after a failed run makes the old tag refuse; delete it or bump `VERSION`.
- Release only from `main`: the appcast commit lands on the current branch while the push targets `main`,
  so a release cut elsewhere would publish a tag and zip no installed copy is offered.
- The private EdDSA key exists only in the login keychain of Mikhail's Mac; losing it means installed
  copies can never be updated. Back it up with
  `.build/artifacts/sparkle/Sparkle/bin/generate_keys -x <file>` into 1Password and delete the file.
- Podushka (up to 0.2.2) is a different app and never updates into Beseda; it is replaced by installing
  Beseda by hand once.

## Headless UI journey

`swift test --jobs 2` runs `UIJourneyContractTests`: an isolated-only `BESEDA_SEEDED_JOURNEY=1` fixture
creates a deterministic two-speaker archived call, and the test verifies archive lookup, search, stored summary,
copy rendering, speaker merge and deletion without recording, network, dialogs or clipboard writes. The app's
stable accessibility surface is:

| Screen | Identifier | Label/action |
| --- | --- | --- |
| Onboarding | `onboarding.window`, `onboarding.advance` | visible step text; «Назад» and the visible advance title |
| Archive | `archive.sidebar`, `archive.search` | call title; «Искать в разговорах» |
| Call result | `call.summary` | picker label «Раздел», segment «Итоги» |
| Copy | `call.copy-transcript` | «Скопировать расшифровку», selected format as value; ⇧⌘C |
| Speaker | `call.speaker-line.<speaker-key>` | «Переименовать участника» and «Объединить с <name>» actions |
| Delete | `call.delete` | «Удалить разговор» |

No app is launched or signed for this contract. Native SwiftUI descendants remain inaccessible in the never-key/non-main harness window on the tested macOS; the kit's regression records this limit. The kit's copied `AccessibilityHarness` hosts a representative
journey action in a transparent, ordered-back `NSWindow`; the test reads its NSAccessibility identifier and label,
presses it in-process without TCC, and proves the window never becomes key or main. This does not claim a driven
end-to-end UI run. External AX remains allowed only when `AXIsProcessTrusted()` is already true without prompting.

## ios kit

The project is built with the kit at `/Users/mikhail/w/learning/ios-kit` (entry: its `docs/index.md`;
`macos.md` covers SwiftPM macOS apps: test, isolated launch, window screenshots). Its skills are copied
into `.agents/skills/`. Gaps are fixed in the kit, not worked around here.
