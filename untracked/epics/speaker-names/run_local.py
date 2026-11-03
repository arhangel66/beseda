# runs (model × window × context × prompt × thinking) configs over a call set through llama-server, resumable by config hash
import contextlib, hashlib, json, os, subprocess, sys, time, urllib.request
from pathlib import Path

import contexts, windows

HERE = Path(__file__).parent
RUNTIME = Path.home() / "Library/Application Support/Beseda/runtime"
LLAMA_SERVER = RUNTIME / "llama/b10819/llama-server"
MODELS = json.loads((HERE / "models.json").read_text())
PORT = int(os.environ.get("SPEAKER_NAMES_PORT", "8792"))
CONTEXT_SIZE = 32768


def log(message: str) -> None:
    line = f"{time.strftime('%H:%M:%S')} {message}"
    print(line, flush=True)
    with open(HERE / "run.log", "a") as f:
        f.write(line + "\n")


class Server:
    def __init__(self, model_key: str):
        self.model_key = model_key
        self.process = None

    def __enter__(self):
        path = Path(os.path.expanduser(MODELS[self.model_key]["path"]))
        if not path.is_absolute():
            path = HERE / path
        self.process = subprocess.Popen(["nice", "-n", "19", str(LLAMA_SERVER), "-m", str(path), "--host", "127.0.0.1",
                                         "--port", str(PORT), "-c", str(CONTEXT_SIZE), "-np", "1", "-ngl", "99", "-fa", "on",
                                         "--jinja", "--no-ui"], stdout=subprocess.DEVNULL,
                                        stderr=open(HERE / f"server-{self.model_key}.log", "a"))
        for _ in range(600):
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2); break
            except Exception:
                if self.process.poll() is not None:
                    raise RuntimeError(f"llama-server died for {self.model_key}")
                time.sleep(1)
        log(f"server up: {self.model_key}")
        return self

    def __exit__(self, *_):
        self.process.terminate(); self.process.wait(timeout=30)
        log(f"server down: {self.model_key}")


def schema_for(labels: list[str], prompt: str) -> dict:
    if prompt == "p4":
        # names restricted to the team plus unknown, each with the line that carries the clue
        entry = {"type": "object", "properties": {"name": {"type": "string", "enum": sorted(windows.PEOPLE) + ["unknown"]},
                 "cue": {"type": "string", "enum": ["addressed", "thanked", "introduced", "none"]}, "line": {"type": "integer"}},
                 "required": ["name", "cue", "line"], "additionalProperties": False}
        return {"type": "object", "properties": {l: entry for l in labels}, "required": labels, "additionalProperties": False}
    if prompt == "p5":
        # evidence before the name, so the model writes its reason first
        entry = {"type": "object", "properties": {"evidence": {"type": "string"}, "name": {"type": "string"}},
                 "required": ["evidence", "name"], "additionalProperties": False}
        return {"type": "object", "properties": {l: entry for l in labels}, "required": labels, "additionalProperties": False}
    names = {"type": "object", "properties": {l: {"type": "string"} for l in labels}, "required": labels, "additionalProperties": False}
    if prompt != "p2":
        return names
    evidence = {"type": "array", "items": {"type": "object", "properties": {"idx": {"type": "integer"}, "label": {"type": "string"},
                "name": {"type": "string"}}, "required": ["idx", "label", "name"], "additionalProperties": False}}
    return {"type": "object", "properties": {"evidence": evidence, "names": names}, "required": ["evidence", "names"], "additionalProperties": False}


def ask(system: str, user: str, schema: dict, thinking: bool, max_tokens: int, model_key: str = "") -> dict:
    remote = MODELS.get(model_key, {}).get("openrouter")
    body = {"model": remote or "local", "temperature": 0, "max_tokens": max_tokens, "stream": False,
            "response_format": {"type": "json_schema", "json_schema": {"name": "names", "schema": schema}},
            "chat_template_kwargs": {"enable_thinking": thinking},
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}]}
    url, headers = f"http://127.0.0.1:{PORT}/v1/chat/completions", {"Content-Type": "application/json"}
    if remote:
        url, headers["Authorization"] = "https://openrouter.ai/api/v1/chat/completions", f"Bearer {openrouter_key()}"
        body.pop("chat_template_kwargs")
    request = urllib.request.Request(url, json.dumps(body).encode(), headers)
    started = time.time()
    reply = json.load(urllib.request.urlopen(request, timeout=1800))
    message = reply["choices"][0]["message"]
    return {"seconds": round(time.time() - started, 1), "prompt_tokens": reply["usage"]["prompt_tokens"],
            "completion_tokens": reply["usage"]["completion_tokens"], "finish": reply["choices"][0]["finish_reason"],
            "raw": message.get("content") or "", "reasoning": message.get("reasoning_content") or "",
            "cache_tokens": (reply.get("timings") or {}).get("cache_n"), "routed_model": reply.get("model"),
            "cost": (reply.get("usage") or {}).get("cost")}


