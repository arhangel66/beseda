---
type: Decision Record
title: Adversarial product and code review
status: proposed
tags: [product, architecture, privacy, release, quality]
---
# Adversarial product and code review

## Scope and evidence

Reviewed the product goals, architecture and decisions linked from `docs/index.md`; the current Swift code;
the speaker-accuracy measurements in `untracked/epics/speaker-accuracy/results/threshold-sweep.md` and
`real-calls-truth.md`; and the release scripts and packaged 0.3.2 app. Built the current HEAD from a private
scratch path and launched an isolated, renamed app with no focus or audio. Screenshots:
`.factory/BESEDA-83-shots/live-popover-preview.png`,
`.factory/BESEDA-83-shots/live-разговоры.png`, and
`.factory/BESEDA-83-shots/settings-обработка.png`.

The one permitted `nice -n 19 swift test --jobs 2` did not start tests within 20 minutes because another
SwiftPM process held `.build`; its log is `.factory/BESEDA-83-swift-test.log`. A scratch `swift build` of
HEAD completed. Real recording was not run because the repository forbids audio output and permission
interaction on the owner's app. Existing result files, tests and the code paths were reviewed instead.

Effort is S (hours), M (days), or L (weeks). Priority is P0 (blocks safe sale or risks calls), P1 (next), P2
(important), or P3 (later).

## Product

1. **There is no product that can collect the stated $49 — P0, M.** `docs/decisions/development-directions.md:52-53`
   names a price but leaves the channel open; the app and package contain no payment, receipt, licence,
   trial, or entitlement code. “Everything included” is also false for OpenRouter, whose key and usage bill
   belong to the buyer. This matters because the current work cannot produce revenue or enforce a one-time
   sale. Pick one channel now: Developer ID plus a small signed licence receipt is the shortest path in
   Russia; state that cloud usage is separate. Do not build both that and StoreKit.

2. **The product serves two unvalidated jobs and postponed validation until after the build — P1, S.**
   `docs/decisions/development-directions.md:35-36,50-55` admits only Mikhail and Irochka use it, combines
   work-call memory with psychologists, and puts the demand check after live mode, classification and
   before-meeting work. The two groups have different confidentiality, speaker, retention and summary
   requirements. Interview five of one group and measure weekly retrieval of an old decision before more
   feature work; remove the other group from positioning until it is tested.

3. **The default summary contradicts the memory promise — P1, L.** The running Processing screen says Gemma
   4 E4B “Теряет часть договорённостей и редко называет исполнителей”
   (`.factory/BESEDA-83-shots/settings-обработка.png`), while the product's main value is remembering
   agreements and next actions. A cheap default that loses those facts makes a polished summary actively
   less trustworthy than the transcript. Build a small, human-labelled agreement/action benchmark from
   real calls and do not present generated conclusions as the primary result until the chosen local model
   clears it; an extractive list with transcript links is a safer interim result.
   Addressed in part by BESEDA-94: a new default prompt («Договорились», «Кто что делает» with names and
   dates, temperature 0.1), checked on one synthetic Russian call with 6 agreements and 9 assignments,
   three runs each, hand-scored ([summarization.md](../architecture/summarization.md)). Both prompts kept 5
   of 6 agreements and all five assignees; the new one kept 23 of 27 assignments against 21. No
   human-labelled benchmark from real calls was built, and the result is still the primary one.

4. **Feature scope is larger than the proved job — P1, M.** Jev, user-defined classifier prompts, live key
   points, LM Studio discovery and the bespoke webhook add failure modes before demand is known
   (`docs/decisions/development-directions.md:37-46`; `Webhooks/WebhookService.swift:10-11`). Cut Jev, live
   LLM key points, LM Studio and the automatic webhook from the paid first release. Keep capture, local
   transcript/search, one local post-call result, calendar naming and previous-call retrieval; add features
   back only when observed use requires them.

5. **The “archive” silently ends at 200 calls — P1, M.** `App/AppController.swift:670` loads only 200 rows,
   and search filters that loaded array even though SQLite searches all segment IDs. At two calls per workday,
   older memory disappears from navigation in about five months. Add cursor pagination and SQLite FTS; make
   search return and open records outside the loaded page.
   Addressed in BESEDA-92: «Показать ещё» pages the sidebar, `searchCalls` searches every call in SQLite
   ([storage.md](../architecture/storage.md)); offset paging and LIKE, no FTS — ~0.1 s on 2000 calls.

