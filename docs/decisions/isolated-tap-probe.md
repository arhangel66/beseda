---
type: Decision Record
title: Isolated process tap feasibility probe
description: Owner-supervised contract for a disposable sandboxed Core Audio tap experiment.
status: proposed
sources:
  - id: implementation
    title: Beseda SystemAudioTap implementation
    url: ../../Sources/Beseda/Audio/SystemAudioTap.swift
  - id: store
    title: Store app entitlements and Info.plist
    url: ../../scripts/store_summary_app.entitlements
  - id: runbook
    title: Owner-supervised sandbox capture experiment
    url: app-store-sandbox.md#owner-supervised-sandbox-capture-experiment-not-run
---

# Isolated process tap probe

Contract for WholeBook/ios-kit, **not** an implementation in Beseda. Use a standalone, provisioned, sandboxed macOS 14.2+ app with fixed bundle ID `app.beseda.TapProbe`. Do not import or load Beseda app code at runtime, reuse its Application Support, defaults or Keychain, or request its existing TCC grant. The probe has no account, profile, network, push, GUI or microphone recording. Its own `NSAudioCaptureUsageDescription` must explain the system-audio fixture capture. Request only `com.apple.security.app-sandbox` and `com.apple.security.device.audio-input` (the Store app has both); omit network-client, calendars, user-selected-file and Keychain capabilities: the fixture/player and bounded result can live in the disposable account/container. Inspect the actual signed entitlements and matching **probe** profile before interpreting results; neither the audio-input entitlement nor a usage string guarantees tap authorization.[^store]

Mirror the integrated `SystemAudioTap` path, not a generic output recorder: translate this process PID via `kAudioHardwarePropertyTranslatePIDToProcessObject`; use `CATapDescription(stereoGlobalTapButExcludeProcesses:)` with that object when available, or an empty exclusion list when unavailable; set a private tap, `muteBehavior = CATapMuteBehavior(rawValue: 0)!`, then `AudioHardwareCreateProcessTap`. Read `kAudioTapPropertyFormat` and `kAudioTapPropertyUID`. Create a private aggregate with a unique UID, the tap UID in `kAudioAggregateDeviceTapListKey`, `kAudioSubTapDriftCompensationKey: true`, and `kAudioAggregateDeviceTapAutoStartKey: true`. Create a block IO proc on that aggregate, then `AudioDeviceStart`. Collect only aggregate **input** samples in the tap format, with finite-sample and channel accounting. Stop with `AudioDeviceStop`, destroy IO proc, destroy aggregate, then destroy tap, even on partial startup failure. Record every call's result as numeric OSStatus and fourCC where printable; report failed property reads and teardown too. Do not copy Beseda's recorder, UI, runtime or persistence.[^implementation]

Owner-safe preparation follows the [supervised runbook](app-store-sandbox.md#owner-supervised-sandbox-capture-experiment-not-run): disposable macOS account/test Mac, owner present for signing/key authorization and TCC, exact source revision, OS, fixed bundle identity, signature/profile/entitlements, known externally generated synthetic spoken WAV followed by silence, fixture hash and BlackHole identity. Route the **external player's output to BlackHole 2ch only**, never the default output, multi-output device or speakers; disable monitoring. If the tap excludes the probe's own process, an in-probe player is invalid unless its audio is demonstrably capturable as a separate process; prefer the external fixture. Do not change the host default route. Stop if sound reaches speakers, a window steals focus, an unexpected prompt appears or isolation cannot be verified. No live calls or user data.[^runbook]

For each of two runs under the **same probe bundle ID** (quit and relaunch between them), bound capture to 5 seconds total, including fixture and equal-duration playback-stopped silence control. Record system-only sample count, format, duration, per-channel RMS for speech and silence, finite-sample status, start/stop timestamps and cleanup outcomes. Capture relevant sandbox and `tccd` denial logs for this bundle ID with private content redacted; note the owner's Screen & System Audio Recording grant or denial. A representative feasibility **PASS** requires the known phrase recognizable by offline inspection of saved probe-only samples, finite nonzero system samples in both runs, speech RMS > 0.01 full scale and > 10× each run's own silence RMS, and no sandbox/TCC denial. A grant or successful tap creation alone is not a pass. Route uncertainty, missing control or signature makes the trial inconclusive; repeatable denial/silence with verified setup fails. Retain only fixture, hashes and sanitized measurements/logs in the project evidence directory; stop player, quit probe, remove its disposable files/grants and confirm no aggregate or monitoring remains.[^runbook]

A probe PASS establishes **representative process-tap feasibility only**. TCC authorization is per bundle ID and cannot transfer to `app.beseda.Beseda`; actual Beseda Store runtime PASS requires the separately provisioned full Store app, its own owner-approved grant, system-only capture/control and relaunch under the [Store runbook](app-store-sandbox.md#owner-supervised-sandbox-capture-experiment-not-run). Do not launch, sign, request permission or play audio unattended for this specification.

[^implementation]: [Integrated tap source](../../Sources/Beseda/Audio/SystemAudioTap.swift).
[^store]: [Store entitlements](../../scripts/store_summary_app.entitlements) and [Info.plist](../../Sources/Beseda/Resources/Info.plist).
[^runbook]: [Owner-supervised sandbox capture experiment](app-store-sandbox.md#owner-supervised-sandbox-capture-experiment-not-run).
