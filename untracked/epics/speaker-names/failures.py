# prints, for one config, every scored label on a call set: reference vs prediction
import json, sys
from pathlib import Path
from score import outcome, FAST, canonical

HERE = Path(__file__).parent


def main(config: str, call_ids: set[str] | None) -> None:
    calls = json.loads((HERE / "data/calls.json").read_text())
    for call in calls:
        if call_ids and call["id"] not in call_ids:
            continue
        path = HERE / "hyp" / config / f"{call['id']}.json"
        if not path.exists():
            continue
        hyp = json.loads(path.read_text()); ref = json.loads((HERE / f"refs/{call['id']}.json").read_text())
        cells = []
        for label in call["labels"]:
            e = ref["labels"][label]; pred = (hyp.get("answer") or {}).get(label)
            o = "INVALID" if hyp.get("invalid") else outcome(pred, e)
            truth = e["name"] if e["status"] == "named" else e["status"]
            mark = {"correct": "✓", "wrong": "✗", "abstain": "·", "unverified": "?", "skip": "s"}.get(o, "!")
            cells.append(f"{label}: {truth} → {canonical(pred)} {mark}")
        print(call["id"], " | ".join(cells))


if __name__ == "__main__":
    main(sys.argv[1], FAST if len(sys.argv) < 3 else None)
