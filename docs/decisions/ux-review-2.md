---
type: Review
title: Pre-handoff UX review, round 2
status: proposed
description: Findings from a first-time-user and psychologist review of native-ui HEAD.
---
# Pre-handoff UX review, round 2

Reviewed on 2026-09-27 from an isolated copy launched only through `scripts/screenshot_copy.sh`, with a
fresh random bundle identifier, a temporary home, preview environment variables, and 64 seeded calls. The
system appearance was Light. Screenshots are in `.factory/shots/BESEDA-ux2/`.

## Findings

### P1 — The first privacy promise is broader than the explanation

**Fixed in BESEDA-155.** The onboarding headline now says «Аудио остаётся на этом Mac»; its adjacent explanation names the optional cloud text paths (OpenRouter, Jev and live key points).

- **Screen and shot:** onboarding, step 1 — [onboarding-1](../../.factory/shots/BESEDA-ux2/onboarding-1-добро-пожаловать-в-beseda.png).
- **What is wrong:** «Ваши разговоры остаются на этом Mac» reads as a complete privacy guarantee. The next
  sentence qualifies it: text can leave the Mac when cloud summaries are enabled. A psychologist choosing a
  recorder for confidential sessions can reasonably stop reading after the headline and take away the wrong
  promise.
- **Concrete fix:** make the headline precise, for example «Аудио остаётся на этом Mac», and put the text/cloud
  exception in the same visual block, not only in body copy.
- **Effort:** S.
- **Priority:** P1.

### P1 — A selected speech model looks ready when it is absent

**Fixed in BESEDA-155.** `SpeechModel.stateLabel` distinguishes «Выбрана · не скачана», «Выбрана · скачана» and «Готова» (only when usable); onboarding and Settings share `SpeechModelList`, and the missing-model popover uses the same label.

- **Screen and shot:** onboarding, step 3 — [onboarding-3](../../.factory/shots/BESEDA-ux2/onboarding-3-добро-пожаловать-в-beseda.png); Settings → Обработка — [missing model](../../.factory/shots/BESEDA-ux2/settings-processing-missing-model-обработка.png).
- **What is wrong:** Parakeet carries the orange «Выбрана» badge next to «Скачать», while the Settings footer says
  «Модели на диске: 0 Б». On first use, «Выбрана» reads as installed and usable. The popover later says the model
  is missing, so three surfaces describe one state differently.
- **Concrete fix:** use separate states and words: «Выбрана · не скачана» or «Скачать выбранную» until ready;
  reserve «Готова» for an installed model, and use the same state label in onboarding, Settings, and the popover.
- **Effort:** S.
- **Priority:** P1.

### P1 — The calendar error and success statistic contradict each other

**Fixed in BESEDA-175.** A missing selected calendar now replaces historical coverage with the effect on new calls.

- **Screen and shot:** Settings → Интеграции — [calendar problem](../../.factory/shots/BESEDA-ux2/settings-integrations-calendar-problem-интеграции.png).
- **What is wrong:** the red row says «Выбранный календарь не найден», but the line directly below says an event
  was found for 63 of 64 conversations. A user cannot tell whether linking is broken now, partly working, or only
  broken for future calls.
- **Concrete fix:** while linking is broken, replace the coverage line with a current-state explanation such as
  «Новые разговоры не получат названия, пока не выбран доступный календарь»; label historical coverage explicitly
  if it remains useful.
- **Effort:** S.
- **Priority:** P1.

### P1 — Speaker controls are unexplained tokens

**Fixed in BESEDA-156.**

- **Screen and shot:** Разговоры → Итоги — [call summary](../../.factory/shots/BESEDA-ux2/call-default-разговоры.png).
- **What is wrong:** the player footer shows tiny circles «В», «С», and raw-looking «t», with no visible legend or
  affordance. For a psychologist, speaker identity is core data; a letter that looks like an implementation key
  makes attribution feel unreliable, and nothing suggests that speakers can be renamed or merged.
