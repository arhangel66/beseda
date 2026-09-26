---
type: Decision Record
title: Development directions
description: Where Beseda goes next and what it deliberately does not do — proposed, awaiting Mikhail's approval.
status: proposed
tags: [product, strategy]
generated:
  by: agent
  at: 2026-09-26T00:00:00Z
sources:
  - id: analysis
    title: External product analysis pasted by Mikhail (competitors checked 2026-09-26)
---

# Development directions

**Status: proposed — awaiting Mikhail's approval. No feature below is built before it is approved.**

## Context

Beseda records calls on the Mac with separate mic and system channels, transcribes locally (Parakeet v3,
GigaAM v3), keeps an archive with search, summarises with a local model, and sends a webhook.

"No bot", "local", "has a summary" and "has MCP" are not differentiators: every one is already sold.[^analysis]

| Local | Price | Cloud | Note |
|---|---|---|---|
| MacWhisper | free / Pro €64 once | Granola | cross-meeting chat, prep, follow-up, MCP |
| Meetily | free / Pro $120/yr; MCP, CLI, webhooks | Krisp, Jamie | |
| Weeve | €12.99/mo; Parakeet, FluidAudio, local summaries — closest | Fathom | free, unlimited |
| Anarlog | free / Pro $15/mo | ChatGPT Record | on Mac |
| Buzz | free, open source | | |

**Main risk.** People admire the first transcript, pile up calls and stop opening the archive. The product
has to serve three moments: *after the call* (what do I do, what did they promise), *before the next call*
(where we stopped, what is open), *during work* (why and where did we decide this).

## Positioning

> Beseda — private memory of work conversations: what was decided, what was promised, what to do next.
> All on your Mac.

The promise: *Call ended — you have verifiable decisions, commitments and a ready summary. Before the next
call Beseda reminds you where you stopped.*

**First segment (hypothesis):** independent technical consultants and developers with several client
projects, on a Mac. Alternative, kept out of v1: private psychologists — different needs, not mixed in.

## Directions

### A. The call card — decisions, actions, open questions

- **What.** A finished call's main screen is an editable card: *Decided* / *Next actions* (who; a deadline
  only if said, otherwise "deadline not named") / *Still open* / *Draft follow-up message*. Every item links to
  the transcript segments it came from. The model proposes, the person confirms or edits.
- **Why.** It is the "after the call" moment and the answer to the archive nobody opens. Summary text alone
  is what every competitor has; checkable items with sources are not.
- **Today.** One free-text `summaryText` per call (`Storage/CallStore.swift`) from a local model
  (`Summarization/`); segments with timestamps and speakers exist.
- **First step.** Store items as structured entities with segment IDs (Markdown only for view and export);
  show the card for one call, with click-through to the segment.
- **Success.** In the demand check, most items are confirmed without heavy edits, and users open the card
  after their calls without being told.
- **Not done.** No invented deadlines or owners; no auto-send of the follow-up; no free-text summary as the
  stored truth.

### B. Project / client level above calls

- **What.** Calls grouped by project or client; a project page with its current state and a compact
  "before the meeting" block: where we stopped, what is open, what each side promised.
- **Why.** The "before the next call" and "during work" moments; this is what makes the archive worth
  opening.
- **Today.** A flat call list with search (`App/Views/ConversationsWindow.swift`); no projects or clients.
- **First step.** Assign a call to a project by hand; the block lists the confirmed open items and actions
  from that project's cards (A). Plain text search first, no semantic search or chat.
- **Success.** Users open the block before a call with the same client.
- **Not done.** Never turn an assumption into a fact — only confirmed items feed the block. Links keep
  opening the text after the audio is deleted. No cross-meeting AI chat in v1.

### C. Results where people work

- **What.** Markdown export to a chosen folder; "copy meeting summary"; one task hand-off scenario; a
  verifiable dev-task draft from a requirements call.
- **Why.** Decisions are useless trapped in the app; the segment works in notes, trackers and editors.
- **Today.** Transcript copy (`Storage/TranscriptCopy.swift`) and a webhook (`Webhooks/`). No MCP server in the
  code yet.
- **First step.** Markdown export of the card (A) to a chosen folder, plus "copy meeting summary".
- **Success.** Exports and copies per confirmed card in the demand check.
- **Not done.** MCP is transport, not a reason to buy — built only after the above. When a cloud agent is
  connected, Beseda warns that data leaves the Mac. One tracker scenario, not a catalogue of integrations.

### D. Russian and mixed-language speech, measured

- **What.** Make the Russian / Russian-English quality a number, not a claim.
- **Why.** It is the one engine-level advantage over the Parakeet/Whisper-based competitors — if it holds.
- **Today.** GigaAM v3 and Parakeet v3 selectable (`Transcription/SpeechModel.swift`); an earlier bakeoff
  in `docs/asr-bakeoff.md`.
- **First step.** A small fixed set of real work calls (Russian, mixed, English terms) with reference text;
  WER for Beseda's engines and the competitors' engines.
- **Success.** A published, reproducible WER table where Beseda is better on Russian and mixed speech.
- **Not done.** No marketing on "has GigaAM" until the table exists.

## Cross-cutting

- **Privacy.** Storage protection, backup and deletion that a user can trust. Recording consent is made
  convenient (a ready notice, a reminder) — never "nobody will know" (see e.g. UK ICO guidance).
- **No Windows version now.**
- **Never lock users out of their own archive,** whatever the pricing.

## Demand check

The current version to 8–12 people of the one segment, plus one complete scenario: a client-call summary
with decisions, actions and source links (A + export from C). Target: **6 of 10 still using after two
weeks, 3 ready to pay.** Price hypothesis: **$49–79 one-time.**

## Proposed order

1. A — the call card, minimal (structured items, segment links, confirm/edit).
2. C, first step only — Markdown export and "copy meeting summary".
3. Privacy basics needed to hand the app to strangers (protection, deletion, consent notice).
4. **Demand check.**
5. After it, only if the targets hold: B (projects and "before the meeting"), D (WER benchmark), then one task
   hand-off, dev-task draft, MCP.

## Decisions for Mikhail

1. Adopt the positioning "private memory of work conversations" and the promise above.
2. First segment: independent technical consultants/developers; psychologists kept out of v1.
3. A: the call card replaces free-text summary as the main screen; items stored as entities with segment IDs.
4. B: projects above calls, confirmed items only, plain search first, no cross-meeting chat in v1.
5. C: Markdown export and copy first; MCP only as transport, later, with a data-leaves-the-Mac warning.
6. D: benchmark Russian/mixed WER before claiming it.
7. Consent made convenient, never hidden recording.
8. No Windows version now.
9. Demand check with 8–12 people; success = 6 of 10 after two weeks, 3 ready to pay.
10. Price hypothesis $49–79 one-time; the archive is never locked.
11. The order above: A → export → privacy basics → demand check → the rest.

[^analysis]: External product analysis pasted by Mikhail, competitors checked 2026-09-26.
