# Check speed (BESEDA-133)

Measured 2026-09-27 on native-ui `af34e12`, M2 Max, `nice -n 19`, memory 63–65 % free throughout.
Nothing in the project was changed.

## 1. Measurements

| What | Wall time |
|---|---|
| Clean `swift build --build-tests --jobs 2` (deps from cache) | **75.7 s** (432 compile steps, `.build` 1.3 GB, `build.db` 2.2 MB) |
| Same, `--disable-index-store` | 68.3 s (index store is 46 MB; not a bloat source) |
| Incremental, `touch` only (Transcription/Diarizer.swift, App/Views/CallDetailView.swift) | 5.2 s / 4.8 s |
| Incremental, comment edit | 2.4 s / 2.7 s |
| Incremental, new top-level func (module interface changes, all tests recompile) | **19.8 s / 19.8 s** |
| `swift test --jobs 2` after build, parallel (default) | **27.6 s** (test run 21.6 s) |
| `swift test --jobs 2 --no-parallel` | 38.7 s (test run 38.0 s) |
| parallel, `--skip noReadGrowsWithTheLengthOfTheCall` | test run **10.7 s** |
| `.build` cloned (`cp -c`) into another folder | fails: ModuleCache has the absolute path baked in; without ModuleCache it is a full 61 s rebuild |
| 3× `swift test list` | `build.db` 2.2 → 2.3 MB, no bloat |

Parallel is safe: 267 tests, 260 run, 7 skipped (env-gated), green both ways. All 48 test files are
swift-testing free functions, so "suite" below = file.

### Slowest tests (serial, seconds)

| s | test | file |
|---|---|---|
| 20.62 | noReadGrowsWithTheLengthOfTheCall | LongCallMemoryTests — synthesises 5 and 20 min of audio |
| 5.95 | liveLoopLogsOnceAndStopsWhenTheSpeechModelIsMissing | LiveTranscriptionTests — waits on the live loop |
| 2.64 | liveLoopTranscribesChunksOfTheGrowingFilesUntilCancelled | LiveTranscriptionTests |
| 0.88 | theOldestOfMoreThanAPageOfCallsIsFoundBySearchAndByPaging | CallArchivePagingTests |
| 0.73 | piecesReadWindowByWindowFromAFileMatchTheWholeArraySplit | LongCallMemoryTests |
| 0.58 | aRecordingKilledMidCallIsReadableAndFailedAfterRelaunch | AppControllerLaunchTests |
| 0.57 | piecesCoverTheOriginalWithoutGapsOrOverlap | UtteranceSplitterTests |
| 0.49 | everyPieceStaysWithinTheLimit | UtteranceSplitterTests |
| 0.46 | aPendingJobResumedAtLaunchWaitsForTheKeychainKey | AppControllerLaunchTests |
| 0.39 | aPendingProcessingJobResumesOnceAfterRelaunch | AppControllerLaunchTests |
| 0.32 | theCutLandsInTheSilenceNotOnTheHardBoundary | UtteranceSplitterTests |
| 0.31 | twoCallsFinishingBackToBackAreBothProcessed | AppControllerLaunchTests |
| 0.23 | aDiskThatRefusesWritesStopsTheRecordingVisiblyAndKeepsWhatWasWritten | RecorderCallbackTests |
| 0.23 | aWriterThatCannotKeepUpStopsTheRecordingVisibly | RecorderCallbackTests |
| 0.22 | progressFractionsReachTheStage | RuntimeInstallerTests |

In the parallel run the 3–4 s tests (Keychain, webhook, installer, AppController) are the same tests
waiting for CPU behind the 20 s one; the wall time is set by `noReadGrows…` alone.

### Slowest suites (serial sum, seconds / tests)

LongCallMemoryTests 21.34/2 · LiveTranscriptionTests 8.77/12 · AppControllerLaunchTests 2.60/12 ·
UtteranceSplitterTests 1.40/4 · CallArchivePagingTests 0.88/1 · WebhookServiceTests 0.67/12 ·
BundledSummaryInstallerTests 0.53/7 · RecorderCallbackTests 0.40/3 · AppSettingsTests 0.35/16 ·
RuntimeInstallerTests 0.33/10 · EchoGateTests 0.18/3 · CallStoreSafetyTests 0.13/9 ·
CallStoreTranscriptTests 0.12/4 · CallStoreWebhookTests 0.11/5 · StoragePrivacyTests 0.08/3.

### What the tests touch

- Real `AppController`: AppControllerLaunchTests only.
- Launch processes (`Process()`): AppControllerLaunchTests, BundledSummaryInstallerTests,
  CallTypeProcessingTests, LiveLoadHarness (env-gated).
