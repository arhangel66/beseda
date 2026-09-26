# UI review — third pass (designer's eye)

Reviewer: Kimi, 2026-08-29. Method: read `untracked/design/prototype-v2.dc.html` and
`docs/ui-redesign-v2-plan.md`, read every view, then measured the running app
(pixel sampling + OCR of `screencapture` output in both appearances — this shell cannot
click, and the model cannot see, so everything below is verified against geometry and
colour, not vibes).

## What is already right

Measured against the prototype, these match and should not be touched:

- Toolbar: one 52 pt row, traffic lights inside it (toggle starts at 82 pt), search field
  260 pt, auto-record pill flush right. Light `#F2F2F4` / dark `#262628` both verified live.
- Sidebar: 300 pt, `#ECECED` / `#232325`, group captions, 52 pt time column, calendar
  glyph, accent selected row with white text, storage footer.
- Detail header: 21 pt headline, name line with badge and event link, meta line, the split
  copy button, 108 pt-min tabs.
- Transcript lines: 20 pt avatar, 2 pt speaker bar at the avatar's centre line, active-line
  tint `rgba(10,108,255,0.07 / 10,132,255,0.13)`, search-hit yellow `rgba(255,214,10,0.45)`.
- Player lanes: 74 pt label, 12 pt rail, share %, both speaker colours render, playhead
  hidden when there is no audio.
- The dynamic-colour trick in `DesignSystem.swift` works: dark mode measured `#1E1E1E`,
  `#232325`, `#262628` live. (Screenshot values for the accent read as `#306AF6` because
  the capture is Display P3 — the colour itself is correct.)
- Settings, menu-bar popover and onboarding follow the prototype's states.

## Findings, in the order a user meets them

### 1. The player bar changes shape between calls
`PlayerBar` drops the play button, the clock and the speed control when
`player.isAvailable` is false, so the lanes jump 50 pt to the left and the bar loses its
left anchor. Today *every* call in the index has lost its audio, and new calls will keep
it — so this is not an edge case, it is the dominant state, and any future call with audio
will look like a different control. Fix: the play button stays, disabled and grey; the
seek gesture is gated on `isAvailable`; the clock/speed stay replaced by the note.

### 2. A lock icon for "audio was deleted"
The missing-audio note leads with a lock glyph. A lock says "locked / private"; the
message is "the retention rule deleted this". `speaker.slash` says exactly that.

### 3. "Настроить" does not take you to the setting it names
The note's link opens Settings, but on whatever section was shown last — the retention
rule lives in Хранение. Same for the toolbar pill, which promises Запись. Fix: a
`requestedSettingsSection` string on the controller, set next to every `SettingsLink`,
consumed by `SettingsWindow` on appear/change.

### 4. The header meta shows a fake person
The meta line draws a monogram circle with the *app's* initial (e.g. "З" for Zoom) in
front of "Вы и собеседник". It reads as a person named З. The app knows the channel, not
the person — so the circle gets a `person.2` glyph (a `mic` for solo notes) instead of an
invented initial. Sidebar/popover rows keep the app monogram: there it stands for the
app, next to the app name, which is honest.

### 5. A failed call gets a broken-looking player
A failed call has audio but no transcript lines, so the bar shows a live play button next
to an empty 12 pt rail and a stray playhead. Fix: with no lanes, the track becomes one
plain progress capsule that still seeks and fills with the accent.

### 6. Scrubbing only seeks on mouse-up
The lane rails take `DragGesture.onEnded` only. Seeking on `onChanged` too gives a live
playhead while dragging — the standard expectation for a scrubber. (AVAudioPlayer seek is
cheap; the lanes redraw from `progress` anyway.)

### 7. No way to clear the search field
Standard macOS search fields offer an ×. One small button when the query is non-empty.

### 8. The popover's "done" state backs the wrong action
The prototype makes **Скопировать расшифровку** the primary action right after a call —
that is what the notification and the done state are *for*. The app makes "Открыть
разговор" the accent button and demotes copy to an outline button cryptically named
"Текст". Swap the emphasis and name the copy button "Скопировать".

### 9. The window has no minimum height
The root has no `minHeight`; the window can be crushed vertically until the toolbar,
transcript and player fight over scraps. Add `minWidth: 880, minHeight: 560`.

## Deliberately not touched

- **Every call being named «Миша созвон»** — that is the calendar matcher being generous
  (one long event covering many recordings), a data problem in `Calendar`/matching, not a
  view problem. Out of scope: the task limits this round to the interface.
- **`TranscriptLines` fallback rendering `markdownText` raw** when a call has markdown but
  no segments. Real state, but rare and harmless; a renderer for it is a feature, not a
  fix.
- **`ContentUnavailableView` for "no call selected"** — system styling, but it is honest,
  centred, and the prototype does not specify this state. Not worth a bespoke empty state.
- **Onboarding** — matches the prototype step for step.
- **Hover states on sidebar rows** — the prototype has none either.
- **«Итоги», «Модели», webhook** — still out of scope, no data behind them.

## Plan

- [x] PlayerBar: persistent (disabled) play button, `speaker.slash` note, gated + live seek,
      progress-rail fallback for lane-less calls, deep link to Settings → Хранение
- [x] AppController + SettingsWindow: `requestedSettingsSection`
- [x] ConversationsWindow: toolbar pill requests Запись; search field clear button;
      window min size
- [x] CallDetailView: pass controller to PlayerBar; participants glyph in the meta line
- [x] MenuBarPopover: copy becomes the primary action in the done state
- [x] Verify: swift build clean, swift test green (37), app builds, light + dark captures
      (`untracked/design/review-shots/`)
