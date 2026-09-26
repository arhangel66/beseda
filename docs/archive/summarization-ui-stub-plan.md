# Plan: Summarization, UI on a stub provider

Goal of this stage: the whole click path works and looks finished, with a fake model
behind it. No network, no API keys, no settings. When the UI feels right, the real
provider replaces one object and nothing else moves.

Success criterion: open a call, switch to «Саммари», press the button, watch a spinner
for ~1.5 s, read a rendered summary, restart the app, the summary is still there.

## Step 1 — Summarization layer (`Summarization/`)

- [x] `SummarizationProvider.swift`
  - `protocol SummarizationProvider: Sendable { func summarize(text: String) async throws -> String }`
    Sendable is required: the package is swift-tools-version 6.0, and the provider is
    awaited from the `@MainActor` controller.
  - `enum SummarizationError: LocalizedError { case emptyTranscript, unavailable(String) }`
  - No `prompt` parameter and no `name`: nothing configures a prompt in this stage, and
    the spinner shows no provider name (a mock's name has no place in a Russian UI).
  - `struct MockSummarizationProvider` in the same file — sleeps 1.5 s, returns a fixed
    Russian summary in the shape the real model should follow. `let failsOnPurpose: Bool`
    (a `let`, so the struct stays Sendable) is set at the injection point to look at the
    error state during development.
- [x] `SummarizationService.swift` — `final class`, one `let provider`.
  - `summarize(_ detail: StoredCallDetail) async throws -> String`
  - Input text is `TranscriptCopy.render(detail, format: .clean)` — the reader-facing
    dialogue already exists, no new formatter.
  - Empty check is on the trimmed render result, not on `segments.isEmpty`: a call with
    only `markdownText` renders that markdown (Storage/TranscriptCopy.swift:39) and must
    reach the provider, not throw.
- [x] `Package.swift`: add `"Summarization"` to `sources`, and `implementation_journal.md`
      to `exclude` (it is the source of the current build warning).

## Step 2 — Controller wiring (`App/AppController.swift`)

- [x] `@ObservationIgnored private let summarizer = SummarizationService(provider: MockSummarizationProvider(failsOnPurpose: false))`
      — one line of dependency injection, the swap point for a real provider.
- [x] `var summarizingCallID: String?` — mirrors the existing `processingCallID` (line 87),
      so the spinner is bound to a call and not to a global flag.
- [x] `var summaryError: String?`, cleared in `selectCall` next to `callBrowserError`
      (line 617), not in an `onChange` inside the view.
- [x] `func generateSummary()`, and the three things that decide whether it works:
  - **Re-read the row.** `loadCallDetail` (line 1226) takes the in-memory
    `StoredCallSummary` as given and only re-reads segments, speaker names and markdown.
    `summaryText` lives on the row, so after `setSummary` the refresh must go
    `callStore.fetchCall(id:)` → `loadCallDetail(freshSummary)`. Without this the summary
    is stored but never shown — the failure `renameSpeaker` does not have, because speaker
    names are a separate table that `loadCallDetail` does re-read.
  - **Do not steal the selection.** The task lives 1.5 s; if the user picks another call
    meanwhile, an unconditional refresh would overwrite `selectedCallDetail` and throw
    them back. Guard on `selectedCallDetail?.id == callID` before refreshing. The DB write
    itself is keyed by call id and stays.
  - **One generation at a time.** `guard summarizingCallID == nil` at the entrance and
    `summarizingCallID = nil` in a `defer`, so a second press cannot kill the first
    spinner.
- [x] No `clearSummary`. «Заново» calls `generateSummary()` again and the successful result
      overwrites the old one; clearing first would leave the user with nothing when the
      regeneration fails.

## Step 3 — The view (`App/Views/CallSummaryView.swift`)

- [x] Third case in `CallDetailTab`: `case summary` → «Саммари», placed between
      «Расшифровка» and «Инфо».
- [x] `CallSummaryView` takes plain values, not the controller: `text: String?`,
      `isRunning: Bool`, `error: String?`, `onGenerate: () -> Void`. `CallDetailView` feeds
      them from `controller`. Other views in this codebase take the controller directly,
      but here it buys something concrete: every state can be shown from literals, which is
      what makes the previews below possible.
- [x] Four states in one view:
  - empty → a centred ✨ button «Сделать саммари» and one line explaining what it does;
  - running → `ProgressView` and a disabled button, no provider name;
  - ready → rendered text and a quiet «Заново» button under it;
  - error → the message in a red-tinted card with «Повторить», styled after
    `FailureBanner`. That banner is file-private in CallDetailView.swift:351, so the
    styling is repeated rather than shared — which is how the other components in this
    codebase are written.
- [x] Rendering: `AttributedString(markdown:options:.inlineOnlyPreservingWhitespace)`.
      This keeps line breaks and renders `**bold**` and `*italic*`, but leaves `#` headers
      as literal characters — so the mock output uses bold lines and `— ` bullets, no
      headers. A real model will emit headers whatever the prompt says, so a proper
      renderer is the first debt of the next stage.
- [x] Nothing is added to the header: the tab is the only entry point.

## Step 4 — Checks

- [x] `swift build` clean, no new warnings.
- [x] `Tests/PodushkaTests/SummarizationTests.swift`, driven by a spy provider that records
      the text it was given and returns at once — not by the mock with its 1.5 s sleep:
  - a call with neither segments nor markdown throws `.emptyTranscript`;
  - a call with only `markdownText` reaches the provider instead of throwing;
  - a renamed speaker appears under the new name in the text handed to the provider —
    the one real transformation the service performs.
- [x] `Tests/PodushkaTests/CallStoreSummaryTests.swift`: `setSummary` then `fetchCall` on a
      temporary `dbURL` returns the text. This is the only automated test that backs the
      "survives a restart" criterion, and it covers the fresh `ALTER TABLE` migration.
- [x] `swift test` green.
- [ ] `./scripts/build_podushka_app.sh`, run it by hand, walk the path from the success
      criterion, and check the summary survives a restart.

## Step 3b — The mock material

What the fake provider returns, verbatim. It ignores its input and returns this for every
call, so the point of agreeing on it now is the shape: no `#` headers (the inline markdown
renderer would show them as literal hashes), bold section lines, `— ` bullets, four
sections, long enough to see how the column breathes.

```
**О чём говорили**
Обсудили готовность релиза 0.6 и то, что осталось закрыть до выката.

**Главное**
— Расшифровка двух каналов работает, осталась разметка говорящих.
— Договорились не тянуть саммаризацию в релиз, если она не успеет к пятнице.
— Ира просила заранее прислать заметки по хранению аудио.

**Что делать**
— Миша: собрать сборку и прогнать на живом звонке, до четверга.
— Ира: проверить, как ведут себя старые записи после обновления базы.

**Открытые вопросы**
— Не решили, чистить ли сырое аудио сразу после расшифровки.
```

- [x] The 1.5 s sleep is a named constant in `MockSummarizationProvider`, so it can be set
      to zero once the wait stops being informative and starts being annoying.
- [x] The error text for `failsOnPurpose` is the one a local model would really produce:
      «Не удалось связаться с моделью на localhost:11434». It is what the error card has to
      fit, so it should not be a placeholder like "mock error".
- [x] Four `#Preview` blocks in `CallSummaryView.swift`, one per state, fed by literals:
      empty, running, ready with the text above, error. This codebase has no previews
      anywhere, so this is a new habit rather than a followed one — deliberate, confined to
      the new file, and the cheapest way to look at four states without recording four
      calls.
- [x] A fifth preview with a two-line summary («**Коротко**\nСозвон на три минуты, ни о чём
      не договорились.»), because the ready state has to survive being nearly empty as well
      as being full.
- [x] Test doubles are not this mock. The spy in Step 4 is its own small type in the test
      file: it records the text it was handed and returns at once.

## Deliberately left out of this stage

- Provider selection, endpoints, model names, custom prompts, and the whole AI settings
  section — they only make sense when there is more than one real provider.
- The markdown fallback sends `transcript.md` whole: its header, the local file paths and
  the ASR statistics written by TranscriptMerger, plus the text duplicated under
  `## Channels`. Harmless for a mock, but a real provider would be handed local paths and
  twice the tokens. Clean this up when the first real provider lands.
- Chunking long transcripts.
- Showing a summary hint in the sidebar list.
