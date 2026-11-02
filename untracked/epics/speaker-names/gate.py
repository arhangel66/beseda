# hyp/gate-<config>/: keeps a p4 name only if its clue line says that name and the label speaks where the cue says it should
import json, sys
from pathlib import Path

import windows

HERE = Path(__file__).parent
REACH = 8  # rows to look before/after the clue line, the same reach as windows.clues


def supported(rows, label: str, name: str, cue: str, line: int) -> bool:
    positions = [i for i, row in enumerate(rows) if row[0] == line]
    if not positions:
        return False
    i = positions[0]; speaker, text = rows[i][2], rows[i][3]
    if name not in {windows.NAME_PATTERN_CANONICAL[m.lower()] for m in windows.NAME_PATTERN.findall(text)}:
        return False
    if cue == "introduced":
        return speaker == label
    if speaker == label:
        return False
    nearby = rows[i + 1:i + 1 + REACH] if cue == "addressed" else rows[max(0, i - REACH):i]
    return any(row[2] == label for row in nearby)


def gate(config: str) -> str:
    out = HERE / "hyp" / f"gate-{config}"
    out.mkdir(parents=True, exist_ok=True)
    for path in (HERE / "hyp" / config).glob("*.json"):
        hyp = json.loads(path.read_text()); rows = windows.read_rows(hyp["call_id"])
        parsed = hyp.get("parsed") or {}
        answer = {label: (e["name"] if e["name"] != "unknown" and supported(rows, label, e["name"], e["cue"], e["line"]) else "unknown")
                  for label, e in parsed.items()} if not hyp.get("invalid") else {}
        (out / path.name).write_text(json.dumps({"call_id": hyp["call_id"], "answer": answer, "invalid": hyp.get("invalid", False),
                                                 "seconds": hyp.get("seconds"), "prompt_tokens": hyp.get("prompt_tokens")}))
    return out.name


if __name__ == "__main__":
    for config_dir in sorted((HERE / "hyp").iterdir()):
        if "__p4__" in config_dir.name and not config_dir.name.startswith(("gate-", "merge-", "vote-")):
            gate(config_dir.name)
