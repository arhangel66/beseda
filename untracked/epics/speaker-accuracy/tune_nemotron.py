"""BESEDA-163: Nemotron-3 variants for multi-person calls, scored like BESEDA-151 (shown `them` speakers after the app's
per-sentence assignment vs the LLM-read count of results/all-calls-nemotron.md: all / 1:1 / multi, exact and ±1) plus
the real benchmark (DER, count error, glued people). Inputs from tune_nemotron.sh. Writes results/nemotron-tuning.md."""

import json
import re
from datetime import datetime
from pathlib import Path

import numpy as np
from pyannote.metrics.diarization import DiarizationErrorRate

import score
from extra_speakers import assigned_speakers
from other_diarizers import benchmark_scores

ROOT = Path(__file__).parent
OTHER = ROOT / "hyp" / "other"
COPY = ROOT / "hyp" / "all-calls"
RESULT = ROOT / "results" / "nemotron-tuning.md"
BENCHMARK = ["ami_ES2004a", "ami_IS1009a", "vox_asxwr", "vox_azisu", "vox_gzvkx"]
SLOTS = 8


def truth() -> dict[str, dict]:
    # the per-call table of BESEDA-151: id, real count, confidence, title
    rows = {}
    for line in (ROOT / "results" / "all-calls-nemotron.md").read_text().splitlines():
        cells = [c.strip() for c in line.strip("|").split("|")]
        if len(cells) == 7 and re.match(r"\d{8}-\d{6} ", cells[0]):
            rows[cells[0][:15]] = {"count": int(cells[2].split()[0]), "confidence": cells[3], "title": cells[0]}
    return rows


def is_daily(call_id: str, minutes: float) -> bool:
    # the 13:00 team daily: starts 12:50–13:10, lasts over 20 min
    started = datetime.strptime(call_id, "%Y%m%d-%H%M%S")
    return (started.hour, started.minute) >= (12, 50) and (started.hour, started.minute) <= (13, 10) and minutes > 20


def probabilities(variant_dir: str, file_id: str) -> np.ndarray:
    return np.fromfile(OTHER / variant_dir / f"{file_id}.f32", dtype=np.float32).reshape(-1, SLOTS)


def segments(probs: np.ndarray, threshold: float = 0.5, min_seconds: float = 0.2) -> list[dict]:
    # Nemotron3Diarizer.segments: runs of frames above the threshold per slot, 10 ms frames
    out = []
    for slot in range(SLOTS):
        active = np.concatenate([[False], probs[:, slot] > threshold, [False]])
        edges = np.flatnonzero(np.diff(active.astype(int)))
        for start, end in zip(edges[::2], edges[1::2]):
            if (end - start) * 0.01 >= min_seconds:
                out.append({"start": start * 0.01, "end": end * 0.01, "speaker": f"spk-{slot}"})
    return sorted(out, key=lambda s: s["start"])


def json_timeline(variant: str, file_id: str) -> list[dict]:
    return sorted(json.loads((OTHER / variant / f"{file_id}.json").read_text())["segments"], key=lambda s: s["start"])


def split_bimodal(file_id: str, timeline: list[dict], distance: float, min_seconds: float = 20.0) -> list[dict]:
    # a speaker whose WeSpeaker segment embeddings fall into two groups, both with ≥ min_seconds of speech and
    # centroids further apart (cosine) than `distance`, becomes two speakers; unembedded segments stay put
    embedded = json.loads((OTHER / "emb-nemotron" / f"{file_id}.json").read_text())["segments"]
    vectors = {(round(s["start"], 2), round(s["end"], 2)): np.array(s["embedding"]) for s in embedded if s["embedding"]}
    timeline = [dict(s) for s in timeline]
    for speaker in sorted({s["speaker"] for s in timeline}):
        own = [s for s in timeline if s["speaker"] == speaker and (round(s["start"], 2), round(s["end"], 2)) in vectors]
        if len(own) < 4:
            continue
        x = np.array([vectors[(round(s["start"], 2), round(s["end"], 2))] for s in own])
        x /= np.linalg.norm(x, axis=1, keepdims=True)
        labels = two_means(x)
        weights = np.array([s["end"] - s["start"] for s in own])
        if min(weights[labels == 0].sum(), weights[labels == 1].sum()) < min_seconds:
            continue
        a, b = (x[labels == k].mean(axis=0) for k in (0, 1))
        if 1 - a @ b / np.linalg.norm(a) / np.linalg.norm(b) > distance:
            for s, label in zip(own, labels):
                if label:
                    s["speaker"] = f"{speaker}b"
    return timeline


def two_means(x: np.ndarray) -> np.ndarray:
    # spherical 2-means seeded by the two most distant points; deterministic
    first = int(np.argmin(x @ x.mean(axis=0)))
    second = int(np.argmin(x @ x[first]))
    centers = x[[first, second]]
    for _ in range(20):
        labels = np.argmax(x @ centers.T, axis=1)
        centers = np.array([x[labels == k].mean(axis=0) if (labels == k).any() else centers[k] for k in (0, 1)])
    return labels


def shown_count(call_id: str, timeline: list[dict]) -> int:
    sentences = json.loads((COPY / f"{call_id}.them.asr.json").read_text())["segments"]
    return len(set(assigned_speakers(sentences, timeline))) if sentences and timeline else min(len(sentences), 1)


def variant_row(name: str, timeline_of, calls: dict[str, dict]) -> dict:
    counts = {c: shown_count(c, timeline_of(c)) for c in calls}
    total, count_errors, glued, cells = DiarizationErrorRate(collar=score.COLLAR), [], 0, []
    for f in BENCHMARK:
        der, shown, real, glued_here = benchmark_scores(f, timeline_of(f))
        for component, value in der.accumulated_.items():
            total.accumulated_[component] += value
        count_errors.append(abs(shown - real))
        glued += glued_here
        cells.append(f"{shown}/{real}")
    return {"name": name, "counts": counts, "der": abs(total), "count_error": float(np.mean(count_errors)),
            "glued": glued, "bench": ", ".join(cells)}


