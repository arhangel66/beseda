---
type: Decision Record
title: At-rest encryption
description: Options for protecting calls on disk beyond FileVault, with threat model, migration and key-loss cost for each; recommends the smallest set for a psychologist's Mac — proposed.
status: proposed
tags: [privacy, security, storage, research]
generated:
  by: agent
  at: 2026-09-27T00:00:00Z
---

# At-rest encryption

Critic finding 19: `calls.sqlite`, transcripts, WAVs and exports lie on disk in plain form
([Privacy](../product/privacy.md)). One target audience is psychologists. This record picks the
cheapest design that actually protects something. No code is written here, and nothing here
touches existing data; encrypting badly can lose every recorded call (Mikhail has 123).

## Threat model

What is on disk: `~/Library/Application Support/Beseda` (`calls/<id>/` WAVs, ASR JSON,
`transcript.md`; `calls.sqlite` with segments and summaries; `calls.sqlite.v<n>.backup`;
`beseda-app.log`) and the export folder picked in Settings ([Storage](../architecture/storage.md)).

| Threat | FileVault | 0700/0600 + file protection (already applied) | Needs something else |
|---|---|---|---|
| Stolen or lost Mac, powered off | **covered** (whole volume encrypted) | adds nothing | — |
| Stolen Mac, asleep and locked | covered while locked; keys live in RAM, a cold/DMA attack is theoretical on Apple silicon | — | — |
| Another macOS user account on the same Mac (not admin) | not covered (volume is unlocked for all) | **covered**: other users cannot read `0600` files | — |
| An admin of the same Mac, or `sudo` | not covered | not covered (root reads anything) | only an app key the admin cannot get: Keychain items are per user, but an admin can reset the password and get in; practically out of scope |
| Unlocked Mac, someone at the keyboard | not covered | not covered | nothing at rest helps: the app decrypts for its own user. Only screen lock |
| Malware or a script running as the user | not covered | not covered | at-rest encryption only slows it: it can read the Keychain item via the app or read decrypted data from the app's process. Out of scope |
| Time Machine backup of Application Support | covered only if the backup disk is encrypted (Time Machine offers it; not the default for network disks created long ago) | not covered: the backup keeps plain files | **exclude** the folder, or encrypt the files |
| Third-party full-Mac backup or cloud backup (Backblaze, Arq, CCC) | not covered: they copy plain files to their own storage | not covered | exclude, or encrypt the files |
| iCloud Drive | Application Support is **not** synced by iCloud Drive | — | the **export folder** is, if it is inside iCloud Drive / Documents / Desktop sync |
| A copied folder (user drags it to a USB stick, a Migration Assistant copy, a support zip) | not covered | permissions are lost on FAT/exFAT sticks | encrypt the files |
| Mac sent for repair / sold without erase | covered if FileVault is on and the password is not given | — | — |

Plain summary: with FileVault on, the realistic leaks for a psychologist are **backups and
copies** (Time Machine to a plain disk, a cloud backup tool, the export folder in iCloud) and an
**unlocked Mac**. The first is fixed by exclusion or file encryption; the second by nothing the
app can do at rest. Without FileVault, a stolen Mac is the biggest leak of all, and every app-level
option below is weaker than simply turning FileVault on.

`completeUntilFirstUserAuthentication` adds little on macOS: after the first login it is the same
as no protection, and with FileVault off it does not encrypt anything.

## Options

Effort in working days for one agent; "ladder" is the rung of the ponytail ladder it stands on.

### (a) FileVault plus a warning when it is off

- **What:** at launch (and in Настройки → Хранение) read `fdesetup status` or
  `/usr/bin/fdesetup isactive` — no root needed for `status` — and show one line «FileVault
  выключен: при краже Mac записи читаются» with a link to System Settings → Privacy & Security.
- **Protects against:** a stolen powered-off Mac, by pushing the user to the platform feature
  that already does full-disk encryption. Nothing else.
- **Migration:** none. Data is untouched.
- **Search, live transcription, speed:** unaffected.
- **Key loss:** FileVault's own recovery key is Apple's concern, not the app's.
- **Effort:** ~0.5 day (one `Process` call, one row in Settings, one test on the parsed output).
- **Risk:** none to data. A wrong reading only shows or hides a line.
- **Ladder:** rung 4 — a native platform feature covers it.