- **Concrete fix:** show stable participant names beside the colours (at least on hover/focus), never derive a
  visible token from a raw speaker key, and expose «Переименовать» / «Объединить с» from a clearly named participant
  control.
- **Effort:** M.
- **Priority:** P1.

### P2 — Live transcription overwhelms the menu-bar surface

**Fixed in BESEDA-175.** Recording hides recent calls and commands, keeps stop beside the status, and puts a capped live preview in a collapsed disclosure.

- **Screen and shot:** popover, live transcription — [live](../../.factory/shots/BESEDA-ux2/popover-live-popover-preview.png).
- **What is wrong:** key points, seven transcript lines, meters, controls, three recent calls, and commands make a
  681-point-tall window. On an 800-point display it nearly fills the usable height. The most urgent controls are
  separated from the status by a dense reading surface, and the latest calls compete with the live call.
- **Concrete fix:** collapse recent calls while recording, cap the transcript to fewer lines, and make key points or
  transcript an explicit compact disclosure.
- **Effort:** M.
- **Priority:** P2.

### P2 — Onboarding calls a check a permission

**Fixed in BESEDA-155.** The step is «Два источника звука», explains microphone versus system sound, uses «Разрешить доступ» versus «Проверить звук», and names «Настройки → Запись» as the later check path.

- **Screen and shot:** onboarding, step 2 — [access](../../.factory/shots/BESEDA-ux2/onboarding-2-добро-пожаловать-в-beseda.png).
- **What is wrong:** «Два доступа» groups «Разрешить» for the microphone with «Проверить» for system sound. Those are
  different actions. The footer says system sound can be checked later, but does not tell a new user where or what
  happens if they continue with a monologue-only recording.
- **Concrete fix:** call the step «Два источника звука», label each row with its real action, and give the deferred
  path by name, for example «Настройки → Запись».
- **Effort:** S.
- **Priority:** P2.

### P2 — The Recording pane hides an option below the fold

**Fixed in BESEDA-175.** Global recording options and the reusable sound check now precede the conditional app list.

- **Screen and shot:** Settings → Запись — [recording](../../.factory/shots/BESEDA-ux2/settings-recording-запись.png).
- **What is wrong:** at the fixed 680×560 window size, «Расшифровывать во время звонка» is clipped at the bottom and
  no scrollbar is visible. A first-time user sees a complete-looking list and can miss the feature entirely.
- **Concrete fix:** keep all global recording options above the long app list, or show a persistent scrollbar / a
  stronger continuation cue.
- **Effort:** S.
- **Priority:** P2.

### P2 — Technical English leaks into ordinary settings

**Fixed in BESEDA-175.** The main rows describe speaker separation and webhook contents; model licence and protocol terms are under «Подробнее».

- **Screen and shot:** Settings → Обработка — [processing](../../.factory/shots/BESEDA-ux2/settings-processing-missing-model-обработка.png); Settings → Интеграции — [integrations](../../.factory/shots/BESEDA-ux2/settings-integrations-интеграции.png).
- **What is wrong:** «Nemotron-3 Diarization», «OpenMDW-1.1», «POST», «Authorization», «Bearer», «https», and
  «localhost» are presented in the main flow. The integration explanation is correct but reads like API
  documentation, not a setting for a psychologist.
- **Concrete fix:** translate the model purpose («Разделение собеседников») and move licences/protocol details into
  «Подробнее» or «Для разработчиков»; keep the main copy about what data is sent and where.
- **Effort:** M.
- **Priority:** P2.

### P2 — The product name switches alphabets throughout the first run

**Fixed in BESEDA-175; completed by the BESEDA-183 sweep.** User-facing Russian prose and permission prompts use «Беседа»; a source guard prevents Latin `Beseda` from returning to Cyrillic UI literals. Technical identifiers, paths, logs, the bundle name, and English UI retain `Beseda`.

