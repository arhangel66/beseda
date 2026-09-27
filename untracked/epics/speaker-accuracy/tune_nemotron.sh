#!/bin/sh
# BESEDA-163: Nemotron-3 variants (diarization/Diarize: slot probabilities, cache-compression knobs, fast128 preset)
# on the system channel of every call with audio and the real benchmark files, then WeSpeaker embeddings of the
# default segments. Read-only on Mikhail's data: store copy, cp -c clones, one call at a time, under 20 % free
# memory it waits. -> hyp/other/<variant>/<id>.json; tune_nemotron.py scores them.
set -eu
cd "$(dirname "$0")"
STORE="$HOME/Library/Application Support/Beseda"
BENCHMARK="ami_ES2004a ami_IS1009a vox_asxwr vox_azisu vox_gzvkx"
VARIANTS="nemotron3-probs nemotron3-pred0.1 nemotron3-minpos0.2 nemotron3-sil3 nemotron3-fast128"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
(cd diarization && nice -n 19 swift build -c release -j 2 2>&1 | tail -1)
mkdir -p hyp/other hyp/all-calls
cp "$STORE"/calls.sqlite "$STORE"/calls.sqlite-wal "$STORE"/calls.sqlite-shm hyp/all-calls/ 2>/dev/null || true

diarize_dir() {
    # every variant, then embeddings, on the one <id>.system.wav in $1
    for variant in $VARIANTS; do
        [ -s "hyp/other/$variant/$2.json" ] && continue
        while [ "$(memory_pressure | awk '/free percentage/ {print $5+0}')" -lt 20 ]; do sleep 60; done
        nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock \
            env AUDIO_DIR="$1" OUTPUT_DIR="$PWD/hyp/other" VARIANTS="$variant" diarization/.build/release/Diarize
    done
    [ -s "hyp/other/emb-nemotron/$2.json" ] || nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock \
        env AUDIO_DIR="$1" SEGMENTS=nemotron3-probs uv run embed_segments.py
}

for id in $BENCHMARK; do
    mkdir "$work/$id"
    cp -c "data/audio/$id.system.wav" "$work/$id/"
    diarize_dir "$work/$id" "$id"
    rm -rf "${work:?}/$id"
done

for dir in "$STORE"/calls/*/; do
    id=$(basename "$dir")
    [ -f "$dir/them.asr.wav" ] && [ -f "$dir/them.asr.json" ] || continue
    mkdir "$work/$id"
    cp -c "$dir/them.asr.wav" "$work/$id/$id.system.wav"
    cp -c "$dir/them.asr.json" "hyp/all-calls/$id.them.asr.json"
    diarize_dir "$work/$id" "$id"
    rm -rf "${work:?}/$id"
done
