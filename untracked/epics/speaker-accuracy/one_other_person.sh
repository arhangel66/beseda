#!/bin/sh
# BESEDA-104: the app's «one other person» question on the 15 truth calls, bundled model only (no cloud).
# Read-only: the store is read from a copy; llama-server runs with the app's arguments on its own port.
set -eu
cd "$(dirname "$0")"
STORE="$HOME/Library/Application Support/Beseda"
RUNTIME="$STORE/runtime"
PORT=8744
CALLS="20260925-114649 20260925-111702 20260924-173649 20260924-173310 20260924-133358 20260924-110157
20260923-125419 20260923-101613 20260922-115609 20260922-084404
20260925-125945 20260924-130017 20260923-130021 20260922-125838 20260921-125925"

work=$(mktemp -d)
cp "$STORE"/calls.sqlite* "$work/"
# others use this Mac: wait while free memory is under 20 %
while [ "$(memory_pressure | awk '/free percentage/ {print $5+0}')" -lt 20 ]; do sleep 60; done
nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock sh -c '
    "$1/llama/b10819/llama-server" -m "$1/models/gemma-4-E4B-it-Q4_0.gguf" --host 127.0.0.1 --port '$PORT' \
        -c 65536 -np 1 -ngl 99 -fa on --jinja --no-ui > "$2/server.log" 2>&1 &
    server=$!
    trap "kill $server; rm -rf \"$2\"" EXIT
    until curl -sf http://127.0.0.1:'$PORT'/health > /dev/null; do sleep 2; done
    (while sleep 20; do ps -o rss= -p $server | awk "{printf \"llama-server RSS %.1f GB\\n\", \$1/1048576}" >&2; done) &
    watcher=$!
    cd ../../..
    BESEDA_ONE_OTHER_PERSON_DB="$2/calls.sqlite" BESEDA_ONE_OTHER_PERSON_CALLS="$3" \
    BESEDA_ONE_OTHER_PERSON_SERVER=http://127.0.0.1:'$PORT'/v1 \
        swift test --jobs 2 --filter oneOtherPersonOnRealCallsWithTheBundledModel 2>&1 | grep ONE_OTHER_PERSON
    kill $watcher
' _ "$RUNTIME" "$work" "$(echo $CALLS)"
