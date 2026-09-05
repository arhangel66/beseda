# Beseda

Beseda records your work calls on a Mac, transcribes them locally and keeps a
searchable archive. Nothing leaves the Mac unless you switch an integration on.

## Install

Requirements: Apple Silicon, macOS 14.2 or newer, about 3 GB of free disk and an
internet connection for the first launch (the speech model is downloaded then).

1. Download `Beseda-<version>.zip` from the [latest release](https://github.com/arhangel66/beseda/releases/latest)
   and unpack it. Move `Beseda.app` into `/Applications`.
2. Open the app once. macOS says it cannot verify the developer: the app is signed
   but not notarised. Close that dialog, open System Settings → Privacy & Security,
   scroll down and press «Open Anyway» next to Beseda. Only on the first launch.
3. Beseda lives in the menu bar. Follow the onboarding: allow the microphone and
   system audio, pick a speech model, make a test recording.

Installed copies update themselves through Sparkle. See `docs/install.md` for
details and `docs/release.md` for publishing.

## Building from source

```bash
./scripts/build_app.sh          # debug build into ~/Applications/Beseda.app
swift test
```

The app lives in the menu bar and opens one window, `Разговоры`. The menu bar
popover has four states — ready, recording (live level meters, pause, stop),
building the transcript, and done. `Записать` starts a call recording; if both
microphone and system audio stay quiet for 60 seconds the app stops it on its
own. It records microphone and system audio into separate raw WAV files,
normalizes both to 16 kHz mono with AVAudioConverter, transcribes them in-process
with transcribe.cpp, and writes files under
`~/Library/Application Support/Beseda/calls/`.

Each dual test call folder contains:

- `me.raw.wav` and `them.raw.wav`
- `me.asr.wav` and `them.asr.wav`
- `me.asr.json` and `them.asr.json`
- `session.json`
- `transcript.md`

The app also maintains a local SQLite index at
`~/Library/Application Support/Beseda/calls.sqlite` with call
status, ASR job metadata, and timestamped transcript segments. The window groups
calls by day, searches inside transcripts, plays a call back from its two WAV
files with a waveform scrubber, and shows the per-call ASR speed and the model
that produced it under `Инфо`.

Settings has two sections. `Запись` covers automatic recording per call app,
the silence stop, the ready notification and launch at login. `Хранение` sets
how long raw and normalized audio survive (`Сразу / 30 дней / 90 дней / Всегда`);
a sweep runs at launch and once a day, and transcripts are never swept.

`Интеграции` holds the calendar and the webhook. With the webhook on, every
finished transcript is POSTed as JSON to the configured address with the secret
in the `Authorization` and `X-Podushka-Secret` headers. The body carries the
Krisp-compatible keys kushetka's `/api/webhooks/krisp` expects (`event`,
`meeting.started_at`, `transcript.text`) next to Beseda's own `call`,
`participants`, `dialogue` and `summary`. Every attempt is a row in
`webhook_deliveries`: network errors and 5xx are retried after 1, 5 and 30
minutes, 4xx stops, and `Отправить тест` sends a probe the server skips. The
journal lives in Settings and under `Инфо` of each call. See `docs/webhook-plan.md`.

On first launch a four-step onboarding checks the microphone permission and the
system audio tap, downloads a speech model, then records ten seconds to prove
both channels are audible without writing anything to disk. Models are picked
from a card list, in onboarding and later under Настройки → Хранение:

| model | languages | size |
| --- | --- | ---: |
| Parakeet v3 (default) | 25 | 485 MB |
| GigaAM v3 (Sber) | Russian | 261 MB |

The file lands in `~/Library/Application Support/Beseda/runtime/models` and is
checked against a pinned sha256 before it is used. Speech recognition itself is
[transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) linked into
the app, so nothing else is installed at runtime. See
`docs/speech-model-choice-plan.md`.

## Giving a dev build to someone else

`./scripts/package_app.sh` builds and zips `dist/Beseda-<VERSION>.zip` without the
updater; `./scripts/release.sh` publishes a real release.

The UI follows the system appearance in both light and dark.
