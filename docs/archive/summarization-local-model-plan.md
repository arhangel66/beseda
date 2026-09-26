# Plan: the real provider (LM Studio) with a settings section

Superseded by `docs/summary-provider-plan.md`: LM Studio is now one of three providers.

Goal of this stage: the button from the previous stage calls the model that is already on
this machine, and the summary is about the actual call. The user can see which server and
model are used, pick another model, edit the prompt, and check the connection — all from a
new «Саммари» section in Settings. The mock stays in the file for previews and tests.

Success criterion: open a real recorded call, press «Сделать саммари», watch a wait that
counts seconds, read a summary of that call. Open Settings → Саммари: the server and model
are shown, «Проверить» answers in a few seconds, the prompt is editable and «Сбросить»
brings the default back. Stop the LM Studio server, press again: a card names what is
wrong and offers a button that starts it. Restart the app: every setting survives.

## What the probe established (30.08.2026, this machine)

- `lms server status --json` prints `{"running":true,"port":1235}` — the server is on
  **1235**, not the documented default 1234. Discovery, not a hardcoded port.
- `GET /v1/models` lists `google/gemma-4-26b-a4b-qat`, `qwen/qwen3.8-27b` and
  `text-embedding-nomic-embed-text-v1.5`. Embedding models must be filtered out of the
  picker (`id` contains `embed`).
- `lms ps --json` lists loaded models with `contextLength` (131072 for gemma). A loaded
  model answers in **3.7 s**, a cold one in **24 s** (20 s of loading 15.63 GB).
- The model keeps the section format and writes no `#` headers with the prompt below.
- The app is signed without hardened runtime — localhost requests and spawning `lms` work.
- `lms` lives at `/Users/mikhail/.cache/lm-studio/bin/lms` and is on PATH here; on a fresh
  machine it may only be at `~/.cache/lm-studio/bin/lms` (and `ExecutableResolver` does
  not expand `~`).
- `ProcessRunner.run` returns **stderr** on success. `lms ... --json` writes to stdout, so
  a stdout-capturing variant is needed.

## Design decisions

- **Settings, not magic.** A «Саммари» section with server, model, prompt and a check
  button. Discovery still fills the server and model in automatically; the settings
  exist so the user can see what is used, override it, and diagnose it.
- **Three persisted values** in `AppSettings`, all with an "unset = automatic" meaning:
  `summaryServerURL: String` ("" → discover via `lms`), `summaryModel: String`
  ("" → first chat model from `/v1/models`), `summaryPrompt: String`
  ("" → `LocalModelProvider.defaultPrompt`). Keys `podushka.summaryServerURL`,
  `podushka.summaryModel`, `podushka.summaryPrompt`.
- **Provider is built per request** from settings + discovery. The `summarizer` line in
  `AppController` goes away; `SummarizationService` takes the provider per call.
- **No streaming, no chunking, no cloud, no temperature slider** this stage.

## Step 1 — Backend (agent A)

### 1a. `ProcessRunner` (Audio/AudioNormalizer.swift)
- [x] Add `static func output(executableURL:arguments:currentDirectoryURL:) async throws -> String`
      that returns trimmed **stdout** on exit 0 and throws `PodushkaError.processFailed`
      otherwise. Same shape as `run`; do not change `run`.

### 1b. `Summarization/LocalModelProvider.swift`
- [x] `struct LocalModelProvider: SummarizationProvider, Sendable` with
      `baseURL: URL` (e.g. `http://localhost:1235/v1`), `model: String`,
      `prompt: String`, `timeout: TimeInterval = 180`.
- [x] `static let defaultPrompt: String` — the measured prompt (Russian, asks for four
      sections «О чём говорили», «Главное», «Что делать», «Открытые вопросы» in
      `**bold**` with `—` bullets, explicitly no `#` headers, no preamble).
- [x] `POST {baseURL}/chat/completions`, body `{model, messages:[system: prompt,
      user: text], temperature: 0.3, stream: false}`, no `max_tokens`, no API key.
      Minimal private `Codable` structs in the same file.
- [x] `static func parse(_ data: Data, status: Int) throws -> String` — pure function
      the tests can hit: 2xx with `choices[0].message.content` → trimmed text; 2xx with
      empty `choices` or blank content → `unavailable("Модель вернула пустой ответ")`;
      non-2xx → `unavailable` with `error.message` from the body if present, else
      «LM Studio ответил кодом <status>». LM Studio answers 200 with the loaded model
      for an unknown id, so there is no 404 case.
