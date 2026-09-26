# Baseline screenshots (before the cleanup)

Taken 2026-09-26 on branch native-ui with main merged in, from an isolated copy of the app
(bundle id `dev.baseline.beseda`, `CFFIXED_USER_HOME` in a temp dir, one made-up call seeded into its SQLite).
How: the ios kit's `docs/macos.md`.

- `conversations-transcript.png` — main window: sidebar with the seeded call, detail on the Transcript tab, player bar.
- `onboarding-step1.png` — first-run onboarding, step 1 of 4 ("your conversations stay on this Mac").
- `menubar-popover.png` — the menu bar popover, opened through `BESEDA_PREVIEW_POPOVER=1`.

Missing: the Summary (Итоги) tab and the Settings window need a click or ⌘, and the shell that took these had
no Accessibility permission, so no synthetic input was possible.
