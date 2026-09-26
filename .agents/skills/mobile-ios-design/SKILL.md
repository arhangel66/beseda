---
name: mobile-ios-design
description: Review and implement compact SwiftUI interfaces using iOS Human Interface Guidelines, semantic styling, accessibility, and stable UI-test anchors.
---

# iOS interface design

This retained skill is from `wshobson/agents` at source revision
`4236bb91f8395b0435f1d8b8baf9e8e4c69a8620`. The baseline trial compiled in
8 seconds and found a useful one-line accessibility improvement; evidence is
in `docs/evidence/skills-prior-art-FAB-10.md`.

## Small-screen defaults

- Use semantic fonts (`.body`, `.headline`) and semantic colors (`.primary`,
  `.secondary`, `.background`) so Dynamic Type and appearance changes work.
- Prefer SF Symbols for familiar actions.
- Keep navigation and sheets conventional: `NavigationStack`, `List`, and
  toolbar actions are preferable to custom chrome.
- Let stacks and safe areas size content. Avoid fixed screen coordinates in
  product UI.
- Give important controls stable `.accessibilityIdentifier` values. Combine a
  row's related values into one `.accessibilityElement` with a useful label
  when VoiceOver would otherwise read fragments out of context.

## Review checklist

Check clarity, contrast, Dynamic Type, dark mode, VoiceOver labels and hints,
hit targets, empty states, and iPad width before adding decoration. Test UI
behavior with XCUITest or AXe only when that recipe is separately verified;
this skill itself does not claim device testing.

For this kit, prefer a small semantic change over a new design abstraction.
The baseline's local `@State` and simple SwiftUI views are sufficient for a
small screen.
