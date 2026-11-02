# renders a call transcript for the model: whole call, name-bearing lines, or turn edges
import json, re
from pathlib import Path

HERE = Path(__file__).parent
PEOPLE = json.loads((HERE / "data/people.json").read_text())
NAME_PATTERN = re.compile(r"\b(" + "|".join(sorted({a for aliases in PEOPLE.values() for a in aliases}, key=len, reverse=True)) + r")\b", re.I)


def read_rows(call_id: str) -> list[tuple[int, float, str, str]]:
    rows = []
    for row in (HERE / f"data/transcripts/{call_id}.tsv").read_text().splitlines():
        idx, start, speaker, text = row.split("\t", 3)
        rows.append((int(idx), float(start), speaker, text))
    return rows


def stamp(start: float) -> str:
    return f"[{int(start) // 60:02d}:{int(start) % 60:02d}]"


def render(rows: list[tuple[int, float, str, str]], window: str) -> str:
    # window: full | names | edges<N> (turns cut to first N and last N chars)
    if window == "full":
        return "\n".join(f"{idx} {stamp(start)} {speaker}: {text}" for idx, start, speaker, text in rows)
    if window == "names":
        keep = {j for i, (_, _, _, text) in enumerate(rows) if NAME_PATTERN.search(text) for j in range(i - 3, i + 4)}
        picked, previous = [], -1
        for i in sorted(j for j in keep if 0 <= j < len(rows)):
            if i != previous + 1:
                picked.append("...")
            idx, start, speaker, text = rows[i]
            picked.append(f"{idx} {stamp(start)} {speaker}: {text}"); previous = i
        return "\n".join(picked)
    if window.startswith("edges"):
        edge = int(window[5:])
        turns: list[list] = []
        for idx, start, speaker, text in rows:
            if turns and turns[-1][2] == speaker:
                turns[-1][3] += " " + text
            else:
                turns.append([idx, start, speaker, text])
        out = []
        for idx, start, speaker, text in turns:
            if len(text) > 2 * edge:
                text = text[:edge] + " … " + text[-edge:]
            out.append(f"{idx} {stamp(start)} {speaker}: {text}")
        return "\n".join(out)
    raise ValueError(window)


def labels_of(rows) -> list[str]:
    return sorted({speaker for _, _, speaker, _ in rows if speaker != "me"})