- Sleep: AppControllerLaunchTests, BundledSummaryInstallerTests, LiveLoadHarness, RecorderCallbackTests,
  RuntimeInstallerTests, WebhookServiceTests.
- Download: none for real — installer/model tests use stubbed `example.invalid` URLs.
- Env-gated, skipped by default: the 4 h `peakMemoryOnASyntheticLongCall` (`BESEDA_LONG_CALL_MEMORY`),
  `liveModeLoadOfATenMinuteCall`, `callbackTimeUnderCPUAndDiskLoad`, recorder child-process tests,
  the live classifier and the real-speech model test.

## 2. Time agents lost, last ~27 h (26.09 07:00 → 27.09 10:30)

Source: `/Users/mikhail/w/learning/beseda/.factory/*.log`, `sample` files, git times. Around 45 tasks landed.
Minutes are estimates where a log is empty (a run killed while stalled has no output).

| Cause | Evidence | ≈ minutes lost |
|---|---|---|
| build.db stall before any output | 9 empty test/build logs (30, 55, 63 ×3, 83 ×2, 118-memory-asr, 123); BESEDA-106 `sample` spends its time in llbuild `KeyID` lookups. Root cause: the package root used to hold `.factory/` and `untracked/` (53 k files) and SwiftPM recorded all of it. Fixed by BESEDA-122 at 09:39 (sources moved to `Sources/`); every `build.db` since is ~2 MB. | 120–180 (10–20 per stall) |
| Clean build on every check | every test log compiles ~398 files: 41–90 s build, mean ≈ 70 s; each task runs the check 1–3 times in a fresh worktree or after deleting `.build` | 45 tasks × ~1.5 runs × 70 s ≈ 80 |
| Waiting on another SwiftPM in the main checkout's `.build` | BESEDA-123 at 09:50 "Another instance of SwiftPM … waiting", BESEDA-83 20 min | 20–40 |
| Rebuild after "input file modified during the build" (edits during a build in the shared checkout) | BESEDA-123 scratch log | ~3 |
| The 20 s `noReadGrows…` test in every run | ≈ 70 runs × 11 s extra | ≈ 13 |
| Isolated app copies / release builds for screenshots | BESEDA-76 release build 105 s, BESEDA-83 scratch build, Beseda-50…f copies | ~15 |
| Memory tests | BESEDA-106 echo/asr 45 + 20 s builds + 15/12 s runs; BESEDA-118 86 s build + 101 s run; the 4 h variant is env-gated and never ran in the default check | ~6 |

The bloat, the largest loss, is already gone. What is left per task is the clean build (~70 s) plus
~22 s of tests plus lock waits whenever agents share the main checkout.

## 3. Proposal, ranked by time saved

1. **Run the check only in the task's own worktree, never in the main checkout.** Saves the 20–40 min/day
   of SwiftPM lock waits and the "modified during the build" reruns. Cost: one line in the worker
   prompt/AGENTS.md. Risk: none.
2. **Reuse worktrees instead of creating a fresh one per task** (a pool of N worktrees reset to the new
   branch): the check becomes an incremental ~20 s build instead of ~70 s clean. Saves ~50 s per run,
   ~60 min/day. Cost: board change. Risk: stale `.build` after a Package.swift change — run clean in that case.
   A shared cached `.build` is **not** safe/cheap: a cloned `.build` fails on the absolute ModuleCache path
   and, without ModuleCache, rebuilds everything (measured).
3. **Fast default check**: `swift test --jobs 2 --skip noReadGrowsWithTheLengthOfTheCall` → test run
   10.7 s instead of 21.6 s; with item 2, the whole check ≈ 35 s. Gate that test behind an env var like
   the other heavy ones (or shrink it to 1 vs 4 min of audio), run it in the full check. Saves ~11 s/run,
   ~13 min/day. Cost: a 1-line trait. Risk: a long-call read regression is caught nightly, not per task.
4. **Full check** (`swift test --jobs 2`, plus the env-gated memory tests) nightly, before a release, and
   when `Package.swift` or `Storage` migrations change. Saves nothing more once 1–3 are in; it keeps the
   coverage 3 removes.
5. **build.db bloat**: done by BESEDA-122. Keep `Sources/` + `Tests/` paths and keep large scratch
   outside the package root; `swift test list` and the index store are not causes (measured: +0.1 MB,
   46 MB). `--disable-index-store` saves ~7 s on a clean build only. Optional; low value.
6. **Screenshots / app copies**: build the app copy from the worktree's existing `.build` (`swift build
   --product Beseda` is incremental there) instead of a separate scratch path. Saves ~1–2 min per UI task.
   Cost: a line in the kit's run docs. Risk: none.

Split test targets / tags are not worth it: without the one 20 s test, the whole suite is 10.7 s.
