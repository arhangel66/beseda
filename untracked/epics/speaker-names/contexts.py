# builds the context block for a call from the roster and the references of EARLIER calls only
import json
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).parent
PEOPLE = json.loads((HERE / "data/people.json").read_text())
ALIASES = {alias: name for name, aliases in PEOPLE.items() for alias in aliases + [name.lower()]}
ME = {"mikhail", "michael", "michail", "misha", "михаил", "миша"}


def canonical(name: str) -> str | None:
    key = name.strip().lower()
    return None if key in ME else ALIASES.get(key, name.strip())


def ordinal(n: int) -> str:
    return f"{n}{'th' if 10 <= n % 100 <= 20 else {1: 'st', 2: 'nd', 3: 'rd'}.get(n % 10, 'th')}"


def load_refs() -> dict[str, dict]:
    return {p.stem: json.loads(p.read_text()) for p in (HERE / "refs").glob("*.json")}


def earlier(call: dict, calls: list[dict], refs: dict[str, dict]) -> list[dict]:
    # calls before this one that have a reference, oldest first
    return [c for c in calls if c["started_at"] < call["started_at"] and c["id"] in refs]


def prev_block(call: dict, calls: list[dict], refs: dict[str, dict]) -> str:
    same_class = [c for c in earlier(call, calls, refs) if (c["group"] == "one") == (call["group"] == "one")]
    if not same_class:
        return ""
    last = same_class[-1]
    names = sorted({e["name"] for e in refs[last["id"]]["labels"].values() if e["status"] in ("named", "mixed")})
    if not names:
        return ""
    return f"In the previous call of this kind ({last['started_at'][:10]}) the other people were: {', '.join(names)}."


def notes_block(call: dict, calls: list[dict], refs: dict[str, dict]) -> str:
    # per person: how often present, usual place in the daily order, topics, who is only mentioned
    present, positions, topics, mentioned = Counter(), defaultdict(list), defaultdict(list), Counter()
    seen_calls = earlier(call, calls, refs)
    for c in seen_calls:
        ref = refs[c["id"]]
        named = {label: canonical(e["name"]) for label, e in ref["labels"].items() if e["status"] in ("named", "mixed")}
        for label, name in named.items():
            if not name:
                continue
            present[name] += 1
            if c["group"] == "multi" and label in ref.get("speaking_order", []):
                positions[name].append(ref["speaking_order"].index(label) + 1)
            if topic := ref.get("topics_per_label", {}).get(label):
                topics[name].append(topic[:70].rsplit(",", 1)[0] if len(topic) > 70 else topic)
        for raw in ref.get("people_named_in_text", []):
            name = canonical(raw)
            if name and name not in named.values():
                mentioned[name] += 1
    if not seen_calls:
        return ""
    lines = [f"What earlier calls ({len(seen_calls)}) taught about the people:"]
    for name, count in present.most_common():
        parts = [f"on {count} earlier calls"]
        if positions[name]:
            parts.append(f"usually gives the {ordinal(Counter(positions[name]).most_common(1)[0][0])} update in the daily")
        if topics[name]:
            parts.append("recent topics: " + "; ".join(topics[name][-2:]))
        lines.append(f"- {name}: " + ", ".join(parts))
    for name, count in mentioned.most_common():
        if present[name] == 0 and count >= 2:
            lines.append(f"- {name}: never a speaker so far, only mentioned by others ({count} calls)")
    return "\n".join(lines)


def build(context: str, call: dict, calls: list[dict], refs: dict[str, dict]) -> str:
    roster = (HERE / "data/roster.txt").read_text().strip()
    blocks = {"none": [], "roster": [roster], "prev": [prev_block(call, calls, refs)],
              "notes": [notes_block(call, calls, refs)], "roster+notes": [roster, notes_block(call, calls, refs)],
              "roster+prev": [roster, prev_block(call, calls, refs)]}[context]
    return "\n\n".join(b for b in blocks if b)


if __name__ == "__main__":
    calls = json.loads((HERE / "data/calls.json").read_text())
    refs = load_refs()
    last_daily = [c for c in calls if c["group"] == "multi"][-1]
    print(build("roster+notes", last_daily, calls, refs))
    print("---"); print(build("prev", last_daily, calls, refs))