### (b) Exclude the Beseda folder from Time Machine and cloud backups

- **What:** set `URLResourceValues.isExcludedFromBackup = true` on
  `~/Library/Application Support/Beseda` at launch (next to `StorageProtection.apply`), behind a
  toggle «Не включать записи в резервные копии» in Настройки → Хранение, default **on** for new
  installs, asked once for existing ones. Warn when the export folder lies under
  `~/Library/Mobile Documents` (iCloud Drive) or `~/Documents` / `~/Desktop` with iCloud sync.
- **Protects against:** Time Machine copies on a plain disk. The flag (`com.apple.metadata:com_apple_backup_excludeItem`)
  is honoured by Time Machine and by most third-party tools (Arq, Backblaze honour it or have their
  own exclusion list; not guaranteed for all). Does **not** protect a manually copied folder.
- **Cost:** the calls are no longer backed up. A dead SSD loses them. For a psychologist this is
  often the wanted behaviour (session notes should not multiply); for Mikhail's 123 calls it is a
  real loss of safety — the toggle must be his choice, and the doc/Settings line must say so.
- **Migration:** none; the flag is metadata. Rollback: clear the flag, the next backup includes the
  folder again. Existing backups keep the old copies — the user deletes them in Time Machine.
- **Search, live transcription, speed:** unaffected.
- **Key loss:** no key.
- **Effort:** ~0.5–1 day with the export-folder warning and a test on the resource value.
- **Risk:** low; it removes a safety net, which is the point.
- **Ladder:** rung 4 — one platform resource value.

### (c) SQLCipher (or SQLite's own encryption) with the key in the Keychain

- **What:** encrypt `calls.sqlite` as a whole with a 256-bit key stored as a Keychain item
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, not synced).
- **Availability:** macOS's system `libsqlite3` has neither SQLCipher nor SEE. SEE (SQLite's own
  encryption extension) is a paid licence with source-only delivery. SQLCipher Community is
  BSD-licensed but means a new dependency (an SPM package vendoring its amalgamation, ~200k lines
  of C) that **replaces** the system SQLite3 import in `CallStore` — the whole storage layer
  moves off the system library the [SQLite call index](sqlite-storage.md) decision chose.
- **Protects against:** a copied or backed-up `calls.sqlite` read without the key. Not the WAVs,
  transcripts, ASR JSON, exports, the log or the `.v<n>.backup` files, which hold the same text —
  so alone it protects almost nothing: `transcript.md` sits next to it in plain form.
- **Migration:** `sqlcipher_export` into a new encrypted file; keep the plain file as
  `calls.sqlite.plain.backup` until the encrypted one opens and row counts match; then delete the
  plain file and every `.v<n>.backup` (and their free space is not wiped on APFS/SSD — the old
  plain blocks stay until overwritten, so migration protects future backups, not a disk already
  copied). Rollback: keep the plain backup for N days, or `sqlcipher_export` back.
- **Search:** unchanged in SQL (`LIKE`, `unicode_lower`) — SQLCipher encrypts pages, not values.
  ~5–15 % slower page I/O; at 123 calls invisible.
- **Live transcription:** writes segments through the same connection; unaffected apart from the
  page cost.
- **Key loss:** the Keychain item is gone (new Mac without migrating the Keychain, a Keychain
  reset, another user, restored from a backup onto a new machine — `ThisDeviceOnly` items do not
  move) → the whole index is **unreadable, forever**. Transcripts survive only because
  `transcript.md` is plain. Needs a recovery key the user writes down, which psychologists will lose.
- **Effort:** 3–5 days plus the full check; touches migrations, `Package.swift`, tests.
- **Risk:** high — a new C dependency for the core store, a migration over the only copy, and a
  key whose loss destroys data.
- **Ladder:** rung 7 — nothing already present covers it; the cost is high for the partial gain.

### (d) Encrypt WAVs, transcripts and exports with CryptoKit and a Keychain key

- **What:** `AES.GCM` (CryptoKit, in the OS) over each file in `calls/<id>/` and each export, key in
  the Keychain as in (c).
- **Protects against:** copied folder and backups, for the files. Not `calls.sqlite` (unless paired
  with (c)), which holds every segment's text and the summaries — so again partial.
