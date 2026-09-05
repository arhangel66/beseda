# Podushka

Local macOS call recorder and transcriber proof of concept.

## Menu Bar App

```bash
cd /Users/mikhail/w/learning/podushka
./scripts/build_podushka_app.sh
open ~/Applications/Podushka.app
```

The app lives in the menu bar and opens one window, `Разговоры`. The menu bar
popover has four states — ready, recording (live level meters, pause, stop),
building the transcript, and done. `Записать` starts a call recording; if both
microphone and system audio stay quiet for 60 seconds the app stops it on its
own. It records microphone and system audio into separate raw WAV files,
normalizes both to 16 kHz mono with AVAudioConverter, transcribes them in-process
with transcribe.cpp, and writes files under
`~/Library/Application Support/Podushka/calls/`.

Each dual test call folder contains:

- `me.raw.wav` and `them.raw.wav`
- `me.asr.wav` and `them.asr.wav`
- `me.asr.json` and `them.asr.json`
- `session.json`
- `transcript.md`

The app also maintains a local SQLite index at
`~/Library/Application Support/Podushka/calls.sqlite` with call
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
`meeting.started_at`, `transcript.text`) next to podushka's own `call`,
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

The file lands in `~/Library/Application Support/Podushka/runtime/models` and is
checked against a pinned sha256 before it is used. Speech recognition itself is
[transcribe.cpp](https://github.com/handy-computer/transcribe.cpp) linked into
the app, so nothing else is installed at runtime. See
`docs/speech-model-choice-plan.md`.

## Giving the app to someone else

`./scripts/package_podushka.sh` builds and zips `dist/Podushka-<VERSION>.zip`;
see `docs/install.md` for what the recipient does. The app is signed with an
Apple Development certificate and not notarised, so the first launch needs
«Open Anyway» in System Settings.

The UI follows the system appearance in both light and dark.
