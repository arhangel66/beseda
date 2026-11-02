# hyp/merge-<rules>+<config>/: the rules' names where they have one, the model's answer for the rest
import json, sys

from score import canonical
from pathlib import Path

HERE = Path(__file__).parent


def merge(rules_dir: str, config: str) -> str:
    out = HERE / "hyp" / f"merge-{rules_dir.split('__')[0]}+{config}"
    out.mkdir(parents=True, exist_ok=True)
    for path in (HERE / "hyp" / config).glob("*.json"):
        model = json.loads(path.read_text()); rules = json.loads((HERE / "hyp" / rules_dir / path.name).read_text())
        taken = {canonical(name) for name in rules["answer"].values() if name != "unknown"}
        # an invalid model reply leaves the rules' answer alone instead of failing the whole call
        model_answer = {} if model.get("invalid") else (model.get("answer") or {})
        # the model fills only what the rules left open, and may not reuse a person the rules already placed
        answer = {}
        for label, name in rules["answer"].items():
            if name != "unknown":
                answer[label] = name
            else:
                guess = model_answer.get(label, "unknown")
                answer[label] = "unknown" if canonical(guess) in taken else guess
        (out / path.name).write_text(json.dumps({"call_id": model["call_id"], "answer": answer, "model_invalid": model.get("invalid", False),
                                                 "seconds": model.get("seconds"), "prompt_tokens": model.get("prompt_tokens")}))
    return out.name


if __name__ == "__main__":
    rules_dir = sys.argv[1] if len(sys.argv) > 1 else "rules3__clues__none__-__nothink"
    for config_dir in sorted((HERE / "hyp").iterdir()):
        if config_dir.name.startswith(("rules", "merge-", "vote-")):
            continue
        merge(rules_dir, config_dir.name)
