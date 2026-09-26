# Webhook delivery for Podushka (kushetka-compatible)

## Context

Podushka records a call, builds `transcript.md` + SQLite segments, and stops there: nothing leaves the Mac. The v2 design (`untracked/design/prototype-v2.dc.html`, «Интеграции» tab) already sketches the missing half: a toggle «Отправлять расшифровку на свой сервис», an address, a secret header, a «Отправить тест» button and a «Журнал доставок». That half was explicitly cut from the v2 UI plan and is what we build now.

First consumer is kushetka (`/Users/mikhail/w/kushetka`), a therapist's session tool whose only ingest is `POST /api/webhooks/krisp` (`backend/src/kushetka/api/webhooks_krisp.py`). Its contract, verified in code:

- Auth: raw secret in `Authorization` header (no `Bearer`), `compare_digest`; 401 on mismatch, 503 when `KRISP_WEBHOOK_SECRET` unset.
- Pydantic models are `extra="ignore"` → unknown keys are dropped. Effective requirements: `event == "transcript_created"`, `meeting.started_at` (ISO datetime), `transcript.text` (lines `"Speaker: text"`). Must NOT send a `data` key (that path takes precedence) nor top-level `started_at`/`meeting_id`.
- Start-time check runs before the event filter → a test payload with `event: "podushka_test"` and a `meeting.started_at` returns 200 `{"action":"skipped_event_type"}` writing nothing. Safe auth/connectivity probe.
- Matches a calendar session by start time ±30 min. Always 200 with `{"action": ingested|skipped_no_match|skipped_duplicate|skipped_no_text|skipped_event_type, "session_id"?}`. 400 only for bad JSON / missing start time. Re-sending is idempotent (`skipped_duplicate`).
- Runs its LLM pipeline synchronously inside the request (10–30 s) behind nginx `proxy_read_timeout 120s` → podushka timeout 150 s.
- Prod URL: `https://kushetka.slotik.app/api/webhooks/krisp`; secret in kushetka `.env.production` (`KRISP_WEBHOOK_SECRET`).

Decisions taken with Mikhail:
1. **One superset payload**: podushka's own rich JSON plus the krisp keys, so kushetka needs no code change and any other service gets everything.
2. **Trigger**: auto-send once when the transcript is ready; retry transient failures at 1, 5, 30 min; manual «Отправить» / «Повторить» from the call view and the journal.
3. **Secret in UserDefaults** like every other setting (Keychain is a later follow-up).

## Design

New directory `Webhooks/` with three files; `CallStore` gets one table; `AppController` gets a `webhooks` property, three one-line `enqueue` calls and one `showCall` call; `AppSettings` gets three keys; UI in `IntegrationSettings` and `CallInfo`.

**Delivery row = one attempt.** States `queued → sending → delivered | failed`. A retryable failure inserts a new `queued` row with `attempt + 1` and `next_retry_at`. Every state change is a persisted timestamp, so the UI can show "ушло 12:04 · доставлено 12:04 · ingested" and the full attempt history per call.

**Payload** (snake_case, explicit `CodingKeys` as in `ASRTranscription`):
```json
{
  "event": "transcript_created",
  "meeting":    { "id": "<call id>", "name": "<displayTitle>", "started_at": "<ISO Z>" },
  "transcript": { "text": "Вы: …\nСобеседник: …" },
  "call": { "id", "started_at", "ended_at", "duration_sec", "app", "kind" },
  "participants": [ { "key": "me", "name": "Вы", "is_me": true }, … ],
  "dialogue": [ { "start_sec", "end_sec", "speaker", "text" }, … ],
  "summary": "<summaryText, key absent when nil>"
}
```
`transcript.text` = `TranscriptCopy.render(detail, format: .clean)` (`Storage/TranscriptCopy.swift:52`), which already yields kushetka's `Speaker: text` lines and honours renamed speakers. Names via `SpeakerNaming.name(for:overrides:)`. Built from `transcript_segments` + `call_speakers`, never from `transcript.md`.

**Headers**: `Content-Type: application/json`, `Authorization: <secret>` (raw, for kushetka), `X-Podushka-Secret: <secret>` (for anything that will not accept a bare Authorization), `X-Podushka-Event: transcript_created|test`, `X-Podushka-Delivery: <row uuid>`, `User-Agent: Podushka`.

