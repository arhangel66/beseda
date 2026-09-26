---
type: Architecture
title: Integrations
description: How a finished call leaves Beseda through the webhook, and how the Mac's calendar names calls.
---
# Integrations

There are two: an outgoing webhook and the macOS calendar. There is no MCP code in the project.

## Webhook

### How it works

- **When it fires** — `AppController.finishCall` calls `WebhookService.enqueue(callID:)` after a
  transcript is indexed. Nothing is written while the webhook is off or the URL is refused (see Request). The
  automatic send also requires the call to be longer than 40 min (`minimumAutomaticCallDuration` 2400 s)
  and at least 30 s of recognized speech both from the microphone and from some other speaker
  (overlapping segments are merged before counting). «Отправить»/«Повторить» (`sendNow`) skips these checks.
- **Queue** — rows in the `webhook_deliveries` table are the queue: each attempt is a row with
  `next_retry_at`. A 60 s timer (`deliverDue`) sends whatever is due, one request per call at a time.
  On start, rows left `sending` by a quit are marked failed and retried; the server dedupes by delivery id.
- **Retries** — only `failed` (network error, timeout, 5xx) is retried: after 60 s, 5 min, 30 min, then
  it gives up (four attempts). A 4xx is `rejected` and not retried: the address or the secret is wrong.
- **Request** (`WebhookSender`) — `POST` with a 150 s timeout (the receiver runs a language model
  behind a 120 s nginx timeout). Headers: `Authorization: Bearer <secret>` (left out when the
  secret is empty), `X-Podushka-Event`, `X-Podushka-Delivery` (the row id), `User-Agent: Beseda`. The response body is kept
  up to 2048 chars; a 2xx JSON `action` field is stored and shown. The URL must be https; plain http is
  accepted only for `localhost`, `127.0.0.1` and `::1`. A saved http address to any other host is not
  sent to: due rows wait, and Settings shows the reason under the address field and in the test result.
- **Payload** (`WebhookPayload`, sorted-key JSON) — `event: "transcript_created"`, `meeting`
  {id, name, started_at} and `transcript.text` in the Krisp shape the receiver (kushetka) already accepts,
  plus Beseda's own `call`, `participants` (key, renamed name, `is_me`), `dialogue` lines and `summary`.
  It is built from the stored segments and speaker names, never from `transcript.md`.
- **Test** — `sendTest` posts `event: "podushka_test"`, which the receiver skips; nothing is stored.

### Main files

`Webhooks/WebhookService.swift` (queue, retries, journal), `Webhooks/WebhookSender.swift` (one POST,
outcome classification), `Webhooks/WebhookPayload.swift`. Settings: `webhookEnabled`, `webhookURL`,
`webhookSecret` in `AppSettings`; the journal is shown in Settings → «Интеграции» and on the call.

### Constraints

- The `X-Podushka-Event`/`-Delivery` header names and the `podushka_test` event are the receiver's contract, kept from
  the app's old name.
- The receiver must accept `Authorization: Bearer <secret>`; `X-Podushka-Secret` is no longer sent.
- The secret is stored in the Keychain, not `UserDefaults` (see [App structure](app-structure.md)).

## Calendar

### How it works

`CalendarService` reads EventKit (full access, macOS 14) to name calls and show upcoming events. It
never starts a recording. `AppController.matchCalendarEvents` fetches events once for the range of
unnamed calls (±1 h) from the chosen calendars (`calendarIdentifiers`, empty = all), then
`CalendarService.match` picks for each call the event that *began* within 5 min of the call start and
lasts over 15 min, nearest start first. All-day events are dropped. A match is stored with
`pinned: false`; a user's choice (`assignEvent`) is pinned and never overwritten.
`hasConferenceLink` (zoom, meet, teams, t.me, telemost, whereby, discord.gg in URL/location/notes) only
feeds the sidebar's guess of what will be recorded.

### Constraints

- Matching is attempted once per call per run (`eventMatchAttempted`).
- An event merely overlapping the call does not match, so long "Busy" blocks do not swallow calls.
