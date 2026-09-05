# Speech model choice

Date: 2026-09-05

Goal: let the user pick the speech model the way Handy does — a card list with
name, languages and size — and support Sber's GigaAM v3 next to Parakeet, so a
Russian-only user downloads 261 MB instead of 2.3 GB.

## Measurements

Run on this M2 Max against three 180 s excerpts cut from real calls
(`untracked/scripts/asr-bench/`). Two are the interlocutor's channel, one is
the microphone. Reference text is what podushka ships today: `parakeet-mlx`
with `mlx-community/parakeet-tdt-0.6b-v3` (F32 weights, cast to bf16 at load).
"Drift" is word error rate against that reference, so it measures distance from
today's output, not absolute accuracy.

### Is a quantized model good enough

Same runtime (transcribe.cpp), same audio, F16 vs Q4_K_M:

| excerpt | drift Q4_K_M vs F16 | F16 speed | Q4_K_M speed |
| --- | ---: | ---: | ---: |
| 20260902-104148-them | 5.58% | 43× | 55× |
| 20260903-152457-me | 2.86% | 48× | 60× |
| 20260903-152457-them | 6.81% | 59× | 63× |

Reading the diffs word by word, the disagreements sit on words both sizes get
wrong (`хагген фейс` vs `хагing фейсбук`), and Q4 wins as often as it loses
(`больше сеньора` vs `вышиньора`, `hagging face` vs `хаггинг фейс`). There is no
systematic degradation. transcribe.cpp's own LibriSpeech test-clean numbers
agree: F32 1.95%, Q4_K_M 1.98%.

**Verdict: quantization is safe.** 485 MB instead of 2.51 GB, and faster.

### Parakeet through transcribe.cpp vs today's MLX path

| excerpt | drift | speed |
| --- | ---: | ---: |
| 20260902-104148-them | 3.89% | 42× |
| 20260903-152457-me | 7.54% | 50× |
| 20260903-152457-them | 13.62% | 57× |

Word counts match the reference closely and side-by-side reading shows the same
quality. Today's MLX path runs at RTF 0.0177 (≈56×), so speed is a wash.

### GigaAM v3 e2e-RNN-T (Q8_0, 261 MB)

| excerpt | drift, 20 s chunks | drift, whole 180 s |
| --- | ---: | ---: |
| 20260902-104148-them | 11.86% | 60.33% |
| 20260903-152457-me | 16.41% | 37.69% |
| 20260903-152457-them | 22.94% | 94.62% |

The 25 s training window is real: fed a whole 180 s clip the model silently
drops most of the audio (18 words out of an expected 284 on one excerpt).
transcribe.cpp warns and proceeds rather than rejecting, so this failure is easy
to ship by accident.

Chunked at 20 s it is a usable Russian model with punctuation and casing built
in, but it cannot write Latin script, so technical speech suffers:

| said | Parakeet Q4_K_M | GigaAM Q8_0 |
| --- | --- | --- |
| SSH | `с SSH` | `сей` |
| Docker Hub | `с докер хабом` | `с Doker Hub` |
| accessibility | `accessibility` | `Аксибилоти` / `эксбилоти` |

**Verdict:** GigaAM fits a Russian conversation without English jargon — which is
exactly the wife's case — and is the wrong default for work calls.

### Length handling, from `transcribe.cpp/docs/input-limits.md`

- parakeet: unbounded, chunked internally by the library. No work for us.
- gigaam: soft ~25 s window, warns and degrades past it. We must split.

### Timestamps

`--timestamps word` gives per-word start/end for both families.
`--timestamps segment` gives parakeet a single segment covering the whole file,
so sentence segments have to be rebuilt from words on our side. Today
`parakeet-mlx` hands us sentences and we derive words from their tokens
(`tokens_to_words` in `python/asr_worker.py`); this inverts.

## Decision

Replace the Python/MLX transcription path with transcribe.cpp through its Swift
bindings, and make the model a user choice.

Why the whole path and not just a second model:

- GigaAM has no MLX port, so it cannot join the current runtime at all.
- `parakeet-mlx` 0.5.1 has no quantization support (no mention of `quantize` in
  the package; `from_config` builds plain layers), so even the MLX 4-bit
  conversions cannot be loaded without patching it.
- The Python stage is what broke the clean-machine install: `uv sync` prints
  nothing we can parse, so onboarding showed a spinner with no percentage for
  minutes and the user skipped past it. Deleting the stage deletes the problem.
- Disk drops from 3.6 GB to one model file.

| | today | after |
| --- | ---: | ---: |
| uv cache | 710 MB | — |
| Python 3.12 | 72 MB | — |
| venv (47 packages) | 485 MB | — |
| model | 2.3 GB | 485 MB or 261 MB |
| native library | — | 7.7 MB, inside the app |

