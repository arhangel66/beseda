#!/usr/bin/env bash
# Full check: every test including the heavy ones, then the memory measurements that are
# safe unattended (1 h synthetic call, both paths). Run from the checkout to test.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export BESEDA_FULL_CHECK=1
nice -n 19 swift test --jobs 2 --package-path "$ROOT"
for memory_path in echo asr; do
    BESEDA_LONG_CALL_MEMORY="$memory_path" BESEDA_LONG_CALL_HOURS=1 \
        nice -n 19 swift test --jobs 2 --package-path "$ROOT" --filter peakMemoryOnASyntheticLongCall
done
