# Median per-word lag between a system-channel sentence and the mic words it repeats, from the kept asr.json.
import json
import re
import statistics
from difflib import SequenceMatcher
from pathlib import Path

CALLS = Path.home() / "Library/Application Support/Beseda/calls"


def norm(text: str) -> str:
    return "".join(re.findall(r"\w+", text.lower()))


def words(path: Path) -> list[dict]:
    return [w | {"n": norm(w["text"])} for s in json.loads(path.read_text())["segments"] for w in s.get("words") or [] if norm(w["text"])]


def main(call_ids: list[str]) -> None:
    for call_id in call_ids:
        folder = CALLS / call_id
        mic = words(folder / "me.asr.json")
        system = json.loads((folder / "them.asr.json").read_text())["segments"]
        lags_per_sentence = []
        for sentence in system:
            sw = [w | {"n": norm(w["text"])} for w in sentence.get("words") or [] if norm(w["text"])]
            if len({w["n"] for w in sw}) < 3:
                continue
            near = [w for w in mic if sentence["start"] - 4 <= w["start"] <= sentence["end"] + 2]
            m = SequenceMatcher(None, [w["n"] for w in sw], [w["n"] for w in near], autojunk=False)
            pairs = [(sw[b.a + k], near[b.b + k]) for b in m.get_matching_blocks() for k in range(b.size)]
            if len(pairs) / len(sw) >= 0.8:
                lags = [a["start"] - b["start"] for a, b in pairs]
                lags_per_sentence.append((round(statistics.median(lags), 2), round(min(lags), 2), round(max(lags), 2), sentence["text"][:50]))
        print(call_id, len(lags_per_sentence))
        for row in lags_per_sentence[:6]:
            print("   ", row)


if __name__ == "__main__":
    main(["20260518-110627", "20260521-110317", "20260601-154105", "20260622-065841", "20260818-190406", "20260917-164259",
          "20261006-173015", "20261016-113955", "20261008-123539", "20261013-125927", "20261019-125920"])