**Outcome classification** (pure, tested): 2xx → `delivered(status, action?, body)`; 4xx → `rejected` (config problem, no retry; kushetka 401/400); 5xx / network / timeout → `failed` (retry; kushetka 503 "not configured", nginx 502/504). Response body stored truncated to 2 KB; `action` parsed from JSON when present.

## Steps

Each step: RED (test/build fails) → GREEN. Run `swift test` from repo root.

- [x] **0. Plan doc in repo**: copy this plan to `docs/webhook-plan.md` (English, checkboxes), per the house workflow.

- [x] **1. `Package.swift`**: add `"Webhooks"` to `sources` (`Package.swift:43-50`).

- [x] **2. `Webhooks/WebhookPayload.swift`** — `struct WebhookPayload: Encodable` with nested `Meeting`, `Transcript`, `Call`, `Participant`, `Line`; `static func make(detail: StoredCallDetail, event: String = "transcript_created")`; `static func test(now: Date)` (event `podushka_test`, `meeting.started_at = now`, `transcript.text = "Вы: тест"`, empty lists); `func encoded() throws -> Data` (`JSONEncoder` with `.sortedKeys`). Participants = unique `segment.speaker` keys in first-appearance order, `is_me = key == TranscriptChannel.microphone.speakerID`.
  Tests `WebhookPayloadTests.swift`: krisp keys present next to podushka keys and no `data` key; renamed speaker reaches both `transcript.text` and `participants`; test payload has `meeting.started_at`; nil summary leaves the key out.

- [x] **3. `Webhooks/WebhookSender.swift`** — `final class WebhookSender: Sendable` with `typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)` (default `URLSession.shared.data(for:)`), `timeout = 150`. `func send(_ body: Data, to: URL, secret: String, event: String, deliveryID: String) async -> WebhookOutcome` never throws. Pure statics: `request(...)`, `classify(data:status:) -> WebhookOutcome`, `endpoint(from: String) -> URL?` (trimmed, http/https, non-empty host). `enum WebhookOutcome: Equatable { delivered, rejected, failed }` with `isRetryable`, `state`, `httpStatus`, `responseAction`, `responseBody`, `error`. Model: `Summarization/LocalModelProvider.swift:28-73`.
  Tests `WebhookSenderTests.swift`: 200+action → delivered; 401 → rejected, not retryable; 503 → failed, retryable; body cut at 2048; request carries all headers and 150 s timeout, `Authorization` has no `Bearer`; spy transport receives the body; `URLError.timedOut` → retryable failure; `endpoint` rejects `ftp://`, bare words, empty.

- [x] **4. `Storage/CallStore.swift`** — in `prepare()` after `call_speakers` (:305-312):
  ```sql
  CREATE TABLE IF NOT EXISTS webhook_deliveries (
    id TEXT PRIMARY KEY,
    call_id TEXT NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
    call_title TEXT NOT NULL, attempt INTEGER NOT NULL, event TEXT NOT NULL, url TEXT NOT NULL,
    state TEXT NOT NULL, http_status INTEGER, response_action TEXT, response_body TEXT, error TEXT,
    created_at TEXT NOT NULL, sent_at TEXT, finished_at TEXT, next_retry_at TEXT);
  CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_call ON webhook_deliveries(call_id, attempt);
  CREATE INDEX IF NOT EXISTS idx_webhook_deliveries_due ON webhook_deliveries(state, next_retry_at);
  ```
  `deleteCall` (:358-368) already re-enables `foreign_keys` per connection, so cascade works. `struct StoredWebhookDelivery: Identifiable, Hashable` (all columns + `isFinished`, `stateLabel` «в очереди/отправляю/доставлено/ошибка», `detailLine`). Functions, template `setSummary` :629 / `fetchSegments` :788: `insertWebhookDelivery(id:callID:callTitle:attempt:event:url:nextRetryAt:)`, `markWebhookSending(id:url:)`, `finishWebhookDelivery(id:state:httpStatus:responseAction:responseBody:error:)`, `fetchWebhookDeliveries(callID:)` (attempt DESC), `fetchRecentWebhookDeliveries(limit: 20)`, `fetchDueWebhookDeliveries(now:)` (`state='queued' AND next_retry_at <= ?`), `webhookAttemptCount(callID:)`, `failInterruptedWebhookDeliveries(reason:) -> [StoredWebhookDelivery]` (rows left `sending`). One shared column-list constant + `makeWebhookDelivery(statement)` decoder; add `columnInt` helper next to `columnDouble` (:912). Make `Date.iso8601WithFractions` (:922) internal. Do not touch the `calls` SELECTs or `makeSummary`.
  Tests `CallStoreWebhookTests.swift` (temp-DB pattern from `CallStoreSummaryTests.swift:6-30`): three-state round trip; cascade on `deleteCall`; only due queued rows returned; `sending` rows failed on launch and returned; attempt count.

