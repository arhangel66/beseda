#!/bin/sh
# BESEDA-84: `them` count of the 15 truth calls through the app's code path (copies, one call at a time)
# -> stdout, one JSON line per call; compare with the winner column of results/short-reply-merge.md.
set -eu
cd "$(dirname "$0")"
STORE="$HOME/Library/Application Support/Beseda"
CALLS="20260925-114649 20260925-111702 20260924-173649 20260924-173310 20260924-133358 20260924-110157
20260923-125419 20260923-101613 20260922-115609 20260922-084404
20260925-125945 20260924-130017 20260923-130021 20260922-125838 20260921-125925"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(cd baseline && nice -n 19 swift build -c release --product AppMerge -j 2 2>&1 | tail -1)

for call in $CALLS; do
    # others use this Mac: wait while free memory is under 20 %
    while [ "$(memory_pressure | awk '/free percentage/ {print $5+0}')" -lt 20 ]; do sleep 60; done
    mkdir "$work/$call"
    cp -c "$STORE/calls/$call"/them.asr.wav "$STORE/calls/$call"/them.asr.json "$work/$call/"
    nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock baseline/.build/release/AppMerge "$work/$call"
    rm -rf "${work:?}/$call"
done