- [x] Transport errors → `unavailable`: cannot connect → «LM Studio не отвечает на
      <host:port>»; timeout → «Модель думает дольше <N> с».

### 1c. `Summarization/LocalModelSupport.swift` (mirrors `FfmpegSupport`)
- [x] `enum LocalModelSupport` with:
  - `static func lmsExecutable() throws -> URL` — `ExecutableResolver.resolve(["lms",
    expandedHomePath])` where the second candidate is `~/.cache/lm-studio/bin/lms`
    expanded with `NSString.expandingTildeInPath`.
  - `static var isInstalled: Bool`.
  - `static func discoverServer() async throws -> URL?` — `lms server status --json`,
    decode `{running, port}`, return `http://localhost:<port>/v1` or nil when not running.
    Throws only when `lms` is missing or the process fails.
  - `static func startServer() async throws` — `lms server start`.
  - `static func chatModels(at baseURL: URL) async throws -> [String]` — `GET
    /models`, ids without `embed` in them, in server order.
  - `static func loadedChatModels() async throws -> [String]` — `lms ps --json`, decode
    an array of `{type, identifier, ...}`, keep `type == "llm"`, return identifiers;
    `[]` when `lms` is missing (decoding lives in the pure `parseLoaded(_ data: Data)
    throws -> [String]`).
  - `static let manualInstructions = "LM Studio не найден. Откройте его и включите Local Server во вкладке Developer."`
- [x] `struct SummaryConnection: Sendable { let baseURL: URL; let model: String }` and
      `static func resolve(serverURL: String, model: String) async throws -> SummaryConnection`:
      serverURL non-empty → use it as is (must parse as URL, else `unavailable("Адрес
      сервера не похож на URL")`), else discover; nil → `unavailable("LM Studio не
      запущен")`. Model non-empty → use it, else the first of `chatModels` that is also
      in `loadedChatModels` (server order) — automatic must mean "the model that is
      already loaded", not just the first one listed — else the first of `chatModels`,
      none → `unavailable("В LM Studio не загружено ни одной чат-модели")`.

### 1d. `AppSettings`
- [x] Three `String` properties with `didSet` persistence and the three keys above,
      read in `init` with `?? ""`. Match the existing style exactly.

### 1e. `SummarizationService` — truncate and say so
- [x] `init(provider:characterBudget: Int = 300_000)` (≈100k tokens at 3 chars/token,
      comfortably under 131k).
- [x] Over budget: send the first `characterBudget` characters cut at the last newline
      before the limit, and prefix the returned summary with
      «Пересказано только начало разговора — целиком в модель не поместилось.\n\n».
