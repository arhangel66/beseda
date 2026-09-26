# UI review: from home-made to native

Two independent reviews of the SwiftUI interface, 2026-09-05: Kimi (k3-256k, code only)
and Codex (GPT-6-Astra, code + screenshot). Both were asked about structure, native
conventions and professionalism, not colours. Claims below were verified against the code.
Full texts: bb threads `thr_mzjb543p96` (Kimi) and `thr_5bq539z6zt` (Codex).

Shared verdict: the app imitates system UI without its behaviour. The three surfaces
(menu-bar popover, Conversations window, Settings) are the right split; no rewrite needed.

## Findings both reviewers agree on

| # | Finding | Where | Fix |
|---|---------|-------|-----|
| 1 | Conversations window fakes the frame: `hiddenTitleBar`, `ignoresSafeArea`, hand-drawn toolbar with a 56 pt gap for traffic lights, fixed 300 pt sidebar, `onTapGesture` rows, custom search field. No arrow-key navigation, no ⌘F, no resizable sidebar. | `BesedaApp.swift`, `ConversationsWindow.swift`, `CallSidebar.swift` | `NavigationSplitView` + `List(selection:)` + `.navigationTitle` + `.toolbar` + `.searchable` |
| 2 | Custom controls instead of system ones: `PillToggle` is a Button (VoiceOver says "button", no focus ring, no label), `AccentButton`/`OutlineButton` on `.plain` lose pressed state and keyboard activation, `SegmentedTabs` is `Text.onTapGesture`. | `PodushkaControls.swift` and every caller | `Toggle(.switch)`, `.bordered`/`.borderedProminent` + `controlSize`, `Picker(.segmented)`. Keep only `SpeakerStrip`, `LevelMeter`, `Avatar`, `HighlightedText` |
| 3 | No keyboard shortcuts at all (`grep keyboardShortcut` is empty) while the UI promises ⌘C for the transcript format. | `CallDetailView.swift:446`, `BesedaApp.swift` | `Commands`: record, Space/arrows in player, ⇧⌘C copy transcript, ⌘F, "Quit Beseda" ⌘Q. Keep ⌘C for selected text |
| 4 | Settings are a hand-rolled sidebar + `ScrollView` + custom rows; grouped by implementation (login item under Recording, speech model under Storage). Storage icon is a lock. | `SettingsWindow.swift` | `TabView` + `Form.formStyle(.grouped)` + `Section`; panes General / Recording / Processing / Storage / Integrations; technical fields under "Advanced" |
| 5 | Palette duplicates semantic colours (`.primary/.secondary`, `controlAccentColor`, window backgrounds) with hex pairs; half-point font sizes 10.5/11.5/12.5/14.5. Breaks accent colour, Increase Contrast, inactive-window selection. | `DesignSystem.swift` | Delete most of `Palette`; keep speaker colours, `searchHit`, recording red. Use `.body/.callout/.caption/.headline` |
| 6 | Detail header inverts hierarchy: date at 21 pt, topic at 14.5 pt; badges, calendar link and two big split buttons crowd the same row. | `CallDetailView.swift` header | Topic is the title; date · duration · app on one secondary line; actions in `.toolbar`, split buttons → `Button` + `Menu` |
| 7 | Player drag gesture covers the speaker legend: clicking an avatar seeks. | `PlayerBar.swift` track | Gesture only on the strip; or a real `Slider` with the strip as decoration |
| 8 | About in Settings plus version + "Обновления" in the popover footer is not the macOS convention. | `AboutSettings`, `MenuBarPopover` footer | "About Beseda" and "Check for Updates…" in the app menu via `CommandGroup`; drop from the popover |
| 9 | Copy: mixed voice ("Остановлю сама" vs imperative), jargon ("Саммари", "Инфо", "меню-бар"), personal domain in the webhook placeholder, `X-Podushka-Secret` in UI text. | `MenuBarPopover`, `CallSidebar`, `SettingsWindow` | One neutral voice; "Итоги", "Сведения", "строка меню"; `https://example.com/webhook` placeholder |

## Findings from one reviewer only

- **Codex [critical]** Popover replaces its whole content per state: while recording or processing the "Разговоры / Настройки / Выйти" commands vanish; after a finished call there is no way to start a new recording without opening the window first. Fix: constant skeleton — status → recording controls → last call → common commands, with disabled-with-reason instead of hidden.
- **Codex [critical]** "Всё обрабатывается на этом Mac" is only conditioned on the webhook, but the summary server accepts any URL and receives the transcript. Show the real destination or restrict the server to localhost.
- **Codex** Popover always says "Микрофон и системный звук на месте" with no error branch; menu-bar label ignores pause; empty archive promises auto-recording even when it is off.
- **Codex** Primary button always copies the transcript, even on the summary tab. Transcript lines seek on click while also offering text selection.
- **Kimi** Onboarding is a 640×520 sheet over the main window; a first-run wizard belongs in its own window.
- **Kimi** UPPERCASE tracked section captions are an iOS pattern; monospace in the info tab for words, not just paths.
- **Kimi** The "Автозапись включена" pill in the toolbar looks like status but is a hidden settings link; toast overlay is not a macOS pattern.

## What is already right

- Popover as a state machine with honest progress (mm:ss in the menu bar while recording).
- `Settings {}` scene with deep links to a section; `SMAppService` with `requiresApproval` handling.
- `ContentUnavailableView` for no selection, `.textSelection(.enabled)` on transcripts.
- Custom drawing only where the system has nothing: `SpeakerStrip`, `LevelMeter`, avatars.
- Speaker colours consistent between transcript and player.

## Proposed order (merged, least churn first)

1. Popover: constant command skeleton, error/pause states, honest privacy text.
2. Controls: `PillToggle` → `Toggle`, custom buttons → system styles, `SegmentedTabs` → `Picker`. Mechanical, touches every view once.
3. Conversations window: `NavigationSplitView` + `List` + `.toolbar` + `.searchable`; drop the fake frame.
4. Settings: `TabView` + grouped `Form`; About and updates move to the app menu.
5. Palette and type: semantic colours and text styles; delete most of `DesignSystem.swift`.
6. Shortcuts and copy: `Commands`, one voice, neutral placeholders, header hierarchy, player gesture.
7. Check: keyboard only, VoiceOver, inactive window, dark mode, Increase Contrast, long titles at minimum width.
