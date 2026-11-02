#!/bin/bash
# runs one stage of run_local.py alone (lock + nice), scores it, and tells Mikhail; usage: night.sh <stage> <score subset> <result name>
set -u
cd "$(dirname "$0")"
stage="$1"; subset="${2:-multi/tune}"; name="${3:-$1}"
lockf -t 0 /tmp/beseda-speaker-names.lock nice -n 19 python3 run_local.py "$stage" >> "night-$stage.log" 2>&1 \
  || { echo "run failed or another run holds the lock"; exit 1; }
errors=$(grep -c "^.\{8\} ERROR" run.log || true)
python3 score.py "$subset" "$name" > /dev/null
head -8 "results/$name.md"
bb notify --level digest --source speaker-names --action "read results/$name.md" \
  "speaker-names: stage $stage done, errors in run.log: $errors. Top: $(sed -n 5p "results/$name.md" | cut -c1-160)" 2>/dev/null || true