- [x] **5. `App/AppSettings.swift`** — keys `podushka.webhookEnabled` (Bool, false), `podushka.webhookURL` (""), `podushka.webhookSecret` (""), three-edit pattern (:47-59, :61-141, :145-162). No validation here; `WebhookSender.endpoint(from:)` is the single check.
  Test in `AppSettingsTests.swift`: defaults and round trip via a second `AppSettings(defaults:)`.

- [x] **6. `Webhooks/WebhookService.swift`** — `@MainActor @Observable final class WebhookService`:
  - `static func retryDelay(afterAttempt:) -> TimeInterval?` — 1→60, 2→300, 3→1800, else nil; `static let tickInterval = 60`.
  - Observable: `recent: [StoredWebhookDelivery]` (journal), `selected: [StoredWebhookDelivery]` (open call), `sending: Set<String>` (call ids in flight), `testResult: String?`, `isTesting`.
  - `init(store: CallStore, settings: AppSettings, sender: WebhookSender = WebhookSender())`, `var log: (String) -> Void = { _ in }` (set by the controller after init).
  - `start()`: `failInterruptedWebhookDeliveries("Interrupted before the app restarted")` → queue follow-ups per `retryDelay`; `deliverDue()`; arm a 60 s `Timer` (shape of `startDailySweep` :1576, own timer because 24 h cannot honour 1 min).
  - `enqueue(callID:)`: no-op with a log line when disabled or URL invalid (no row); else insert `attempt = count + 1`, `next_retry_at = now`, then `deliverDue()`.
  - `sendNow(callID:)`: same insert, used by «Отправить»/«Повторить».
  - `showCall(id:)`, `refresh()`.
  - `sendTest()`: mirrors `checkSummaryConnection` (:1342); no row written; result strings: delivered → «Сервис ответил 200 · skipped_event_type за 0.3 с», 401 → «Секрет не подошёл (401)», other 4xx → «Сервис отклонил запрос: HTTP n», failed → error text.
  - `deliver(row)`: guard per-call `sending`; guard enabled + valid URL (else leave queued); load `StoredCallDetail` from store (`fetchCall`, `fetchSegments`, `fetchSpeakerNames`, `markdownText: nil, jobStats: nil`); `markWebhookSending`; `WebhookPayload.make(...).encoded()`; `await sender.send(...)`; `finishWebhookDelivery`; if retryable and `retryDelay` non-nil → insert next `queued` row; log every transition via `log`.
  Tests `WebhookServiceTests.swift` (`@MainActor`, temp DB + `UserDefaults(suiteName:)` + actor spy transport as in `SummarizationTests.swift`): retry schedule table; ready call → one `delivered` row and body has `event == "transcript_created"`; disabled → no row; 503 → row 1 failed + row 2 queued attempt 2 ~60 s ahead; 401 → one failed row only.

- [x] **7. `App/AppController.swift`** — `@ObservationIgnored let webhooks: WebhookService` created in `init` before `wireNotifier()`, then `webhooks.log = { [weak self] in self?.appendLog($0) }`; `webhooks.start()` inside the `do` block right after `failInterruptedCalls` (:212-215). `webhooks.enqueue(callID: callID)` after `status = .completed` at the three ready points (:890 dual, :1003 mic retry, :1125 dual retry). `webhooks.showCall(id: call.id)` at the end of `loadCallDetail` (:1428); `webhooks.showCall(id: nil)` in `selectCall(id: nil)` (:651-653).