6. **“В прошлый раз” is incompatible with the advertised custom prompts — P1, M.**
   `Storage/RelatedCalls.swift:21-22,50-72` extracts three exact headings from the default Russian prompt
   and otherwise displays the first five lines. A user-defined psychology or 1:1 prompt can therefore show
   an introduction instead of agreements, and calls without calendar metadata often cannot relate at all
   (`docs/architecture/related-calls.md:24-29`). Store decisions, actions and open questions as structured
   fields independent of presentation, and add a manual relation when calendar matching has no answer.
   Addressed in BESEDA-94 without structured fields: a result with the default headings shows the digest,
   any other result is shown whole, collapsed with «Показать полностью»
   ([related-calls.md](../architecture/related-calls.md)). No manual relation.

## Architecture and code

7. **Index failures are converted into apparent success — P0, M.** `App/AppController.swift:1061-1074`
   swallows a failed `replaceSegments`, then persists `ready`, cleans audio and enqueues integrations;
   `saveCall` itself also uses the swallowing `updateCallIndex` at `App/AppController.swift:1446-1460,1533-1539`.
   Disk-full or SQLite corruption can leave a “completed” call with no searchable transcript, or an orphan
   folder absent from the UI. Make storage mutations throwing, commit segments and ready status in one
   transaction, and only clean audio or send webhooks after that transaction succeeds.
   Fixed in BESEDA-89: pipeline index writes throw into the job's error status; `markReady` commits segments
   and `ready` in one transaction before audio cleanup, webhooks and auto-processing.

8. **Crash recovery only handles calls that already reached SQLite — P0, M.** Recording creates a directory
   before the non-throwing index write (`App/AppController.swift:735-736`); startup repairs only folders
   returned by `failInterruptedCalls` and ignores errors from `repairWAVHeader`
   (`App/AppController.swift:257-265`). A crash or index failure in that gap leaves audio forever invisible.
   Reconcile every folder under `calls/` at launch, validate both WAV headers and lengths, reconstruct a
   failed row from `session.json` or file times, and expose a recovery error instead of silently continuing.
   Fixed in BESEDA-100: launch gives every orphan folder under `calls/` a failed, retryable row; both raw WAVs
   are repaired and opened, a failure is logged and written into the call's error; an unavailable index is
   shown in the status line. `AppController` takes its paths by injection, so this is tested end to end.

9. **Disk I/O and allocations run on real-time audio callbacks — P0, M.** Both capture callbacks call
   `PCMFloatRecorder.append` directly (`Audio/MicrophoneCapture.swift:55-59`,
   `Audio/SystemAudioTap.swift:89-94`); it allocates/interleaves arrays and an `AVAudioPCMBuffer`, locks, then
   performs `AVAudioFile.write` synchronously (`Audio/PCMFloatRecorder.swift:86-96,175-200`). A slow or busy
   disk can glitch before the polling UI notices an error, and `droppedBufferCount` counts thrown writes,
   not callback starvation. Copy into bounded preallocated ring buffers and write on dedicated serial
   workers; stop visibly on overflow. Stress this while ASR, diarization and the local LLM load the machine.
   Fixed in BESEDA-101: the callback only copies into a preallocated lock-free ring; a writer thread per
   recorder writes the file, an overflow stops the recording through the write-error path. Under CPU and disk
   load callback p99 fell from 1.6–11.8 ms to 27–122 µs ([audio capture](../architecture/audio-capture.md)).

10. **Deletion can destroy files while leaving a live database row — P1, M.**
    `Storage/CallStore.swift:450-463` deletes the transcript, export and call folder first, then deletes the
    SQLite row. If the final database operation fails, retry cannot restore the files and the archive keeps a
    broken call. Atomically rename files to an app-owned trash location, delete the row in a transaction,
    then remove trash; restore the rename if the transaction fails.
    Fixed in BESEDA-89: the folder is renamed into `trash/`, the row deleted, then files removed; a failed
    row delete restores the folder, leftover trash is emptied at launch.

