# Jev 1.13 (TypeSafe System One via OpenRouter): one Choice question per them-N label, answers with probabilities
import json, sys, time, urllib.request
from pathlib import Path

import windows
from run_local import openrouter_key
from score import FAST

HERE = Path(__file__).parent
URL = "https://openrouter.ai/api/v1/systemone"
PEOPLE = json.loads((HERE / "data/people.json").read_text())


def questions_for(labels: list[str]) -> dict:
    # who each remote voice is, judged only by name clues in the transcript
    questions = {}
    for label in labels:
        criteria = {name: f"{label} is {name}: someone says the name {name} (or a speech-recognition garble of it such as "
                          f"{', '.join(PEOPLE[name][:4])}) to address {label}, and {label} is the voice that answers; or someone thanks "
                          f"{name} right after {label} spoke; or {label} introduces itself as {name}" for name in PEOPLE}
        criteria["unknown"] = f"No line in the transcript ties a name to {label}: nobody addresses, thanks or introduces {label} by name"
        questions[label] = {"type": "choice", "criteria": criteria,
                            "instructions": f"In this call transcript \"me\" is Mikhail; them-1, them-2, ... are other voices from a speaker diarizer. "
                                            f"Who is the voice {label}? Decide only from name clues in the lines: a name said to someone and the next "
                                            f"voice that answers, thanks after a voice finished, a self-introduction. Topics and roles are not clues."}
    return questions


def ask(call_id: str, window: str) -> dict:
    rows = windows.read_rows(call_id)
    labels = windows.labels_of(rows)
    body = {"model": "typesafe/jev-1.13", "state": windows.render(rows, window), "questions": questions_for(labels)}
    request = urllib.request.Request(URL, json.dumps(body).encode(), {"Content-Type": "application/json", "Authorization": f"Bearer {openrouter_key()}"})
    started = time.time()
    reply = json.load(urllib.request.urlopen(request, timeout=300))
    return {"call_id": call_id, "seconds": round(time.time() - started, 1), "reply": reply}


def run(window: str, call_ids: list[str]) -> None:
    out = HERE / "hyp" / f"jev-1.13__{window}__raw"
    out.mkdir(parents=True, exist_ok=True)
    for call_id in call_ids:
        path = out / f"{call_id}.json"
        if path.exists():
            continue
        try:
            record = ask(call_id, window)
        except Exception as error:
            print("ERROR", call_id, error, getattr(error, "read", lambda: b"")()[:300]); continue
        path.write_text(json.dumps(record, ensure_ascii=False, indent=1))
        answers = record["reply"].get("answers", {})
        print(call_id, record["seconds"], {l: (a.get("choice"), round(a.get("confidence", 0), 2)) for l, a in answers.items()}, flush=True)


if __name__ == "__main__":
    run(sys.argv[1] if len(sys.argv) > 1 else "edges100", sys.argv[2:] or ["20260907-172950"])
