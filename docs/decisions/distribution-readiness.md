---
type: Decision Record
title: Distribution readiness
status: proposed
tags: [distribution, macos, release]
---

# Distribution readiness

Independent GPT-6 Astra source-only review of commit `822294fcc1d764cb529ce48a92f7334f542c7567` via the authenticated `openai-codex/gpt-6-astra` route (high reasoning). No build, app launch, signing, notarization, submission, live data or current Apple policy check was part of this review. These are source-level verdicts, not Apple approvals.

## Private notarized distribution: candidate, not verified

The bundle script signs nested components with Developer ID when available; the fresh-asset path in `release.sh` submits a ZIP, staples the app and checks Gatekeeper (`scripts/lib/bundle_app.sh`, `scripts/release.sh`). Acceptance and launch of the **delivered** archive on a clean Mac are still unverified. A private packaging path is needed: `release.sh` publishes a GitHub release and updates the public Sparkle feed; the release bundle points at that feed. Do not treat a private handoff as ready merely because the build script has a notarization path.

## Mac App Store: blocked in current source

- `scripts/Beseda.entitlements` has microphone and calendar entitlements, but no App Sandbox. A sandboxed store variant needs a tested file, network, audio-capture and helper execution model.
- `BundledSummaryInstaller.swift` downloads and installs executable `llama-server` code; `LlamaServer.swift` launches it via `Process`. Package signed executable code in a store variant instead. Downloaded model *weights* are a separate question.
- Sparkle is packaged and used (`Package.swift`, `AppUpdater.swift`); a store variant must use store updates instead.
- Export-folder selection saves a path, not a security-scoped bookmark (`SettingsWindow.swift`, `AppSettings.swift`, `AppController.swift`). Persistent sandbox access is not implemented.

See the [sandbox audit](app-store-sandbox.md). Process taps, Keychain migration, LM Studio discovery, FileVault detection and login items in the sandbox are unresolved checks, not demonstrated failures.

## Public direct distribution: not ready

`REQUIRE_NOTARIZATION` defaults to `0`, so `scripts/release.sh` can publish an Apple Development build. Even with `REQUIRE_NOTARIZATION=1`, an existing release ZIP bypasses the build/notarization block; recovery paths can exit before checking the delivered archive. The later byte comparison and Sparkle signature check do not prove Developer ID signing or a stapled notarization ticket. Require and verify notarization of the exact published archive on fresh and resumed runs before public release.

Also verify on a clean Mac the final ZIP, permissions, both audio tracks, transcription, local summaries, updates and preservation of Keychain secrets. Update the [installation instructions](../product/install.md), which currently describe an unnotarized build and “Open Anyway.” Audit dependency/model notices and applicable privacy-manifest requirements; the bundle script explicitly copies only transcribe.cpp and Sparkle licenses. Confirm published [privacy disclosures](../product/privacy.md) match the shipped product. Seller/payment eligibility is a separate gate for paid sales ([payment path](payment-path.md)), not for free distribution.

Sources: `scripts/release.sh` (lines 15–17, 34–44, 81–146), `scripts/lib/bundle_app.sh` (26–40, 53–83), `scripts/Beseda.entitlements`, `Sources/Beseda/Summarization/BundledSummaryInstaller.swift` (119–147), `Sources/Beseda/Summarization/LlamaServer.swift` (94–109), `Sources/Beseda/App/Views/SettingsWindow.swift` (662–669), `Sources/Beseda/App/AppSettings.swift` (255–258), `Sources/Beseda/App/AppController.swift` (1603–1613). See also [build and release](../architecture/build-release.md).
