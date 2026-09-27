---
type: Proposal
title: Beseda landing message
status: proposed
---
# Beseda landing message

**Audience:** Independent consultants and developers who need to remember what was agreed in client calls, dailies and other work conversations. Write for Western-market Mac users; do not imply an English-only interface.

**Headline:** Remember what you agreed on in your last work call.

**Subhead:** Beseda records calls on your Mac and transcribes them locally. After a call, search the transcript or create a summary with your own prompt. Before the next related call, revisit what was agreed last time.

**Optional, separate use case — psychologists:** A personal archive with a custom summary prompt, **not** clinical documentation, a diagnosis, or a promise of confidentiality without action by the user. Do not blend this use case into the work-call productivity message.

## Three moments

- **After:** Open the transcript, search for words or create a summary in your chosen format; automatic processing is off by default.
- **During:** Optionally turn on draft transcription and key points; this is a preview and may fall behind.
- **Before the next call:** See stored decisions, next steps and questions from a previous related conversation, if one with a summary is found. Do not promise a reminder for every meeting.

## What makes it different

Do not base comparisons on “no bot”, “local” or “has summaries”: others offer these too. Against Granola, MacWhisper and Weeve, show Beseda's own flow: separate microphone and system-audio recording, local transcription, configurable call types and summary prompts, and a return to the previous conversation. Do not claim competitors cannot do this or promise better accuracy without measurements. See [development directions](../decisions/development-directions.md) and [current features](features.md).

## Honest demo

Use only a synthetic conversation without real names, clients, patients or calendar addresses. Capture again from fixture data; never present a mockup as a working screen:

1. **Recording:** Show the menu with two audio sources and a collapsed “Key points and draft” section. Do not put a finished transcript in an empty screen or show unverified in-call hints.
2. **After:** Show the Conversations screen with a synthetic transcript and a short prompt-based summary; label the data “Example conversation”. The current reference frame `seeded-call-разговоры.png` in `.factory/shots/BESEDA-ux2-final/` shows the “Итоги” tab but only one line of output, not a rich task card.
3. **Before:** Capture the “В прошлый раз” section from genuinely related synthetic calls. Until a verified frame exists in that set, do not draw or publish it as an app screenshot.

The reference set also contains `popover-live-no-commands.png` with its section collapsed and `popover-idle-popover-preview.png` without a downloaded model: do not present either as a fully configured user session. Check frames against a running build before publication.

## Page FAQ

**Does the recording go to the cloud?** Audio and local transcription stay on the Mac. Text may leave it when OpenRouter (summaries, classification or live key points), a remote LM Studio server or a webhook is enabled; models and updates are downloaded from the internet. See [Privacy](privacy.md).

**Can I record any call?** The user is responsible for recording lawfully, obtaining participants' consent and storing the data. Beseda does not notify other participants on the user's behalf.

**Can I use it for sensitive conversations?** There is a local-only mode and retention controls, but files are not protected from someone using an unlocked Mac, programs running as the same user or unencrypted backups. See [Privacy](privacy.md).

**Do I need internet?** Yes, to download models and updates; transcription with an installed model works locally. Cloud features require a connection.

**What does it cost, and how can I buy it?** Payment provider and sales channel are not confirmed; do not display a price or payment form until the channel is confirmed.

## CTA (not a sale yet)

**“See how Beseda works”** — jump to the synthetic demo on the page, without a form, payment or contact collection. Do not publish the page or register a domain as part of this proposal.
