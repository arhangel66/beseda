# Summary provider picker

Date: 2026-09-06. Follows `docs/summary-model-choice-plan.md`.

## Context

Summaries today go only through LM Studio: `LocalModelSupport.resolve` finds the `lms`
server, `LocalModelProvider` posts to its `chat/completions`. Decision after the
quality experiment: three providers the user picks in Settings.

| provider | what it is | why |
| --- | --- | --- |
| OpenRouter | user's key + model name, `https://openrouter.ai/api/v1` | the quality option, ~$0.20 per hour of call, 30–50 s |
| Built-in | Gemma 4 E4B Q4_0 served by `llama-server` the app downloads and runs itself | works offline, no third-party app, rough but usable |
| LM Studio | unchanged | already works for people with a big local model |

Facts that shape the design:

- All three speak the same OpenAI-compatible `chat/completions`. OpenRouter adds an
  `Authorization: Bearer` header. So one HTTP provider serves all three; the picker
  decides the base URL, the model and the header.
- `llama-server` from the llama.cpp GitHub release (`llama-b10819-bin-macos-arm64.tar.gz`,
  11 MB) is self-contained: the binary plus ten dylibs next to it, `@loader_path`
  rpath, Metal library embedded, ad-hoc signed. Checked on this Mac with the E4B
  model: Metal is used, `llama-bench` throughput matches the Homebrew build. First
  launch after download takes ~30 s (Metal shader compile, cached by macOS after
  that); later cold starts 2–5 s.
- The app is not sandboxed and has no hardened runtime, so spawning a downloaded
  binary and talking to `127.0.0.1` needs no entitlement. Files the app downloads
  through `URLSession` carry no quarantine flag, so Gatekeeper does not look at them.
- `RuntimeInstaller` already downloads a pinned file to `runtime/models`, checks its
  sha256, shows progress, and warms the model up once. `LocalTranscriber` already has
  the load-on-demand, unload-after-10-min pattern. Both are copied, not generalised:
  `RuntimeStage` is a closed enum and `SpeechModel` is ASR-shaped.
- `ProcessRunner` only knows how to run a process to completion; a supervised child
  process is new code.
- `AppController.summaryRecovery(for:)` decides the recovery button by matching the
  Russian error text against «LM Studio не запущен». That has to become typed errors.
- The current `defaultPrompt` makes small models write everything in bold
  (`docs/summary-model-choice-plan.md`, «Prompt finding»). The reworded prompt ships
  with this change.

## Design

### Settings

New keys in `AppSettings`, plain `UserDefaults` like everything else:

```
beseda.summaryProvider     "openrouter" | "builtin" | "lmstudio", default "builtin"
beseda.openRouterAPIKey    string, default ""
beseda.openRouterModel     string, default "google/gemini-3.8-flash"
```

`summaryServerURL` and `summaryModel` keep their meaning for LM Studio only.
`summaryPrompt` stays shared. The key sits in UserDefaults like the webhook secret;
Keychain for both is the existing roadmap item «only if the app leaves the family».

### Provider

`LocalModelProvider` becomes `ChatCompletionsProvider` (same file, renamed): fields
`baseURL`, `model`, `prompt`, `apiKey: String?`, `serviceName` for messages, and an
injected `Transport` closure like `WebhookSender` so it is testable. It sends
`Authorization: Bearer <key>` when `apiKey` is set and `max_tokens: 4096` always
(the cloud run needed it; llama-server and LM Studio honour it as well).

`SummarizationError` gets typed cases instead of one string:

```
emptyTranscript
serverDown(String)      "<service> не отвечает" — LM Studio not running, llama-server not up
unauthorized            OpenRouter 401 / 402
modelMissing            built-in model or runtime not downloaded yet
unavailable(String)     everything else, message as today
```

`SummaryRecovery` gets `.downloadModel` next to `.startServer` and `.openSettings`;
`summaryRecovery(for:)` switches on the error, no string matching.

