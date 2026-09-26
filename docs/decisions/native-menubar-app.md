---
type: Decision Record
title: Native SwiftUI menu-bar app
status: accepted
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
---

# Native SwiftUI menu-bar app

**Status: accepted.**

## Context
The [MVP phase plan](../archive/mvp-phase-plan.md) fixed "macOS menu bar app" and a "SwiftUI menu bar app" in
its architecture; [Swift app pipeline](../archive/swift-app-pipeline.md) built it as a SwiftPM executable wrapped
into a local `.app`, "menu-bar-first through SwiftUI `MenuBarExtra`". The capture path it needs (Core Audio process taps, `AVAudioEngine`) is native API.
The [native UI plan](../archive/native-ui-plan.md) later replaced custom controls with system ones: "system
controls over custom ones".
Rationale: incidental — how it was first built; open to change if a refactor improves quality or
load (Mikhail, 2026-09-26). See [refactor for quality and load](refactor-for-quality-and-load.md).

## Decision
One SwiftPM target, SwiftUI, `MenuBarExtra` popover as the entry point (`App/BesedaApp.swift`) plus a
conversations window and Settings; system controls (`Toggle`, `Picker`, `NavigationSplitView`, `Form`).

## Consequences
- macOS only; the minimum is macOS 14.2 (`Package.swift`), which process taps need.
- Built and packaged by `scripts/`, not an Xcode project.
