---
type: Decision Record
title: Development directions
description: Where Beseda goes next — Mikhail's answers to the twelve decisions and the phased plan the next epics follow.
status: approved with changes
tags: [product, strategy, plan]
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
sources:
  - id: mikhail
    title: Mikhail's answers to the twelve decisions, 2026-09-26
  - id: analysis
    title: External product analysis pasted by Mikhail (competitors checked 2026-09-26)
---

# Development directions

**Status: approved with changes. Source: Mikhail, 2026-09-26.**[^mikhail] The plan at the end is what the
next epics follow.

## Context

Beseda records calls on the Mac with separate mic and system channels, transcribes locally, keeps an
archive with search, summarises with a user-editable prompt and sends a webhook. "No bot", "local", "has a
summary" and "has MCP" are already sold by others — MacWhisper, Meetily, Weeve (closest: Parakeet,
FluidAudio, local summaries), Granola, Fathom.[^analysis] The risk is an archive nobody opens, so the product
serves three moments: after the call, before the next one, and during it.

## Decisions

1. **Positioning** — "private memory of work conversations" is accepted as a working line, not final.
   Today Mikhail uses Beseda mainly as transcription during work calls; a reminder of what was said on the
   previous call is what he values most.
2. **First users** — two groups, both in: people who don't want to forget what was said at dailies and
   work calls, and psychologists.
3. **No fixed call card.** The post-call screen shows whatever processing ran: the transcript alone if only
   transcription ran, the summary if a summary ran. Summaries come from the user-editable prompt that exists
   today (`AppSettings.summaryPrompt`). New direction: a cheap local classifier first picks the call type
   (work meeting, daily, personal 1:1, psychology session, … — types defined by the user), then that type's
   prompt runs and its result is shown. The user configures what is collected and how it is shown.
4. **Speaker errors** — yes: the echo gate on the mic and the diarizer's timeline instead of per-word
   labels, as in [speaker-accuracy.md](speaker-accuracy.md).
5. **Recording to disk first** — yes, stream audio to disk while recording (today `PCMFloatRecorder` keeps
   the whole call in memory until stop). New optional mode: live transcription during the call, with key
   points of what was just discussed on screen; later contextual hints (e.g. who does what).
6. **Export is mandatory** — results into one chosen folder now; routed by call type later.
7. **Privacy basics** — yes: storage protection and deletion. Notifying the other side about recording is
   dropped entirely, by Mikhail's decision; the legal responsibility for recording stays with the user.
8. **Before handing it to people** — several polish rounds (cleanup, proofreading of UI copy, UI quality)
   and the features above. Users today: Mikhail and Irochka. A demand check comes later, with no fixed bar.
