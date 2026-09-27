---
type: Decision
status: proposed
---
# English first buyers: language gate

**Gate: not verified.** The [English landing message](../product/landing-brief.md) does not promise an English-only interface. The [feature flow](../product/features.md) now has English and Russian resources for first run, menu, settings, archive and export. An English page and source coverage cannot establish payment readiness: the app has not been launched on an English macOS installation.

## What a buyer sees

| Surface | Current coverage and minimum English path | File areas / effort |
| --- | --- | --- |
| First run and permissions | First-run and permission copy has en/ru resources, including localized purpose strings. Source and bundle structure are checked; denied/retry states still need an English-system visual run. | `App/Views/OnboardingWindow.swift`, `App/PermissionChecks.swift`, `Resources/Info.plist`; medium |
| Menu bar and recording | Start/stop, status, live preview, empty states and notifications have en/ru resources. Visual behavior remains unverified. | `App/Views/MenuBarPopover.swift`, `App/CallNotifications.swift`, `App/AppController.swift`; medium |
| Settings | Settings tabs, instructions, provider/privacy disclosures, failures and accessibility text have en/ru resources; visual coverage remains unverified. | `App/Views/SettingsWindow.swift`, `App/Views/SpeechModelList.swift`, `App/AppSettings.swift`, `Transcription/SpeechModel.swift`; large |
| Archive and result | Archive actions, deletion warnings, speaker names and generated labels have en/ru resources. Unknown external summary/provider error text can still appear verbatim; authored titles, speaker overrides and transcript text are intentionally unchanged. Visual recovery remains unverified. | `App/Views/{ConversationsWindow,CallSidebar,CallDetailView,CallSummaryView,PreviousCallBlock,PlayerBar}.swift`, `App/AppController.swift`, `Transcription/SpeakerNaming.swift`, `Summarization/`, `Storage/`; large |
| Copy and export | Source now selects generated export labels, copy menu text and default speaker names by locale; display dates use the system locale while filenames remain POSIX. Authored content is unchanged. Pure-unit locale checks cover this source path; the packaging script copies the SwiftPM resource bundle beside the executable, but packaged runtime localization is not verified by launching the app. | `Storage/{CallExport,CallFormatting,TranscriptCopy}.swift`, `Transcription/SpeakerNaming.swift`; small–medium |

Model/product names such as Parakeet, OpenRouter, LM Studio, Markdown, POST and Bearer are English technical labels, **not** English interface coverage. The 25-language Parakeet speech model supports recognition, not UI localization. System-provided date/permission/button text may follow macOS language. `Sources/Beseda/Resources/{en,ru}.lproj` contains FirstRun, Menu, Settings, Archive, Export and InfoPlist string tables. The build bundle contains en/ru resources and `scripts/lib/bundle_app.sh` copies it into the packaged app; this verifies the lookup structure, not a launched app. Authored call types, user content and fixture text are not translations; unrecognized external summary errors are not guaranteed English.

**Verification status:** Source-only checks do not prove payment readiness. The English-system GUI first-run and end-to-end check is parked under the host-screen incident: no app launch, windows, audio, focus or permission prompts. After the incident is resolved and permission is granted, the safe route is `scripts/screenshot_copy.sh` and the kit's `scripts/window-shot.swift` for an English-system first-run → recording → archive → copy/export and permission-recovery journey without activating the host session. The overnight check is `swift build --jobs 2` plus proven window-free unit filters; full `swift test --jobs 2` awaits morning permission.

**Minimum shippable gate:** on an English-language Mac, a new buyer must be able to grant/repair permissions, choose an English-capable speech model, record, find a call, read/copy/export its transcript and result, understand local/cloud privacy choices and recover from common failures without Russian UI or generated labels. Cover accessibility labels and destructive warnings too. Source review plus an English-system-locale first-run and end-to-end check are needed before changing the payment claim; this audit did not run the app. This is a bounded translation/content pass across the listed existing surfaces, not a request for a speculative i18n framework or new feature.
