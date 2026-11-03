# turns raw Jev answers into hyp dirs: a name only when its confidence clears the threshold
import json
from pathlib import Path

HERE = Path(__file__).parent


def threshold(window: str, minimum: float) -> str:
    name = f"jev-1.13__{window}__none__c{int(minimum * 100)}__nothink"
    out = HERE / "hyp" / name
    out.mkdir(parents=True, exist_ok=True)
    for path in (HERE / "hyp" / f"jev-1.13__{window}__raw").glob("*.json"):
        record = json.loads(path.read_text()); answers = record["reply"]["answers"]
        answer = {label: (a["choice"] if a["confidence"] >= minimum else "unknown") for label, a in answers.items()}
        (out / path.name).write_text(json.dumps({"call_id": record["call_id"], "answer": answer, "seconds": record["seconds"],
                                                 "prompt_tokens": record["reply"]["usage"]["input_tokens"]}))
    return name


if __name__ == "__main__":
    for window in ("edges100", "full"):
        for minimum in (0.0, 0.5, 0.7, 0.8, 0.9, 0.95):
            threshold(window, minimum)