11. **Long calls are repeatedly loaded whole into memory — P1, M.** `LocalTranscriber.readSamples` allocates
    an array for the entire normalized file (`Transcription/LocalTranscriber.swift:188-202`), and
    `AppController.echoGated` loads both channels together (`App/AppController.swift:968-972`). A four-hour
    call is roughly 0.9 GB per mono Float array before model, words and FFT scratch; the built-in summary model
    separately needs about 5 GB. Stream fixed windows through ASR and echo cancellation, retaining only word
    metadata, and publish a peak-memory test for the four-hour supported limit.
    Fixed in BESEDA-102: ASR and the echo gate read the normalized files in windows through `SampleSource`;
    on a synthetic 4-hour call peak RSS fell from 3576 MB to 62 MB (echo gate) and from 1772 MB to 77 MB
    (reading for ASR) ([ASR](../architecture/asr.md)).

12. **Migrations have no version, transaction or backup — P1, M.** `CallStore.prepare` conditionally executes
    many `ALTER TABLE` statements (`Storage/CallStore.swift:290-361`) outside a migration transaction and
    drops a column in place. A crash half-way leaves a schema that no declared version can diagnose or roll
    back. Use `PRAGMA user_version`, one transaction per migration, a pre-migration SQLite backup, and tests
    from every released schema.
    Fixed in BESEDA-89: `PRAGMA user_version` migrations, one transaction each, `VACUUM INTO` backup before
    migrating; tests migrate the 0.3.x schema and roll back a failing migration.

13. **Automatic processing jobs disappear on quit — P1, M.** The architecture explicitly says the queue is
    memory-only (`docs/architecture/summarization.md:12-13`). A user who closes the app after a call can have
    auto-processing silently never happen, with no pending state on restart. Persist a processing state on
    the call and resume it idempotently; manual jobs can remain in memory.
    Fixed in BESEDA-100: migration 2 adds `calls.processing_pending`, set before an auto job is queued and
    cleared when it ends; launch re-queues the marked calls once. Back-to-back calls queue in order.

## Speaker separation

14. **The new six-second merge is a fitted deletion rule, not speaker identification — P1, S.**
    `docs/decisions/speaker-accuracy.md:160-183` merges every speaker lacking a six-second segment into the
    nearest long speaker. A real participant who only says short replies is erased; the document already
    reports that a nearby threshold merges a real daily participant. For the failing 1:1 calls, skip remote
    diarization and force one remote speaker when the calendar has two attendees or the user chooses “1:1”.
    Keep unconstrained diarization only for group calls. This directly fixes the 2–3-label symptom without a
    new model.

15. **The claimed real-call truth is not adequate ground truth — P1, M.**
    `untracked/epics/speaker-accuracy/results/real-calls-truth.md` derives participant counts from anonymised
    transcript content using Claude, with medium and low confidence, not from humans listening to audio; it
    does not label who spoke when. Counts cannot detect two real people being merged while another is split.
    Human-label speaker intervals on a small, consented set of real 1:1, daily and psychology calls, then
    report DER and count error per call type before changing global heuristics.

16. **The echo gate can assign the right text to the wrong time and person — P1, M.** The implementation keeps
    the whole ASR sentence text but moves its bounds to only the longest own-speech run
    (`docs/decisions/speaker-accuracy.md:148-153`; `Transcription/EchoGate.swift:14-45`). Mixed me/echo
    sentences therefore retain remote words under “Я”, and clicking seeks to fabricated bounds. The measured
    synthetic echo is a single delay/gain, while the decision says real rooms smear it. Gate words by their
    timestamps against the mask, and rescore the app pipeline on real speaker playback; if that fails, use a
    proven AEC rather than sentence surgery.

## Privacy and security

17. **Turning on live text can transmit an ongoing therapy/work call without a per-call gate — P0, M.** Live
    key points send accumulated lines every 180 seconds to whichever summary provider is selected
    (`docs/architecture/live-transcription.md:30-33`; `App/AppController.swift:823-829`), while Jev sends the
    opening automatically whenever a key exists. One settings note is not meaningful consent for every call,
    and a private call type cannot prevent Jev because classification happens first. Disable cloud use in
    live mode, require an explicit first-send confirmation naming the destination, and add a per-call
    “never leave this Mac” switch that bypasses Jev, cloud summaries and webhooks.
    Fixed in BESEDA-88: a global «Только локально» switch (off by default, OpenRouter stays the default with a
    key) turns off Jev and webhooks and moves summaries and live key points to the built-in model; Settings
    show one line saying what goes to the cloud now. No per-call gate or confirmation dialog, by decision.