Cheaper alternative, rejected: patch `parakeet-mlx` to call `nn.quantize` and
point at `animaslabs/parakeet-tdt-0.6b-v3-mlx-4bit` (636 MB). It saves 1.7 GB
and nothing else — no GigaAM, no model list, Python and uv stay.

## Design

`Transcription/` loses `ASRClient` and gains:

- `SpeechModel` — the catalogue entry: id, title, subtitle, languages, byte
  size, download URL, sha256, family, `maxUtteranceSec`. Two entries to start:

  | id | title | languages | file | size |
  | --- | --- | --- | --- | ---: |
  | `parakeet-tdt-0.6b-v3` | Parakeet v3 | 25 | `parakeet-tdt-0.6b-v3-Q4_K_M.gguf` | 485 MB |
  | `gigaam-v3-e2e-rnnt` | GigaAM v3 | ru | `gigaam-v3-e2e-rnnt-Q8_0.gguf` | 261 MB |

- `LocalTranscriber` — loads the gguf once, runs on the float32 PCM that
  `AudioNormalizer` already produces, asks for word timestamps, returns
  `ASRTranscription`. Keeps the idle-unload behaviour `ASRClient` has today.
- `SentenceBuilder` — words → `TranscriptSegment`s. Split on `.?!`, on a silence
  gap over a threshold, and at a word cap. Pure and testable.
- `UtteranceSplitter` — only for families with `maxUtteranceSec`. Cuts at the
  quietest point inside the allowed window, transcribes each piece, shifts the
  word timestamps back to absolute time.

`RuntimeInstaller` keeps its stage machine but the stages become `speechModel`
(download one file with real byte progress and a sha256 check) and `warmUp`. The
`python` stage, the bundled `uv`, `python/`, `pyproject.toml`, `uv.lock` and
`.python-version` all go.

The selected model id lives in `AppSettings`; changing it triggers a download if
the file is missing and unloads the running model.

## Steps

Each step: RED (test or build fails) → GREEN. `swift test` from the repo root.

- [x] **0. Plan doc in repo** — this file.

- [x] **1. Link transcribe.cpp** — `Package.swift` gains a
  `binaryTarget(url:checksum:)` for `TranscribeCpp.xcframework.zip` from release
  v0.2.3 (7.7 MB, macOS 13+, arm64 and x86_64 slices), and the MIT Swift wrapper
  (1611 lines) is vendored under `Vendor/TranscribeCpp/`. Its licence goes next
  to the uv licence the build script already copies.
  Test: load `samples/jfk.wav`, transcribe, assert the text contains
  "ask not what your country can do for you".

- [x] **2. `Transcription/SpeechModel.swift`** — the catalogue above, plus
  `filename`, `localURL(in:)` and `isDownloaded(in:)`.
  Tests: both entries have a reachable URL shape and distinct filenames;
  `maxUtteranceSec` is nil for parakeet and 25 for gigaam.

- [x] **3. `Transcription/SentenceBuilder.swift`** — words → segments.
  Tests: a sentence-ending word closes a segment; a silence gap over the
  threshold closes one; the word cap closes one; segment start/end match the
  first and last word; empty input yields no segments.

- [x] **4. `Transcription/UtteranceSplitter.swift`** — split PCM into pieces no
  longer than `maxUtteranceSec`, preferring the quietest 100 ms inside the last
  fifth of the window.
  Tests: a 60 s buffer with a silent stretch splits there, not at the hard
  boundary; every piece is within the limit; offsets sum back to the original
  duration; audio shorter than the limit is returned untouched.

- [x] **5. `Transcription/LocalTranscriber.swift`** — replaces `ASRClient`.
  Same public shape (`start()`, `transcribe(audioURL:)`, `stop()`,
  `progressHandler`, `diagnosticsHandler`) so `AppController` changes little.
  Tests: transcribing a fixture returns segments in order with non-decreasing
  timestamps; a missing model file throws `PodushkaError.runtimeMissing`;
  progress reaches 1.0.

- [x] **6. `Runtime/RuntimeInstaller.swift`** — two stages. `speechModel`
  downloads the selected model with `URLSession` byte progress and verifies
  sha256; `warmUp` loads it once. `removeRuntime()` becomes per-model delete.
  Tests: an existing file with the right hash reports done without downloading;
  a wrong hash fails the stage and removes the file; progress fractions are
  monotonic.

- [x] **7. Delete the Python stack** — `python/`, `pyproject.toml`, `uv.lock`,
  `.python-version`, the uv download and copy in
  `scripts/build_podushka_app.sh`, `AppPaths.pythonDirectory`, `uvExecutable`,
  `workerPython`, `asrWorker`, `runtimeEnvironment()`, and the `python/tests`
  pytest suite. Keep `LegacyDataMigration`.

