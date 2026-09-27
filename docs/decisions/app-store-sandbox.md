---
type: Decision Record
title: App Store sandbox audit
description: Source audit and private stub-signing evidence for Beseda's App Sandbox route.
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
  - id: apple-taps
    title: Apple Core Audio process tap sample and permission notes
    url: https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps
  - id: apple-sandbox
    title: Apple App Sandbox entitlement
    url: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox
  - id: apple-input
    title: Apple Audio Input entitlement
    url: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input
  - id: apple-system-usage
    title: Apple system audio capture usage description
    url: https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription
  - id: apple-mic-usage
    title: Apple microphone usage description
    url: https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription
---

# App Store sandbox audit

## Scope and evidence

This is a local source audit with the private packaging checks recorded below. The archive was downloaded,
but no app was launched or installed, no live user data was used, and no provisioned signature, runtime,
TCC or App Review check was performed. Those checks are **parked**, not failed. The status labels mean:

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
| FileVault check (`fdesetup`) | **unconfirmed; no source-justified change** | The app launches `/usr/bin/fdesetup isactive` with `Process` (`Sources/Beseda/Storage/StorageJanitor.swift:200-226`). No available local Apple or kit document establishes whether the sandbox profile permits that executable. Do not claim pass or denial without the runtime check; the feature already represents an unclear result as `nil`. | Small if `Process` is allowed; medium to replace or omit the status feature if denied. | In the sandbox build on FileVault-on and FileVault-off Macs, call the check and inspect unified sandbox-denial logs; verify exact true/false parsing and the `nil` UI path. |
| Time Machine backup exclusion | **works** | Despite the feature wording, the code does not execute `tmutil`: it sets and reads `URLResourceValues.isExcludedFromBackup` on the app data directory (`Sources/Beseda/Storage/StorageJanitor.swift:175-186`). That directory is inside the app's own Application Support/container, so no extra external-file access is implied. | Small/no code change. | Toggle exclusion in the sandbox build, relaunch, verify the resource value both ways, create a new call and confirm the directory flag still covers it; optionally confirm `tmutil isexcluded` only as an external diagnostic. |
| Keychain access group | **re-entry chosen; provisioned behavior unconfirmed** | Generic-password queries specify class, service and account but no `kSecAttrAccessGroup` (`Sources/Beseda/App/Keychain.swift`). `Keychain.app` derives the service from the bundle identifier; `AppSettings.loadSecrets` reads both keys and leaves them empty when unavailable. The direct-build ACL copy is signature-based, not evidence of access from a provisioned Store signature ([Build and release](../architecture/build-release.md#keychain-keys-survive-the-identity-change)). | No speculative migration or explicit group entitlement. Use the Store app's provisioned default access group; ask users to re-enter OpenRouter and webhook secrets if absent. Do not delete direct-build items. | On a provisioned sandbox build, inspect actual signed entitlements and `SecItem*` results; save/read/update/delete both secrets across relaunch. Upgrade from a direct build with existing keys on a disposable account: verify absence leads to re-entry without repeated prompts and that the direct build still retains its keys. If provisioning denies default-group writes, revisit the entitlement with the assembly owner using observed group and Team ID. |

## Process-tap sandbox research

**Works (API shape, not sandbox capture):** Apple's [Core Audio tap sample](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps) creates a tap and HAL aggregate device, matching `SystemAudioTap.start`. Apple specifies macOS 14.2 or later and says the system prompts for system audio recording permission when recording first starts from an aggregate containing a tap. The [system-audio usage key](https://developer.apple.com/documentation/bundleresources/information-property-list/nsaudiocaptureusagedescription) is `NSAudioCaptureUsageDescription`, already present in Beseda's plist. System audio permission is separate from microphone permission; creating an aggregate does not prove nonempty captured samples.

**Unknown:** Apple's [App Sandbox entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox) enables sandboxing, and its [Audio Input entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.audio-input) permits microphone recording and Core Audio input. Neither explicitly promises sandboxed process-tap capture; the tap sample does not assert sandbox compatibility. `com.apple.security.device.audio-input` is in the direct-build entitlements, but `com.apple.security.app-sandbox` is not. [Microphone usage text](https://developer.apple.com/documentation/bundleresources/information-property-list/nsmicrophoneusagedescription) is required for APIs accessing the device microphone; it cannot substitute for system-audio usage text. A compile-only helper could verify API linkage and entitlement syntax, not permission or samples; no helper was built because it cannot resolve the release gate.

**Blocker to proof (live test parked):** A fresh bundle identity has no Screen & System Audio Recording TCC grant, so starting its aggregate may prompt. The authorized real app has Mikhail's live Application Support, defaults, Keychain and potentially calls in progress. `CFFIXED_USER_HOME` does not isolate defaults or login Keychain, and changing identity loses TCC authorization (ios-kit `docs/macos.md`). There is no safe unattended no-focus capture on the real bundle without touching his data. Owner-assisted gate: on a separate macOS user account or disposable Mac with no real Beseda data, sign a sandboxed build with the intended store identifier, `app-sandbox` and `device.audio-input` entitlements and applicable usage descriptions; have the owner explicitly grant Screen & System Audio Recording if prompted. Route a known fixture exclusively to BlackHole (never Mac output), capture to a temporary file for a fixed short interval, verify nonzero sample energy and no sandbox denial, stop and repeat after relaunch. Verify microphone authorization separately if microphone capture is in scope. Never transfer the owner's live container, defaults or Keychain. Until then, sandboxed call capture is **unknown**, not a pass.

## Proposed decision

A store-specific runtime path now selects a bundle helper via `BesedaStoreSummary` and does not
fetch or execute Application Support code. A deterministic fixture check (`bash scripts/test_package_store_summary.sh`)
rejected a wrong hash and confirmed helper/dylib placement, plist flag and inheritance-entitlement signing
arguments without running the helper. On 2026-09-28, the pinned b10819 archive matched SHA-256
`8933e736495eadfef0731ae32054acfaa75699bf4a6ccba77cd8475db085ec66`;
`package_store_summary.sh` embedded it into a private minimal stub app, ad-hoc signed it (`-`), and
`codesign --verify --strict --deep` passed. This is **not** a Developer ID or provisioned store signature,
a full Beseda bundle, or a sandbox launch. No signed store build or sandbox runtime test has been performed. The App Store
route remains **blocked pending a complete store build** (including the independent Sparkle split). Before submission it also
requires persistent security-scoped export access, a store build without Sparkle and store entitlements. In-process CTranscribe, EventKit and the resource-value backup
exclusion fit the sandbox based on current source. Process tap, login item and `fdesetup` remain explicitly
unproven until the parked signed/live checks run; available local evidence does not justify a stronger
claim.

**Secret decision (source-verified, runtime parked):** The Store build does not claim direct-build ACL transfer and does not request a shared Keychain group for migration. Secrets are re-entered when unavailable. The app uses the default provisioned Keychain group, with no explicit `kSecAttrAccessGroup` in queries; no entitlement change is requested from the assembly worker unless the provisioned check proves this fails. No live Keychain call was made. A user with keys still in UserDefaults may instead have those values migrated by `AppSettings.loadSecrets`; that source path is not proof of cross-signature Keychain access. Test re-entry and rollback only in an owner-approved disposable account, not against the live login Keychain.

**Other parked runtime checks:** `SMAppService.mainApp` is already the native login-item API and handles approval/error states in Settings; no source evidence warrants a fallback. Install the provisioned sandbox app in Applications on the disposable account, register, approve if requested, log out/in, verify background start and unregister. `FileVault.isOn` already returns `nil` for a failed `Process.run`, unknown exit code or unrecognized output. Do not replace `fdesetup` on speculation: on owner-approved FileVault-on and FileVault-off test Macs, compare true/false/nil with actual status and sandbox denial logs, and confirm the unknown-status UI remains honest. Neither feature was exercised here.

Only private ad-hoc stub signing is recorded above; no app was launched. When an App Store target exists, run the exact
checks in the table and update this proposed record with observed results and the target's final
entitlements.

[^kit]: The repository's kit is at `/Users/mikhail/w/learning/ios-kit`; the relative link resolves when the project remains in its documented sibling layout. Its guidance says isolated bundle IDs have no TCC grants and share the login Keychain, so permission prompts and Keychain behavior require a deliberately signed/live check rather than an audit launch.
