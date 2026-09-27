#!/bin/sh
# BESEDA-115: other local diarizers on the system channel of the 15 truth calls (copies, one at a time) and the
# real benchmark files. FluidAudio 0.17.4 variants -> hyp/other/<variant>/<id>.json, then stronger embeddings of
# the offline-t0.7 segments -> hyp/other/emb-<model>/<id>.json; peak memory per run -> hyp/other/memory.log.
# other_diarizers.py scores them.
set -eu
cd "$(dirname "$0")"
STORE="$HOME/Library/Application Support/Beseda"
CALLS="20260925-114649 20260925-111702 20260924-173649 20260924-173310 20260924-133358 20260924-110157
20260923-125419 20260923-101613 20260922-115609 20260922-084404
20260925-125945 20260924-130017 20260923-130021 20260922-125838 20260921-125925"
BENCHMARK="ami_ES2004a ami_IS1009a vox_asxwr vox_azisu vox_gzvkx"
VARIANTS="offline-t0.7 sortformer lseend-dihard3 lseend-callhome nemotron3-offline"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(cd diarization && nice -n 19 swift build -c release -j 2 2>&1 | tail -1)
mkdir -p hyp/other

wait_for_memory() {
    # others use this Mac: wait while free memory is under 20 %
    while [ "$(memory_pressure | awk '/free percentage/ {print $5+0}')" -lt 20 ]; do sleep 60; done
}

run() {
    # $1 = label for the memory log, rest = command; peak RSS from /usr/bin/time -l
    label=$1; shift
    wait_for_memory
    nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock /usr/bin/time -l "$@" 2> "$work/time.log"
    echo "$label $(awk '/maximum resident set size/ {printf "%.2f", $1/1073741824}' "$work/time.log") GB" >> hyp/other/memory.log
}

diarize_dir() {
    # every variant and embedding model on every <id>.system.wav in $1
    for variant in $VARIANTS; do
        [ -s "hyp/other/$variant/$2.json" ] && continue
        run "$variant $2" env AUDIO_DIR="$1" OUTPUT_DIR="$PWD/hyp/other" VARIANTS="$variant" diarization/.build/release/Diarize
    done
    run "embeddings $2" env AUDIO_DIR="$1" uv run embed_segments.py
}

for call in $CALLS; do
    mkdir "$work/$call"
    cp -c "$STORE/calls/$call/them.asr.wav" "$work/$call/$call.system.wav"
    diarize_dir "$work/$call" "$call"
    rm -rf "${work:?}/$call"
    echo "$call done"
done

for id in $BENCHMARK; do
    mkdir "$work/$id"
    cp -c "data/audio/$id.system.wav" "$work/$id/"
    diarize_dir "$work/$id" "$id"
    echo "$id done"
done
