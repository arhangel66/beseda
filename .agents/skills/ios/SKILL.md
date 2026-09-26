---
name: ios-development
description: Apply the proven, platform-simple SwiftUI, accessibility, testing, and shell-loop practices for iOS work in this kit.
allowed-tools: [Read, Glob, Grep]
---

# iOS development

This local aggregate was adapted from GymBuddy's documented `.claude/skills/ios`
pattern at repository revision `4401a135c3ddb75ef45466647d802ea46b91defa`.
The staged aggregate referenced module files that were not present; the
available UI-test pattern was nevertheless compiled in 16 seconds in a private
baseline trial. See `docs/evidence/skills-prior-art-FAB-10.md`.

## Choose the smallest approach

- Keep a small local SwiftUI screen on `@State`, closures, and value types.
  Add MVVM, Combine, persistence, or networking only when the behavior needs
  them.
- Use semantic fonts/colors, SF Symbols, accessibility labels, and stable
  accessibility identifiers.
- For UI tests, assert structure and behavior through identifiers rather than
  brittle screen text. Keep XCUITest for UI automation.
- For shell work, use private DerivedData, a simulator owned by the run, and
  one explicit simulator UDID for build/install/launch/screenshot.

Review app code, UI, accessibility, and test boundaries separately. This skill
is guidance; it does not grant permission to run commands or claim an MCP-only
recipe was verified.