`AppController` gets one `makeSummaryProvider() async throws -> (ChatCompletionsProvider,
characterBudget: Int)` used by both `runSummary` and `checkSummaryConnection`:

| provider | baseURL | model | budget |
| --- | --- | --- | --- |
| OpenRouter | `https://openrouter.ai/api/v1` | `openRouterModel` | 300 000 chars (as today) |
| Built-in | `http://127.0.0.1:<port>/v1` after `LlamaServer.ensureRunning()` | ignored by llama-server | 150 000 chars (~53k tokens, fits the 64k context) |
| LM Studio | `LocalModelSupport.resolve` as today | as today | 300 000 chars |

### Built-in runtime

Two pinned downloads, both into `~/Library/Application Support/Beseda/runtime/`:

| what | source | size | sha256 |
| --- | --- | ---: | --- |
| llama.cpp b10819 macOS arm64 | `https://github.com/ggml-org/llama.cpp/releases/download/b10819/llama-b10819-bin-macos-arm64.tar.gz` | 11 MB | `8933e736495eadfef0731ae32054acfaa75699bf4a6ccba77cd8475db085ec66` |
| Gemma 4 E4B it Q4_0 | `https://huggingface.co/ggml-org/gemma-4-E4B-it-GGUF/resolve/b8093469224f83f5c38f691eb906c380e9e63114/gemma-4-E4B-it-Q4_0.gguf` | 4.59 GB | `a555b900214b477d8880e7832e0b8925e139b0159640036b09fe472b6f2097f2` |

Layout after install:

```
runtime/llama/b10819/llama-server + libllama*.dylib, libmtmd*.dylib, libggml*.dylib
runtime/models/gemma-4-E4B-it-Q4_0.gguf
runtime/llama/b10819/warm-up.ok
```

Only the server and its dylibs are kept from the tarball; the other 30 tools are
dropped. A new pinned build is a new directory, the old one is deleted on install.

`BundledSummaryInstaller` (`Summarization/`, `@MainActor @Observable`): stages
`runtime → model → warmUp`, states reuse `RuntimeStageState`, download through the
same `RuntimeDownloader` closure and `RuntimeInstaller.sha256(of:)`, tarball unpacked
with `/usr/bin/tar` via `ProcessRunner.run`. Warm-up starts the server once and waits
for `/health`, so the ~30 s Metal compile happens during install, not on the first
summary. `remove()` deletes the model (the 11 MB runtime stays).

`LlamaServer` (`Summarization/LlamaServer.swift`, `final class`, serialised on its own
`DispatchQueue` like `LocalTranscriber`):

```
ensureRunning() async throws -> URL     spawn if needed, poll /health up to 120 s, return base URL
stop()                                  terminate + wait
idle unload                             DispatchWorkItem 10 min after the last request
```

Launch line: `llama-server -m <gguf> --host 127.0.0.1 --port 8734 -c 65536 --parallel 1
-ngl 99 -fa on --jinja --no-webui`. Fixed port; if it is taken the server fails to
start and the error card says so. stdout/stderr go to `runtime/llama/server.log`,
truncated on each start. `AppController` calls `stop()` next to `transcriber.shutdown()`
on quit.

### Settings UI

`ProcessingPane`, section «Итоги»:

```
Провайдер        [OpenRouter | Встроенная модель | LM Studio]     segmented picker

OpenRouter:      Ключ API   [SecureField + «Показать»]
                 Модель     [TextField, placeholder google/gemini-3.8-flash]
                 note: «Расшифровка уходит в OpenRouter»
Встроенная:      Gemma 4 E4B · 4,6 ГБ   [Скачать | progress NN% | Готово · Удалить]
                 note: «Работает без интернета. Итоги грубее облачных: теряет часть
                 договорённостей.»
LM Studio:       exactly today's rows (server status, model picker, «Запустить LM Studio»,
                 «Обновить список», server address in «Дополнительно»)

«Проверить»      for every provider, through makeSummaryProvider()
Дополнительно    prompt editor, shared
```

