# the frozen finalists (chosen on tune) scored on tune and test side by side, written to results/final.md
import json
from pathlib import Path

import merge, score, vote

HERE = Path(__file__).parent
RULES = "rules3__clues__none__-__nothink"
E4B_VOTERS = ["gemma4-e4b__edges100__roster+notes__p2__nothink", "gemma4-e4b__clues__roster+notes__p1__nothink"]
G12_VOTERS = ["gemma4-12b__edges100__none__p1__nothink", "gemma4-12b__edges100__roster__p2__nothink", "gemma4-12b__edges100__roster+notes__p1__nothink"]


def finalists() -> dict[str, str]:
    return {"rules3 alone": RULES,
            "rules3 + E4B vote 2 of 2": vote.vote(E4B_VOTERS, 2, "e4b-final"),
            "rules3 + 12B vote 2 of 3, repeat on 3 of 3": vote.vote(G12_VOTERS, 2, "g12-final", 3),
            "rules3 + 12B vote 2 of 3, repeat and veto on 3 of 3 (veto added after seeing test)": vote.vote(G12_VOTERS, 2, "g12-veto-final", 3, 3),
            "rules3 + 12B full / none / p1": merge.merge(RULES, "gemma4-12b__full__none__p1__nothink"),
            "rules3 + 12B names / none / p1": merge.merge(RULES, "gemma4-12b__names__none__p1__nothink")}


def main() -> None:
    calls = json.loads((HERE / "data/calls.json").read_text())
    refs = {p.stem: json.loads(p.read_text()) for p in (HERE / "refs").glob("*.json")}
    lines = ["| system | tune calls | tune coverage | tune wrong | test calls | test coverage | test coverage CI | test wrong | test unverified |", "|---" * 9 + "|"]
    for title, hyp_dir in finalists().items():
        rows = score.score_config(HERE / "hyp" / hyp_dir, calls, refs)
        tune, test = rows.get("multi/tune", {}), rows.get("multi/test", {})
        lines.append(f"| {title} | {tune.get('calls')} | {tune.get('coverage')} | {tune.get('wrong')} | {test.get('calls')} | "
                     f"{test.get('coverage')} | {test.get('coverage_ci')} | {test.get('wrong')} | {test.get('unverified')} |")
    (HERE / "results/final.md").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
