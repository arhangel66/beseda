# Self-contained Podushka for another Mac

## Context

Today `~/Applications/Podushka.app` is a developer build. It works only next to this
source tree:

- `ProjectPaths.projectRoot` walks up from the compile-time `#filePath`
  (`/Users/mikhail/w/learning/podushka`). On another Mac that path does not exist, the
  root falls back to the working directory and nothing is found.
- The ASR worker is `python/asr_worker.py`, launched through a `uv` found on `PATH`
  (Homebrew). `uv` fetches Python 3.12 and `parakeet-mlx` on first run into the user's
  global uv caches; the model (`mlx-community/parakeet-tdt-0.6b-v3`, 2.3 GB
  `model.safetensors`) lands in `~/.cache/huggingface`.
- Audio normalisation shells out to `ffmpeg` (Homebrew); onboarding installs it with
  `brew install ffmpeg` and refuses to finish without it.
- Calls, the SQLite index and the app log live under `untracked/` in the repo.
- Summaries need LM Studio's `lms` and its local server.
- The bundle is signed with an Apple Development certificate and is not notarised.

Goal: one `Podushka.app` a person with a fresh Mac drops into `/Applications`, opens,
and the app itself downloads everything it needs while the person only ticks options.
No Homebrew, no terminal, no source tree.

Hard requirements that stay: Apple Silicon and macOS 14.2+ (MLX and the system audio
tap), internet on first launch (about 2.7 GB with the speech model, +2.4 GB if the
built-in summary model is chosen), and one "Open Anyway" in System Settings because the
app is not notarised (that needs a paid Developer ID; see follow-ups).

## Design

### Files on the recipient's Mac

```
/Applications/Podushka.app
  Contents/MacOS/Podushka
  Contents/MacOS/uv                         pinned static uv binary, signed with the app
  Contents/Resources/podushka/pyproject.toml   the uv workspace root
  Contents/Resources/podushka/uv.lock          committed; installs are reproducible
  Contents/Resources/podushka/python/asr_worker.py
  Contents/Resources/podushka/python/pyproject.toml
~/Library/Application Support/Podushka/
  calls/                                    was untracked/calls
  calls.sqlite                              was untracked/calls.sqlite
  podushka-app.log                          was untracked/podushka-app.log
  runtime/python/                           UV_PYTHON_INSTALL_DIR
  runtime/venv/                             UV_PROJECT_ENVIRONMENT
  runtime/cache/                            UV_CACHE_DIR
  runtime/models/                           HF_HOME: speech model, optional summary model
```

Everything Podushka creates sits in one folder: uninstalling is deleting the app and
that folder. The bundle is never written to (writing inside a signed bundle breaks the
signature and Gatekeeper).

`ProjectPaths` becomes `AppPaths`: `dataDirectory` is Application Support;
`pythonDirectory` is `Bundle.main.resourceURL/python` when that exists, else the source
tree via `#filePath` (so `swift run` and tests keep working); `uvExecutable` is
`Contents/MacOS/uv` when bundled, else `uv` on `PATH`. The `PODUSHKA_ROOT` override goes
away. One-time migration on launch: when `calls.sqlite` is missing in Application
Support and the legacy `untracked/calls.sqlite` exists next to the sources, move
`calls/`, `calls.sqlite` and the log over and write a log line. That is Mikhail's Mac;
nobody else has the legacy layout.

### Runtime install = a state machine the UI can draw

`Runtime/RuntimeInstaller.swift` (`@MainActor @Observable`) owns four stages, each
persisted as "done" by the artefact it leaves on disk, so a relaunch resumes instead of
restarting:

1. `python` — `uv sync --frozen --no-dev --project <Resources/python>` with the env
   above. Done when `runtime/venv/bin/python` exists and `uv sync --frozen` reports
   nothing to do. Progress is indeterminate (uv prints no stable percentages); the UI
   shows "Скачиваю Python и библиотеки (~300 МБ)".
2. `speechModel` — `python asr_worker.py --prepare --cache-dir runtime/models`: the
   worker downloads `config.json` and `model.safetensors` for `DEFAULT_MODEL` with
   `huggingface_hub`, emitting JSONL `{"type":"download_progress","fraction":…,"bytes":…,"total":…}`
   every 500 ms (total from `HfApi().model_info(files_metadata=True)`, bytes from the
   file on disk), then `{"type":"prepared"}`. Done when both files exist in the cache.
