# Agents

## Project knowledge

Project knowledge is stored in `docs/` using the
[Open Knowledge Format](https://github.com/inkeep/open-knowledge-skills) (OKF).

- Start from `docs/index.md` when project context is needed, and navigate through directory `index.md`
  files progressively. Open only the documents the current task needs.
- Treat code as the source of current behaviour, and `docs/` as the source of product intent,
  architectural rationale, constraints and previous decisions.
- Keep `docs/` current as part of the work, not after it: a new part gets its document and its line in the
  index, and a document a change makes wrong is fixed in the same change.

## How the code is written

By a lazy senior developer — the ponytail ladder, after
[DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail) (MIT). Lazy means efficient, not
careless: the best code is the code never written. Before writing any, stop at the first rung that holds —
is it needed at all, is it already in this codebase, does the standard library do it, does the platform
cover it, does an installed dependency solve it, can it be one line — and only then write the minimum that
works.

No abstraction nobody asked for, no configurability for a value that never changes, no scaffolding "for
later". Deletion over addition, boring over clever, the fewest files possible. Not lazy about:
understanding the problem, validation at trust boundaries, error handling that prevents data loss,
security, accessibility, and anything the task asks for.

## Commits

Every finished step is a commit: the check below is green before it, the message is one short line in
english saying what changed. No work is left uncommitted when a task is handed off.

## Check

The first task writes the check here — the one command that builds and tests this project — and it stays
green from then on.

```
swift test --jobs 2
```

Agents in this repo do not use Serena/LSP tools (sourcekit-lsp indexing eats tens of GB of RAM); they use grep/read, and `swift test` runs with `--jobs 2`.

Run builds and checks only in your own worktree, never in the main checkout
/Users/mikhail/w/learning/beseda: SwiftPM locks `.build`, and waiting on another agent's lock costs 20–40 min a day.

It builds the app and runs every test except the heavy ones gated by `BESEDA_FULL_CHECK=1`
(`noReadGrowsWithTheLengthOfTheCall`, `liveLoopLogsOnceAndStopsWhenTheSpeechModelIsMissing`); ~11 s after the build. `theInstalledModelTranscribesRealSpeech` is skipped unless the
speech model is installed in Application Support and `samples/jfk.wav` (gitignored) is in the checkout.

The app sources live in `Sources/Beseda` and the tests in `Tests/BesedaTests`, so SwiftPM never walks the
rest of the checkout: `.factory/`, `untracked/` or a large scratch folder at the root do not slow the build.
If the check still stalls before compiling and `.build/build.db` is gigabytes, delete `.build` and rerun: a
clean run takes ~1.5 min and ~1.2 GB of `.build`.

The full check is `scripts/full_check.sh` (~1.7 min after the build): every test with `BESEDA_FULL_CHECK=1`,
then the 1 h synthetic-call memory tests. Run it when `Package.swift`, `Storage` migrations, `Audio/` capture
or the long-call read path (`EchoGate`, `UtteranceSplitter`, `GrowingWAVFile`) change. `release.sh` always
runs it, and a LaunchAgent runs it nightly on native-ui (`scripts/install_nightly_check.sh`; see
docs/architecture/build-release.md).

## No-focus, no-sound

Someone works on this Mac. Never bring a window to the front and never play into the Mac's output device:
launch Beseda only through `scripts/screenshot_copy.sh`: it bundles a copy with a random bundle id per run (`app.beseda.shot.<random>`, its own defaults domain,
deleted when the copy quits) from this
worktree's `.build` (incremental after the check, never a scratch build path) and opens it with
`open -n -g -j --env CFFIXED_USER_HOME="$(mktemp -d)"`; shoot windows with the kit's `scripts/window-shot.swift` (it never activates), and send audio to files or
BlackHole only. See the kit's `docs/headless.md` and `docs/macos.md`.
The login keychain is shared even so: `Keychain` keeps secrets in memory unless the bundle id is
`app.beseda.Beseda` with no `CFFIXED_USER_HOME` or `BESEDA_NO_KEYCHAIN`, so copies and tests never prompt.
Isolated copies must not request permissions (`IsolatedCopy.skips` guards every dialog-capable call); screenshots
that need capture use BlackHole plus a pre-granted real app, never a new bundle id.

## Kit

This project is built with the ios kit at `/Users/mikhail/w/learning/ios-kit`: its `docs/index.md` is the
way in, its skills are copied into this project's `.agents/skills/` (`.claude/skills` links there).
What the kit lacks is fixed in the kit, never worked around here.
