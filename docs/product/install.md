---
type: Guide
---
# Installing Beseda on another Mac

What you need: a Mac with Apple Silicon (M1 or newer), macOS 14.2 or newer, free
disk as below and an internet connection for the first launch.

| Setup | What goes on disk | Free disk before installing |
|---|---|---|
| Transcription only | app 32 MB, speech model 485 MB (Parakeet v3) or 274 MB (GigaAM v3) | 1 GB |
| With the built-in summary | the above, plus Gemma 4 E4B 4.59 GB and its llama.cpp engine ~25 MB | 6 GB |

A model downloads beside its final place as a `.partial` file and is moved in, so the
download needs its own size free and no more; the engine archive is unpacked in a
scratch folder that is deleted afterwards (well under 100 MB). The minimums leave a few
hundred MB for this and for the first calls; recordings need their own space on top
(the raw WAVs stay until the retention rule under Настройки → Хранение removes them).

An hour of a call takes, from the formats in `Audio/`:
- raw audio: two WAVs of 32-bit float samples at the device rate and channel count
  (`PCMFloatRecorder`). At 48 kHz that is ~0.7 GB/h for a mono microphone and ~1.4 GB/h
  for the stereo system-audio tap, so ~2 GB per recorded hour;
- normalized audio: 16 kHz mono 16-bit (`AudioNormalizer`), ~115 MB/h per channel,
  ~230 MB for a two-channel call;
- transcripts and summaries: kilobytes.

The retention rules under Хранение («Исходное аудио», «Подготовленное аудио») delete the
audio and free this space; «Очистить сейчас» applies them at once.
The app does not check free space before a download: a full disk shows as a failed
download.

1. Copy `Beseda-<version>.zip` to the Mac (AirDrop, a USB stick, a chat) and
   double-click it. Move the unpacked `Beseda.app` into `/Applications`.
2. Open the app once. macOS says it cannot verify the developer: the app is signed
   but not notarised. Close that dialog, open System Settings → Privacy & Security,
   scroll to the bottom and press «Open Anyway» next to Beseda, then confirm.
   This happens only on the first launch.
3. Beseda lives in the menu bar (the pillow icon). Its first window is the
   onboarding:
   - **Микрофон** and **Системный звук**: allow both when macOS asks.
   - **Речевая модель**: pick one and press «Скачать». Parakeet v3 (485 MB)
     understands 25 languages; GigaAM v3 from Sber (274 MB) is Russian only but
     lighter and writes punctuation. The file goes into
     `~/Library/Application Support/Beseda/runtime/models`. The step can be
     skipped: the download keeps running and the menu bar shows its progress.
     The model can be changed later under Настройки → Обработка.
   - **Пробная запись**: say a few words with some music playing to see both
     channels move.
4. Record a call: «Начать запись» in the menu bar, or let the automatic detection start
   with Zoom, Meet and the other apps listed under Настройки → Запись.

Everything the app creates lives in `~/Library/Application Support/Beseda`. To
uninstall, drag the app to the Trash and delete that folder.

Summaries are written by one of three providers, picked in Настройки → Обработка →
Итоги: the built-in Gemma 4 E4B, which the app downloads once (4.6 GB) and runs on
this Mac, taking about 5 GB of memory while it works; OpenRouter with your own key; or a model loaded in LM Studio. Recording and
transcription work whatever you pick.

## Updating

The app updates itself: it checks
https://github.com/arhangel66/beseda hourly and installs a new version as soon as
no call is being recorded. Настройки → Основные → Обновления forces a check. Calls,
the index and the downloaded engine stay in Application Support.

A Podushka copy is replaced by hand once: install `Beseda.app`, open it, then delete
`Podushka.app`. Permissions for the microphone and system audio are asked again
because macOS sees a new app; calls, settings and the model come along.

## Publishing a version

Publishing is described under [Architecture](../architecture/index.md). `scripts/package_app.sh` still builds a dev zip without the
updater for trying a build on another Mac.
