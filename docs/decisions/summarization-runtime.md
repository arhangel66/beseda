---
type: Decision Record
title: Summarization runtime: provider picker, built-in llama-server by default
status: accepted
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
---

# Summarization runtime: provider picker, built-in llama-server by default

**Status: accepted** (2026-09-06). Supersedes LM Studio as the only provider.

## Context
Summaries first went only through LM Studio ([local model plan](../archive/summarization-local-model-plan.md)).
The [summary model choice experiment](../archive/summary-model-choice-plan.md) ran Gemma 4 E2B/E4B Q4_0 through
`llama-server` on four real calls, judged against Claude Opus via OpenRouter: small models keep the format but
miss about half the agreements; E2B fabricates, E4B is "better than nothing"; the cloud model costs about
$0.20 per hour of call.

## Decision
Per the [summary provider plan](../archive/summary-provider-plan.md): three providers picked in Settings
(`SummaryProvider`, key `beseda.summaryProvider`), all speaking OpenAI-compatible `chat/completions` through one
`ChatCompletionsProvider`:
- built-in — Gemma 4 E4B served by `llama-server` that the app downloads and runs itself
  (`LlamaServer.swift`, `BundledSummaryInstaller.swift`); the default in `AppSettings`;
- OpenRouter with the user's key — the quality option;
- LM Studio — unchanged, for people who already run a big local model.
E2B is dropped.

## Consequences
- Works offline by default, at the quality of a 4B model.
- OpenRouter sends the transcript off the Mac; that is the user's explicit choice.
- The app supervises a child process and downloads a pinned llama.cpp build with a sha256 check.
