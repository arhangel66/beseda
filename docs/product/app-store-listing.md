---
type: Proposal
title: Mac App Store listing draft
status: proposed
---
# Mac App Store listing draft

Not submitted. This copy describes the current app, not an approved store build: [distribution readiness](../decisions/distribution-readiness.md) still blocks Mac App Store release. Proposed primary locale: **English (U.S.)**. Do not publish, enter pricing, or claim a release date from this document.

## English metadata

- **App name:** Beseda
- **Subtitle:** Recall what your calls decided
- **Keywords:** meeting,transcript,call notes,summary,conversation,audio,search,recap,client
- **Description (plain text):**

> Remember what you agreed on in your last work call.
>
> Beseda records your microphone and system audio as separate channels on your Mac. With a downloaded speech model, it transcribes calls on-device. Search past transcripts and play back recordings to revisit a client call or daily stand-up.
>
> After a call, create a summary using a call type and prompt you choose. Processing is manual by default; automatic processing is optional. If a related earlier call has a summary, revisit its stored decisions, next steps and open questions. Optional live draft transcription and key points are previews and may fall behind.
>
> Recordings and local transcripts stay on your Mac by default. Built-in summaries run locally after you download the required model and engine. If you select OpenRouter or a remote LM Studio server, conversation text may leave your Mac; a configured webhook sends transcript and result text to its destination. Classification can send a transcript excerpt to OpenRouter when a key is set and local classification is not used. Model and app updates require internet access.
>
> Record only when lawful and obtain any consent required from call participants. Beseda does not notify them for you.

This draft avoids accuracy percentages, security guarantees, competitor trademarks, medical claims and testimonials. Apple's limits are 30 characters for name and subtitle, 100 bytes for keywords (each keyword longer than two characters), and 4,000 characters for the plain-text description; recheck in App Store Connect at submission. [Features](features.md) and [privacy](privacy.md) are the source for product claims.

## Privacy and consent copy

For listing or support FAQ: “Your microphone and system-audio recordings and local transcripts are stored on your Mac. Summaries and live key points can send text to OpenRouter or a remote LM Studio server when selected; classification can send a transcript excerpt to OpenRouter when a key is set and classification is not local. A configured webhook sends the transcript, title, time and summary to its destination. An export folder in a synced location may upload exported text. Local files and backups are not end-to-end encrypted by Beseda. Review your settings and backup location before recording sensitive calls.”

Recording notice: “Before you record, tell everyone on the call and obtain any consent required where you and they are located. Beseda does not alert other participants.” This is suggested user-facing copy, not a claim that the app currently displays this notice. Do not mark Apple's App Privacy answers until the shipped store variant and third-party SDK/data flows are audited; a privacy policy must explain retention, deletion, optional network flows and contact details.

## Missing publication inputs

- **Support URL — missing.** Apple requires a reachable full URL with actual contact information for support. No domain or support page has been selected; do not insert a placeholder into App Store Connect.
- **Privacy Policy URL — missing.** Apple requires this for macOS; [project privacy notes](privacy.md) are not yet a published user-facing policy at a stable URL. Verify the store build and disclosures before hosting it.
- **Price (internal only):** planned **USD $39.99 one-time paid download**, no introductory discount or subscription, per [first-sale decision](../decisions/first-sale-price.md). Keep this out of public copy and App Store Connect until Paid Apps is Active and the owner approves the public listing. Confirm the US price point and regional prices then.

## Screenshot storyboard (not assets)

Use **macOS screenshots**, not iPhone/iPad art: Apple lists 16:10 sizes **1280 × 800, 1440 × 900, 2560 × 1600 or 2880 × 1800 px**. Choose one size consistently, e.g. 1440 × 900 PNG, and verify current requirements at upload. Apple requires screenshots; prepare an **English (U.S.)** set for the primary locale. Add Russian-localized screenshots only if Russian storefront metadata is prepared and verified; do not put English captions over Russian UI or imply English-system screenshots were visually verified. Captions below are proposed accessible descriptions for the asset handoff (also use as concise on-image headings only if the captured UI supports them), not fake UI or a claim that App Store Connect has a per-screenshot alt-text field.

1. **Record:** Real app menu popover while a consented, wholly synthetic two-voice call is recording. Show separate microphone/system sources and collapsed live preview; no finished transcript or fabricated live hints. Caption: “Recording menu showing microphone and system audio as separate sources.”
2. **Find the call:** Conversations window populated only with synthetic, clearly identified “Example conversation” fixture data. Show a searchable transcript and actual controls; remove personal names and calendar addresses. Caption: “Conversations archive with a searchable example transcript.”
3. **Review the result:** Same example call after processing with a short prompt-based summary visible in the real Итоги/result screen. Do not fabricate task cards or a richer result than the app renders. Caption: “Example call result beside its recorded conversation.”
4. **Return to context (conditional):** Two genuinely related synthetic calls, the older one already summarized; capture the actual “В прошлый раз” section only if the running build displays it. Otherwise omit this frame. Caption: “Previous related call summary with decisions and next steps.”

The isolated `BESEDA_SEEDED_JOURNEY=1` path in `UIJourneyContract` now seeds two English example conversations: a route sketch (older, summarized with stored decisions and next steps) and a route review (current, with a result and searchable two-speaker transcript). `UIJourneyContractTests` checks the archive search, previous-call ownership, copy text and repeatable stored state without launching the app. This is a test fixture, not a captured English-system frame: the previous-call digest still uses the app's existing Russian section headings, and no popover/recording frame is available from this fixture. A later owner-approved real-app GUI capture must verify the actual language, layout, result and conditional previous-call section before using captions or assets.

Capture actual UI from a verified build and synthetic fixtures only, following the [landing demo constraints](landing-brief.md). **Never upload the static design concept PNGs as app screenshots**, mock up nonexistent screens, use live calls, or launch a GUI/browser window for this drafting task. No screenshot files are produced here. Check display scale, UI language, crop, legibility, consent and absence of identifiers before any later upload. No invented ratings or reviews.

## Apple references (official, checked via HTTP)

- [App information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information) — app name, subtitle and macOS privacy policy URL.
- [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information) — description, keywords, required support URL and screenshots.
- [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) — Mac 16:10 pixel dimensions.
- [Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots) — localization and upload workflow.
- [App Review Guidelines §2.3](https://developer.apple.com/app-store/review/guidelines/#accurate-metadata) — accurate, non-misleading metadata.
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/) — disclosure workflow, separate from this draft.