def openrouter_key() -> str:
    env = Path.home() / ".claude/skills/consilium/.env"
    return next(line.split("=", 1)[1].strip().strip('"') for line in env.read_text().splitlines() if line.startswith("OPENROUTER_API_KEY="))


def run(configs: list[dict], call_filter) -> None:
    # configs: {"model", "window", "context", "prompt", "thinking"}; call_filter(call) -> bool
    calls = json.loads((HERE / "data/calls.json").read_text())
    refs = contexts.load_refs()
    chosen = [c for c in calls if call_filter(c) and c["id"] in refs]
    log(f"{len(chosen)} calls, {len(configs)} configs")
    by_model: dict[str, list[dict]] = {}
    for config in configs:
        by_model.setdefault(config["model"], []).append(config)
    for model_key, model_configs in by_model.items():
        pending = []
        for call in chosen:
            for config in model_configs:
                name = f"{config['model']}__{config['window']}__{config['context']}__{config['prompt']}__{'think' if config['thinking'] else 'nothink'}"
                rows = windows.read_rows(call["id"])
                system = (HERE / f"prompts/{config['prompt']}.txt").read_text().strip()
                context = contexts.build(config["context"], call, calls, refs)
                if context:
                    system += "\n\n" + context
                user = windows.render(rows, config["window"])
                labels = windows.labels_of(rows)
                schema = schema_for(labels, config["prompt"])
                digest = hashlib.sha256(json.dumps([system, user, schema, MODELS[model_key]["sha256"], config["thinking"], CONTEXT_SIZE]).encode()).hexdigest()[:16]
                out = HERE / "hyp" / name / f"{call['id']}.json"
                if out.exists() and json.loads(out.read_text()).get("hash") == digest:
                    continue
                pending.append((call, config, name, system, user, labels, schema, digest, out))
        if not pending:
            log(f"{model_key}: nothing pending"); continue
        log(f"{model_key}: {len(pending)} pending")
        with (contextlib.nullcontext() if MODELS[model_key].get("openrouter") else Server(model_key)):
            for n, (call, config, name, system, user, labels, schema, digest, out) in enumerate(pending, 1):
                max_tokens = 4000 if config["thinking"] else (1500 if config["prompt"] in ("p2", "p5") else 600 if config["prompt"] == "p4" else 400)
                try:
                    reply = ask(system, user, schema, config["thinking"], max_tokens if not MODELS[model_key].get("openrouter") else 16000, model_key)
                except Exception as error:
                    log(f"ERROR {name} {call['id']}: {error}"); continue
                try:
                    parsed = json.loads(reply["raw"])
                    answer = parsed["names"] if config["prompt"] == "p2" else parsed
                    if config["prompt"] in ("p4", "p5"):
                        answer = {label: entry["name"] for label, entry in parsed.items()}
                    invalid = reply["finish"] != "stop" or not isinstance(answer, dict)
                except (json.JSONDecodeError, KeyError, TypeError):
                    parsed, answer, invalid = None, {}, True
                record = {"call_id": call["id"], "config": config, "answer": answer, "parsed": parsed, "invalid": invalid, "hash": digest, **reply}
                out.parent.mkdir(parents=True, exist_ok=True)
                tmp = out.with_suffix(".tmp"); tmp.write_text(json.dumps(record, ensure_ascii=False, indent=1)); tmp.replace(out)
                log(f"{n}/{len(pending)} {name} {call['id']} {reply['seconds']}s {'INVALID' if invalid else ''} {answer}")


from score import FAST


def grid(models, windows_, contexts_, prompts, thinkings) -> list[dict]:
    return [{"model": m, "window": w, "context": c, "prompt": p, "thinking": t}
            for m in models for w in windows_ for c in contexts_ for p in prompts for t in thinkings]