3. `warmUp` — launch the worker once and wait for `ready`; catches a broken install
   (wrong architecture, missing Metal) before the first real call.
4. `summaryModel` (optional, see step 9).

Each stage streams its stderr into the app log. Failure keeps the stage `failed(message)`
with a «Повторить» button; the installer never deletes anything on its own.
`ASRClient.launchWorker` runs `runtime/venv/bin/python asr_worker.py` directly (no
`uv run` resolution on every launch) with `HF_HOME` set, and reports
`RuntimeMissing` when the venv is absent instead of the current "uv not found".

### No more ffmpeg

`AudioNormalizer` rewrites the raw WAV with `AVAudioFile` + `AVAudioConverter`
(16 kHz, mono, Int16, `.max` sample-rate quality). Both inputs are WAV files Podushka
wrote itself, so no container zoo. `FfmpegSupport`, the ffmpeg onboarding step, the
«Установить ffmpeg» banner and `isInstallingFfmpeg` go away.

### Onboarding

Steps become: 1 Микрофон, 2 Системный звук, 3 Распознавание речи, 4 Саммари
(optional), 5 Пробная запись (the existing ten-second test). Step 3 shows the four
stages as rows with a state each, the total download size up front, one «Установить»
button, live progress, and a «Пропустить» link (a call recorded without the runtime
fails with a banner that offers to install, the same shape as today's ffmpeg banner).
Step 4 offers three radio options: «Встроенная модель (~2.4 ГБ)», «LM Studio» (the
current path), «Позже». A first screen for a Mac that cannot run Podushka: Intel or
macOS < 14.2 shows one explanation and quits; `LSMinimumSystemVersion` becomes 14.2.

Settings gets a «Хранение» row group "Движок распознавания": versions, disk usage per
stage, «Переустановить», «Удалить модели».

### Build and packaging

`scripts/build_podushka_app.sh` additionally copies `python/{asr_worker.py,pyproject.toml,uv.lock}`
into `Contents/Resources/python`, downloads the pinned uv release archive for
`aarch64-apple-darwin` from GitHub into `.build/` (sha256 checked against a constant in
the script), places `uv` in `Contents/MacOS`, signs with `--deep` as now. Version comes
from a `VERSION` file into `CFBundleShortVersionString`; `CFBundleVersion` is a build
counter. New `scripts/package_podushka.sh` produces `dist/Podushka-<version>.zip` via
`ditto -c -k --keepParent` (preserves the signature). `docs/install.md` is the
recipient's page: copy to `/Applications`, first open via System Settings → Privacy &
Security → «Open Anyway», then follow the onboarding.

Signing stays Apple Development: the identity is stable, so microphone and system-audio
grants survive updates (ad-hoc signatures change per build and would re-prompt).

## Steps

Each step: RED (test or build fails) → GREEN, `swift test` from the repo root,
`uv run --project python pytest python/tests` for the worker.

- [x] **0. Plan in repo** — this file. Decisions: first release ships with LM Studio only
  (step 9 deferred); signing stays Apple Development, the recipient is one person.

- [x] **1. `App/AppPaths.swift`** replaces `ProjectPaths`: `dataDirectory`, `callsDirectory`,
  `callIndexURL`, `appLogURL` under Application Support; `pythonDirectory` and
  `uvExecutable` bundle-first with source-tree fallback; `runtimeDirectory` and the four
  runtime sub-paths; `workerEnvironment()` with `UV_*` and `HF_HOME`. `AppController`
  gets `migrateLegacyDataIfNeeded()` called before `callStore.prepare()`.
  Tests: paths resolve under a given base; migration moves the three items once and is
  a no-op when the target already has a database.

- [x] **2. `Audio/AudioNormalizer.swift`** on AVFoundation. Test: normalise a 2 s
  48 kHz stereo fixture written with `AVAudioFile` in the test → output is 16 kHz, one
  channel, Int16, ±1 % duration. Delete `FfmpegSupport`, `PermissionsModel.ffmpeg`,
  the ffmpeg branches in `OnboardingWindow`, `CallDetailView.FailureBanner`,
  `AppController` (`installFfmpeg`, `isInstallingFfmpeg`) and the README lines.

- [x] **3. `python/asr_worker.py --prepare`** — download with progress events, plus
  `python/uv.lock` committed and `huggingface_hub` made an explicit dependency. Python
  test: `--prepare` with a monkeypatched `hf_hub_download` emits at least one
  `download_progress` and ends with `prepared`.

- [x] **4. `Runtime/RuntimeInstaller.swift`** — stages, persistence-by-artefact,
  `install()`, `retry(stage:)`, `diskUsage`, `remove(models:)`; process launching goes
  through an injectable `Runner` so tests use a fake. Tests: a fresh directory reports
  every stage pending; a stage whose artefact exists is skipped; a failing runner leaves
  `failed(message)` and the next stage untouched; progress lines from the fake worker
  update `fraction`.

- [x] **5. `Transcription/ASRClient.swift`** — launch through `runtime/venv/bin/python`,
  `RuntimeMissing` error when absent; `AppController` turns that into the call's
  `error` and the banner text «Движок распознавания не установлен». Test on the
  existing ASRClient tests: missing venv → the typed error, no process launched.

- [x] **6. Onboarding** — `OnboardingWindow` steps 3 and 4 with the stage rows, install
  button, progress bar, skip link; the unsupported-Mac screen; `LSMinimumSystemVersion`
  14.2. Settings section «Движок распознавания». Texts in Russian, matching the existing
  tone. (The unsupported-Mac screen turned out unnecessary: the binary is arm64-only and
  `LSMinimumSystemVersion` makes macOS itself refuse older systems with its own dialog.)

- [x] **7. Build script and packaging** — bundle python sources and pinned uv, `VERSION`
  file, `package_podushka.sh`, `docs/install.md`. Verify: `codesign --verify --strict
  --deep`, `spctl -a -t exec -vv` prints the expected "rejected (no notarisation)" line
  and nothing worse.

- [x] **8. Clean-machine test** — done on a fresh account. It worked, but the
  «Python и библиотеки» stage showed a spinner with no percentage for minutes, so the
  step looked stuck and got skipped. That stage no longer exists: the engine is linked
  into the binary and the only download is one model file with real byte progress. See
  `docs/speech-model-choice-plan.md`. Worth one more pass on a fresh account.

- [ ] **9. Built-in summaries (separable)** — deferred, and the plan below is stale:
  it assumed a Python runtime that no longer exists. Whatever replaces LM Studio will
  have to run through a C/Metal runtime too, next to transcribe.cpp, rather than
  `mlx-lm` behind `uv`.

- [x] **10. Docs** — README (install path, data folder, what leaves the Mac), AGENT.md tree
  (`Runtime/`, `docs/install.md`), remove ffmpeg and `untracked/calls` mentions.

## Verification

1. `swift test` and the Python tests green.
2. Build, package, copy the zip to the fresh user account (step 8), open from Finder:
   Gatekeeper prompt → Open Anyway → onboarding → download shows sizes and progress →
   test recording → a real call is transcribed. Application Support holds every file;
   `~/.cache`, `~/.local/share/uv` and Homebrew stay untouched.
3. Quit mid-download, relaunch: the installer resumes at the same stage.
4. Airplane mode during step 3 of onboarding: the stage fails with a readable message
   and «Повторить» works once the network is back.
5. Mikhail's Mac: first launch of the new build moves `untracked/calls*` into
   Application Support, old calls open and play.

## Risks / notes

- No notarisation: every recipient sees "Apple could not verify" once. Fixing that is
  a Developer ID certificate (paid) plus `notarytool`; a follow-up, not this plan.
- The speech model is 2.3 GB and the Python packages about 300 MB; on slow Wi-Fi step 3
  takes a while, which is why sizes are shown before the button.
- `uv` is redistributed under Apache-2.0/MIT; the licence text goes into
  `Contents/Resources/licenses/uv.txt`.
- AVAudioConverter's resampler differs from ffmpeg's; transcripts may change in the
  last decimal of timing. Step 2's test pins format, not waveform equality.
- Updates are manual (a new zip, replace the app); data in Application Support
  survives. Sparkle or a "check for updates" link is a later feature.
- Model downloads go to Hugging Face directly; a corporate proxy or a blocked host
  surfaces as a failed stage, not a hang, because `--prepare` uses a request timeout.
