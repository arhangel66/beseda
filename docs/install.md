# Installing Podushka on another Mac

What you need: a Mac with Apple Silicon (M1 or newer), macOS 14.2 or newer, about
3 GB of free disk and an internet connection for the first launch.

1. Copy `Podushka-<version>.zip` to the Mac (AirDrop, a USB stick, a chat) and
   double-click it. Move the unpacked `Podushka.app` into `/Applications`.
2. Open the app once. macOS says it cannot verify the developer: the app is signed
   but not notarised. Close that dialog, open System Settings → Privacy & Security,
   scroll to the bottom and press «Open Anyway» next to Podushka, then confirm.
   This happens only on the first launch.
3. Podushka lives in the menu bar (the pillow icon). Its first window is the
   onboarding:
   - **Микрофон** and **Системный звук**: allow both when macOS asks.
   - **Речевая модель**: pick one and press «Скачать». Parakeet v3 (485 MB)
     understands 25 languages; GigaAM v3 from Sber (261 MB) is Russian only but
     lighter and writes punctuation. The file goes into
     `~/Library/Application Support/Podushka/runtime/models`. The step can be
     skipped: the download keeps running and the menu bar shows its progress.
     The model can be changed later under Настройки → Хранение.
   - **Пробная запись**: say a few words with some music playing to see both
     channels move.
4. Record a call: «Записать» in the menu bar, or let the automatic detection start
   with Zoom, Meet and the other apps listed under Настройки → Запись.

Everything the app creates lives in `~/Library/Application Support/Podushka`. To
uninstall, drag the app to the Trash and delete that folder.

Summaries need LM Studio with its local server turned on (Настройки → Саммари);
without it every other feature works.

## Updating

From 0.2.1 the app updates itself: it checks
https://github.com/arhangel66/podushka hourly and installs a new version as soon as
no call is being recorded. «Обновления» in the menu bar popover forces a check. Calls,
the index and the downloaded engine stay in Application Support.

An older copy is replaced by hand once: drop the new `Podushka.app` over the old one.

## Publishing a version

See `release.md`. `scripts/package_podushka.sh` still builds a dev zip without the
updater for trying a build on another Mac.
