# Beseda UX concepts

Static light-appearance **concepts, not product screenshots**. All names, dates and statuses are illustrative fixtures. Drawn directly to PNG using Pillow with no app, browser, macOS window, capture permission, audio or live data. At 1200 × 900, these frames show proposed hierarchy, not native SwiftUI controls, verified interactions or current appearance. Baselines are repository preview/fixture images, not evidence of today's rendered UI; current behavior is inferred from source and the [sales UX audit](../../../docs/decisions/design-review-sales.md).

| Concept | Existing comparator | Change and what a person notices |
| --- | --- | --- |
| [01 — first-run channels](01-first-run-channels.png) | [older dark onboarding test](../BESEDA-75/after/onboarding-4-добро-пожаловать-в-beseda.png), [older model step](../BESEDA-75/after/onboarding-3-добро-пожаловать-в-beseda.png) | Separate mic success and system-audio failure, with an explicit one-sided-call consequence and installed-model handoff. A person sees what remains unsafe before continuing, not just a green combined meter. `OnboardingWindow.swift` already reports separate outcomes; this is a proposed presentation, not a claim that the app currently renders it. |
| [02 — effective processing](02-processing-effective-provider.png) | [later light local-only preview](../BESEDA-99/processing-local-only-openrouter-обработка.png), [older dark processing pane](../BESEDA-75/after/settings-processing-обработка.png) | Put actual local provider/outbound-text status ahead of selected-but-overridden OpenRouter and installed speech model. A person can distinguish preference from effective behavior at a glance. `SettingsWindow.swift` supplies effective-provider and privacy logic; this composition is hypothetical. |
| [03 — archive and current result](03-archive-current-result.png) | [later light expanded previous-result fixture](../BESEDA-99/previous-default-digest-разговоры.png), [300-call archive fixture](../BESEDA-112/sidebar-300-calls-разговоры.png) | Date and source distinguish repeated titles; the collapsed previous digest stays subordinate to today's result. A person reaches the current outcome first. `CallDetailView.swift` opens processed calls on results and `PreviousCallBlock.swift` now collapses by default, so the expanded comparator is **not** today's default. |

## Phone-readable concept cards

The full 1200 px concepts become too small at 390 px. These reflowed Pillow cards are 780 px wide (2×); body text is 16 px at 390 px. They summarize the same invented scenarios, not native Mac screenshots or evidence of actual UI. Compare each card with its full concept above.

- [01 — channel outcomes and one-sided warning](01-first-run-channels-phone.png)
- [02 — effective local status versus selected OpenRouter](02-processing-effective-provider-phone.png)
- [03 — dated archive entries and today's result before the previous digest](03-archive-current-result-phone.png)

Source of design priorities: [sales UX audit](../../../docs/decisions/design-review-sales.md). No competitor UI or user behavior was verified. The static frames cannot establish native spacing, accessibility, dynamic text, scroll behavior or actual current light/dark rendering.
