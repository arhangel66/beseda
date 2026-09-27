"""BESEDA-115: score the other local diarizers of other_diarizers.sh on the 15 truth calls (shown `them` speakers
after the app's per-sentence assignment, vs real-calls-truth.md) and the real benchmark (DER, speaker-count error,
real people glued). Embedding rows re-cluster the offline-t0.7 segments with a stronger model. Prints markdown."""

import json
from pathlib import Path

import numpy as np
from pyannote.core import Segment, Timeline
from pyannote.metrics.diarization import DiarizationErrorRate
from scipy.cluster.hierarchy import fcluster, linkage

import score
from extra_speakers import DAILIES, ONE_ON_ONE, STORE, assigned_speakers, load_sentences
from score_sweep import annotation
from short_reply_merge import BENCHMARK, CALLS, merged_timeline

OTHER = score.ROOT / "hyp" / "other"
RAW = ["offline-t0.7", "sortformer", "lseend-dihard3", "lseend-callhome", "nemotron3-offline"]
EMBEDDINGS = ["resnet34", "campplus", "eres2netv2", "resnet293"]
THRESHOLDS = [round(t, 2) for t in np.arange(0.3, 0.95, 0.05)]


def raw_timeline(variant: str, file_id: str) -> list[dict]:
    segments = json.loads((OTHER / variant / f"{file_id}.json").read_text())["segments"]
    return sorted(({**s, "embedding": []} for s in segments), key=lambda s: s["start"])


def clustered_timeline(model: str, file_id: str, threshold: float) -> list[dict]:
    # average-linkage cosine clustering of the embedded segments; unembedded (short) ones take the nearest in time
    segments = json.loads((OTHER / f"emb-{model}" / f"{file_id}.json").read_text())["segments"]
    embedded = [s for s in segments if s["embedding"]]
    vectors = np.array([s["embedding"] for s in embedded])
    labels = fcluster(linkage(vectors, "average", metric="cosine"), threshold, "distance") if len(embedded) > 1 else [1] * len(embedded)
    for s, label in zip(embedded, labels):
        s["speaker"] = f"spk-{label}"
    for s in segments:
        if not s["embedding"]:
            s["speaker"] = min(embedded, key=lambda e: max(e["start"] - s["end"], s["start"] - e["end"], 0.0))["speaker"]
    return [{**s, "embedding": []} for s in sorted(segments, key=lambda s: s["start"])]


def processing_seconds(variant: str, file_id: str) -> float:
    return json.loads((OTHER / variant / f"{file_id}.json").read_text())["processing_seconds"]


def audio_seconds(file_id: str) -> float:
    if file_id in BENCHMARK:
        return json.loads((score.REFS / f"{file_id}.json").read_text())["duration"]
    # 16 kHz mono int16 behind a 44-byte header; only the size is read, never the audio
    return ((STORE / file_id / "them.asr.wav").stat().st_size - 44) / 32000


def benchmark_scores(file_id: str, timeline: list[dict]) -> tuple[DiarizationErrorRate, int, int, int]:
    # DER, shown speakers, real speakers, and real people glued: reference speakers whose most-overlapping
    # hypothesis speaker is also another reference speaker's
    reference = json.loads((score.REFS / f"{file_id}.json").read_text())
    ref_segments = [s for s in reference["segments"] if s["channel"] == "system"]
    der = DiarizationErrorRate(collar=score.COLLAR)
    der(annotation(ref_segments), annotation(timeline), uem=Timeline([Segment(0, reference["duration"])]))
    dominant = {}
    for ref_speaker in {s["speaker"] for s in ref_segments}:
        overlaps: dict[str, float] = {}
        for r in (s for s in ref_segments if s["speaker"] == ref_speaker):
            for h in timeline:
                overlaps[h["speaker"]] = overlaps.get(h["speaker"], 0) + max(0, min(r["end"], h["end"]) - max(r["start"], h["start"]))
        dominant[ref_speaker] = max(overlaps, key=overlaps.get) if overlaps and max(overlaps.values()) > 0 else None
    owners = [d for d in dominant.values() if d is not None]
    return der, len({s["speaker"] for s in timeline}), len(dominant), len(owners) - len(set(owners))


