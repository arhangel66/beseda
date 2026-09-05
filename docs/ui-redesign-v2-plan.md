# UI redesign v2 — what the app still gets wrong, and the calendar

Source: `untracked/design/prototype-v2.dc.html`, pulled from the claude.ai/design project
`46818607-492c-452d-84f4-f0136d039a36`, file `Podushka - Интерактивный прототип v2.dc.html`.
The v1 file stays next to it as `prototype.dc.html`; `docs/ui-redesign-plan.md` describes the
round that is already in the app.

Scope agreed with Mikhail: fix the four things that are visibly broken, close the gap to the
v2 design, and add the calendar. The webhook half of the v2 **Интеграции** section
(«Отправлять расшифровку на свой сервис») is **out** — it is the only thing that would leave
the Mac and it was not asked for. The **Итоги** tab and the **Модели** settings section stay
out, as before: nothing in the app produces their data.

The calendar gives the conversation its name and lists what is coming up. It does **not**
start recordings; recording still starts from the sound of a call app.

---

## 0. What is actually wrong today

Measured, not guessed:

| Complaint | Cause found in the code / data |
| --- | --- |
| Switching calls is slow | `TranscriptLines` draws every line in a plain `VStack`, not `LazyVStack`. The index holds a call with **2247** lines and five more over 500. Every line builds an `AttributedString` and turns on `.textSelection`. On top of that `CallDetailView` reads `player.currentTime`, so during playback the whole list is rebuilt 20 times a second, and `CallPlayer.load` kicks off `WaveformPeaks.peaks(from:)`, which reads the WAV files end to end. |
| The search field slid off the top row | The window is `.hiddenTitleBar`, but SwiftUI still hands the content a top safe-area inset, so the toolbar starts *below* the traffic lights instead of sharing the 52 px row with them. |
| No playback at all | Not a player bug: **no call folder on disk has audio**. Every existing recording was made by the older code that deleted audio right after the transcript, so `player.isAvailable` is false and `PlayerBar` is simply not shown — with no word about why. |
| «Кто где говорит» missing | v2 replaces the waveform with two per-speaker lanes. Nothing like it exists yet. |

---

## 1. Speed

- [x] `TranscriptLines`: `LazyVStack` instead of `VStack`, so only visible lines are built.
- [x] Pull the playing-line highlight out of the parent body. `CallDetailView` must not read
      `player.currentTime`; a small `TranscriptLine` subview reads it, so a player tick
      repaints the rows and not the screen.
- [x] Delete `Audio/WaveformPeaks.swift` and its call site — the v2 player track comes from
      the transcript lines, so no audio file has to be decoded to draw it.
- [x] `AppController.loadCallDetail`: log how long the three SQLite reads take, so a future
      slowdown has a number attached instead of a feeling.
- **Measured.** Temporary instrumentation walked all **52** calls in the index, timing the
  longest main-thread run-loop turn each switch caused — that turn is the freeze a person
  sees. Debug build, the same one `build_podushka_app.sh` installs.

  | Run | Worst freeze | Average | `20260622-065841` (2247 lines) |
  | --- | --- | --- | --- |
  | one switch every 0.7 s | 57 ms | 32 ms | 47 ms |
  | switch every 60 ms | 58 ms | 22 ms | 31 ms |
  | switch every 60 ms, search «the» active | 43 ms | 21 ms | 30 ms |

  The eager `VStack`, measured the same way, came out at 63 ms worst / 34 ms average — so the
  one-second freeze is **not reproducible in this code**, and `LazyVStack` is not what removed
  it. Something in the build Mikhail was running is already gone; the lazy list is still the
  right shape for a call this size and costs nothing to keep.

## 2. The toolbar and the title bar

The v2 toolbar is one 52 px row: traffic lights, sidebar toggle, «Разговоры», the 260 px
search field, and — pushed right — the auto-record status pill.

- [x] Drop the top safe-area inset so the content really starts at the window edge, and keep
      the 78 px leading gap for the traffic lights inside the row.
- [x] Sidebar toggle button (`#p-sidebar` icon): collapses the list to zero width, blue while
      the list is open, grey while it is closed. With the list closed the reading column in
      the detail pane centres itself, as in the prototype (`readInline`).
- [x] The auto-record pill: a dot (green on / grey off) plus «Автозапись включена|выключена»,
      opening Settings → Запись.
- [x] Remove «Записать», «Поделиться» and the gear from the toolbar — v2 has none of them.
      Recording starts from the menu bar popover, copying from the new button in the detail
      header, settings from ⌘, and from the pill.
- **Check:** a screenshot of the window matches the prototype's toolbar row: search field on
  the same line as the traffic lights.

## 3. The sidebar list

- [x] Row layout from v2: a 52 px right-aligned column with the start time (`14:08`, bold)
      over the duration (`34 мин`), then the title, then the meta line. The avatar circle goes.
- [x] A calendar glyph in front of the title when the name came from an event.
- [x] «Дальше по календарю» block above the list — see §6.
- **Check:** light and dark, selected and not, a search hit inside a title still highlighted.

## 4. The detail header

