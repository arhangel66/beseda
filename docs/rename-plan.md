# Podushka → Beseda, and the code goes public

Decided 2026-09-05: the app and the repository are renamed to **Beseda**; the source
is published in the same public repository that serves releases and the update feed.

## What changes

| Area | Now | After |
| --- | --- | --- |
| GitHub | `arhangel66/podushka`, releases only | `arhangel66/beseda`, source + releases + `appcast.xml` |
| Bundle | `Podushka.app`, `app.podushka.Podushka` | `Beseda.app`, `app.beseda.Beseda` |
| SwiftPM | product/target `Podushka`, tests `PodushkaTests` | `Beseda`, `BesedaTests` |
| Data | `~/Library/Application Support/Podushka` | `…/Beseda`, moved once on first launch (calls, index, log, downloaded models) |
| Settings | `UserDefaults` of the old bundle id, keys `podushka.*` | new bundle id, keys `beseda.*`, copied once from the old domain |
| Scripts | `build_podushka_app.sh`, `package_podushka.sh`, `release_podushka.sh` | `build_app.sh`, `package_app.sh`, `release.sh`; `pkill -x Beseda`, `~/Applications/Beseda.app` |
| Texts | "Podushka" in onboarding, settings hints, notifications, log lines, transcript headers | "Beseda" |
| Docs | README, AGENT.md, install.md, release.md, roadmap, auto-update plan | renamed; older plan documents stay as history |

Stays as is:

- Webhook wire format: headers `X-Podushka-*`, test event `podushka_test`. That is the
  contract with kushetka; renaming it means changing both sides, a separate task.
- The app icon. It is a pillow; a new one is a design task, not part of the rename.
- The source directory `~/w/learning/podushka`. Git does not care about it; renaming it
  moves the bb environment and is a separate one-line step at the very end if wanted.

## Consequences on the two Macs

- New bundle id = new app for macOS: microphone, system audio, calendar and
  notifications are asked again; the login item has to be switched on again. The
  onboarding flag is migrated, so the app opens straight to the archive and the
  permission banners do the asking.
- The installed Podushka 0.2.2 never becomes Beseda: Sparkle refuses an update with a
  different bundle id. Both Macs install `Beseda-0.3.0.zip` by hand once and delete
  `Podushka.app`. After that, updates are automatic again.
- The two Podushka releases are deleted from the renamed repo so the feed only ever
  describes Beseda.

## Steps

Each step: `swift test` green, then the dev build launches.

- [ ] **1. Git.** `git init`, review `.gitignore` (`untracked/`, `samples/`, `dist/`,
  `.build/` are already there; add `.qwen38-work/`), scan the tree for personal data
  and secrets before the first commit (`grep -rniE "secret|token|password|@gmail"`
  over tracked files). First commit as "Podushka 0.2.2" so the rename is a readable
  diff.

- [ ] **2. Rename in SwiftPM and the bundle.** `Package.swift` product/targets,
  `Tests/BesedaTests`, `@testable import Beseda`, `BesedaApp`, `BesedaError`.
  `Resources/Info.plist`: executable, name, identifier, usage descriptions.
  Dispatch-queue labels and notification category ids get the `app.beseda.` prefix.

- [ ] **3. Data and settings migration.** `AppPaths.dataDirectory` → `Beseda`.
  `LegacyDataMigration` is replaced: when `…/Beseda` does not exist and `…/Podushka`
  does, move the whole directory (the untracked-layout migration is obsolete: it ran
  on the only Mac that had that layout). `AppSettings`: on first launch with an empty
  new domain, copy every `podushka.*` value from `UserDefaults(suiteName:
  "app.podushka.Podushka")` into the `beseda.*` key. Tests: directory moved once and
  not again; defaults copied once, existing new values not overwritten.

- [ ] **4. User-facing texts and log lines.** Onboarding, settings hints, notification
  body, mic-permission error, transcript headers, aggregate device names.

- [ ] **5. Scripts and docs.** Rename the three scripts, `bundle_app.sh` constants
  (feed URL to `arhangel66/beseda`), `release.sh` additionally requires a clean git
  tree, tags `v<version>` and pushes the tag. README (the GitHub one merges into the
  repo README), AGENT.md, install.md, release.md, roadmap, auto-update plan.

- [ ] **6. GitHub.** `gh repo rename beseda`, delete releases `v0.2.1` and `v0.2.2`
  and their tags, push `main`. `VERSION` → 0.3.0, `./scripts/release.sh`.

- [ ] **7. Mikhail's Mac.** Quit Podushka, install `Beseda-0.3.0.zip`, grant the
  permissions, check: the archive is there, the model is not re-downloaded, settings
  kept, login item switched on. Delete `Podushka.app`. Then publish 0.3.1 with a
  visible change and confirm the automatic update still works under the new name.

- [ ] **8. The other Mac.** Same install by hand; then updates arrive on their own.

## Open points to confirm before starting

1. Bundle id `app.beseda.Beseda` (same pattern as today).
2. Webhook headers stay `X-Podushka-*` for now.
3. First Beseda version is 0.3.0; Podushka releases are deleted from the repo.
4. The source directory is renamed to `~/w/learning/beseda` at the end (yes/no).
