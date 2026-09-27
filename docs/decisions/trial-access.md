---
type: Decision Record
title: Trial and access
status: proposed
tags: [distribution, privacy, storage]
generated:
  by: agent
  at: 2026-09-27T18:54:12Z
---

# Trial and access

**Proposed, not implemented.** For first direct sales, ship without a timed trial if buyers can evaluate the existing demo or a clearly disclosed refund policy. This avoids a second access state, clock logic and license recovery before the payment route is known. Do not promise a refund window until the seller and provider confirm one. If evaluation of real calls is necessary, use the selected platform/vendor's supported trial and entitlement recovery rather than building a server or DRM. A trial is not an account requirement for Beseda.

## Access boundary

A one-time purchase grants capture and new processing, not ownership of the archive. Keep access entitlement outside `calls.sqlite` and call folders; never delete, encrypt behind a license, or migrate user data on entitlement change. At trial expiry or revoked purchase, stop **new** automatic/manual capture and **new** transcription, retry, reprocessing and summary generation, including queued jobs; do not interrupt an active recording or discard its audio. Finish and save that call and any in-flight processing safely, then pause later work. Explain the pause and how to restore purchase. Existing archive browsing, search, transcript and summary reading, playback of retained audio, copy/export of existing results, and deletion remain available indefinitely without payment or network. Do not let auto-start or background recovery bypass the same boundary. Audio retention still follows the user's setting; access loss must not change it.

A fresh install on the same Mac and a restored device should recover a purchase through the chosen distribution channel when available; copied local data must remain readable even if purchase verification is unavailable. A direct-sale license may require a user-held receipt/key for another Mac if the vendor has no restore facility; disclose this before sale. Do not identify a device by its call archive. Refund or chargeback revokes future paid actions once the provider reports it, but never removes existing calls or exports. Offline verification must allow already validated paid use during transient outages; exact grace and trial duration depend on the chosen provider's capabilities and belong to the later implementation decision. A new install without proof of purchase cannot start paid actions merely because an archive was copied there.

## Risks and acceptance conditions

- Prefer Store purchase restoration or a direct vendor's existing license verification. No custom account, always-on license server, hardware fingerprint, telemetry of calls, transcripts or model use. Send only the minimum purchase identifier needed by the vendor; document any online check before implementing it. Local entitlement cache is not a secure anti-piracy boundary.
- A local elapsed-time trial is vulnerable to clock rollback, reinstall and backup restore. Do not claim tamper resistance or use filesystem timestamps as a substitute for a vendor entitlement. If the channel cannot support a privacy-respecting offline trial, omit the trial instead of adding invasive DRM.
- Test paid, unverified/offline, expired-trial and refunded states: paid capture and processing work; restricted states cannot start them through menu, auto-detection, retry, queue or launch recovery; an active call survives a state change; pre-existing archive, search, playback, transcripts, export and deletion work in every state. Verify fresh install/restore with and without a valid purchase proof, and that a network outage does not lock out a previously validated paid installation. These are requirements for a later implementation, not claims about today's app.

See [development directions](development-directions.md), [payment path](payment-path.md), [installation](../product/install.md) and [storage](../architecture/storage.md).
