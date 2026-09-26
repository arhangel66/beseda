#!/bin/sh
# BESEDA-79: diarizer segments + embeddings + levels of the 1:1 calls and the 20260923-130021 daily (copies,
# one call at a time), and of the benchmark system channels (BESEDA-82: also t0.80 as `system80`) -> hyp/extra/*.json; ../extra_speakers.py reads them.
set -eu
cd "$(dirname "$0")"
STORE="$HOME/Library/Application Support/Beseda"
CALLS="20260925-114649 20260925-111702 20260924-173649 20260924-173310 20260924-133358 20260924-110157
20260923-125419 20260923-101613 20260922-115609 20260922-084404 20260923-130021
20260925-125945 20260924-130017 20260922-125838 20260921-125925"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(cd baseline && nice -n 19 swift build -c release --product RealCalls -j 2 2>&1 | tail -1)
mkdir -p hyp/extra

wait_for_memory() {
    # others use this Mac: wait while free memory is under 20 %
    while [ "$(memory_pressure | awk '/free percentage/ {print $5+0}')" -lt 20 ]; do sleep 60; done
}

for call in $CALLS; do
    [ -s "hyp/extra/$call.json" ] && continue
    wait_for_memory
    mkdir "$work/$call"
    cp -c "$STORE/calls/$call"/me.asr.wav "$STORE/calls/$call"/them.asr.wav "$work/$call/"
    nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock baseline/.build/release/RealCalls "$work/$call" dump > "hyp/extra/$call.json"
    rm -rf "${work:?}/$call"
    echo "$call done"
done

for wav in data/audio/*.system.wav; do
    id=$(basename "$wav" .system.wav)
    [ -s "hyp/extra/bench_$id.json" ] && continue
    wait_for_memory
    nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock baseline/.build/release/RealCalls "$wav" dump > "hyp/extra/bench_$id.json"
    echo "$id done"
done
