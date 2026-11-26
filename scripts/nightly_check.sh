#!/usr/bin/env bash
# Nightly full check of main in its own worktree, started by the LaunchAgent
# app.beseda.nightly-check (install: scripts/install_nightly_check.sh). Skips a busy Mac.
set -uo pipefail

REPO="/Users/mikhail/w/learning/beseda"
WORKTREE="$HOME/Library/Caches/beseda-nightly-check"
echo "=== $(date '+%F %T')"

free_percent="$(memory_pressure -Q | sed -n 's/.*free percentage: \([0-9]*\)%.*/\1/p')"
if [ "${free_percent:-0}" -lt 20 ]; then
    echo "skipped: ${free_percent:-?} % memory free"
    exit 0
fi
# a Beseda call recording holds its microphone file open
if lsof -c Beseda 2>/dev/null | grep -q '\.raw\.wav'; then
    echo "skipped: a call is recording"
    exit 0
fi

notify_failure() {
    echo "FAILED: $1"
    bb notify --route digest --source beseda-nightly-check --dedupe-key beseda-nightly-check \
        --title "Beseda nightly check failed" --action "$1; see ~/Library/Logs/beseda-nightly-check.log"
    exit 1
}

git -C "$REPO" fetch -q origin main 2>/dev/null || true
if [ ! -d "$WORKTREE" ]; then
    git -C "$REPO" worktree add -q --detach "$WORKTREE" main || notify_failure "could not create the worktree"
fi
# detached, so the worktree never holds main and the main checkout can always switch to it
git -C "$WORKTREE" checkout -q --detach main || notify_failure "could not check out main"
echo "main $(git -C "$WORKTREE" rev-parse HEAD)"
nice -n 19 "$WORKTREE/scripts/full_check.sh" || notify_failure "full check failed on main $(git -C "$WORKTREE" rev-parse --short HEAD)"
echo "passed"