9. **Price** — one-time $49, everything included. Payment channel open: no Stripe (Russia), so crypto or
   the Mac App Store (Apple Developer enrollment in progress). See [App Store sandbox](#app-store-sandbox).
10. **"Before the meeting" block** — yes, and not deferred behind a demand check: where we stopped and what
    was agreed on the previous related call. See [Related calls](#related-calls).
11. **ASR benchmark and model choice** — skipped for now. Open question: Mikhail praises a local
    transcription app he dictates with (unnamed); what it runs and whether Beseda should match it.
12. **Windows** — only if it can come from one shared core. See [Windows](#windows).

## App Store sandbox

What the Mac App Store demands against what the code does today:

| Part | Today | In the sandbox |
|---|---|---|
| System audio (`Audio/SystemAudioTap.swift`, `AudioHardwareCreateProcessTap`, macOS 14.2+) | works | Process taps ask the user through `NSAudioCaptureUsageDescription`, not an entitlement; expected to work sandboxed, **to verify on a sandboxed build first** — it is the whole product. |
| Microphone (`Audio/MicrophoneCapture.swift`) | works | Needs `com.apple.security.device.audio-input`. Fine. |
| Calendar (`Calendar/CalendarService.swift`, EventKit) | works | Needs `com.apple.security.personal-information.calendars`. Fine. |
| llama-server (`Summarization/LlamaServer.swift`) | downloaded into Application Support by `BundledSummaryInstaller`, then run with `Process` | **Breaks**: review guideline 2.5.2 forbids downloading executable code. It must ship inside the bundle (signed, sandbox-inherited helper) or be linked as a library. |
| Speech and summary models | downloaded, hash-checked | Allowed — models are data. Needs `com.apple.security.network.client`. |
| Updates (Sparkle, `Runtime/AppUpdater.swift`) | appcast | Removed in the store build; the store updates. |
| Signing (`scripts/lib/bundle_app.sh`) | no hardened runtime, no entitlements | Hardened runtime and an entitlements file become required for both channels (notarization also needs them). |
| OpenRouter / LM Studio, webhook | HTTP | Network client entitlement. Fine. |
| Export folder (decision 6) | — | A user-picked folder kept through a security-scoped bookmark. |

**Verdict.** The store is possible once llama-server ships inside the bundle and the process tap is
confirmed sandboxed; everything else is an entitlement. **Alternative:** direct sale outside the store —
Developer ID signed and notarized DMG, Sparkle as today, payment in crypto with a licence key. It keeps the
downloaded runtime as is but still needs the hardened runtime.

## Related calls

No project model. A previous call is related when, simplest first:

1. same calendar series (EventKit recurring event) — or the same event title;
2. same call type (decision 3) and the same participants;
3. picked by hand from the list, when the first two find nothing.

The block shows that call's summary result — nothing inferred beyond it.

## Windows

Platform-bound today: system audio (Core Audio process taps), microphone and playback (AVFoundation),
diarizer and VAD (FluidAudio on CoreML), the whole UI (SwiftUI `MenuBarExtra`), calendar (EventKit),
Sparkle. Shareable in principle: transcribe.cpp (C++, cross-platform), llama-server, the SQLite store,
the transcript assembly (`Transcription/` merging and sentence building, pure Swift), prompts and webhook.

**Verdict: separate product → postponed.** Capture, diarization and UI — most of the app — would be
rewritten; a shared core means porting the Swift logic to C++ or Swift-on-Windows first, which is not worth
it before the Mac version has users.

## Plan

Ordered phases; each line is its definition of done. What needs no new UI and protects data goes first.

0. **Stream to disk, macOS 14.2 minimum.** Both channels are written to disk while recording, a crash
   loses at most seconds; `Package.swift` and the 14.2 `#available` branches collapse to macOS 14.2.
1. **Speaker fixes.** Echo gate on the mic and the diarizer timeline ship in the app; the
   speaker-accuracy numbers hold on a real echoed call.
2. **Processing pipeline.** User-defined call types; a local classifier picks one ([which classifier](call-type-classifier.md)); that type's prompt runs;
   the post-call screen shows what ran; results export as Markdown to one chosen folder.
3. **"Before the meeting" block.** For a call with a related previous call, the block shows where it
   stopped and what was agreed.
4. **Live transcription mode.** Optional; the transcript and key points of the last minutes appear during
   the call.
5. **Polish rounds.** UI copy proofread, a UI review applied, storage protection and deletion in place.
6. **Distribution.** Sandbox check done; App Store or direct build shipped with a $49 payment path.

**In parallel without sharing files:** 0 (`Audio/` recorder, `Package.swift`) and 1 (`Transcription/`
speaker code, mic gate at the capture boundary — coordinate if the gate lands in `Audio/`) and the sandbox
check of 6 (`scripts/`, a throwaway build). 2 and 3 share the post-call screen and `Storage/`, so 3 follows
2; 4 needs 0's streaming. 5 runs last over everything.

[^mikhail]: Mikhail's answers to the twelve decisions, 2026-09-26.
[^analysis]: External product analysis pasted by Mikhail, competitors checked 2026-09-26.
