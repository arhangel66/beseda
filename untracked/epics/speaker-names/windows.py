# renders a call transcript for the model: whole call, name-bearing lines, or turn edges
import json, re
from pathlib import Path

HERE = Path(__file__).parent
PEOPLE = json.loads((HERE / "data/people.json").read_text())
NAME_PATTERN_CANONICAL = {a.lower(): name for name, aliases in PEOPLE.items() for a in aliases}
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
    if window == "clues":
        return render_clues(rows)
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


def clues(rows: list[tuple[int, float, str, str]]) -> list[dict]:
    # every line that mentions a known name: who says it, the remote voice before it and the one that answers after it
    found = []
    for i, (idx, start, speaker, text) in enumerate(rows):
        names = sorted({NAME_PATTERN_CANONICAL[m.lower()] for m in NAME_PATTERN.findall(text)})
        if not names:
            continue
        before = next((rows[j][2] for j in range(i - 1, max(-1, i - 8), -1) if rows[j][2] not in ("me", speaker)), None)
        after = next(((rows[j][2], rows[j][3]) for j in range(i + 1, min(len(rows), i + 8)) if rows[j][2] not in ("me", speaker)), None)
        found.append({"idx": idx, "start": start, "speaker": speaker, "text": text, "names": names, "before": before,
                      "after": after[0] if after else None, "after_text": after[1][:80] if after else None})
    return found


def render_clues(rows) -> str:
    lines = [f"Remote voices in this call: {', '.join(labels_of(rows))}.", "Lines where a name is said (with the remote voice that spoke last before the line, and the first remote voice that speaks after it):"]
    for c in clues(rows):
        lines.append(f"{c['idx']} {stamp(c['start'])} {c['speaker']}: {c['text'][:160]}")
        lines.append(f"    names: {', '.join(c['names'])} | remote voice before: {c['before'] or '-'} | remote voice after: {c['after'] or '-'}"
                     + (f" says: \"{c['after_text']}\"" if c['after'] else ""))
    return "\n".join(lines)


def labels_of(rows) -> list[str]:
    return sorted({speaker for _, _, speaker, _ in rows if speaker != "me"})
