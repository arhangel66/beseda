#!/bin/sh
# Rerun the whole benchmark: baseline -> diarization variants -> ASR engines, heavy runs one at a time.
set -eu
cd "$(dirname "$0")"
LOCK="nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock"

nice -n 19 sh baseline/run.sh  # takes the lock itself around the model run
(cd diarization && nice -n 19 swift build -c release)
for variants in offline-t0.5 sortformer lseend-dihard3,lseend-callhome offline-t0.6,offline-t0.7,offline-t0.8 \
    offline-t0.7-minseg0.3,offline-t0.7-known-count; do
    VARIANTS=$variants $LOCK diarization/.build/release/Diarize
done
nice -n 19 uv run diarization/assemble.py
(cd asr && $LOCK uv run run.py)