def row(name: str, timeline_of, timing_variant: str | None, merge: bool) -> dict:
    # counts per call and benchmark totals for one approach; `merge` applies the app's <6 s short-reply rule
    def final(file_id: str) -> list[dict]:
        timeline = timeline_of(file_id)
        return merged_timeline(timeline, 6, "time") if merge else timeline

    counts, other_shares = {}, {}
    for call in CALLS:
        sentences = load_sentences(call)
        labels = assigned_speakers(sentences, final(call))
        seconds: dict[str, float] = {}
        for sentence, label in zip(sentences, labels):
            seconds[label] = seconds.get(label, 0) + sentence["end"] - sentence["start"]
        counts[call] = len(seconds)
        other_shares[call] = 1 - max(seconds.values()) / sum(seconds.values())
    total, count_errors, glued, cells = DiarizationErrorRate(collar=score.COLLAR), [], 0, []
    for f in BENCHMARK:
        der, shown, real, glued_here = benchmark_scores(f, final(f))
        for component, value in der.accumulated_.items():
            total.accumulated_[component] += value
        count_errors.append(abs(shown - real))
        glued += glued_here
        cells.append(f"{shown}/{real}")
    speed = None
    if timing_variant:
        files = CALLS + BENCHMARK
        speed = sum(map(audio_seconds, files)) / sum(processing_seconds(timing_variant, f) for f in files)
    return {"name": name, "counts": counts, "der": abs(total), "count_error": float(np.mean(count_errors)),
            "glued": glued, "margin": margin(other_shares), "bench": ", ".join(cells), "speed": speed,
            "one_on_one": sum(counts[c] == 1 for c in ONE_ON_ONE),
            "dailies": sum(counts[c] == DAILIES[c] for c in DAILIES)}


def margin(per_call: dict[str, float]) -> float:
    # "one speaker vs more": how far the lowest daily sits above the highest 1:1 call; < 0 = no threshold separates
    return min(per_call[c] for c in DAILIES) - max(per_call[c] for c in ONE_ON_ONE)


def top_merge_distance(model: str, file_id: str) -> float:
    # the cosine distance at which average linkage joins everything into one speaker
    segments = json.loads((OTHER / f"emb-{model}" / f"{file_id}.json").read_text())["segments"]
    vectors = np.array([s["embedding"] for s in segments if s["embedding"]])
    return float(linkage(vectors, "average", metric="cosine")[-1, 2]) if len(vectors) > 1 else 0.0


def peak_memory() -> dict[str, float]:
    peaks: dict[str, float] = {}
    for line in (OTHER / "memory.log").read_text().splitlines():
        label, _, gigabytes, _ = line.split()
        peaks[label] = max(peaks.get(label, 0.0), float(gigabytes))
    return peaks


def main() -> None:
    rows = []
    for variant in RAW:
        rows.append(row(variant, lambda f, v=variant: raw_timeline(v, f), variant, merge=False))
        rows.append(row(f"{variant} + <6 s merge", lambda f, v=variant: raw_timeline(v, f), variant, merge=True))

    print("## Embedding threshold sweep (benchmark DER / count error / glued; 1:1 exact; dailies exact)\n")
    print("| model | " + " | ".join(str(t) for t in THRESHOLDS) + " |")
    print("|---|" + "---|" * len(THRESHOLDS))
    for model in EMBEDDINGS:
        sweep = [row(f"offline-t0.7 segments + {model} t{t}", lambda f, m=model, t=t: clustered_timeline(m, f, t), None, merge=False)
                 for t in THRESHOLDS]
        print(f"| {model} | " + " | ".join(f"{r['der']:.3f}/{r['count_error']:.1f}/{r['glued']}; {r['one_on_one']}; {r['dailies']}" for r in sweep) + " |")
        best = min(sweep, key=lambda r: r["der"])
        distances = {c: top_merge_distance(model, c) for c in CALLS}
        print(f"| {model} top merge distance: 1:1 max {max(distances[c] for c in ONE_ON_ONE):.3f}, "
              f"dailies min {min(distances[c] for c in DAILIES):.3f}, margin {margin(distances):+.3f} |")
        timing = f"emb-{model}"
        best["speed"] = 1 / sum(1 / x for x in (
            sum(map(audio_seconds, CALLS + BENCHMARK)) / sum(processing_seconds(v, f) for f in CALLS + BENCHMARK)
            for v in ("offline-t0.7", timing)))
        rows.append(best)
    print()

    memory = peak_memory()
    print("## Summary\n")
    print("| approach | 1:1 correct (of 10) | dailies correct (of 5) | total \\|Δ\\| calls | other-speaker share margin | benchmark DER / count error / glued | bench shown/real | × realtime |")
    print("|---|---|---|---|---|---|---|---|")
    for r in rows:
        delta = sum(abs(r["counts"][c] - DAILIES.get(c, 1)) for c in CALLS)
        speed = f"{r['speed']:.0f}" if r["speed"] else "–"
        print(f"| {r['name']} | {r['one_on_one']} | {r['dailies']} | {delta} | {r['margin']:+.3f} | {r['der']:.3f} / {r['count_error']:.2f} / {r['glued']} | {r['bench']} | {speed} |")
    print()

    print("## Per call: shown `them` speakers\n")
    print("| call | real | " + " | ".join(r["name"] for r in rows) + " |")
    print("|---|---|" + "---|" * len(rows))
    for call in CALLS:
        print(f"| {call} | {DAILIES.get(call, 1)} | " + " | ".join(str(r["counts"][call]) for r in rows) + " |")
    print()

    print("## Peak memory per run (GB, max over files)\n")
    print("| run | peak |\n|---|---|")
    for label, gigabytes in sorted(memory.items()):
        print(f"| {label} | {gigabytes:.2f} |")


if __name__ == "__main__":
    main()