- [x] Update `MockSummarizationProvider`'s failure string to «LM Studio не отвечает на
      localhost:1235» (the old one named Ollama's port).

### 1f. Tests (swift-testing, top-level `@Test` funcs, no network)
- [x] `LocalModelProviderTests.swift`: `parse` on a normal answer, an error body with
      `error.message`, an empty `choices`.
- [x] `SummarizationTests.swift`: over budget → spy receives ≤ budget chars and the
      result starts with the warning line; under budget → untouched.
- [x] `AppSettingsTests` (new or existing file): the three summary settings round-trip
      through a `UserDefaults(suiteName:)` instance and default to "".
- [x] `swift build` and `swift test` green.

## Step 2 — Controller and UI (agent B, after Step 1)

### 2a. `AppController`
- [x] Remove the `summarizer` field. `runSummary` becomes: `LocalModelSupport.resolve(
      serverURL: settings.summaryServerURL, model: settings.summaryModel)` → build
      `LocalModelProvider(baseURL:model:prompt: settings.summaryPrompt.isEmpty ?
      LocalModelProvider.defaultPrompt : settings.summaryPrompt)` →
      `SummarizationService(provider:).summarize(detail)`. All three guards from the
      previous stage stay (one at a time, do not steal the selection, re-read the row).
- [x] `var summaryStartedAt: Date?` set with `summarizingCallID`, cleared with it, so
      the view can count seconds.
- [x] `var summaryRecovery: SummaryRecovery?` where `enum SummaryRecovery { case
      startServer, openSettings }`, set next to `summaryError`: `.startServer` when the
      error is the "не запущен"/"не отвечает" kind and `LocalModelSupport.isInstalled`,
      `.openSettings` otherwise. Cleared wherever `summaryError` is cleared.
- [x] `func startLocalModelServer()` — `isStartingLocalModelServer` flag, calls
      `LocalModelSupport.startServer()`, on success clears the error and re-runs
      `generateSummary()`; on failure sets `summaryError`.
- [x] Settings-screen helpers on the controller: `var summaryServerStatus: String?`,
      `var summaryModels: [String]`, `var summaryCheckResult: String?`,
      `var isCheckingSummary: Bool`; `func refreshSummaryModels()` (discover + list,
      writes status line «LM Studio запущен на порту 1235» / «LM Studio не запущен»),
      `func checkSummaryConnection()` (sends «Скажи «готово»» through the real provider,
      reports «Ответила за 3.7 с» or the error text).

### 2b. `CallSummaryView`
- [x] New value parameters: `startedAt: Date?`, `recovery: SummaryRecovery?`,
      `onRecover: () -> Void`. Keep the view controller-free.
- [x] Running state shows «Читаю расшифровку… 8 с» using `TimelineView(.periodic(from:
      by: 1))`; after 10 s the line becomes «Модель ещё думает, первый раз это долго…».
- [x] Error card gets an `AccentButton` «Запустить LM Studio» for `.startServer` and
      «Открыть настройки» for `.openSettings` (the latter is a `SettingsSectionLink`
      with `section: "summary"` — this is the one place the view needs the controller;
      pass it as an optional `settingsLink: AnyView?` or accept `controller` only for
      that link, whichever keeps previews working). «Повторить» stays.
- [x] Previews updated; add one for the recovery card.

### 2c. Settings section «Саммари»
- [x] `SettingsSection.summary` with title «Саммари», icon `sparkles`, after
      `integrations`. Section id `"summary"` for `SettingsSectionLink`.
- [x] `private struct SummarySettings: View`, styled like `IntegrationSettings`:
  - Server card: status line from `controller.summaryServerStatus`; text field
    «Адрес сервера» bound to `settings.summaryServerURL`, placeholder
    «автоматически (lms server status)»; `OutlineButton` «Обновить» →
    `refreshSummaryModels()`; when not running and `isInstalled`, `OutlineButton`
    «Запустить» → `startLocalModelServer()`; when `lms` is missing, the
    `manualInstructions` line.
  - Model row: a `Picker(.menu)` over `["" (Автоматически)] + controller.summaryModels`
    bound to `settings.summaryModel`; if the stored value is not in the list, show it
    as an extra entry so the picker never silently changes it.
  - Prompt card: `TextEditor` bound to `settings.summaryPrompt`, showing
    `defaultPrompt` as placeholder-style text when empty; `OutlineButton` «Сбросить»
    sets it to ""; hint «Без заголовков `#` — панель показывает только жирный текст и
    переносы».
  - Check row: `AccentButton` «Проверить» → `checkSummaryConnection()`, disabled while
    checking, result line next to it.
  - `.onAppear { controller.refreshSummaryModels() }` (only once per window show).
- [x] Settings window height may grow; if 460 is too short for this section, bump
      the frame in `SettingsWindow` rather than squeezing the prompt editor.

### 2d. Checks
- [x] `swift build` and `swift test` green, no new warnings.
- [x] `./scripts/build_podushka_app.sh` produces the app.

## Step 3 — Review (agent C) and manual walk (Mikhail)

- [x] Review pass over the diff: silent failures, Swift 6 concurrency, style match,
      Russian strings, no leftover mock wiring, no `#` in the prompt.
- [ ] By hand: real call end to end; Settings → Саммари shows port 1235 and gemma;
      «Проверить» answers; change the prompt, «Заново», see the change; `lms server
      stop`, press, read the card, «Запустить LM Studio», get a summary; restart the
      app, settings survive.

## Deliberately left out of this stage

- Streaming, chunking, cloud providers, a temperature control, per-call prompt overrides.
- The markdown fallback still sends `transcript.md` whole (header, paths, ASR stats)
  for calls with no segments — rare, and a separate cleanup.