- [x] **8. UI**
  - `App/Views/SettingsWindow.swift`: `private struct WebhookSettings: View` appended to `IntegrationSettings.body` (:252) after a `Divider()`: `SettingRow` «Отправлять расшифровку на свой сервис» / «POST после каждой готовой расшифровки» bound to `webhookEnabled`; warning line «Это единственное, что покидает ваш Mac. Уходит только на этот адрес: расшифровка, участники, саммари и время звонка.»; card (styling of `serverCard` :389-432) with «Адрес» `TextField` and «Секрет» `SecureField`/`TextField` + `OutlineButton` «Показать/Скрыть», hint «Уходит в заголовках Authorization и X-Podushka-Secret»; `checkRow` clone with `AccentButton` «Отправить тест» → `controller.webhooks.sendTest()` and `testResult`; «Журнал доставок»: `ForEach(controller.webhooks.recent)` rows `clock · callTitle · stateLabel (coloured) · detailLine` + `OutlineButton` «Повторить» when failed and not in flight; empty state «Пока ничего не отправлялось». `.onAppear { controller.webhooks.refresh() }`.
  - `App/Views/CallDetailView.swift`: `CallInfo` (:551) gains `let controller: AppController` (call site :69-70); `rows` (:603-622) gets `("Вебхук", …)` = latest `selected` row `"stateLabel · detailLine"`, or «выключен», or «не отправлялся»; below the grid a «Доставки» list of `selected` rows (`attempt · clock · stateLabel · detailLine`) and one `OutlineButton` «Повторить»/«Отправить сейчас» → `controller.webhooks.sendNow(callID:)`, disabled while in flight, when disabled, or when `detail.segments.isEmpty`. No new banner in v1.

- [x] **9. kushetka compatibility test (kushetka repo, test only, no code change)** — add `backend/tests/api/fixtures/podushka_transcript_created.json` (the exact payload from step 2, captured from a real send) and one test in `backend/tests/api/test_webhooks_krisp.py`: with a session at the same start time the podushka payload is `ingested` and `session_source.text` equals `transcript.text`; and `event: "podushka_test"` is `skipped_event_type`. Run `cd backend && uv run pytest -x`. Pins the contract on the receiving side so a future kushetka change cannot silently break podushka. Commit separately in kushetka (`ship.sh` refuses a dirty tree).

- [x] **10. Docs** — README: one paragraph on «Интеграции → Вебхук» (what leaves the Mac, headers, kushetka URL). AGENT.md: `Webhooks/` in the tree.

## Verification

1. `swift test` green (77 existing + new); `pytest python/tests` untouched and green.
2. `./scripts/build_podushka_app.sh`, open the app.
3. Local kushetka: `cd /Users/mikhail/w/kushetka/backend && KRISP_WEBHOOK_SECRET=test-secret uv run uvicorn kushetka.main:app --port 8090`. In podushka Settings → Интеграции: URL `http://127.0.0.1:8090/api/webhooks/krisp`, secret `test-secret`, toggle on, «Отправить тест» → «Сервис ответил 200 · skipped_event_type». Wrong secret → «Секрет не подошёл (401)». Kushetka `GET /api/webhooks/krisp/recent` shows the probe.
4. Open an existing call → Инфо → «Отправить сейчас» → row `delivered · skipped_no_match` (no session at that time in the local kushetka DB). Create/import a session at the call's start time (or insert one in `data/kushetka.db`), send again → `ingested`, kushetka shows the transcript with `Вы:`/`Собеседник:` lines and runs insights.
5. Stop kushetka, send → `failed · HTTP 0 / connection refused`, next row `queued` with retry in 1 min; start kushetka again, wait a minute → `delivered`. Quit podushka while a row is `sending`, relaunch → row `failed · Interrupted…`, follow-up queued.
6. Record a real call end-to-end with the webhook on → log line `Webhook <id> attempt 1: delivered …` and the journal entry in Settings.
7. Prod: point at `https://kushetka.slotik.app/api/webhooks/krisp` with the value of `KRISP_WEBHOOK_SECRET` from kushetka `.env.production`; «Отправить тест» must return 200 · skipped_event_type.

## Risks / notes

- Auto-send fires before speaker renames or a summary exist; kushetka dedupes, so a later manual re-send does not update it there (`skipped_duplicate`). Acceptable for v1.
- `timeoutInterval` is an inactivity timeout; 150 s covers kushetka's silent LLM run behind the 120 s nginx read timeout. Per-call `sending` guard prevents duplicate concurrent attempts.
- Quit mid-request may deliver twice after relaunch; idempotent on kushetka.
- Secret is plaintext in `~/Library/Preferences` and visible when «Показать» is pressed. Keychain later.
- `next_retry_at <= ?` relies on every timestamp coming from `Date.iso8601WithFractions` (UTC `Z`), which is why it becomes internal and is the only formatter used.
- Queued rows stay «в очереди» if the user disables the webhook; failing them on disable is a two-line follow-up if it reads badly.
- `docs/summarization-feature-spec.md` and `implementation_journal.md` are stale (feature shipped, diverged); unrelated, left alone.
