# Plan: three HIGH findings from the audit

Source: `docs/review-claude-sonnet-5/architecture-review.md`, findings #1, #2, #5.
Baseline before the work: `swift test` 71 tests green, `pytest python/tests` 5 tests green.

Scope: the three cheap, testable HIGH findings. The two audio findings (#3 real-time thread
violation, #4 clock alignment between the two capture streams) are deliberately left out —
they need a lock-free ring buffer and a shared clock, which is a separate, riskier change.

---

## 1. ASR client can hang forever (finding #1)

`Transcription/ASRClient.swift`

Two separate holes, both end with `transcribe()` never returning and the call stuck in
`transcribing` with no way out:

- No deadline. A worker that hangs inside inference (not crashed, just silent) leaves the
  continuation pending forever.
- `handleLine` catch branch only logs `Invalid ASR response:`. If a `job_done` arrives but
  fails to decode, `pendingJobs[id]` is never resumed at all.

### Steps

- [x] **1.1** Watchdog on worker silence, not a fixed job deadline. The worker emits
  `job_progress` per audio chunk, so silence is the real signal. Per pending job keep a
  `DispatchWorkItem` on `queue`, re-armed on every event that carries the job id
  (`job_started`, `job_progress`). On fire: resume the continuation with
  `PodushkaError.processFailed`, then `terminateWorker()` so the next job starts on a clean
  process instead of the wedged one. Timeout is an `init` parameter, default 5 minutes.
  - *Check:* `swift build` green; no automated test — see the note below.
- [x] **1.2** A `job_done`/`job_failed` that fails to decode must still resolve its job.
  Add `ASRClient.jobID(inUndecodableLine:)`: a second, lenient decode of `{type, id}` only;
  when it yields a job id, resume that continuation with a failure instead of only logging.
  - *Check (RED→GREEN):* new test in `Tests/PodushkaTests/ASRClientTests.swift` —
    a truncated `job_done` line with a readable `id` returns that id, a line with no id
    returns nil, a `job_progress` line returns nil (progress must not kill a live job).
- [x] **1.3** Cancel the watchdog wherever the job leaves `pendingJobs`
  (`job_done`, `job_failed`, `terminateWorker`, `handleTermination`).
  - *Check:* `swift test` green, and the app records one real call end to end.

Honest gap: the watchdog itself has no unit test. `ASRClient` launches a real `uv` process,
so testing it means injecting a transport — a refactor larger than the fix. Only the parsing
part (1.2) gets a test; the timer path is verified by hand.

---

## 2. The janitor deletes audio a retry still needs (finding #2)

`Storage/StorageJanitor.swift`, `Storage/CallStore.swift`, `App/AppController.swift`

`RetentionRule.immediately.maximumAge == 0`, so every file is expired the moment it exists.
`AppController.init` marks interrupted calls as `failed` (retry button visible) and then, on
the same launch, sweeps their audio away. The daily timer can equally delete the `*.asr.wav`
a running transcription is reading, since the janitor only knows file names and mtimes.

### Steps

- [x] **2.1** `CallStore.protectedAudioDirectories()` — the folders whose audio is still
  needed: `status IN ('recording', 'normalizing', 'transcribing', 'failed')`.
  - *Check (RED→GREEN):* test in `CallStoreProtectedAudioTests.swift` — a `ready`, a
    `failed` and a `transcribing` call in one temp database; only the last two folders come back.
- [x] **2.2** `sweep(rules:protecting:now:)` and `expiredBytes(rules:protecting:now:)` skip
  any file inside a protected folder. `expiredBytes` feeds the settings screen, so it has to
  use the same rule or the number lies.
  - *Check (RED→GREEN):* test in `StorageJanitorTests.swift` — two call folders, both with
    expired raw audio, one protected; the protected `me.raw.wav` survives, the other goes,
    and `freed` counts only the deleted one.
- [x] **2.3** `AppController.sweepExpiredAudio()` and `refreshStorageUsage()` pass the set
  from 2.1. A store read that throws must not silently sweep everything — on error, protect
  everything (skip the sweep) and log it.
  - *Check:* `swift test` green; launch the app with retention `Сразу`, kill it mid
    transcription, relaunch, confirm `Повторить` still finds the audio.

---

## 3. One bad stdin line kills the whole Python worker (finding #5)

`python/asr_worker.py`

- `run_jsonl` only catches `JSONDecodeError`. Valid-but-not-a-dict JSON (`[1,2]`, `null`, `42`)
  reaches `handle_job`, where `job.get` raises `AttributeError` and the process dies — every
  future job with it, not just this one.
- `worker.load_model()` sits outside any `try`, before the stdin loop. A bad model id, a
  broken HF cache or a full disk means no `ready` and no `job_failed` — the Swift side only
  sees a closed pipe.

### Steps

- [x] **3.1** In `run_jsonl`, reject a non-dict payload with `job_failed` and keep looping.
  - *Check (RED→GREEN):* test — feed `[1,2]`, `null`, `42` plus one valid `ping` through
    `run_jsonl` with a fake worker; three `job_failed` events, then `pong`, exit code 0.
- [x] **3.2** Wrap `load_model()` so a failure emits `job_failed` with `id: None` and returns
  a non-zero code. `ASRClient.handleLine` already turns an id-less `job_failed` into a startup
  failure, so the app gets a real message instead of a dead pipe.
  - *Check (RED→GREEN):* test — a fake worker whose `load_model` raises produces one
    `job_failed` carrying the message, and no `ready`.

---

## Done when

- [x] `swift test` green: 77 tests (71 + 6 new).
- [x] `pytest python/tests` green: 7 tests (5 + 2 new).
- [x] `./scripts/build_podushka_app.sh` builds and signs.
- [ ] By hand: one real call end to end with retention `Сразу`, then the crash-and-retry walk
  from step 2.3.
