#!/bin/sh
# BESEDA-151: Nemotron-3 (the app's diarizer) on the system channel of every call of Mikhail's that still has
# them.asr.wav + them.asr.json. Read-only on his data: the store is read from a copy, each call is cloned
# (cp -c) one at a time. -> hyp/other/nemotron3-offline/<id>.json, hyp/all-calls/<id>.them.asr.json and
# hyp/all-calls/calls.sqlite (the store copy all_calls.py reads). all_calls.py scores them.
set -eu
cd "$(dirname "$0")"
STORE="$HOME/Library/Application Support/Beseda"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(cd diarization && nice -n 19 swift build -c release -j 2 2>&1 | tail -1)
mkdir -p hyp/other hyp/all-calls
cp "$STORE"/calls.sqlite "$STORE"/calls.sqlite-wal "$STORE"/calls.sqlite-shm hyp/all-calls/ 2>/dev/null || true

for dir in "$STORE"/calls/*/; do
    id=$(basename "$dir")
    [ -f "$dir/them.asr.wav" ] && [ -f "$dir/them.asr.json" ] || continue
    [ -f "hyp/other/nemotron3-offline/$id.json" ] && continue
    # others use this Mac: wait while free memory is under 20 %
    while [ "$(memory_pressure | awk '/free percentage/ {print $5+0}')" -lt 20 ]; do sleep 60; done
    mkdir "$work/$id"
    cp -c "$dir/them.asr.wav" "$work/$id/$id.system.wav"
    cp -c "$dir/them.asr.json" "hyp/all-calls/$id.them.asr.json"
    nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock \
        env AUDIO_DIR="$work/$id" OUTPUT_DIR="$PWD/hyp/other" VARIANTS=nemotron3-offline diarization/.build/release/Diarize
    rm -rf "${work:?}/$id"
done
