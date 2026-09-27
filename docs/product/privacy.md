---
type: Guide
title: Privacy
description: What Beseda stores where, what protects it, what does not, and what leaves the Mac.
---
# Privacy

Beseda records calls that can hold sensitive material (a psychologist's session, a
medical or legal talk). This page says plainly what the app protects and what it leaves
to macOS and to the user.

## What is stored where

All under `~/Library/Application Support/Beseda` ([Storage](../architecture/storage.md)):

- `calls/<call-id>/` — raw and 16 kHz WAVs of both channels, ASR JSON, `transcript.md`.
- `calls.sqlite` — the index: titles, transcript segments, summaries (`summary_text`),
  matched calendar event and attendee emails, and the webhook delivery log with each
  endpoint's **response body** (`webhook_deliveries.response_body`). Plain SQLite, not
  encrypted.
- `calls.sqlite.v<n>.backup` — a copy written before a schema migration.
- `beseda-app.log` — the app log.
- The OpenRouter key and the webhook secret are in the Keychain.

Outside that folder: the **export folder** picked in Settings, one Markdown file per
processed call.

## What protects it

- Owner-only access: at launch the app sets umask 077 and strips group/other bits from
  the data folder (`StorageProtection.apply`), so files are `0600`, folders `0700`.
  Other macOS users on the Mac cannot read them.
- File protection `completeUntilFirstUserAuthentication` where the volume supports it:
  files are unreadable until the first login after a boot.
- Deleting a call removes its folder, its row with segments and webhook log, and its
  export copies; SQLite `secure_delete` keeps the text out of free pages.
- Audio retention (Настройки → Хранение) deletes WAVs after the chosen period; the
  transcript and summary stay.

## What it does not protect against

- **An unlocked Mac.** Anyone at the keyboard of the logged-in user sees every call.
- **Anything running as the same user**: malware, a script, another app with Full Disk
  Access, and an admin, who can read any file.
- **A Mac without FileVault.** Without disk encryption a removed or stolen disk is
  readable; file protection adds little on its own.
- **Backups.** Time Machine copies Application Support, with every call, unless it is
  excluded; an unencrypted backup disk holds them in the clear. Application Support is
  not synced by iCloud Drive, but a full-Mac backup tool may copy it.
- **The export folder.** It lives outside the managed folder: its files keep the
  permissions of wherever it is, retention never touches them, and if it is inside
  iCloud Drive, Dropbox or Documents synced to the cloud, every export goes to that
  cloud. Retention deletes audio only; exports stay until the call is deleted.
- **What a webhook endpoint answers.** Its response body is stored in `calls.sqlite`.

## What leaves the Mac

- **Summaries** with OpenRouter: the whole transcript and the call-type prompt go to
  OpenRouter and the model it routes to. With LM Studio they go to that server (local
  unless it runs on another machine). The built-in Gemma model sends nothing.
- **Call type (Jev)**: with an OpenRouter key and classification not set to local, the
  opening of the transcript and the call type names go to OpenRouter's Decisions API.
- **Live key points**: while live text is on, the accumulated lines go to the selected
  summary provider every few minutes.
- **Webhook**: when set, the transcript, title, time and summary go to its URL (HTTPS
  only, except localhost).
- **Downloads**: models, the llama.cpp engine and updates are fetched from Hugging Face
  and GitHub; no call data is sent.

The line under the provider in Настройки → Обработка says what goes to the cloud now.
«Только локально» there turns off Jev and webhooks and moves summaries and live key
points to the built-in model.

## For sensitive calls

- Turn FileVault on and lock the Mac when away.
- Keep the export folder out of iCloud Drive and other synced folders, or leave export off.
- Pick short audio retention.
- Use the built-in model (or «Только локально»); no OpenRouter key, no webhook.
- Exclude `~/Library/Application Support/Beseda` from Time Machine, or encrypt the backup disk.

Not done: the index and the exports are not encrypted with a key of their own.
