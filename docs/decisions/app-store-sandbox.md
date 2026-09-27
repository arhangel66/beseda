---
type: Decision Record
title: App Store sandbox audit
description: Source-only audit of the App Sandbox effects on Beseda's current macOS features.
status: proposed
tags: [distribution, macos, sandbox, app-store]
generated:
  by: agent
  at: 2026-09-28T00:00:00Z
sources:
  - id: source
    title: Beseda source tree, audited 2026-09-28
  - id: build-release
    title: Beseda build and release documentation
  - id: kit-macos
    title: ios-kit macOS SwiftPM guidance
---

# App Store sandbox audit

## Scope and evidence

This is a local source and documentation audit. It did not build, sign, launch or install an app and did
not use the network or live user data. Consequently, every runtime, signing, TCC and App Review check below
is **parked**, not failed. The status labels mean:

- **works** — the implementation shape is compatible, subject to the listed parked check;
- **needs change** — known code or packaging work is required;
- **blocker** — the current implementation cannot be submitted as-is.

The repository has no App Store target or sandbox entitlement. Its current entitlements only contain audio
input and calendars (`scripts/Beseda.entitlements:5-8`), while the package always links Sparkle and
CTranscribe (`Package.swift:13-26`, `Package.swift:39-43`). The existing build documentation confirms the
current product is not sandboxed and deliberately omits the network-client entitlement
([Build and release](../architecture/build-release.md#developer-id-и-нотаризация)). The kit documents why
permission and Keychain behavior cannot be inferred from an isolated launch
(ios-kit `docs/macos.md`); those checks remain parked.[^kit]

## Findings

| Area | Status | Source evidence and sandbox effect | Effort | Exact later check |
|---|---|---|---|---|
| Core Audio process tap | **works, unconfirmed** | The app creates a private global `CATapDescription`, then calls `AudioHardwareCreateProcessTap` and creates an aggregate device (`Sources/Beseda/Audio/SystemAudioTap.swift:47-57`, `Sources/Beseda/Audio/SystemAudioTap.swift:61-78`). `NSAudioCaptureUsageDescription` already exists (`Sources/Beseda/Resources/Info.plist:31-32`). No local Apple or kit document establishes that these Core Audio calls work from App Sandbox, so this is not a proven pass. | Small configuration; potentially large if the API is denied. | In a development-signed sandbox build with `com.apple.security.app-sandbox`, grant system-audio capture, record known audio through the tap, verify non-empty samples, stop, and repeat after relaunch. This is the release gate. |
| Downloaded `llama-server` execution | **blocker** | The app downloads and extracts an archive, preserves `llama-server` and dylibs in Application Support (`Sources/Beseda/Summarization/BundledSummaryInstaller.swift:119-147`), then executes that downloaded path with `Process` (`Sources/Beseda/Summarization/LlamaServer.swift:76-106`). This is downloaded executable code, not an App Store-compatible package shape. | Large: ship a signed bundled helper with sandbox inheritance, or link llama.cpp in-process; remove runtime download/extraction. | Inspect the archive and signatures; run summary warm-up and a real local summary in the sandbox build; verify helper launch, dylib loading, termination and relaunch. Then submit that exact architecture for App Review. |
| transcribe.cpp / CTranscribe | **works** | ASR is in-process: `LocalTranscriber` imports `TranscribeCpp` and opens only the downloaded model as data (`Sources/Beseda/Transcription/LocalTranscriber.swift:1-7`, `Sources/Beseda/Transcription/LocalTranscriber.swift:142-150`). CTranscribe is a pinned binary XCFramework, not a downloaded runtime (`Package.swift:18-32`), and the current bundle script already signs its framework ([Build and release](../architecture/build-release.md#signing-in-place-works-with-either-identity)). | Small packaging/signing work. | In the sandbox build, inspect embedded framework signatures and entitlements, load each supported downloaded model, transcribe a bundled fixture, and verify Metal/library validation produces no sandbox denial. |
| Speech and summary model downloads | **needs change** | Speech models are downloaded as files and hash-checked before install (`Sources/Beseda/Runtime/RuntimeInstaller.swift:155-180`); the summary model follows the same data-file pattern (`Sources/Beseda/Summarization/BundledSummaryInstaller.swift:151-163`). The App Store target needs outbound network access; the current entitlement file has none. The summary install path must be split from the prohibited executable download above. | Small for `com.apple.security.network.client`; medium to split summary model from runtime installation. | Download each model over HTTPS in a clean sandbox container, interrupt and resume/retry, reject a bad hash, warm up ASR and summarization, then remove and redownload it. |
| Export folder | **needs change** | The picker stores only `url.path` (`Sources/Beseda/App/Views/SettingsWindow.swift:631-638`), settings explicitly say there is no bookmark (`Sources/Beseda/App/AppSettings.swift:255-258`), and later background exports recreate a URL from that path (`Sources/Beseda/App/AppController.swift:1594-1601`). Access granted by the panel is therefore not persisted across launches. | Medium: add user-selected read/write entitlement, store stale-aware security-scoped bookmark data, resolve it, and balance resource access around export and deletion. | Pick a folder outside the container, export, quit and relaunch, export and delete an export again; move/rename the folder and verify stale-bookmark recovery; deny or revoke access and verify a visible, recoverable error. |
| Sparkle | **needs change** | Sparkle is an unconditional package dependency (`Package.swift:14-16`, `Package.swift:39-43`), `AppUpdater` imports it and performs update installation (`Sources/Beseda/Runtime/AppUpdater.swift:1-3`, `Sources/Beseda/Runtime/AppUpdater.swift:32-67`), and the bundler always copies its framework (`scripts/lib/bundle_app.sh:34-40`). Mac App Store supplies updates instead. | Medium: separate store package/build condition, omit Sparkle code, framework, feed keys, settings and licenses while retaining it for direct distribution. | Inspect the store archive dependency graph and bundle for Sparkle symbols/files and `SU*` plist keys; install through TestFlight and verify StoreKit/App Store update ownership. |
| EventKit | **works** | The app requests full event access and reads calendars/events (`Sources/Beseda/Calendar/CalendarService.swift:38-61`, `Sources/Beseda/Calendar/CalendarService.swift:80-99`). Both usage text and the calendar entitlement already exist (`Sources/Beseda/Resources/Info.plist:33-36`, `scripts/Beseda.entitlements:7-8`). | Small: carry these into the store profile/entitlements. | On a sandbox build with a clean TCC state, test allow, deny, Settings recovery, calendar selection and event matching after relaunch. |
| Login item | **works, unconfirmed** | Settings uses `SMAppService.mainApp.register()`/`unregister()` and handles `requiresApproval` (`Sources/Beseda/App/Views/SettingsWindow.swift:160-188`). This is the platform API, but no available local document proves its App Store behavior. | Small configuration if accepted. | Install the sandbox build in Applications, enable and approve it in Login Items, log out/in, verify background launch without UI focus, then unregister and verify it stays off. |
| FileVault check (`fdesetup`) | **needs change, evidence incomplete** | The app launches `/usr/bin/fdesetup isactive` with `Process` (`Sources/Beseda/Storage/StorageJanitor.swift:200-226`). No available local Apple or kit document establishes whether the sandbox profile permits that executable. Do not claim pass or denial without the runtime check; the feature already represents an unclear result as `nil`. | Small if `Process` is allowed; medium to replace or omit the status feature if denied. | In the sandbox build on FileVault-on and FileVault-off Macs, call the check and inspect unified sandbox-denial logs; verify exact true/false parsing and the `nil` UI path. |
| Time Machine backup exclusion | **works** | Despite the feature wording, the code does not execute `tmutil`: it sets and reads `URLResourceValues.isExcludedFromBackup` on the app data directory (`Sources/Beseda/Storage/StorageJanitor.swift:175-186`). That directory is inside the app's own Application Support/container, so no extra external-file access is implied. | Small/no code change. | Toggle exclusion in the sandbox build, relaunch, verify the resource value both ways, create a new call and confirm the directory flag still covers it; optionally confirm `tmutil isexcluded` only as an external diagnostic. |
| Keychain access group | **needs change** | Generic-password queries specify class, service and account but no `kSecAttrAccessGroup` (`Sources/Beseda/App/Keychain.swift:45-53`, `Sources/Beseda/App/Keychain.swift:89-93`). The current entitlements contain no keychain access group (`scripts/Beseda.entitlements:1-10`). The direct-build ACL migration documented today is signature-based and is not evidence for a provisioned App Store build ([Build and release](../architecture/build-release.md#keychain-keys-survive-the-identity-change)). | Medium: choose the store app identifier's provisioned group, add the entitlement, use it consistently, and define one-time migration from direct-build items or explicitly document that keys must be re-entered. | On a provisioned sandbox build, save/read/update/delete both secrets across relaunch; inspect `SecItem*` status codes; upgrade from a direct build with existing keys and verify the chosen migration or re-entry behavior without repeated prompts. |

## Proposed decision

The App Store route is **blocked by the downloaded `llama-server` architecture**. Before submission it also
requires persistent security-scoped export access, a store build without Sparkle, store entitlements and a
provisioned Keychain access-group decision. In-process CTranscribe, EventKit and the resource-value backup
exclusion fit the sandbox based on current source. Process tap, login item and `fdesetup` remain explicitly
unproven until the parked signed/live checks run; available local evidence does not justify a stronger
claim.

No signing or runtime result is recorded by this audit. When an App Store target exists, run the exact
checks in the table and update this proposed record with observed results and the target's final
entitlements.

[^kit]: The repository's kit is at `/Users/mikhail/w/learning/ios-kit`; the relative link resolves when the project remains in its documented sibling layout. Its guidance says isolated bundle IDs have no TCC grants and share the login Keychain, so permission prompts and Keychain behavior require a deliberately signed/live check rather than an audit launch.
