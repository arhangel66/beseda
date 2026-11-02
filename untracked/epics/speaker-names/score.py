# scores every hyp/<config>/ against refs/: per group and split, coverage / precision / wrong / unverified
import json, random, sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).parent
PEOPLE = json.loads((HERE / "data/people.json").read_text())
ALIASES = {alias: name for name, aliases in PEOPLE.items() for alias in aliases + [name.lower()]}


def canonical(name: str | None) -> str:
    name = (name or "").strip().strip(".").lower()
    if name in ("", "unknown", "none", "null", "?"):
        return "unknown"
    return ALIASES.get(name, name)


def outcome(predicted: str, ref_entry: dict) -> str:
    # correct | wrong | unverified | abstain | skip (echo/mixed labels are not scored)
    if ref_entry["status"] in ("echo", "mixed"):
        return "skip"
    predicted = canonical(predicted)
    truth = canonical(ref_entry["name"]) if ref_entry["status"] == "named" else "unknown"
    if predicted == "unknown":
        return "abstain"
    if truth == "unknown":
        return "unverified"
    return "correct" if predicted == truth else "wrong"


def score_config(hyp_dir: Path, calls: list[dict], refs: dict[str, dict]) -> dict[str, dict]:
    # one row per (group, split) subset plus "multi/all"; per-call outcome lists for the bootstrap
    per_call = {}
    for call in calls:
        ref = refs.get(call["id"]); path = hyp_dir / f"{call['id']}.json"
        if not ref or not path.exists():
            continue
        hyp = json.loads(path.read_text())
        answer = hyp.get("answer") or {}
        invalid = hyp.get("invalid", False) or any(label not in answer for label in call["labels"])
        outcomes = {label: ("invalid" if invalid else outcome(answer.get(label), ref["labels"][label]))
                    for label in call["labels"] if label in ref["labels"]}
        per_call[call["id"]] = {"outcomes": outcomes, "seconds": hyp.get("seconds"), "tokens": hyp.get("prompt_tokens"),
                                "segments": call["segments_per_label"], "group": call["group"], "split": call["split"]}
    rows = {}
    subsets = {"multi/tune": lambda c: c["split"] == "tune", "multi/test": lambda c: c["split"] == "test",
               "multi/all": lambda c: c["group"] == "multi", "two": lambda c: c["group"] == "two", "one": lambda c: c["group"] == "one"}
    for subset, keep in subsets.items():
        chosen = [c for c in per_call.values() if keep(c)]
        if chosen:
            rows[subset] = summarize(chosen)
    return rows


def summarize(chosen: list[dict]) -> dict:
    counts = defaultdict(int); seg_named = seg_correct = 0
    clean = exact = 0
    for c in chosen:
        for label, o in c["outcomes"].items():
            counts[o] += 1
            if o in ("correct", "wrong", "abstain") and c["segments"].get(label):
                pass
        named_labels = [l for l, o in c["outcomes"].items() if o in ("correct", "wrong", "abstain")]
        seg_named += sum(c["segments"][l] for l in named_labels)
        seg_correct += sum(c["segments"][l] for l, o in c["outcomes"].items() if o == "correct")
        clean += not any(o in ("wrong", "invalid") for o in c["outcomes"].values())
        exact += all(o == "correct" for l, o in c["outcomes"].items() if o != "skip") and bool(named_labels)
    named = counts["correct"] + counts["wrong"] + counts["abstain"]
    unknown = counts["unverified"] + sum(1 for c in chosen for l, o in c["outcomes"].items() if o == "abstain" and False)
    given = counts["correct"] + counts["wrong"]
    seconds = [c["seconds"] for c in chosen if c["seconds"]]
    tokens = [c["tokens"] for c in chosen if c["tokens"]]
    return {"calls": len(chosen), "labels_named": named, "coverage": ratio(counts["correct"], named),
            "precision": ratio(counts["correct"], given), "wrong": ratio(counts["wrong"], named),
            "unverified": counts["unverified"], "seg_coverage": ratio(seg_correct, seg_named),
            "call_clean": ratio(clean, len(chosen)), "call_exact": ratio(exact, len(chosen)),
            "invalid": counts["invalid"], "sec": round(sum(seconds) / len(seconds), 1) if seconds else None,
            "tokens": round(sum(tokens) / len(tokens)) if tokens else None,
            "coverage_ci": bootstrap(chosen)}


def ratio(a: int, b: int) -> float | None:
    return round(a / b, 3) if b else None


def bootstrap(chosen: list[dict], n: int = 500) -> str:
    rng = random.Random(0); values = []
    for _ in range(n):
        sample = [rng.choice(chosen) for _ in chosen]
        correct = sum(o == "correct" for c in sample for o in c["outcomes"].values())
        named = sum(o in ("correct", "wrong", "abstain") for c in sample for o in c["outcomes"].values())
        values.append(correct / named if named else 0)
    values.sort()
    return f"{values[int(n * 0.05)]:.2f}–{values[int(n * 0.95)]:.2f}"


def main(subset: str, out_name: str, only: str | None = None) -> None:
    calls = json.loads((HERE / "data/calls.json").read_text())
    refs = {p.stem: json.loads(p.read_text()) for p in (HERE / "refs").glob("*.json")}
    table = {}
    for hyp_dir in sorted((HERE / "hyp").iterdir()):
        if not hyp_dir.is_dir() or (only and only not in hyp_dir.name):
            continue
        rows = score_config(hyp_dir, calls, refs)
        if subset in rows:
            table[hyp_dir.name] = rows[subset]
    columns = ["calls", "labels_named", "coverage", "coverage_ci", "precision", "wrong", "unverified", "seg_coverage", "call_clean", "call_exact", "invalid", "sec", "tokens"]
    lines = [f"# {subset}", "", "| config | " + " | ".join(columns) + " |", "|---" * (len(columns) + 1) + "|"]
    for name, row in sorted(table.items(), key=lambda kv: (-(kv[1]["coverage"] or 0), kv[1]["wrong"] or 0)):
        lines.append(f"| {name} | " + " | ".join("" if row[c] is None else str(row[c]) for c in columns) + " |")
    (HERE / f"results/{out_name}.md").write_text("\n".join(lines) + "\n")
    (HERE / f"results/{out_name}.json").write_text(json.dumps(table, indent=1))
    print("\n".join(lines))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "multi/tune", sys.argv[2] if len(sys.argv) > 2 else "tune", sys.argv[3] if len(sys.argv) > 3 else None)
