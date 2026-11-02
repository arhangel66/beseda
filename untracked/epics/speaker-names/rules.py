# no-model baseline: votes from name mentions (address → next remote voice, thanks → previous remote voice), written as a hyp dir
import json, re, sys
from collections import defaultdict
from pathlib import Path

import windows

HERE = Path(__file__).parent
THANKS = re.compile(r"\b(thank|thanks|спасибо)\b", re.I)
GREETING = re.compile(r"\b(hi|hello|hey|привет|здравствуй)\b", re.I)
HANDOVER = re.compile(r"\b(can you|could you|please|your turn|go ahead|you can go|continue|next|давай|расскаж|твоя очередь)\b", re.I)
FILLER = r"(?:\b(?:uh|um|so|okay|ok|anyway|and|yeah|yes|hi|hello|hey|but|now|привет|ну|так|окей)\b[\s,.]*)*"
YOU = re.compile(r"\b(you|your|yours|ты|тебе|тебя|твой|твоя|вы|вам|вас)\b|\?", re.I)


def is_address(text: str, alias: str, version: int = 2) -> bool:
    # the name in a vocative position: opening the line, set off by commas, or closing it
    name = re.escape(alias)
    if re.match(rf"^\W*{FILLER}{name}\b[\s,.!?]", text, re.I):
        return version < 4 or bool(YOU.search(text) or HANDOVER.search(text) or len(text.split()) <= 4)
    if re.search(rf",\s*{FILLER}{name}\b\s*[,.!?]?\s*$", text, re.I):
        return True
    if re.search(rf"[,.]\s*{FILLER}{name}\b\s*,", text, re.I) and YOU.search(text):
        return True
    return bool(re.search(rf"\b{name}\b\s*,", text, re.I) and YOU.search(text))


def vote(rows, version: int) -> dict[str, str]:
    votes: dict[str, dict[str, float]] = defaultdict(lambda: defaultdict(float))
    not_self: set[tuple[str, str]] = set()
    for c in windows.clues(rows):
        if len(c["names"]) != 1:
            continue
        name = c["names"][0]; text = c["text"]; speaker = c["speaker"]
        alias = next(m for m in windows.NAME_PATTERN.findall(text) if windows.NAME_PATTERN_CANONICAL[m.lower()] == name)
        if speaker != "me":
            not_self.add((speaker, name))
        thanked = bool(re.search(rf"\b(thank|thanks|спасибо)\b\W+(\w+\W+){{0,3}}{re.escape(alias)}\b", text, re.I)) if version >= 4 else bool(THANKS.search(text))
        if thanked and c["before"]:
            votes[c["before"]][name] += 1
        elif version == 1 and ADDRESS_V1.search(text) and c["after"]:
            votes[c["after"]][name] += 1
        elif version >= 2 and is_address(text, alias, version) and c["after"]:
            votes[c["after"]][name] += 0.5 if version >= 4 and GREETING.search(text) and not HANDOVER.search(text) else 1
    answer = {}
    taken = set()
    if version >= 3:
        # a voice saying a name counts against it being that person, but diarization glues lines: a penalty, not a veto
        for label, name in not_self:
            votes[label][name] -= 1
        pairs = sorted(((score, label, name) for label, by_name in votes.items() for name, score in by_name.items() if score > 0), reverse=True)
    else:
        pairs = sorted(((score, label, name) for label, by_name in votes.items() for name, score in by_name.items() if (label, name) not in not_self), reverse=True)
    for score, label, name in pairs:
        if label in answer or name in taken:
            continue
        if version >= 4:
            # a strict winner both ways: no other name ties on this label, no other label ties on this name
            rival_names = [s for n, s in votes[label].items() if n != name and n not in taken]
            rival_labels = [votes[l][name] for l in votes if l != label and l not in answer and name in votes[l]]
            if (rival_names and max(rival_names) >= score) or (rival_labels and max(rival_labels) >= score):
                continue
        answer[label] = name; taken.add(name)
    return {label: answer.get(label, "unknown") for label in windows.labels_of(rows)}


ADDRESS_V1 = re.compile(r"\b(can you|could you|would you|please|your turn|go ahead|you can go|you go|next|what about|how about|are you|do you|did you|have you|hi|hello|hey|привет|здравствуй|давай|расскаж|можешь|пожалуйста|твоя очередь)\b|\?", re.I)


def main(version: int) -> None:
    out = HERE / f"hyp/rules{version}__clues__none__-__nothink"; out.mkdir(parents=True, exist_ok=True)
    for call in json.loads((HERE / "data/calls.json").read_text()):
        rows = windows.read_rows(call["id"])
        (out / f"{call['id']}.json").write_text(json.dumps({"call_id": call["id"], "answer": vote(rows, version), "invalid": False, "seconds": 0.01, "prompt_tokens": 0}))


if __name__ == "__main__":
    main(int(sys.argv[1]) if len(sys.argv) > 1 else 2)
