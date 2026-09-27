---
type: Architecture
title: Build and release
description: Package.swift, the build/sign/package/release scripts, Sparkle updates, the check and the ios kit.
---
# Build and release

## Package

`Package.swift` (tools 6.0, macOS 14.2) has one executable target, `Beseda`, with `path: "."` and sources
`App`, `Audio`, `Calendar`, `Storage`, `Summarization`, `Transcription`, `Webhooks`, `Runtime`, plus
`Resources`. Dependencies: FluidAudio (diarization), Sparkle (updates), and transcribe.cpp as the
`CTranscribe` binary xcframework (pinned v0.2.3 with checksum) wrapped by the vendored
`Vendor/TranscribeCpp` target. Tests are `Tests/BesedaTests`.

Because the target sits at the repo root, `exclude` lists `.agents`, `.gitignore`, `.idea`, `.venv`,
`AGENT.md`, `dist`, `README.md`, `Tests`, `VERSION`, `Vendor`, `docs`, `implementation_journal.md`,
`samples`, `scripts`, `skills-lock.json` and `untracked`. Other root files (`AGENTS.md`,
`Package.resolved`, `appcast.xml`, `.mcp.json`) are not excluded. In a clean worktree some of these do not exist and SwiftPM
warns about the missing excluded paths; the warnings are harmless.

## Check

`swift test --jobs 2` (from `AGENTS.md`) builds the app and runs every test.
`theInstalledModelTranscribesRealSpeech` is skipped unless the speech model is installed and
`samples/jfk.wav` is present.

## Scripts

- `scripts/build_app.sh` — dev loop: kills Beseda, debug build, bundles, installs to
  `/Applications/Beseda.app` (removing any other copy so LaunchServices sees one bundle id), relaunches.
- `scripts/package_app.sh` — runs `build_app.sh` and zips the app with `ditto` to
  `dist/Beseda-<VERSION>.zip`.
- `scripts/lib/bundle_app.sh <bin-dir> <app-dir> [release]` — assembles `Beseda.app`: `Info.plist` with
  `VERSION` and a timestamp `CFBundleVersion`, `CTranscribe` and `Sparkle` frameworks, licenses, the icon
  compiled by `actool`, then `codesign --deep` with the first "Apple Development" identity. No hardened
  runtime: it would require an audio-input entitlement and silently kill microphone capture. Only the
  `release` flavour adds the Sparkle feed, public EdDSA key and hourly automatic checks.
- `scripts/release.sh` — publishes a release (below).

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

A failure at any step leaves the feed untouched (or, at step 6, committed but not pushed), so the fix is to
rerun; a published release without the feed is finished by the rerun, not refused.

Installed release copies check the feed hourly; `AppUpdater` holds the install until no call is being
recorded. Dev builds carry no feed and never update themselves.

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

## ios kit

The project is built with the kit at `/Users/mikhail/w/learning/ios-kit` (entry: its `docs/index.md`;
`macos.md` covers SwiftPM macOS apps: test, isolated launch, window screenshots). Its skills are copied
into `.agents/skills/`. Gaps are fixed in the kit, not worked around here.