- **Migration:** encrypt each call folder into `*.enc` next to the plain file, verify decrypt,
  delete plain; per-call so a crash leaves at most one call half-done. Rollback: decrypt back
  while the key exists. Same APFS caveat: old plain blocks are not wiped.
- **Live transcription:** the long-call read path (`GrowingWAVFile`, `UtteranceSplitter`,
  `EchoGate`) reads the WAV while it grows. AES-GCM is not seekable per byte; it needs a chunked
  format (e.g. 64 KiB sealed boxes) and a rewrite of the reader and the writer — the most fragile,
  memory-tested part of the app. Encrypting only after the call ends leaves the file plain during
  the call and until processing ends.
- **Exports:** an encrypted Markdown export cannot be opened by the user's editor, which is the
  export's whole purpose. Encrypting exports is self-defeating; turning export off is the honest option.
- **Search:** unaffected if the text lives in `calls.sqlite` (it does); `transcript.md` is
  read by the UI and would need decryption.
- **Key loss:** every WAV and transcript file is gone; the index (if plain) keeps the text.
- **Effort:** 5–8 days, the full check, and a new file format for audio.
- **Risk:** high — touches the audio capture path and every call folder.
- **Ladder:** rung 3 (CryptoKit is in the OS), but the amount of code is rung 7.

### (e) «Строгий режим» for psychologists

- **What:** one switch in Настройки that sets together, and shows as one line: audio retention
  «сразу после расшифровки» (delete WAVs once the transcript is saved), export off, «Только
  локально» on (no OpenRouter, Jev, webhook, live key points to the cloud), the backup exclusion
  of (b) on, and the FileVault warning of (a) as a blocker message. All of these except (a) and (b)
  already exist as separate settings.
- **Protects against:** the biggest volume of sensitive data (voice, a biometric identifier) not
  being there at all; nothing leaving the Mac; no copies multiplying through exports and backups.
  What remains on disk is `calls.sqlite` + `transcript.md`, inside a `0700` folder on a
  FileVault volume, not in backups.
- **Migration:** none; turning it on applies retention to existing WAVs on the next janitor run —
  it must ask before deleting existing audio ("удалить аудио N записей?"). Rollback: switch off;
  deleted audio does not come back (said in the confirmation).
- **Search, live transcription, speed:** unaffected (retention runs after processing; live
  transcription reads the WAV during the call as today). Re-transcribing with another model
  becomes impossible once the audio is gone.
- **Key loss:** no key.
- **Effort:** ~1–1.5 days: one setting that writes existing settings, a confirmation, a test that
  the mode sets all of them.
- **Risk:** low; the only destructive step is audio deletion behind a confirmation.
- **Ladder:** rung 2 — reuses retention, export, «Только локально»; adds (a) and (b).

## Summary

| Option | Protects | Effort | Data risk | Key loss |
|---|---|---|---|---|
| (a) FileVault warning | stolen Mac (via FileVault) | 0.5 d | none | n/a |
| (b) Backup exclusion | Time Machine / backup tools | 0.5–1 d | lose backup safety net | n/a |
| (c) SQLCipher | copied `calls.sqlite` only | 3–5 d | high | index lost |
| (d) CryptoKit files | copied WAVs/transcripts only | 5–8 d | high | files lost |
| (e) Строгий режим | less data, nothing leaves, no copies | 1–1.5 d | audio deletion, confirmed | n/a |

## Recommendation

Do **(a) + (b) + (e)**, and **not** (c) or (d) now.

- (a) makes the one real disk-encryption layer, FileVault, visible; it covers a stolen Mac better
  than any app key.
- (b) closes the realistic leak left with FileVault on — a backup on a plain disk or a cloud
  backup tool — as an opt-in for existing users (Mikhail keeps his backups) and on in (e).
- (e) bundles what a psychologist needs into one switch: no audio kept, no export, local only,
  excluded from backups. Data that is not kept cannot leak.
- (c) and (d) protect only a copied folder with FileVault on, cost 8–13 days together, add a
  C dependency and a new audio format, and turn a lost Keychain item into lost sessions. Revisit
  only if a user needs to hand the folder to someone else or store it on shared media — then
  (c)+(d) together, never one alone, with a written recovery key.

The unlocked Mac and same-user malware stay out of scope; [Privacy](../product/privacy.md)
already says so.
