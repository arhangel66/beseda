#!/bin/sh
# Speaker counts, old vs new pipeline, on Mikhail's archived calls: most recent first, read-only on his data.
# Each call is cloned into a temp dir; the store is read from a copy. Counts only -> hyp/real-calls.jsonl.
set -eu
cd "$(dirname "$0")"
LIMIT=15
MAX_MINUTES=90
STORE="$HOME/Library/Application Support/Beseda"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cp "$STORE"/calls.sqlite* "$work/"
(cd baseline && nice -n 19 swift build -c release --product RealCalls -j 2)
mkdir -p hyp
out=hyp/real-calls.jsonl

sqlite3 "$work/calls.sqlite" \
    "select id from calls where status = 'ready' and duration_sec <= $MAX_MINUTES * 60 order by started_at desc" |
while read -r call; do
    [ "$(wc -l < "$out" 2>/dev/null || echo 0)" -ge "$LIMIT" ] && break
    dir="$STORE/calls/$call"
    for f in me.asr.wav them.asr.wav me.asr.json them.asr.json; do [ -f "$dir/$f" ] || continue 2; done
    grep -q "\"$call\"" "$out" 2>/dev/null && continue
    # others use this Mac: wait while free memory is under 20 %
    while [ "$(memory_pressure | awk '/free percentage/ {print $5+0}')" -lt 20 ]; do sleep 60; done
    mkdir "$work/$call"
    cp -c "$dir"/me.asr.wav "$dir"/them.asr.wav "$dir"/me.asr.json "$dir"/them.asr.json "$work/$call/"
    nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock baseline/.build/release/RealCalls "$work/$call" >> "$out"
    rm -rf "${work:?}/$call"
    tail -1 "$out"
done
