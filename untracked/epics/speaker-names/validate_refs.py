# checks every refs/<id>.json against the rubric: labels match, names canonical or new, evidence lines exist and carry the name
import json, sys
from pathlib import Path

HERE = Path(__file__).parent
PEOPLE = json.loads((HERE / "data/people.json").read_text())
ALIASES = {alias: name for name, aliases in PEOPLE.items() for alias in aliases + [name.lower()]}
STATUSES = {"named", "unknown", "echo", "mixed"}


def read_lines(call_id: str) -> dict[int, tuple[str, str]]:
    lines = {}
    for row in (HERE / f"data/transcripts/{call_id}.tsv").read_text().splitlines():
        idx, _, speaker, text = row.split("\t", 3)
        lines[int(idx)] = (speaker, text)
    return lines


def problems(call: dict, ref: dict) -> list[str]:
    out = []
    if set(ref.get("labels", {})) != set(call["labels"]):
        out.append(f"labels {sorted(ref.get('labels', {}))} != {call['labels']}")
    lines = read_lines(call["id"])
    for label, entry in ref.get("labels", {}).items():
        status, name = entry.get("status"), entry.get("name")
        if status not in STATUSES:
            out.append(f"{label}: bad status {status!r}")
        if status in ("named", "mixed"):
            if not name or name == "unknown":
                out.append(f"{label}: {status} without a name")
            elif name.lower() not in ALIASES:
                out.append(f"{label}: new person {name!r} (not in people.json)")
            cited = [e for e in entry.get("evidence", []) if e.get("idx") in lines]
            if len(cited) != len(entry.get("evidence", [])):
                out.append(f"{label}: evidence idx not in transcript")
            aliases = [a for a in PEOPLE.get(ALIASES.get((name or "").lower(), ""), []) + [(name or "").lower()]]
            if not any(any(a in lines[e["idx"]][1].lower() for a in aliases) for e in cited):
                out.append(f"{label}: no cited line contains {name!r}")
        if status == "unknown" and name != "unknown":
            out.append(f"{label}: unknown with name {name!r}")
    return out


def main() -> None:
    calls = {c["id"]: c for c in json.loads((HERE / "data/calls.json").read_text())}
    missing, bad = [], {}
    for call_id, call in calls.items():
        path = HERE / f"refs/{call_id}.json"
        if not path.exists():
            missing.append(call_id); continue
        try:
            ref = json.loads(path.read_text())
        except json.JSONDecodeError as error:
            bad[call_id] = [f"invalid json: {error}"]; continue
        if found := problems(call, ref):
            bad[call_id] = found
    print(f"{len(calls) - len(missing)} refs, {len(missing)} missing, {len(bad)} with problems")
    for call_id, found in bad.items():
        print(call_id, *found, sep="\n  ")
    if missing and "-v" in sys.argv:
        print("missing:", *missing)


if __name__ == "__main__":
    main()
