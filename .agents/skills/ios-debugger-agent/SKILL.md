---
name: ios-debugger-agent
description: Build, launch, inspect, and capture logs from an iOS app with XcodeBuildMCP when that MCP server is available; otherwise use the explicit-UDID shell fallback.
---

# iOS debugger

This skill was retained from `dimillian/skills` at source revision
`05ba982bfeb0d77d3c97d4542b0ee15034d05f84`. The MCP flow was not shell-tested;
its boundary and the tested shell fallback are recorded in
`docs/evidence/skills-prior-art-FAB-10.md`.

## XcodeBuildMCP flow (MCP only)

When XcodeBuildMCP is available:

1. List simulators and choose a booted simulator. Do not silently use a
   different device.
2. Set project/workspace, scheme, and simulator ID as session defaults.
3. Build and run. After a successful build, call `describe_ui` or `screenshot`
   before interacting.
4. Call `describe_ui` before taps. Prefer accessibility IDs or labels, then
   type into the focused field. Use screenshots for visual confirmation.
5. Start and stop simulator log capture around the launch when logs are needed.

These MCP calls are guidance only. Do not report them as shell verification.

## Explicit-UDID shell fallback

The proven kit boundary is ordinary Xcode and `simctl`:

```sh
xcodebuild build -project App.xcodeproj -target App -sdk iphonesimulator \
  -configuration Debug \
  OBJROOT="$DERIVED/Build/Intermediates.noindex" \
  SYMROOT="$DERIVED/Build/Products" CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/App.app"
xcrun simctl launch "$UDID" com.example.app
xcrun simctl io "$UDID" screenshot screenshot.png
```

Pass the same explicit UDID to every command. The FAB-10 shell trial verified
boot, build, install, and screenshot. Launch timed out under that trial's
simulator contention, and an unbounded `log stream` is not a reliable check;
do not claim those operations are proven by this skill. For bounded shell logs,
use `xcrun simctl spawn "$UDID" log stream --predicate 'subsystem == "..."'`
and stop the process explicitly.
