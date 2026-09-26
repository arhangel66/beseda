---
name: xcode-build-baseline
description: Measure reproducible Xcode builds with fixed inputs, private DerivedData, medians, raw logs, and JSON output.
---

# Xcode build baseline

This candidate is from `xopoko/build-swift-apps` at source revision
`3d3a30a7c685f2d1f6b0c0a32588e04f8267864b`. Its helper was not usable on this
Mac, so this rewrite keeps the fixed-input measurement shape and the proven
shell fallback. FAB-11 measured clean median 3.141 s, cached-clean 4.970 s,
zero-change 1.793 s, and touched incremental 2.818 s; raw JSON and logs are
under `docs/evidence/skills-search-trial-FAB-11-20260920/`.

Toolchain selection is per-command through `DEVELOPER_DIR`; this skill does
not require a privileged global toolchain switch.

## Fixed-input recipe

Record Xcode, Swift, project, scheme or target, configuration, SDK, flags,
DerivedData paths, and cache state. Warm once only to prove the command. Run
three samples for each requested class, retain raw output, and report median
plus min/max. Never edit source or project files as part of a benchmark.

When a helper is unavailable, use the kit's shell-safe target build:

```sh
xcodebuild build -project App.xcodeproj -target App \
  -sdk iphonesimulator -configuration Debug \
  OBJROOT="$DERIVED/Build/Intermediates.noindex" \
  SYMROOT="$DERIVED/Build/Products" CODE_SIGNING_ALLOWED=NO
```

Use private DerivedData per candidate. On this arm64 Mac, the measured warm
loop additionally used `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` and retained app-local
DerivedData. A concrete simulator destination and the generic scheme build
were not eligible with the installed SDK/runtime combination. Do not substitute
that failure with a claimed test result; use a matching runtime before running
`xcodebuild test`.
