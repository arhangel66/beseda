---
type: Decision Record
title: Call-type classifier
description: Which classifier picks the call type — TypeSafe Jev on OpenRouter by default when a key is set, the summary model otherwise.
status: accepted
tags: [classification, summarization, privacy]
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
sources:
  - id: openrouter-models
    title: OpenRouter model list, https://openrouter.ai/api/v1/models (read 2026-09-26)
  - id: jev-docs
    title: Jev guide, https://openrouter.ai/docs/guides/community/jev
  - id: gliclass
    title: Knowledgator GLiClass, https://github.com/Knowledgator/GLiClass
---

# Call-type classifier

**Status: accepted** (2026-09-26, implemented in BESEDA-57). For phase 2 of [development directions](development-directions.md):
classify a finished transcript into a user-defined type, then run that type's prompt.

## What "JEV" is
**Jev** by TypeSafe, on OpenRouter since September 2026: a "System One" decision model. It does not
generate text; it takes a `state` object plus typed questions (e.g. "which of these types?") and returns
a typed answer with probabilities. Models: `typesafe/jev-1.13` (context 32k), `typesafe/jev-latest`,
and `typesafe/jev-router` (released 2026-09-25, routes a request to a model and reasoning effort).

- **Price** (`jev-1.13`): $0.042 per 1M input tokens, output free. One call: a 1-hour transcript
  (~10k tokens) ≈ $0.0004; its first ~2k tokens ≈ $0.00008. Cost is not a factor.
- **Runs:** cloud only — no open weights, no gguf/MLX, size undisclosed. The transcript leaves the Mac.
- **Russian:** not documented; must be tried on real ru and ru-en calls before relying on it.
- **New types:** zero-shot — the type list is sent with each request, no training.
- **Wiring:** Beseda's `ChatCompletionsProvider` already talks to OpenRouter, but Jev's request is
  state + questions, not a free-form prompt, so it needs its own small request/response shape.
- **Maturity:** days old, one vendor; the model id and API may change.

## Local alternatives
- **Bundled llama-server** (see [summarization](../architecture/summarization.md)): ask the model already
  loaded for summaries to answer with one type name from the list. Zero new code paths, zero new
  downloads, Russian as good as the summary model, fully local. Costs a few seconds per call.
- **GLiClass** (Knowledgator, Apache-2.0): a zero-shot classifier on multilingual mDeBERTa, ~0.2–0.4B
  parameters, ONNX exports and a C engine (GLiClass.c). Runs locally and fast, but would add a new runtime
  to the app; not worth it while llama-server already does the job.

## Decision
Mikhail decided on 2026-09-26: **Jev is the default whenever an OpenRouter key is set**; without a key the
summary model (local by default) classifies. Settings → «Определение типа»: «Jev через OpenRouter (по
умолчанию, если есть ключ)» / «Локально», with a note that the call's time, duration and transcript
excerpt leave the Mac when Jev is used. A Jev failure falls back to the summary model and is logged.
Per-type privacy is impossible: the type is unknown until the classifier has seen the call. How it is
wired: [summarization](../architecture/summarization.md).

## Original recommendation (superseded on the default)
1. **Default: the bundled llama-server** picks the type from the user's list (first ~2k tokens plus the
   type descriptions). Local, private, no new dependency.
2. **Opt-in cloud: Jev via OpenRouter**, off by default, with a warning in settings that the transcript
   is sent to OpenRouter/TypeSafe — never for private calls such as psychology sessions.
3. Add Jev only if the local pick proves too slow or wrong on real calls; first test its Russian.