- **Screen and shot:** [onboarding-1](../../.factory/shots/BESEDA-ux2/onboarding-1-добро-пожаловать-в-beseda.png), [general settings](../../.factory/shots/BESEDA-ux2/settings-general-основные.png), [idle popover](../../.factory/shots/BESEDA-ux2/popover-idle-popover-preview.png).
- **What is wrong:** Russian sentences use Latin «Beseda» («Добро пожаловать в Beseda», «Завершить Beseda»). It is
  visually conspicuous and leaves pronunciation and brand spelling unresolved.
- **Concrete fix:** choose one display name and apply it everywhere; for a Russian-only interface, use «Беседа» in
  prose and reserve `Beseda` for bundle names, paths, and technical identifiers.
- **Effort:** S.
- **Priority:** P2.

### P3 — Summary history duplicates the current page before the current result

**Fixed in BESEDA-156.**

- **Screen and shot:** Разговоры → Итоги — [call summary](../../.factory/shots/BESEDA-ux2/call-default-разговоры.png); [expanded previous summary](../../.factory/shots/BESEDA-ux2/call-previous-whole-разговоры.png).
- **What is wrong:** «В прошлый раз» occupies the first large card and repeats the same headings as the current
  result. The current call starts only below a type picker and copy button. A user opening the call can mistake the
  historical actions for today’s actions.
- **Concrete fix:** collapse history to a one- or two-line digest by default, add the previous call title, and make
  the current result the first full document.
- **Effort:** S.
- **Priority:** P3.

### P3 — The General pane looks unfinished

**Fixed in BESEDA-175.** Settings uses a shorter window for the compact General pane.

- **Screen and shot:** Settings → Основные — [general](../../.factory/shots/BESEDA-ux2/settings-general-основные.png).
- **What is wrong:** two compact groups occupy the top third of a large fixed window and leave most of it blank.
  Next to the dense Recording and Processing panes, this looks like an unfinished placeholder rather than calm
  spacing.
- **Concrete fix:** allow the Settings window to size to each tab, or move a small set of genuinely general options
  here so pane density is consistent.
- **Effort:** S.
- **Priority:** P3.

## States that worked well

- The destructive delete dialog is concise, names all deleted material, and says that recovery is impossible:
  [delete](../../.factory/shots/BESEDA-ux2/call-delete-2.png).
- The FileVault warning names the risk and offers the exact recovery action:
  [FileVault off](../../.factory/shots/BESEDA-ux2/settings-storage-filevault-off-хранение.png).
- The recording-size warning says what stopped, why, and what remains safe:
  [warning](../../.factory/shots/BESEDA-ux2/popover-warning-popover-preview.png).

## Coverage limits

BESEDA-155 changed the onboarding and model-state copy described above. The referenced after shots under `.factory/shots/BESEDA-153/` are not present in this checkout, so no visual verification or working after-shot links can be cited here; the fixed markers reflect the source changes, not a new screenshot review.

No screenshots were taken for BESEDA-175 because signing, installation, and app launch were paused. Exact shots left for the follow-up: recording popover with the live disclosure collapsed and expanded; Settings → Основные; Settings → Запись with automatic recording on; Settings → Запись during and after «Проверить звук»; Settings → Обработка with model details collapsed and expanded; Settings → Интеграции with a missing selected calendar; Settings → Интеграции with webhook developer details collapsed and expanded.

The host process did not have Accessibility permission. AX tree queries returned no descendants, AX actions could
not find controls, and targeted `CGEvent` mouse/keyboard events did not change the hidden app. Therefore the
accessibility tree, tab order, actual keyboard activation, search result, paging result, «Расшифровка», «Сведения»,
and «Объединить с» could not be verified by driving this run. The app has no preview state for recording without
live transcription: `BESEDA_PREVIEW_POPOVER=recording` rendered the idle state. Dark appearance could not be changed
per isolated copy without changing the owner’s global appearance, so only Light was visually reviewed. The cloud
notice was below the initial fixed-height Storage viewport and could not be scrolled into view under the same input
limit.