- [x] Big line: `Сегодня, 18:31 · 31 мин` — when and how long, tabular figures.
- [x] Name line: calendar glyph (when the name is from an event), the name, a grey badge
      «из календаря» or «по теме разговора», and a blue «Привязать событие» / «Изменить»
      that opens the event picker (§6).
- [x] Meta line: avatar, who, app, and the «два канала» badge.
- [x] «Скопировать расшифровку» as a split button with a format menu:
      **Диалог с таймкодами** / **Чистый диалог** / **Markdown для заметок**. The chosen
      format sticks and is what ⌘C copies. The prototype's fourth entry, «Только итоги», is
      dropped — there are no summaries.
- [x] `AppSettings.copyFormat` holds the choice.
- **Check:** each format lands on the clipboard in the shape its menu line promises; the
  toast names the format.

## 5. Transcript lines and the player

- [x] Line layout from v2: a 20 px avatar circle, the speaker name, the timecode; below it
      the text with a 2 px coloured bar down its left side. Speaker colours from the
      prototype — me `#4b57d8`, the other side `#e0654a`, each with its soft avatar fill and
      ink. Names stay «Вы» and «Собеседник»: the app knows the channel, not the person.
- [x] `PlayerBar` rebuilt as the v2 track: one lane per speaker — a 74 px label, a 12 px
      rail with a rounded segment per line (dimmed ahead of the playhead, solid behind it),
      and the share of talk time in per cent on the right. A blue 1.5 px playhead crosses
      both lanes. Clicking anywhere on the rails seeks.
- [x] Show the bar whenever a call is selected. When the audio is gone, the bar carries the
      reason instead of the controls — «Аудио удалено по правилу хранения» with a link into
      Settings → Хранение — rather than disappearing without a word.
- [x] Keep play/pause, the clock and the 1×/1.5×/2× cycle.
- **Check:** record a short two-channel call, then open it — both lanes fill in, the playhead
  tracks the audio, clicking a lane seeks, clicking a line seeks, the playing line highlights.
  Open an old call — the bar explains why there is nothing to play.

## 6. Calendar

- [x] `Calendar/CalendarService.swift` — one class over `EventKit`: access request, the list
      of calendars, events in a range, and the match for a call.
- [x] `Resources/Info.plist`: `NSCalendarsFullAccessUsageDescription` (macOS 14 splits
      calendar access; events need full access even to be read).
- [x] `AppSettings`: `calendarEnabled`, `calendarIdentifiers` (empty = all).
- [x] `CallStore`: `event_title`, `event_id`, `event_pinned` columns, added next to the
      existing ad-hoc `columnExists` migrations.
- [x] Matching: the event whose **start** is within ±5 minutes of the recording's, and that
      was planned for more than 15 minutes. Overlap alone is not enough — a flight, a "Busy"
      block or a day-long hold would otherwise name every call inside it. New calls are
      matched when they are saved; the calls already in the index are matched in one pass —
      one EventKit fetch over the whole range, then matched in memory — when the browser
      opens with the calendar on. A pinned call is never re-matched.
- [x] `StoredCallSummary.displayTitle` prefers the event title; the transcript-derived title
      stays the fallback and keeps the badge «по теме разговора».
- [x] Event picker in the header: the events near the call's start, plus «Без события».
      Choosing one sets `event_pinned`.
- [x] «Дальше по календарю» in the sidebar: events from now to the end of tomorrow, each with
      time, name, and «запишу» / «пропущу». **«запишу» means:** auto-record is on *and* the
      event carries a conferencing link (`EKEvent.url`, location or notes pointing at Zoom /
      Meet / Teams / Telegram). It is a guess about the event, and the hint under the block
      says so. The block hides itself when the calendar is off or nothing is coming up.
- [x] Settings → **Интеграции**: the «Брать название из календаря» switch, the account row
      with «Выбрать календари», and the honest counter «Событие нашлось у N из M разговоров».
- **Check:** unit tests for the match (event starting with the call, 4 minutes off, 6 minutes
  off, a long event the call merely falls inside, a 10-minute event, a 15-minute event, two
  events starting nearby, no events); with the calendar off nothing calls
  EventKit; revoking calendar access in System Settings leaves the section showing the state
  and a button that opens the right pane.

## 7. Verification

- [x] `swift build` clean, no new warnings.
- [x] `swift test` green — the existing tests plus the calendar match and the copy formats.
- [ ] `./scripts/build_podushka_app.sh` runs and the app launches, but the manual pass is
      Mikhail's: this shell has no accessibility access, so it cannot click through the calls,
      record a two-channel call, or grant calendar access.
- [x] Screenshots of the window in Light and Dark against the prototype.


---

## 8. What ended up different from the plan

- The player lanes are drawn for every call, audio or not: they come from the transcript, and
  every call in the index today has lost its audio. Gating them on playback would have left
  «кто где говорит» invisible exactly where it was asked for.
- The first lane build gave every line a floor of 0.5% of the call, and 316 lines added up to
  172% of talk time. The floor now lives in the drawing code, in pixels, where it belongs;
  `SpeakerLaneTests` holds the case that caught it.
- `loadCallDetail` logs its SQLite time. On the 316-line call it reads in **1 ms**, so the
  index was never the slow part — the eager `VStack` was.
- The Info tab gained a «Событие календаря» row: once a name comes from the calendar, the
  event it came from should be visible somewhere.
