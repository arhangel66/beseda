# quick look: the installed Gemma 4 E4B names the them-N labels of one call, a few prompt/context variants
import json, re, sqlite3, subprocess, time, urllib.request
from pathlib import Path

RUNTIME = Path.home() / "Library/Application Support/Beseda/runtime"
DB = Path.home() / "Library/Application Support/Beseda/calls.sqlite"
PORT = 8792
HERE = Path(__file__).parent

ROSTER = "People who may be on the call: Rustam, Fish, Pixel, Sergei, Gus, Mohammed. Others may appear too."
NOTES = """People who may be on the call, with what is known about them from earlier calls:
- Rustam: backend lead, usually runs the daily and hands the turn to the next person ("Pixel, do you want to be next?"); reports payouts, NG engine, security, feature flags; speaks Russian with Mikhail; ASR garbles his name as Rustan/Rustin/Mustam.
- Pixel: frontend/admin; reports provider earnings UI, blog posts, docs, backups, PR merges; often says "Thanks, Rustam" and takes the turn after him.
- Sergei: backend; reports scalability, pods, Redis, API keys, TMC; ASR writes Serge/Sergey.
- Gus: sales and commercial; reports provider outreach, long-term rentals, marketing campaigns; often the last speaker; ASR writes Gas.
- Mohammed: infrastructure; reports EKS/Karpenter, LMD binary, node IP changes; ASR writes Muhammad.
- Fish: founder; comments on feature flags, prices, Stripe; rarely gives an update.
Others may appear too."""

INSTRUCTION = """You read a transcript of a call recorded by Mikhail. "me" is Mikhail. The other speakers are labelled them-1, them-2, ... by a speaker diarizer; each label is one distinct voice.
Work out the real name of each them-N label from the transcript: who is addressed by name right before they answer, who introduces themselves, who is thanked after speaking, who is asked a question and replies. Names may be garbled by speech recognition (Mustam = Rustam).
Answer with JSON only: an object with one key per label, value = the person's name or "unknown" when the transcript gives no reliable evidence. Never guess."""

HINT = """
On these calls people address each other by name all the time, so there are almost always clues: a greeting ("Hi Rustam"), a question to someone ("Sergei, what about the reliability score?") answered by the next speaker, a hand-over ("Mohammed, you can go" — the next voice is Mohammed), thanks after an update ("Thank you, Sergei" — the previous voice was Sergei). Look for those first; a person's topics are only a second hint."""


NAME_PATTERN = re.compile(r"\b(rust[aei]n|rustam|mustam|pixel|serge[iy]?|gus|gas|moham+[ae]d|muham+[ae]d|fish)\b", re.I)


def transcript(call_id: str, window: str | int | None, edge: int = 100) -> tuple[str, list[str]]:
    # window: None = whole call, int = first N chars, "names" = lines naming someone plus 3 neighbours each side
    rows = sqlite3.connect(f"file:{DB}?mode=ro", uri=True).execute(
        "select start_sec, speaker, text from transcript_segments where call_id=? order by order_idx", (call_id,)
    ).fetchall()
    labels = sorted({speaker for _, speaker, _ in rows if speaker != "me"})
    lines = [f"[{int(start) // 60:02d}:{int(start) % 60:02d}] {speaker}: {text}" for start, speaker, text in rows]
    if window == "edges":
        turns: list[list] = []
        for start, speaker, text in rows:
            if turns and turns[-1][1] == speaker:
                turns[-1][2] += " " + text
            else:
                turns.append([start, speaker, text])
        out = []
        for start, speaker, text in turns:
            if len(text) > 2 * edge:
                text = text[:edge] + " … " + text[-edge:]
            out.append(f"[{int(start) // 60:02d}:{int(start) % 60:02d}] {speaker}: {text}")
        return "\n".join(out), labels
    if window == "names":
        keep = {j for i, (_, _, text) in enumerate(rows) if NAME_PATTERN.search(text) for j in range(i - 3, i + 4)}
        picked, previous = [], -1
        for i in sorted(j for j in keep if 0 <= j < len(lines)):
            if i != previous + 1:
                picked.append("...")
            picked.append(lines[i]); previous = i
        return "\n".join(picked), labels
    text = "\n".join(lines)
    return (text[:window] if isinstance(window, int) else text), labels


def ask(system: str, user: str, labels: list[str], extra: dict) -> dict:
    schema = {"type": "object", "properties": {label: {"type": "string"} for label in labels},
              "required": labels, "additionalProperties": False}
    body = {"model": "local", "temperature": 0, "max_tokens": 512, "stream": False,
            "response_format": {"type": "json_schema", "json_schema": {"name": "names", "schema": schema}},
            "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}], **extra}
    request = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/chat/completions", json.dumps(body).encode(),
                                     {"Content-Type": "application/json"})
    started = time.time()
    reply = json.load(urllib.request.urlopen(request, timeout=900))
    return {"seconds": round(time.time() - started, 1), "prompt_tokens": reply["usage"]["prompt_tokens"],
            "finish": reply["choices"][0]["finish_reason"], "answer": reply["choices"][0]["message"]["content"],
            "reasoning": reply["choices"][0]["message"].get("reasoning_content") or ""}


def main(call_id: str, variants: list[tuple[str, str, int | None, dict, int, bool]]) -> None:
    server = subprocess.Popen(["nice", "-n", "19", str(RUNTIME / "llama/b10819/llama-server"),
                               "-m", str(RUNTIME / "models/gemma-4-E4B-it-Q4_0.gguf"), "--host", "127.0.0.1",
                               "--port", str(PORT), "-c", "32768", "-np", "1", "-ngl", "99", "-fa", "on", "--jinja",
                               "--no-ui"], stdout=subprocess.DEVNULL, stderr=open(HERE / "smoke-server.log", "w"))
    try:
        while True:
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2)
                break
            except Exception:
                time.sleep(1)
        for name, context, max_chars, extra, edge, hint in variants:
            text, labels = transcript(call_id, max_chars, edge)
            system = INSTRUCTION + (HINT if hint else "") + {"none": "", "roster": "\n" + ROSTER, "notes": "\n" + NOTES}[context]
            out = ask(system, text, labels, extra)
            (HERE / f"smoke-{name.replace('/', '-')}.json").write_text(json.dumps(out, ensure_ascii=False, indent=1))
            print(name, json.dumps({k: v for k, v in out.items() if k != "reasoning"}, ensure_ascii=False), flush=True)
    finally:
        server.terminate()


if __name__ == "__main__":
    NO_THINK = {"chat_template_kwargs": {"enable_thinking": False}}
    THINK = {"max_tokens": 3000}
    main("20261102-125941", [(f"edges{edge}/{context}/{'hint' if hint else 'plain'}", context, "edges", NO_THINK, edge, hint)
                             for edge in (100, 50)
                             for hint in (False, True)
                             for context in ("roster", "notes")])