if __name__ == "__main__":
    stage = sys.argv[1] if len(sys.argv) > 1 else "smoke"
    if stage == "smoke":
        run(grid(["gemma4-e4b"], ["edges100"], ["roster"], ["p1"], [False]), lambda c: c["id"] == "20261102-125941")
    elif stage == "smoke-models":
        run(grid(["gemma4-12b", "qwen3.5-9b"], ["edges100"], ["roster"], ["p1"], [False, True]), lambda c: c["id"] == "20261102-125941")
    elif stage == "fast1":
        run(grid(["gemma4-e4b"], ["edges100"], ["none", "roster", "roster+notes"], ["p0", "p1", "p2"], [False])
            + grid(["gemma4-e4b"], ["clues"], ["none", "roster", "roster+notes"], ["p1", "p3"], [False])
            + grid(["gemma4-e4b"], ["edges50", "names"], ["roster"], ["p1"], [False]),
            lambda c: c["id"] in FAST)
    elif stage == "fast-models":
        run(grid(["gemma4-12b", "qwen3.5-9b"], ["edges100"], ["none", "roster", "roster+notes"], ["p1"], [False])
            + grid(["gemma4-12b", "qwen3.5-9b"], ["clues"], ["roster"], ["p3"], [False])
            + grid(["gemma4-12b", "qwen3.5-9b"], ["edges100"], ["roster"], ["p2"], [False]),
            lambda c: c["id"] in FAST)
    elif stage == "fast-hybrid":
        run(grid(["gemma4-e4b"], ["edges100"], ["rules", "roster+rules", "roster+notes+rules"], ["p1"], [False]), lambda c: c["id"] in FAST)
    elif stage == "tune-e4b-top":
        run(grid(["gemma4-e4b"], ["names", "clues"], ["roster", "roster+notes"], ["p1"], [False])
            + grid(["gemma4-e4b"], ["edges100"], ["roster+notes"], ["p1", "p2"], [False]),
            lambda c: c["split"] == "tune")
    elif stage == "tune-e4b-plain":
        run(grid(["gemma4-e4b"], ["edges100", "edges50", "names", "full"], ["none", "roster"], ["p0", "p1", "p2"], [False]),
            lambda c: c["split"] == "tune")
    elif stage == "tune-e4b":
        run(grid(["gemma4-e4b"], ["clues"], ["none", "roster", "roster+notes"], ["p1", "p3"], [False])
            + grid(["gemma4-e4b"], ["edges100", "edges50", "names", "full"], ["none", "roster", "prev", "notes", "roster+notes"], ["p0", "p1", "p2"], [False])
            + grid(["gemma4-e4b"], ["edges100", "full", "clues"], ["roster+notes"], ["p1"], [True]),
            lambda c: c["split"] == "tune")
    elif stage == "night1":
        # finalists on the whole tune half, then Qwen on the fast set
        run(grid(["gemma4-e4b"], ["edges100"], ["roster+notes"], ["p2"], [False])
            + grid(["gemma4-e4b"], ["edges100"], ["none"], ["p1"], [False])
            + grid(["gemma4-e4b"], ["clues"], ["roster+notes"], ["p1"], [False])
            + grid(["gemma4-e4b"], ["names"], ["roster"], ["p1"], [False])
            + grid(["gemma4-12b"], ["edges100"], ["roster"], ["p2"], [False])
            + grid(["gemma4-12b"], ["edges100"], ["roster+notes", "none"], ["p1"], [False]),
            lambda c: c["split"] == "tune")
        run(grid(["qwen3.5-9b"], ["edges100"], ["roster"], ["p1", "p2"], [False]), lambda c: c["id"] in FAST)
    elif stage == "night2":
        # p4: team-only names with the clue line, gated in code afterwards (gate.py)
        run(grid(["gemma4-e4b"], ["edges100", "full", "names"], ["none", "roster"], ["p4"], [False]), lambda c: c["id"] in FAST)
        run(grid(["gemma4-12b"], ["edges100"], ["roster"], ["p4"], [False]), lambda c: c["id"] in FAST)
    elif stage == "night3":
        # more 12B voters with different windows on the whole tune half
        run(grid(["gemma4-12b"], ["names", "clues"], ["none", "roster+notes"], ["p1"], [False])
            + grid(["gemma4-12b"], ["edges50", "full"], ["none"], ["p1"], [False]),
            lambda c: c["split"] == "tune")
    elif stage == "night4":
        # the finalists' voters, once, on the held-out test half
        run(grid(["gemma4-e4b"], ["edges100"], ["roster+notes"], ["p2"], [False])
            + grid(["gemma4-e4b"], ["clues"], ["roster+notes"], ["p1"], [False])
            + grid(["gemma4-12b"], ["edges100"], ["none", "roster+notes"], ["p1"], [False])
            + grid(["gemma4-12b"], ["edges100"], ["roster"], ["p2"], [False]),
            lambda c: c["split"] == "test")
    elif stage == "night5":
        # the simplest single-config finalists on test
        run(grid(["gemma4-12b"], ["full", "names"], ["none"], ["p1"], [False]), lambda c: c["split"] == "test")
    elif stage == "night6":
        # 1:1 and two-remote calls: how often the finalist model invents a name where the text gives none
        run(grid(["gemma4-12b"], ["edges100"], ["none", "roster+notes"], ["p1"], [False]), lambda c: c["group"] in ("one", "two"))
    elif stage == "jev-fast":
        run(grid(["jev-router"], ["edges100"], ["none"], ["p1"], [False]) + grid(["jev-router"], ["edges100"], ["roster"], ["p2"], [False]),
            lambda c: c["id"] in FAST)
    elif stage == "p5-example":
        run(grid(["gemma4-12b", "gemma4-e4b"], ["edges100"], ["none"], ["p5"], [False]), lambda c: c["id"] == "20261009-125957")
    elif stage == "p5-fast":
        run(grid(["gemma4-12b", "gemma4-e4b"], ["edges100"], ["none"], ["p5"], [False]), lambda c: c["id"] in FAST)
