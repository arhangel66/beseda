---
type: Architecture
title: Summarization
description: How a call summary is produced, shown and exported, through one chat-completions request to OpenRouter, LM Studio or the built-in llama-server.
---
# Summarization

## How it works

A summary is written on request («Итоги» tab, `AppController.generateSummary`), or right after
`finishCall` marks a call ready when `AppSettings.autoProcessCalls` is on (off by default).
Both go through one `SerialQueue` in `AppController`: a call that finishes while another is processed
waits its turn and is processed after it, in order. The queue lives in memory only — a quit drops it.

**Call types.** `AppSettings.callTypes` (`[CallType]`, JSON under `beseda.callTypes`) — name, description
for the classifier, prompt; never empty. `callTypes[0]` is the built-in «Другое» (`CallType.otherName`):
editable, but `deleteCallType` refuses it; it holds the general prompt and is the fallback. On a fresh
install it is seeded with the old `beseda.summaryPrompt` if that was edited, else
`ChatCompletionsProvider.defaultPrompt`. Migration: a first type still named «Созвон» (the BESEDA-46
default) is renamed «Другое» on load, prompt and id kept.
`SummarizationService.process` picks the type and then summarizes with its prompt:
- a type given by the caller (`generateSummary(as:)`, for a picker on the call screen) is used as is;
- with only «Другое», it is used without asking any model;
- otherwise the classifier gets a `ClassifierContext`: the call's weekday and local time, its duration in
  minutes and the first 8000 chars (~2k tokens) of the clean transcript, plus type names and descriptions.
  - **Jev** (`JevClassifier`, when `AppSettings.classifiesWithJev`: an OpenRouter key is set and
    «Определение типа» is not «Локально»): `POST https://openrouter.ai/api/alpha/decisions`, model
    `typesafe/jev-1.13`, `state` = started / duration / transcript_opening, one `choice` question
    `call_type` whose criteria map name → description. The answer's `choice` and its entry in
    `probabilities` are read; below `jevMinimumProbability` (0.5, untuned) or an unknown name → «Другое».
    Any Jev error is logged and the summary model classifies instead.
  - **Summary model**: the same provider gets `classifierPrompt` (names + descriptions, «Другое» when
    nothing fits) and the context as text; `pickType` matches the answer case-insensitively by
    containment, longest name first. An unknown answer falls back to «Другое» and is logged.
  - Privacy is per app, not per type: the type is unknown before classification, so a private type
    cannot keep its call away from Jev. Settings say what leaves the Mac next to the picker.
  Decision: [call-type classifier](../decisions/call-type-classifier.md).

The chosen type's name is stored on the call (`callStore.setCallType`, column `calls.call_type`).

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

The default prompt (`ChatCompletionsProvider.defaultPrompt`, the starting prompt of every type) asks for four Russian
sections with bold names only.

## Call screen and export

A call with a stored result opens on «Итоги» (`CallDetailView.openingTab`); `ResultActions` shows the
stored type and reruns with a picked one through `generateSummary(as:)`, and copies the result.

After `setSummary`/`setCallType`, `AppController.exportResult` writes `CallExport.markdown` into
`AppSettings.exportFolder` when it is set, as `yyyy-MM-dd HH-mm <title>.md` (title stripped of
`/\:*?"<>|` and newlines, max 120 chars). A write error is logged and does not fail processing. The folder
is a plain path, not a security-scoped bookmark: the app is not sandboxed; sandboxing would need one.
A title change (e.g. linking a calendar event) writes a new file rather than renaming the old one.

## Built-in runtime install

`BundledSummaryInstaller` downloads, per `BundledSummary.current`, a pinned llama.cpp macOS arm64
release (keeps only `llama-server` and dylibs, in `runtime/llama/<build>`) and the Gemma GGUF (into
`runtime/models`), checking SHA-256 before moving each in, then starts the server once to warm up Metal
shaders and writes a marker. `remove()` deletes only the model.

## Main files

`Summarization/SummarizationService.swift`, `JevClassifier.swift`, `ChatCompletionsProvider.swift`, `SummaryProvider.swift`
(provider enum, `BundledSummary` pins), `LlamaServer.swift`, `LocalModelSupport.swift` (`lms`,
`ProcessRunner`), `BundledSummaryInstaller.swift`; `App/ExecutableResolver.swift`.

## Constraints

- `ProcessRunner` reads the stdout/stderr pipes only after the process exits. A tool printing over
  64 KB fills the pipe and hangs. `lms` and `tar` print far less today.
- The built-in model takes about 5 GB of memory while running, which is why it is stopped when idle.
- Only one summary runs at a time (`summarizingCallID`).
