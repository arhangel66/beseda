---
type: Decision
status: proposed
---
# English first buyers: language gate

**Gate: no.** Asking US/EU users to pay today for an English-language app would be misleading. The proposed [English landing message](../product/landing-brief.md) explicitly does not promise an English-only interface, but the [shipped feature flow](../product/features.md) is predominantly Russian. An English page cannot substitute for an English first run. This is a source audit, not a verified run on an English macOS installation.

## What a buyer sees

| Surface | Current coverage and minimum English path | File areas / effort |
| --- | --- | --- |
| First run and permissions | Welcome, privacy caveat, audio-source setup, model choice and sound check are Russian. App-owned permission explanations and calendar/microphone purpose text are Russian; macOS may localize its *own* permission controls, not Beseda's copy. Translate the full setup path including denied/retry states and privacy qualifications. | `App/Views/OnboardingWindow.swift`, `App/PermissionChecks.swift`, `Resources/Info.plist`; medium |
| Menu bar and recording | Start/stop, status, live preview, empty states and notifications are Russian. Translate recording controls, status, help and notifications. | `App/Views/MenuBarPopover.swift`, `App/CallNotifications.swift`, `App/AppController.swift`; medium |
| Settings | Tabs and instructions for recording, speech/summary models, storage, calendar, webhook and updates are Russian. Translate all buyer-facing rows, provider/privacy disclosures, failures and accessibility text. | `App/Views/SettingsWindow.swift`, `App/Views/SpeechModelList.swift`, `App/AppSettings.swift`, `Transcription/SpeechModel.swift`; large |
| Archive and result | Search, sidebar, deletion warnings, player, speaker names, transcript tabs, summary actions, previous-call block and recovery errors are Russian. Translate these, plus dynamic status/errors from controller and services. | `App/Views/{ConversationsWindow,CallSidebar,CallDetailView,CallSummaryView,PreviousCallBlock,PlayerBar}.swift`, `App/AppController.swift`, `Transcription/SpeakerNaming.swift`, `Summarization/`, `Storage/`; large |
| Copy and export | Export combines Russian `Тип:` with English `## Transcript`; copied transcript can contain Russian default speaker names. Dates are explicitly `ru_RU` in `CallFormatting`, while filename date uses `en_US_POSIX`. Make generated headings, labels, speaker names and display dates consistent with the English path; do not alter stored user text or filenames gratuitously. | `Storage/{CallExport,CallFormatting,TranscriptCopy}.swift`, `Transcription/SpeakerNaming.swift`; small–medium |

Model/product names such as Parakeet, OpenRouter, LM Studio, Markdown, POST and Bearer are English technical labels, **not** English interface coverage. The 25-language Parakeet speech model supports recognition, not UI localization. System-provided date/permission/button text may follow macOS language; explicit `ru_RU`, Russian literals and `Info.plist` purpose strings do not become English merely because macOS is English. No `.strings` or `.xcstrings` resources were found in `Sources`; `Info.plist` declares a development region but no localized purpose-string resources. SwiftUI's implicit localization of literal keys cannot supply absent English translations or translate runtime-composed `String` values.

**Minimum shippable gate:** on an English-language Mac, a new buyer must be able to grant/repair permissions, choose an English-capable speech model, record, find a call, read/copy/export its transcript and result, understand local/cloud privacy choices and recover from common failures without Russian UI or generated labels. Cover accessibility labels and destructive warnings too. Source review plus an English-system-locale first-run and end-to-end check are needed before changing the payment claim; this audit did not run the app. This is a bounded translation/content pass across the listed existing surfaces, not a request for a speculative i18n framework or new feature.