`RecordingPane.processingNote` (the privacy line) says «расшифровка уходит в
OpenRouter» when that provider is picked; the host-based check stays for LM Studio.
Onboarding does not mention summaries today and stays untouched.

`CallSummaryView` recovery button: `.downloadModel` → «Скачать модель», which opens
Settings → processing (the download lives there, no second progress UI).

## Steps

Every step ends with `swift build` and `swift test` green.

- [ ] **1. Prompt.** Replace `defaultPrompt` with the reworded text from
      `untracked/scripts/summary-bench/run_prompt_v2.py`.
      Check: existing prompt tests pass; a summary from LM Studio has bold section
      names only.
- [ ] **2. Provider + typed errors.** Rename `LocalModelProvider` →
      `ChatCompletionsProvider`, add `apiKey`, `serviceName`, `Transport`, `max_tokens`;
      new `SummarizationError` cases; `summaryRecovery(for:)` switches on them.
      Check: tests — request carries the bearer header only when a key is set; 401 →
      `.unauthorized`; connection refused → `.serverDown`; recovery mapping per case.
- [ ] **3. Settings.** Three new keys with round-trip test; `makeSummaryProvider()` in
      `AppController`, `runSummary` and `checkSummaryConnection` use it.
      Check: with `summaryProvider = lmstudio` behaviour is byte-for-byte today's.
- [ ] **4. OpenRouter end to end.** Settings UI rows, privacy note, `.unauthorized`
      recovery → «Открыть настройки».
      Check: real key, real call, summary lands in the archive; wrong key shows
      «Ключ OpenRouter не принят» with the settings button; «Проверить» reports the
      round trip time.
- [ ] **5. Installer.** `BundledSummaryInstaller` with the two pinned artifacts, tar
      unpack, sha256, warm-up marker, remove.
      Check: tests with a fake downloader — happy path leaves the three files, wrong
      hash leaves nothing, failed runtime download stops before the model; real install
      on this Mac ends with `runtime/llama/b10819/llama-server` executable and no
      `com.apple.quarantine` attribute on it.
- [ ] **6. LlamaServer.** Spawn, `/health`, idle stop, stop on quit, log file.
      Check: test with a fake executable path → `.modelMissing`; manual: generate a
      summary, `pgrep llama-server` shows one process, gone 10 min later and gone
      immediately after quitting the app; RSS during a summary ≈ 5 GB.
- [ ] **7. Built-in end to end.** Settings row with download/progress/delete, the
      «Скачать модель» recovery, budget 150 000 chars.
      Check: the 87-minute call from the experiment gets a four-section summary in
      ≈3 min; the E4B output for it matches the shape recorded in
      `untracked/scripts/summary-bench/out/E4B-Q4_0-prompt2/`.
- [ ] **8. Docs.** `docs/roadmap.md` deferred entry → done pointer; `docs/install.md`
      mentions the picker; `docs/summarization-local-model-plan.md` gets a one-line
      «superseded by» header.

## Decisions

- **Default provider.** Decided: `builtin`. A fresh install works after one download,
  no account, no third-party app. Both current Macs will see «Скачать модель» on
  the next summary until Mikhail picks LM Studio or OpenRouter there once.
- **OpenRouter default model.** Decided 2026-09-06 (Mikhail): `google/gemini-3.8-flash`.
  The experiment measured `anthropic/claude-opus-5` as the ceiling; flash is the cheap
  everyday choice and the field is editable.
- **Runtime download vs bundling `llama-server` in the .app.** Decided: download. No
  dylib retargeting in `bundle_app.sh`, no signing of third-party code, the pinned
  build moves independently of the app. Cost: one more 11 MB download on setup, same
  network requirement the model already has.

## Out of scope

Keychain for the key, streaming output, automatic summary after transcription, a
model picker for the built-in provider (one model, pinned), Intel Macs (the runtime
is arm64 only; README and `docs/install.md` already require Apple Silicon).