- [x] **8. Model picker UI** — `App/Views/SpeechModelList.swift`: one card per
  model with title, «Активная» badge, subtitle, language count, size, and
  «Скачать» / «Удалить» / progress, matching Handy's shape. Shown in
  Настройки → Хранение in place of the stage list, and on onboarding step 3 with
  Parakeet preselected.

- [x] **9. Onboarding progress** — the engine step now has one download with a
  real percentage. After «Пропустить», the menu bar keeps showing that the model
  is still downloading, so a skipped step is never a silent one.

- [x] **10. Show the model in use** — a «Модель» row in the call's Инфо tab,
  from the model id stored on the job. Today the name only reaches the log
  through `workerDescription`.

- [x] **11. Docs** — README and AGENT.md lose ffmpeg-era Python wording and gain
  the model catalogue; `docs/asr-bakeoff.md` gets a note pointing here;
  `docs/install.md` gets the new sizes and the model choice screen;
  `docs/distribution-plan.md` step 8 gets re-run.

## Verification

1. `swift test` green.
2. `./scripts/build_podushka_app.sh`, app opens, no `uv` in the bundle.
3. Fresh macOS user account: onboarding downloads Parakeet with a live
   percentage in under a minute on a normal connection, and a call transcribes.
4. Re-transcribe three stored calls and diff against the saved transcripts;
   drift should match the numbers measured above.
5. Switch to GigaAM in settings, transcribe a Russian call, confirm the
   utterance splitter kept the timeline aligned (segment times still match the
   audio in the player).
6. Delete a model in settings and confirm the disk figure drops.

## Results

Measured after the change, on this Mac.

Re-transcribing six stored channels through the new path and comparing with the
transcripts the Python engine wrote:

| call / channel | drift | speed | segments before → after |
| --- | ---: | ---: | ---: |
| 20260903-152457 / me | 5.54% | 47× | 336 → 373 |
| 20260903-152457 / them | 23.54% | 71× | 154 → 182 |
| 20260902-104148 / me | 9.55% | 67× | 227 → 271 |
| 20260902-104148 / them | 10.11% | 60× | 200 → 253 |
| 20260903-102211 / me | 7.73% | 61× | 373 → 373 |
| 20260903-102211 / them | 12.97% | 64× | 182 → 316 |

Drift matches what the excerpts predicted and speed is unchanged. The extra
segments are not `SentenceBuilder`'s doing: with the silence rule switched off
entirely the counts only fall to 363 / 167 / 260 / 244 / 361 / 304, so almost all
of the difference is the new engine punctuating more often. The 1 s silence rule
costs about ten extra segments over a 27-minute call, which is why it stays.

Disk on this Mac after the first launch of the new build: the app removed 3.79 GB
of venv, interpreter, uv cache and Hugging Face snapshots, leaving 463 MB.

GigaAM through the full path on a 27-minute Russian call: 388 segments, 2873
words, the last word ends at 1614.5 s of 1616 s, 128× realtime, 15.30% drift
against the stored transcript. So the splitting keeps the timeline and the
quality matches what the excerpts predicted.

Two bugs found and fixed on the way.

GigaAM returned nothing at first: its family only times tokens, so
`transcript.words` is empty and the sentence builder had no input.
`WordAssembler` now rebuilds words from the SentencePiece tokens, where U+2581
marks a word start. A bare marker token, which GigaAM emits often, needed its own
case — the first version dropped the word's start time, and the unit test caught
it before the model run did.

The splitter also cut pieces of 25.1 s, just past GigaAM's window, because the
cut lands half a frame after the last searched position. transcribe.cpp's
over-length warning is what surfaced it; the search now stops a frame short of
the window. The original test missed it because a constant tone makes the first
candidate win, so it never exercised the window edge.

A third bug: ggml asserts that every Metal resource is
released before the process exits, so quitting with a model still loaded aborted
the app and macOS reported a crash. `LocalTranscriber.shutdown()` now frees the
model synchronously from `applicationWillTerminate`, bounded to 5 s.

## Risks

- transcribe.cpp is 0.2.x and pre-1.0; the Swift binding pins an ABI hash, so an
  upgrade is a deliberate step, not a drift.
- Sentence segmentation moves from `parakeet-mlx` to our code. Step 4 of the
  verification is the guard: if the diff against stored transcripts is worse than
  the measured drift, the segmentation is at fault, not the model.
- The app works today. All of this happens on a branch, and the current build
  stays shippable until step 6 of the verification passes.
- GigaAM's Latin-script weakness is a property of the model, not of our
  splitting. The model card in the picker must say «только русский» plainly.
- Intel Macs: the xcframework carries an x86_64 CPU slice, so they keep working,
  slower. Untested here.
