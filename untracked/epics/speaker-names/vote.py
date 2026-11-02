# hyp/vote-<k>of<n>-<tag>/: rules3 names fixed, an open label gets a name only if >= k of the given model configs agree on it
import json
from collections import Counter
from pathlib import Path

from score import canonical

HERE = Path(__file__).parent
RULES = "rules3__clues__none__-__nothink"


def vote(configs: list[str], need: int, tag: str, repeat_need: int | None = None, veto_need: int | None = None) -> str:
    # repeat_need: votes needed to give a label a name the rules already placed (one person split over two labels)
    out = HERE / "hyp" / f"vote-{need}of{len(configs)}-{tag}"
    out.mkdir(parents=True, exist_ok=True)
    for rules_path in (HERE / "hyp" / RULES).glob("*.json"):
        answers = [json.loads(p.read_text()) for c in configs if (p := HERE / "hyp" / c / rules_path.name).exists()]
        if len(answers) < len(configs):
            continue
        rules = json.loads(rules_path.read_text())["answer"]
        taken = {canonical(n) for n in rules.values() if n != "unknown"}
        answer = {}
        for label, name in rules.items():
            votes = Counter(canonical((a.get("answer") or {}).get(label)) for a in answers if not a.get("invalid"))
            votes.pop("unknown", None)
            if name != "unknown":
                # veto_need voters naming someone else take the rules' name back to unknown
                against = sum(n for v, n in votes.items() if v != canonical(name))
                answer[label] = "unknown" if veto_need and against >= veto_need else name; continue
            best = votes.most_common(1)
            enough = best and best[0][1] >= (need if best[0][0] not in taken else (repeat_need or len(configs) + 1))
            answer[label] = best[0][0] if enough else "unknown"
        (out / rules_path.name).write_text(json.dumps({"call_id": rules_path.stem, "answer": answer}))
    return out.name


if __name__ == "__main__":
    e4b = ["gemma4-e4b__edges100__roster+notes__p2__nothink", "gemma4-e4b__edges100__none__p1__nothink",
           "gemma4-e4b__clues__roster+notes__p1__nothink", "gemma4-e4b__names__roster__p1__nothink"]
    for need in (2, 3):
        vote(e4b, need, "e4b4")
    vote(e4b[:3], 2, "e4b3")
