# Installing Beseda on another Mac

What you need: a Mac with Apple Silicon (M1 or newer), macOS 14.2 or newer, about
3 GB of free disk and an internet connection for the first launch.

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
     understands 25 languages; GigaAM v3 from Sber (261 MB) is Russian only but
     lighter and writes punctuation. The file goes into
     `~/Library/Application Support/Beseda/runtime/models`. The step can be
     skipped: the download keeps running and the menu bar shows its progress.
     The model can be changed later under Настройки → Хранение.
   - **Пробная запись**: say a few words with some music playing to see both
     channels move.
4. Record a call: «Записать» in the menu bar, or let the automatic detection start
   with Zoom, Meet and the other apps listed under Настройки → Запись.

Everything the app creates lives in `~/Library/Application Support/Beseda`. To
uninstall, drag the app to the Trash and delete that folder.

Summaries are written by one of three providers, picked in Настройки → Обработка →
Итоги: the built-in Gemma 4 E4B, which the app downloads once (4,6 GB) and runs on
this Mac; OpenRouter with your own key; or a model loaded in LM Studio. Recording and
transcription work whatever you pick.

## Updating

The app updates itself: it checks
https://github.com/arhangel66/beseda hourly and installs a new version as soon as
no call is being recorded. «Обновления» in the menu bar popover forces a check. Calls,
the index and the downloaded engine stay in Application Support.

A Podushka copy is replaced by hand once: install `Beseda.app`, open it, then delete
`Podushka.app`. Permissions for the microphone and system audio are asked again
because macOS sees a new app; calls, settings and the model come along.

## Publishing a version

See `release.md`. `scripts/package_app.sh` still builds a dev zip without the
updater for trying a build on another Mac.