def hinted(call_id: str, calls: dict[str, dict], default, fallback):
    # the count hint: on a daily with fewer than 3 shown people, take the fallback timeline instead
    timeline = default(call_id)
    if call_id in calls and calls[call_id]["daily"] and shown_count(call_id, timeline) < 3:
        return fallback(call_id)
    return timeline


def main() -> None:
    calls = truth()
    lengths = {c: max((s["end"] for s in json.loads((COPY / f"{c}.them.asr.json").read_text())["segments"]), default=0) / 60 for c in calls}
    for call_id, call in calls.items():
        call["daily"] = is_daily(call_id, lengths[call_id])

    probs = lambda f: probabilities("nemotron3-probs-f32", f)
    variants = [("Nemotron offline (app now)", lambda f: json_timeline("nemotron3-probs", f))]
    for threshold in (0.3, 0.4, 0.6):
        variants.append((f"activity threshold {threshold}", lambda f, t=threshold: segments(probs(f), t)))
    for min_seconds in (0.5, 1.0):
        variants.append((f"min segment {min_seconds} s", lambda f, m=min_seconds: segments(probs(f), 0.5, m)))
    for knob in ("pred0.1", "minpos0.2", "sil3", "fast128"):
        variants.append((f"knob {knob}", lambda f, k=knob: json_timeline(f"nemotron3-{k}", f)))
    default = lambda f: json_timeline("nemotron3-probs", f)
    for distance in (0.3, 0.4, 0.5):
        # only when the call has ≥ 3 voices: Mikhail plus ≥ 2 remote speakers
        variants.append((f"split bimodal d>{distance}, ≥3 voices",
                         lambda f, d=distance: split_bimodal(f, default(f), d) if len({s["speaker"] for s in default(f)}) >= 2 else default(f)))
    for distance in (0.3, 0.4):
        variants.append((f"split bimodal d>{distance}, all calls", lambda f, d=distance: split_bimodal(f, default(f), d)))
    variants.append(("hint: daily <3 → threshold 0.3", lambda f: hinted(f, calls, default, lambda g: segments(probs(g), 0.3))))
    variants.append(("hint: daily <3 → split d>0.3", lambda f: hinted(f, calls, default, lambda g: split_bimodal(g, default(g), 0.3))))

    rows = [variant_row(name, timeline_of, calls) for name, timeline_of in variants]
    groups = [("all", lambda c: True), ("1:1", lambda c: c["count"] == 1), ("multi-person", lambda c: c["count"] > 1),
              ("dailies (4–5 expected)", lambda c: c["daily"])]

    out = ["# Nemotron-3 tuning for multi-person calls (BESEDA-163, 2026-09-27)", "",
           "Every variant through the app's per-sentence assignment on the 70 calls with audio (copies, "
           "`tune_nemotron.sh`), against the real count of [all-calls-nemotron.md](all-calls-nemotron.md) (LLM reading; "
           "the 15 of [real-calls-truth.md](real-calls-truth.md) inside it), and the real benchmark (VoxConverse ×3, AMI ×2: "
           "DER collar 0.25 s, count error, glued people). Dailies = calls starting 12:50–13:10 over 20 min "
           "(" + ", ".join(c for c in calls if calls[c]["daily"]) + "): Mikhail says 3–6 people, usually 4–5; "
           "for them `exact` = 4–5 and `±1` = 3–6.", "",
           "| variant | " + " | ".join(f"{g} exact | {g} ±1" for g, _ in groups) + " | bench DER / count err / glued | bench shown/real |",
           "|---|" + "---|---|" * len(groups) + "---|---|"]
    for r in rows:
        cells = []
        for _, pick in groups:
            chosen = [c for c in calls if pick(calls[c])]
            exact = sum(ok(calls[c], r["counts"][c], 0) for c in chosen)
            near = sum(ok(calls[c], r["counts"][c], 1) for c in chosen)
            cells.append(f"{exact}/{len(chosen)} | {near}/{len(chosen)}")
        out.append(f"| {r['name']} | " + " | ".join(cells) + f" | {r['der']:.3f} / {r['count_error']:.2f} / {r['glued']} | {r['bench']} |")

    out += ["", "## Per multi-person call and daily: shown `them` speakers", "",
            "| call | real | daily | " + " | ".join(r["name"] for r in rows) + " |",
            "|---|---|---|" + "---|" * len(rows)]
    for c in calls:
        if calls[c]["count"] > 1 or calls[c]["daily"]:
            out.append(f"| {calls[c]['title']} | {calls[c]['count']} | {'yes' if calls[c]['daily'] else ''} | "
                       + " | ".join(str(r["counts"][c]) for r in rows) + " |")
    out += ["", "## 1:1 calls a variant gets wrong", ""]
    for r in rows:
        wrong = [f"{c}→{r['counts'][c]}" for c in calls if calls[c]["count"] == 1 and r["counts"][c] != 1]
        out.append(f"- {r['name']}: {' '.join(wrong) or 'none'}")
    RESULT.write_text("\n".join(out) + "\n")
    print("\n".join(out[:30]))


def ok(call: dict, shown: int, slack: int) -> bool:
    # dailies are scored against Mikhail's range (4–5 exact, 3–6 near), the rest against the LLM count
    if call["daily"]:
        return (4 - slack) <= shown <= (5 + slack)
    return abs(shown - call["count"]) <= slack


if __name__ == "__main__":
    main()
