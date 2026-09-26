---
type: Architecture
title: Summarization
description: How a call summary is produced through one chat-completions request to OpenRouter, LM Studio or the built-in llama-server.
---
# Summarization

## How it works

A summary is written on request («Итоги» tab, `AppController.generateSummary`), never automatically.

1. `SummarizationService.summarize` renders the stored call as clean dialogue with renamed speakers
   (`TranscriptCopy.render(.clean)`). An empty render throws `emptyTranscript`. Text over the character
   budget is cut at the last newline before it, and the summary is prefixed with a note that only the start
   was summarized.
2. `AppController.makeSummaryProvider` builds a `ChatCompletionsProvider` for the provider chosen in
   settings (`SummaryProvider`). All three speak the OpenAI-compatible `chat/completions` API; one request
   shape (system prompt + transcript, temperature 0.3, `max_tokens` 4096):
   - **OpenRouter** — cloud, needs a key; model defaults to `OpenRouter.defaultModel`. Budget 300k chars.
   - **LM Studio** — `LocalModelSupport.resolve` takes the URL/model from settings or discovers them with
     the `lms` CLI (`lms server status --json`, `lms ps --json` to prefer an already loaded chat model).
     Budget 300k chars.
   - **Built-in** — `LlamaServer` runs the downloaded `llama-server` with Gemma 4 E4B on
     `127.0.0.1:8734` (64k context, one slot), waits for `/health` up to 300 s, and stops it 10 min after
     the last use and on quit. Budget 150k chars.
3. The text is stored on the call row (`callStore.setSummary`). Errors map to `SummarizationError`; the
   error card offers a recovery (`SummaryRecovery`), e.g. starting LM Studio with `lms server start`.

The prompt (`ChatCompletionsProvider.defaultPrompt`, overridable in settings) asks for four Russian
sections with bold names only.

## Built-in runtime install

`BundledSummaryInstaller` downloads, per `BundledSummary.current`, a pinned llama.cpp macOS arm64
release (keeps only `llama-server` and dylibs, in `runtime/llama/<build>`) and the Gemma GGUF (into
`runtime/models`), checking SHA-256 before moving each in, then starts the server once to warm up Metal
shaders and writes a marker. `remove()` deletes only the model.

## Main files

`Summarization/SummarizationService.swift`, `ChatCompletionsProvider.swift`, `SummaryProvider.swift`
(provider enum, `BundledSummary` pins), `LlamaServer.swift`, `LocalModelSupport.swift` (`lms`,
`ProcessRunner`), `BundledSummaryInstaller.swift`; `App/ExecutableResolver.swift`.

## Constraints

- `ProcessRunner` reads the stdout/stderr pipes only after the process exits. A tool printing over
  64 KB fills the pipe and hangs. `lms` and `tar` print far less today.
- The built-in model takes about 5 GB of memory while running, which is why it is stopped when idle.
- Only one summary runs at a time (`summarizingCallID`).
