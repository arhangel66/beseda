---
type: Architecture
title: Related calls
description: How the previous related call is found for a call or a calendar event, and what digest of its stored summary is shown.
---
# Related calls

Logic for the «В прошлый раз» block (epic BESEDA-52); code in `Storage/RelatedCalls.swift`, the rule from
[development directions](../decisions/development-directions.md#related-calls).

## Entry points

- `CallStore.previousRelatedCall(toCallID:)` — for a stored call.
- `CallStore.previousRelatedCall(to: CalendarEvent)` — for an upcoming event before any call exists.

Both return `PreviousRelatedCall` (call id, its start, digest) or nil — nil means show nothing.

## The rule

`RelatedCalls.previousCall` looks only at `ready` calls that started before the target, newest first;
first hit wins:

1. the same calendar series (`event_series_id`) or the same event title, case-insensitive and trimmed —
   checked over the whole history before rule 2;
2. the same `call_type` and at least one shared participant (event attendees).

An event has no call type yet, so it only gets rule 1. Participants exist only for calls linked to a
calendar event with attendees after the columns landed; calls without an event never match rule 2.
The scan covers the latest 1000 calls in memory.

## The digest

`RelatedCalls.digest(ofSummary:)` uses only `calls.summary_text`, never the transcript and never a model:
the sections **Главное**, **Что делать**, **Открытые вопросы** of the default prompt
(`ChatCompletionsProvider.defaultPrompt`) with their headings; if none are there, the first five non-empty
lines. No summary — nil, and the call is not offered at all.
