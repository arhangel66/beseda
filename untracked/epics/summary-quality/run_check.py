# runs the installed Gemma 4 E4B llama-server (read-only) on transcript.txt with a prompt and temperature
import json, subprocess, sys, time, urllib.request
from pathlib import Path

RUNTIME = Path.home() / "Library/Application Support/Beseda/runtime"
PORT = 8791
HERE = Path(__file__).parent


def summarize(prompt: str, temperature: float) -> str:
    body = {"model": "local", "temperature": temperature, "max_tokens": 4096, "stream": False,
            "messages": [{"role": "system", "content": prompt},
                         {"role": "user", "content": (HERE / "transcript.txt").read_text()}]}
    request = urllib.request.Request(f"http://127.0.0.1:{PORT}/v1/chat/completions", json.dumps(body).encode(),
                                     {"Content-Type": "application/json"})
    return json.load(urllib.request.urlopen(request, timeout=600))["choices"][0]["message"]["content"]


def main(runs: list[tuple[str, str, float, int]]) -> None:
    server = subprocess.Popen(["nice", "-n", "19", str(RUNTIME / "llama/b10819/llama-server"),
                               "-m", str(RUNTIME / "models/gemma-4-E4B-it-Q4_0.gguf"), "--host", "127.0.0.1",
                               "--port", str(PORT), "-c", "16384", "-np", "1", "-ngl", "99", "-fa", "on", "--jinja",
                               "--no-ui"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        while True:
            try:
                urllib.request.urlopen(f"http://127.0.0.1:{PORT}/health", timeout=2)
                break
            except Exception:
                time.sleep(1)
        for name, prompt_file, temperature, seeds in runs:
            for n in range(seeds):
                out = summarize((HERE / prompt_file).read_text(), temperature)
                (HERE / f"{name}-{n + 1}.md").write_text(out)
                print(name, n + 1, "done", flush=True)
    finally:
        server.terminate()


if __name__ == "__main__":
    main([("runs-before/run", "runs-before/prompt.txt", 0.3, 3), ("runs-v1/run", "runs-v1/prompt.txt", 0.1, 3)])
