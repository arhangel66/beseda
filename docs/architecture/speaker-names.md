---
type: Architecture
title: Speaker names
description: How Beseda optionally names the remote speakers of a call from a people list, with rules and then Gemma 4 12B, and keeps the evidence.
---
# Speaker names

Optional, off by default: Settings → «Имена собеседников» → «Определять имена собеседников». After a call
is transcribed, Beseda names its remote speakers (`them-N`) from a list of people the user writes in
settings («Люди в звонках»), and keeps why it chose each name.

## How it works

1. `SpeakerNameRules` (port of rules v3 from the eval) reads the transcript. Only lines that say exactly one
   known person count: thanks votes for the remote voice before the line, an address (the name opening
   the line, set off by commas, or closing it) votes for the remote voice after it, up to 7 lines away. A
   voice that says a name gets −1 for that name. Greedy assignment: one name per speaker, one speaker per
   name.
2. If Gemma 4 12B is downloaded, `SpeakerNamer` sends the whole clean transcript in one request with the
   eval's p1 prompt (temperature 0, JSON schema, thinking off) to its own `llama-server` on port 8735. The
   server is stopped right after, unless the summary that follows also runs on the 12B
   (`AppSettings.summaryUsesGemma12B`); then it stays loaded and writes the summary. The model fills only the speakers the rules left open, and never names a
   person the rules already placed. Without the 12B the rules alone run.
3. Every guess goes to `call_speaker_guesses` (name or `unknown`, source `rules`/`model`, evidence, the raw
   model reply). A name goes to `call_speakers` only for a speaker without a manual name; the transcript
   file is rewritten with it. A manual rename always wins and is never overwritten.
4. The call screen shows a small «авто» mark next to a name that is still the guess; hovering it shows the
   evidence.

It runs in the processing queue after transcription and before the summary, also when auto-summary is
off. A call is named once: stored guesses are not recomputed.

## Why this design

The eval (`untracked/epics/speaker-names/`, not shipped) compared rules, local models, merges and votes on
calls labelled by Opus. Rules + one 12B request (whole call, p1) scored 0.80 right / 5.0 % wrong on the
tune set and 0.745 / 7.3 % on the test set, against rules alone at 0.70 / 3.3 % and 0.709 / 7.3 %. A
2-of-3 vote of 12B runs scored better on test (0.782 / 5.5 %) but costs three requests; the single request
was chosen to watch on real calls first.

## Main files

- `Summarization/SpeakerNamer.swift` — `CallPeople`, `SpeakerNameRules`, `SpeakerNamer`.
- `App/AppController.swift` — `nameSpeakers(of:)`, queue order.
- `Storage/CallStore.swift` — `call_speaker_guesses` (migration 5).
- `Summarization/SummaryProvider.swift` — `BundledSummary.gemma12B`, the pinned 12B GGUF.
