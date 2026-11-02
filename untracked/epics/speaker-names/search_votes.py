# tries every 2..4-config vote over the configs complete on tune, prints the best by coverage with wrong <= 5 %
import itertools, json, shutil
from pathlib import Path

import score, vote

HERE = Path(__file__).parent
POOL = ["gemma4-12b__edges100__none__p1__nothink", "gemma4-12b__edges100__roster__p2__nothink", "gemma4-12b__edges100__roster+notes__p1__nothink",
        "gemma4-e4b__edges100__roster+notes__p2__nothink", "gemma4-e4b__edges100__none__p1__nothink",
        "gemma4-e4b__clues__roster+notes__p1__nothink", "gemma4-e4b__names__roster__p1__nothink"]


def main(subset: str) -> None:
    calls = json.loads((HERE / "data/calls.json").read_text())
    refs = {p.stem: json.loads(p.read_text()) for p in (HERE / "refs").glob("*.json")}
    found = []
    for size in (2, 3, 4):
        for combo in itertools.combinations(POOL, size):
            for need in range(2, size + 1):
                name = vote.vote(list(combo), need, "search")
                row = score.score_config(HERE / "hyp" / name, calls, refs).get(subset)
                shutil.rmtree(HERE / "hyp" / name)
                if row and row["calls"] == 17:
                    found.append((row["coverage"], -row["wrong"], need, combo, row))
    found.sort(reverse=True)
    for cov, _, need, combo, row in [f for f in found if f[4]["wrong"] <= 0.05][:10]:
        print(f"{cov} wrong={row['wrong']} ci={row['coverage_ci']} {need}of{len(combo)}: " + " + ".join(c.replace('__nothink', '') for c in combo))


if __name__ == "__main__":
    main("multi/tune")
