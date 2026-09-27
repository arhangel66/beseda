#!/bin/sh
# BESEDA-131: the app's old diarizer (offline t0.70) and its new one (Nemotron-3 offline) on the system channel of
# the 15 truth calls (copies, one at a time) and the real benchmark -> hyp/other/<variant>/<id>.json, peak memory
# per run -> hyp/other/memory.log. nemotron_switch.py scores them with and without the 6 s rule.
set -eu
cd "$(dirname "$0")"
STORE="$HOME/Library/Application Support/Beseda"
CALLS="20260925-114649 20260925-111702 20260924-173649 20260924-173310 20260924-133358 20260924-110157
20260923-125419 20260923-101613 20260922-115609 20260922-084404
20260925-125945 20260924-130017 20260923-130021 20260922-125838 20260921-125925"
BENCHMARK="ami_ES2004a ami_IS1009a vox_asxwr vox_azisu vox_gzvkx"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(cd diarization && nice -n 19 swift build -c release -j 2 2>&1 | tail -1)
mkdir -p hyp/other

run() {
    # $1 = variant, $2 = file id, $3 = dir holding <id>.system.wav; waits while free memory is under 20 %
    while [ "$(memory_pressure | awk '/free percentage/ {print $5+0}')" -lt 20 ]; do sleep 60; done
    nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock /usr/bin/time -l \
        env AUDIO_DIR="$3" OUTPUT_DIR="$PWD/hyp/other" VARIANTS="$1" diarization/.build/release/Diarize 2> "$work/time.log"
    echo "$1 $2 $(awk '/maximum resident set size/ {printf "%.2f", $1/1073741824}' "$work/time.log") GB" >> hyp/other/memory.log
}

for id in $CALLS $BENCHMARK; do
    mkdir "$work/$id"
    case " $BENCHMARK " in
        *" $id "*) cp -c "data/audio/$id.system.wav" "$work/$id/" ;;
        *) cp -c "$STORE/calls/$id/them.asr.wav" "$work/$id/$id.system.wav" ;;
    esac
    for variant in offline-t0.7 nemotron3-offline; do
        run "$variant" "$id" "$work/$id"
    done
    rm -rf "${work:?}/$id"
done