18. **Secrets and transcripts can be sent in plaintext — P0, S.** The OpenRouter key and webhook secret are
    stored in UserDefaults (`App/AppSettings.swift:149-150,227-230`); webhook validation accepts `http://`
    and duplicates the secret into two headers (`Webhooks/WebhookSender.swift:100-109,127-132`). Malware or a
    backup can read credentials, and an HTTP endpoint exposes both transcript and secret on the network.
    Move both secrets to Keychain, accept HTTPS only except an explicit localhost development case, and send
    one standard authorization header.
    Fixed in BESEDA-91: both secrets live in the Keychain with a silent one-time move out of UserDefaults;
    the webhook refuses http except localhost/127.0.0.1/::1 and sends the secret as-is in one `Authorization` header (no `Bearer` prefix: kushetka compares the whole value).

19. **“Local” storage has no stated threat model for the target's sensitive data — P1, L.** Owner-only modes
    and `completeUntilFirstUserAuthentication` (`Storage/StorageJanitor.swift:153-171`) do not protect an
    unlocked Mac, exports live outside the managed folder, and webhook response bodies are persisted. For
    psychologists this can contain regulated client material. Remove psychologists from marketing until the
    product documents FileVault/backup/export exposure, offers a strict-local profile, supports short
    retention defaults, and encrypts the index and exported sensitive fields with a Keychain-held key.
    Docs part addressed in BESEDA-90: [privacy.md](../product/privacy.md); encryption of the index and exports is not done.

## Docs, tests and release

20. **The published app fails normal macOS trust checks — P0, M.** `scripts/lib/bundle_app.sh:47-57` chooses
    an Apple Development identity, omits hardened runtime and entitlements, and never notarizes. The packaged
    0.3.2 app was rejected by `spctl` and had no stapled ticket; `docs/product/install.md:11-14` tells buyers
    to bypass Gatekeeper. A $49 release must use Developer ID Application signing, hardened runtime with the
    audio entitlement, notarization and stapling, then pass `codesign`, `spctl` and `stapler validate` in the
    release command.

21. **A failed GitHub upload can publish a permanently broken update feed — P0, S.**
    `scripts/release.sh:58-67` writes and pushes the appcast and tag before `gh release create` uploads the
    referenced zip. Network or GitHub failure at the last command leaves installed apps offered a missing
    asset. Create a draft release and upload the asset first, verify its URL and signature, then push/publish
    the feed; make reruns idempotent.
    Fixed in BESEDA-88: the release is uploaded on a pushed tag, downloaded back and compared with the local
    zip before the appcast is written into the repo, committed and pushed; a rerun needs the tag deleted.

22. **Tests do not prove the destructive and distributable paths — P1, M.** The suite has unit coverage for
    copied WAV repair and storage helpers, but no subprocess-kill test spanning capture → crash → relaunch →
    folder reconciliation → retry, no disk-full test through both capture callbacks and the controller, no
    migration matrix from released databases, and no packaged-app trust/update smoke test. Add those four
    black-box checks; make the release script consume their packaged artifact instead of rebuilding after
    tests.

23. **Installation requirements are internally impossible — P2, S.** `docs/product/install.md:6-7` asks for
    about 3 GB free, while the same page says the built-in model alone is 4.6 GB at lines 32-34, before ASR,
    runtime, temporary downloads and calls. State separate minimums for transcription-only and local-summary
    installs, including temporary download headroom, and enforce them before downloads.
    Addressed in BESEDA-90: separate minimums in [install.md](../product/install.md); no free-space check before downloads.

## Anything else

24. **The first-use UI reports a missing model as “Активная” — P2, S.** In the current Processing screenshot,
    Parakeet is marked active while the card still says “Скачать” and total model storage is 0 B
    (`.factory/BESEDA-83-shots/settings-обработка.png`). “Selected” and “installed/ready” are different states;
    calling the former active makes a user expect recording to work. Rename it “Выбрана”, reserve “Готова”
    for a verified model, and put the blocking state beside the record control.

25. **The native UI has no automated accessibility contract — P2, M.** Only the player position has an
    explicit accessibility label in `App/Views/` (`PlayerBar.swift:140`), and there is no UI-test target.
    Icon-only recording, status, speaker editing and navigation controls can regress for VoiceOver and cannot
    be driven reliably by a release smoke test. Add labels/values to icon-only and dynamic controls, then one
    XCUITest journey for onboarding, record state, archive navigation, copy and delete.
