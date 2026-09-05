# Native UI plan

Turns the findings in [ui-review.md](ui-review.md) into work. Mock-ups that were agreed on
2026-09-05 live in `untracked/ui-mockup/` (not committed). Branch `native-ui`; merged to
`main` after Mikhail checks each step on his Mac.

Rules for every step: system controls over custom ones, delete what becomes unused,
existing bindings and controller calls stay, tests green before push.

## Step 1. Menu-bar popover: constant skeleton
- [x] Layout never changes shape by state: status row → recording controls → last call → commands
- [x] Status row covers ready / recording / paused / processing / failed with an honest subtitle
      (microphone permission, auto-record on/off, error text with a next step)
- [x] Recording controls: `Начать запись` (disabled with reason while processing), pause/stop
      with level meters while recording; system `Button` and `Toggle`
- [x] Menu-bar icon reflects pause
- [x] Commands block always present: Разговоры…, Настройки…, Завершить Beseda with ⌘ hints
- [x] Version and «Обновления» leave the popover (they move to the app menu in step 4)
- [x] Check: `swift test`; idle state seen via `BESEDA_PREVIEW_POPOVER=1`, recording/processing/failed states need a live call (Mikhail)

## Step 2. System controls everywhere
- [x] `PillToggle` → `Toggle(.switch)` with a label
- [x] `AccentButton` / `OutlineButton` → `Button` with `.borderedProminent` / `.bordered`
- [x] `SegmentedTabs` → `Picker(.segmented)`
- [x] Split buttons in the call header → `Button` + `Menu`
- [x] `PodushkaControls.swift` keeps only Avatar, LevelMeter, SpeakerStrip, ProgressTrack,
      HighlightedText; file renamed to `Controls.swift`
- [x] Check: build + tests green; keyboard/VoiceOver walkthrough is Mikhail's (needs a live session)

## Step 3. Conversations window on the system frame
- [x] `NavigationSplitView` with `List(selection:)`; drop `hiddenTitleBar`, `ignoresSafeArea`,
      the traffic-light spacer, the sidebar toggle, manual row highlight
- [x] `.navigationTitle`, `.toolbar` (copy menu, link event, record), `.searchable` in the sidebar
- [x] Header: topic is the title; date · duration · app · participants on one secondary line
- [x] Transcript: consecutive lines of one speaker merged; seek on the timestamp, not the line
- [x] Player: `Slider` over the speaker strip; legend outside the drag area; Space = play/pause
- [ ] Check: ⌘F, arrow keys in the list, resizable sidebar, full screen (screen busy; pending)

## Step 4. Settings and app menu
- [x] `TabView` + `Form(.grouped)`: Основные / Запись / Обработка / Хранение / Интеграции
- [x] Основные: login item, notifications, updates (auto-update toggle, version, last check, Проверить сейчас…)
- [x] Обработка: speech model + summary model; server URL and prompt under «Дополнительно»
- [x] App menu via `CommandGroup`: «О Beseda», «Проверить обновления…»; remove `AboutSettings`
- [x] Honest processing note: name the real destination when the summary server is remote
- [ ] Check: ⌘, opens the right pane, deep links from summary/player still land (screen busy; pending)

## Step 5. Palette and type
- [x] Text colours → `.primary/.secondary/.tertiary`; accent → `Color.accentColor`;
      backgrounds → system materials; keep speaker colours, `searchHit`, recording red
- [x] Font sizes → `.body/.callout/.caption/.headline/.title2`
- [x] Delete unused `Palette` and `Metrics` members
- [ ] Check: dark mode, Increase Contrast, custom accent colour (screen busy; pending)

## Step 6. Shortcuts and copy
- [ ] `Commands`: ⌘R record, ⇧⌘C copy transcript, ⌘F search, Space/←/→ in the player
- [ ] One neutral voice: «Идёт запись», «Итоги», «Сведения», «строка меню»; no persona
- [ ] Webhook placeholder `https://example.com/webhook`; no «Podushka» in UI text
- [ ] Onboarding in its own window instead of a sheet
- [ ] Check: keyboard only walkthrough, long titles at minimum width
