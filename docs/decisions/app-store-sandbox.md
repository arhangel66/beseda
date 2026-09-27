---
type: Decision Record
title: App Store sandbox audit
description: Proposed Store split, private full-bundle static verification, and parked runtime gates.
status: proposed
tags: [distribution, macos, sandbox, app-store]
generated:
  by: agent
  at: 2026-09-28T00:00:00Z
sources:
  - id: source
    title: Beseda source tree and packaging scripts, audited 2026-09-28
  - id: build-release
    title: Beseda build and release documentation
  - id: verification
    title: BESEDA-288 private full-artifact verification handoff, 2026-09-28
  - id: apple-taps
    title: Apple Core Audio process tap sample
    url: https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
  - id: apple-sandbox
    title: Apple App Sandbox entitlement
    url: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox
---

# App Store sandbox audit

## Scope and evidence

The direct and Store variants are distinct build modes, not two proven distribution channels. `BESEDA_STORE=1`
selects a Sparkle-free SwiftPM manifest and Store-only runtime branches; the direct build retains Sparkle,
its update path and its existing entitlements. [Build and release](../architecture/build-release.md#private-store-artifact-beseda-257)
describes the assembly. BESEDA-288 built both modes and statically verified a **full** private ad-hoc
Store bundle, not merely a helper stub. No app was installed or launched, no capture or sandbox runtime
was exercised, and no provisioned signing, TestFlight or App Review was performed.[^verification]

| Area | Current implementation and evidence | Parked gate |
|---|---|---|
| Core Audio process tap | `SystemAudioTap` creates a private tap and aggregate device; the Store app carries sandbox and audio-input entitlements and the plist has system-audio usage text. Apple's [tap sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) does not prove sandbox capture. **Unknown at runtime.** | Owner-assisted grant on a disposable account with the intended signed identity; route known audio only to BlackHole, verify nonzero samples and no sandbox denial, stop and repeat after relaunch. Check microphone permission separately. |
| Local summary helper | In Store mode `BesedaStoreSummary` selects the bundled `Contents/Helpers/llama-server`; `BundledSummaryInstaller` skips runtime archive download. `scripts/package_store_summary.sh` checks the pinned b10819 archive digest, embeds the helper and dylibs, signs the helper with sandbox inheritance and signs the app. Direct mode keeps its downloaded runtime. | In a provisioned sandbox app, launch/stop the helper, load dylibs, produce a real local summary and retry after relaunch; seek App Review of this exact architecture. Static signing is not execution proof. |
| Speech and summary models | Downloads are data files; Store mode downloads **models only**, not an executable. The Store app has network-client entitlement. `CTranscribe` is a packaged pinned XCFramework; speech recognition runs in-process. | Sandbox download, interrupted retry, bad hash rejection, model load and real transcription/summary; inspect library validation and denial logs. |
| Export and deletion | `AppSettings` persists security-scoped bookmarks and resolves stale data; `withExportFolder` balances access for exports and for deletion of old export copies (`AppController`). Pure tests cover bookmark recovery, scope cleanup and deletion. The Store app has user-selected read/write entitlement. Direct mode preserves its plain-path behavior. | Pick an external folder, export, relaunch, export and delete; move/revoke the folder and confirm recoverable reselection without losing call data. |
| Updates | `Package.swift` excludes Sparkle and `AppUpdater.swift` in Store mode; the Store UI omits update controls, and assembly omits Sparkle framework, feed keys, appcast and license. Direct mode and its update tests remain intact. | TestFlight install/update ownership and Apple review; the static absence of Sparkle does not prove Store updates. |
| EventKit and backup exclusion | Store signing carries calendars entitlement and the app carries calendar usage text. Backup exclusion uses `URLResourceValues.isExcludedFromBackup` in the app's own data directory, not `tmutil`. | Calendar TCC allow/deny/recovery and backup flag persistence in a sandbox runtime. |
| Login item and FileVault | Settings uses `SMAppService.mainApp` with approval/error handling; `StorageJanitor` runs `/usr/bin/fdesetup isactive` and represents an unclear result as `nil`. No source evidence proves or disproves sandbox behavior. | On owner-approved test machines, register/approve/login/unregister; check `fdesetup` on FileVault-on/off systems, denial logs and the unknown-status UI. Do not add a speculative fallback. |
| Keychain | Queries have no explicit access group; missing Store secrets require re-entry, without deleting direct-build items. A direct signature's ACL is not proof of access from a provisioned Store app. | On a disposable account with provisioned signing, test save/read/update/delete across relaunch, direct-to-Store re-entry and rollback, without touching the live login Keychain. Revisit group entitlement only if observed provisioning requires it. |

## Proposed decision

Keep the separate Store build and the direct distribution path. Store bundles a pinned signed summary
helper, downloads only model weights, uses security-scoped export bookmarks and omits Sparkle. Keep this
record **proposed** until the parked owner-assisted runtime and Apple gates are observed. Do not infer
sandbox compatibility from entitlement syntax or ad-hoc signature verification.

BESEDA-288 checked the pinned b10819 macOS arm64 archive SHA-256
`8933e736495eadfef0731ae32054acfaa75699bf4a6ccba77cd8475db085ec66` and assembled the full
ad-hoc artifact at
`/Users/mikhail/w/learning/beseda/.factory/work/BESEDA-288/.build/Beseda-store.app`.
`codesign --verify --strict --deep` passed on that bundle. Its app entitlements include App Sandbox,
audio input, user-selected read/write, network client and calendars; the helper has sandbox and inherit.
The resource bundle contains English and Russian localizations; helper/dylib symlinks resolve. The static
inspection found no Sparkle framework, feed plist keys, appcast files or Sparkle dynamic dependency (a
binary text occurrence of “sparkles” was an unrelated localized word). Both flavor builds, 12 filtered
Store bookmark/deletion/localization tests, three direct updater tests and packaging/release shell stubs
passed. This is **ad-hoc full-bundle static evidence**, not provisioned Store signing or runtime proof.[^verification]

The BESEDA-288 worktree was removed; its path above is historical evidence. BESEDA-290 downloaded the
pinned archive again, verified the same SHA-256, built direct and Store variants with `swift build --jobs 2`
in its own worktree, then assembled the full ad-hoc app. The inspectable retained copy is
`/Users/mikhail/w/learning/beseda/.factory/private/BESEDA-255/Beseda-store.app`, outside worker
worktrees in the ignored factory private directory. Both source and copy passed
`codesign --verify --strict --deep`. Both have English and Russian resources, a sandboxed app with audio,
calendar, network and user-selected read/write entitlements, an inherited-sandbox helper, and 35 dylibs
(including 18 resolving symlinks). No Sparkle files, appcast, feed keys or Sparkle executable dependency
were found. This is still only ad-hoc static evidence, not a provisioned or runtime-tested Store build.

Still parked: owner-assisted full `swift test --jobs 2` including AppControllerLaunchTests; process-tap
capture, sandbox runtime and permission prompts; provisioned Keychain/re-entry and login-item/FileVault
checks; provisioned Apple signing, TestFlight and App Review. No launch, full suite, release or upload was
performed for this retained artifact rebuild.

[^verification]: BESEDA-288 verification handoff supplied the artifact path, digest, static checks and
filtered test results. Its ignored worktree artifact is no longer present; BESEDA-290 repeated the archive, build and full-bundle static checks on a new copy.
