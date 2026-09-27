"""BESEDA-114: re-cluster the embeddings the diarizer already computed, no new model. Reads hyp/chunks/*.json
(embedding_clustering.sh: t0.70 timeline, raw per-window WeSpeaker embeddings, FluidAudio knob timelines),
scores every variant on the real benchmark (DER, speaker-count error, real people glued) and counts `them` on the
15 truth calls through the app's per-sentence assignment. Each variant's one global setting is picked on the
benchmark only, then applied to the calls. Prints markdown tables."""

import json
import time
from collections import Counter

import numpy as np
from pyannote.core import Segment, Timeline
from pyannote.metrics.diarization import DiarizationErrorRate
from scipy.cluster.hierarchy import fcluster, linkage
from sklearn.cluster import KMeans

import score
from extra_speakers import DAILIES, ONE_ON_ONE, assigned_speakers, load_sentences
from score_sweep import annotation

CHUNKS = score.ROOT / "hyp" / "chunks"
BENCHMARK = ["ami_ES2004a", "ami_IS1009a", "vox_asxwr", "vox_azisu", "vox_gzvkx"]
CALLS = ONE_ON_ONE + list(DAILIES)
MAX_SPEAKERS = 10


def normalized(vectors: np.ndarray) -> np.ndarray:
    return vectors / np.linalg.norm(vectors, axis=1, keepdims=True)


def ahc(vectors: np.ndarray, method: str, threshold: float) -> np.ndarray:
    # cosine-distance AHC cut at `threshold`; labels 0..k-1
    if len(vectors) < 2:
        return np.zeros(len(vectors), dtype=int)
    return fcluster(linkage(normalized(vectors), method=method, metric="cosine"), threshold, criterion="distance") - 1


def overlap(a_start: float, a_end: float, b_start: float, b_end: float) -> float:
    return max(0.0, min(a_end, b_end) - max(a_start, b_start))


def relabelled_timeline(timeline: list[dict], chunks: list[dict], chunk_labels: np.ndarray) -> list[dict]:
    # each diarizer segment takes the new label with most overlap among the windows of its own speaker;
    # a segment no window covers takes its speaker's most common new label
    by_speaker = Counter()
    for chunk, label in zip(chunks, chunk_labels):
        by_speaker[(chunk["speaker"], int(label))] += 1
    relabelled = []
    for segment in timeline:
        votes = Counter()
        for chunk, label in zip(chunks, chunk_labels):
            if chunk["speaker"] == segment["speaker"]:
                votes[int(label)] += overlap(segment["start"], segment["end"], chunk["start"], chunk["end"])
        if not votes or max(votes.values()) <= 0:
            votes = Counter({label: n for (speaker, label), n in by_speaker.items() if speaker == segment["speaker"]})
        relabelled.append({**segment, "speaker": f"N{max(votes, key=votes.get)}" if votes else segment["speaker"]})
    return relabelled


def long_only(timeline: list[dict], chunks: list[dict], vectors: np.ndarray, min_seconds: float, threshold: float) -> np.ndarray:
    # variant 1: AHC (average) over windows lying in a diarizer segment of >= min_seconds; every other window
    # goes to the nearest resulting centroid, never to a new cluster
    long_segments = [s for s in timeline if s["end"] - s["start"] >= min_seconds]
    is_long = np.array([any(s["speaker"] == c["speaker"] and overlap(s["start"], s["end"], c["start"], c["end"]) >= 0.5 * (c["end"] - c["start"])
                            for s in long_segments) for c in chunks])
    if is_long.sum() < 2:
        return np.zeros(len(chunks), dtype=int)
    long_labels = ahc(vectors[is_long], "average", threshold)
    centroids = normalized(np.array([vectors[is_long][long_labels == k].mean(axis=0) for k in range(long_labels.max() + 1)]))
    labels = np.argmax(normalized(vectors) @ centroids.T, axis=1)
    labels[is_long] = long_labels
    return labels


def spectral(vectors: np.ndarray, one_speaker_bar: float | None) -> tuple[np.ndarray, int, float]:
    # variant 2: cosine affinity pruned to each row's top 10 % (symmetrized), k = largest eigengap of the
    # normalized Laplacian over 1..MAX_SPEAKERS, then k-means on the first k eigenvectors; with a bar, a mean
    # window-to-centroid cosine above it means one speaker. Returns labels, k, that mean cosine.
    unit = normalized(vectors)
    mean_to_centroid = float(np.mean(unit @ normalized(unit.mean(axis=0, keepdims=True)).T))
    if len(unit) < 3 or (one_speaker_bar is not None and mean_to_centroid >= one_speaker_bar):
        return np.zeros(len(unit), dtype=int), 1, mean_to_centroid
    affinity = np.clip(unit @ unit.T, 0, None)
    keep = max(1, int(0.1 * len(unit)))
    pruned = np.zeros_like(affinity)
    top = np.argsort(-affinity, axis=1)[:, :keep]
    np.put_along_axis(pruned, top, np.take_along_axis(affinity, top, axis=1), axis=1)
    pruned = (pruned + pruned.T) / 2
    degree = pruned.sum(axis=1)
    inverse_root = 1 / np.sqrt(np.maximum(degree, 1e-12))
    laplacian = np.eye(len(unit)) - inverse_root[:, None] * pruned * inverse_root[None, :]
    values, vectors_ = np.linalg.eigh(laplacian)
    limit = min(MAX_SPEAKERS, len(unit) - 1)
    k = int(np.argmax(np.diff(values[: limit + 1]))) + 1
    if k == 1:
        return np.zeros(len(unit), dtype=int), 1, mean_to_centroid
    # a window with no pruned neighbours has an all-zero row here
    embedding = np.nan_to_num(normalized(vectors_[:, :k]))
    return KMeans(n_clusters=k, n_init=10, random_state=0).fit_predict(embedding), k, mean_to_centroid


def speaker_means(chunks: list[dict], vectors: np.ndarray) -> tuple[list[str], np.ndarray]:
    speakers = sorted({c["speaker"] for c in chunks})
    unit = normalized(vectors)
    return speakers, np.array([unit[[c["speaker"] == sp for c in chunks]].mean(axis=0) for sp in speakers])


def mean_ahc(timeline: list[dict], chunks: list[dict], vectors: np.ndarray, method: str, threshold: float) -> list[dict]:
    # variant 4: AHC over the diarizer speakers' normalized mean embeddings, merged speakers share a label
    speakers, means = speaker_means(chunks, vectors)
    labels = dict(zip(speakers, ahc(means, method, threshold)))
    return [{**s, "speaker": f"M{labels[s['speaker']]}" if s["speaker"] in labels else s["speaker"]} for s in timeline]


def variant_timeline(dump: dict, variant: tuple) -> list[dict]:
    timeline = sorted(dump["timeline"], key=lambda s: s["start"])
    kind, *setting = variant
    if kind == "gate":
        bar, inner = setting
        vectors = np.array([c["embedding"] for c in dump["chunks"]], dtype=float)
        if spectral(vectors, bar)[1] == 1:
            return [{**s, "speaker": "S1"} for s in timeline]
        return variant_timeline(dump, inner)
    if kind == "now":
        return timeline
    if kind == "knob":
        return sorted(dump["knobs"][setting[0]], key=lambda s: s["start"])
    chunks = dump["chunks"]
    vectors = np.array([c["embedding"] for c in chunks], dtype=float)
    if kind == "long":
        return relabelled_timeline(timeline, chunks, long_only(timeline, chunks, vectors, *setting))
    if kind == "spectral":
        return relabelled_timeline(timeline, chunks, spectral(vectors, *setting)[0])
    return mean_ahc(timeline, chunks, vectors, *setting)


def benchmark_score(file_id: str, timeline: list[dict]) -> tuple[DiarizationErrorRate, int, int, int]:
    # DER, shown and real speaker counts, and glued: reference speakers whose most-overlapping hypothesis
    # speaker is also the most-overlapping one of another reference speaker
    reference = json.loads((score.REFS / f"{file_id}.json").read_text())
    ref_segments = [s for s in reference["segments"] if s["channel"] == "system"]
    der = DiarizationErrorRate(collar=score.COLLAR)
    der(annotation(ref_segments), annotation(timeline), uem=Timeline([Segment(0, reference["duration"])]))
    home = {}
    for ref_speaker in {s["speaker"] for s in ref_segments}:
        seconds = Counter()
        for r in (s for s in ref_segments if s["speaker"] == ref_speaker):
            for h in timeline:
                seconds[h["speaker"]] += overlap(r["start"], r["end"], h["start"], h["end"])
        home[ref_speaker] = max(seconds, key=seconds.get) if seconds and max(seconds.values()) > 0 else None
    homes = Counter(h for h in home.values() if h is not None)
    glued = sum(n - 1 for n in homes.values())
    return der, len({s["speaker"] for s in timeline}), len(home), glued


def benchmark_row(bench: dict[str, dict], variant: tuple) -> dict:
    total, count_errors, glued, cells = DiarizationErrorRate(collar=score.COLLAR), [], 0, []
    for file_id in BENCHMARK:
        der, shown, real, file_glued = benchmark_score(file_id, variant_timeline(bench[file_id], variant))
        for component, value in der.accumulated_.items():
            total.accumulated_[component] += value
        count_errors.append(abs(shown - real))
        glued += file_glued
        cells.append(f"{shown}/{real}")
    return {"der": abs(total), "count_error": float(np.mean(count_errors)), "glued": glued, "cells": " ".join(cells)}


def picked(bench: dict[str, dict], grid: list[tuple], glued_now: int) -> tuple[tuple, list[tuple[tuple, dict]]]:
    # benchmark only: glues no more people than today, then the lowest count error, then the lowest DER;
    # on a tie the later (more merging) setting
    rows = [(variant, benchmark_row(bench, variant)) for variant in grid]
    allowed = [row for row in rows if row[1]["glued"] <= glued_now] or rows
    best = min(reversed(allowed), key=lambda row: (row[1]["count_error"], round(row[1]["der"], 3)))
    return best[0], rows


def name(variant: tuple) -> str:
    kind, *setting = variant
    return {
        "now": lambda: "now: FluidAudio 0.15.6 t0.70",
        "knob": lambda: f"FluidAudio knob {setting[0]}",
        "long": lambda: f"long-only ≥{setting[0]} s, AHC avg cos-dist {setting[1]}",
        "spectral": lambda: "eigengap + spectral" + (f", one speaker if mean cos ≥ {setting[0]}" if setting[0] is not None else ""),
        "mean": lambda: f"AHC {setting[0]} on speaker means, cos-dist {setting[1]}",
        "gate": lambda: f"one speaker if mean cos ≥ {setting[0]}, else {name(setting[1])}",
    }[kind]()


def main() -> None:
    bench = {f: json.loads((CHUNKS / f"bench_{f}.json").read_text()) for f in BENCHMARK}
    calls = {call: json.loads((CHUNKS / f"{call}.json").read_text()) for call in CALLS}
    sentences = {call: load_sentences(call) for call in CALLS}
    knobs = sorted(next(iter(bench.values()))["knobs"])
    thresholds = [round(t, 2) for t in np.arange(0.3, 1.01, 0.05)]
    grids = {
        "now": [("now",)],
        "knobs": [("knob", k) for k in knobs],
        **{f"long {n}": [("long", n, t) for t in thresholds] for n in (1.5, 2.0, 3.0)},
        "spectral": [("spectral", None)] + [("spectral", bar) for bar in (0.5, 0.6, 0.7, 0.8)],
        "mean average": [("mean", "average", t) for t in thresholds],
        "mean complete": [("mean", "complete", t) for t in thresholds],
    }

    glued_now = benchmark_row(bench, ("now",))["glued"]
    print("## Benchmark sweep (every setting; the picked one per group is bold)\n")
    print("| variant | DER real | count error | glued | shown/real per file (ES2004a IS1009a asxwr azisu gzvkx) |")
    print("|---|---|---|---|---|")
    chosen = []
    for group, grid in grids.items():
        best, rows = picked(bench, grid, glued_now)
        chosen += [best] if group != "knobs" else grid
        if group == "long 3.0":
            long_best = best
        for variant, row in rows:
            bold = "**" if variant == best and group != "knobs" else ""
            print(f"| {bold}{name(variant)}{bold} | {row['der']:.3f} | {row['count_error']:.2f} | {row['glued']} | {row['cells']} |")
    print()

    # the benchmark has no one-speaker file, so it cannot pick the bar: these are listed, not picked
    chosen += [("gate", bar, inner) for inner in (("now",), long_best) for bar in (0.65, 0.7, 0.75)]
    print("## Picked settings on the 15 calls\n")
    print("| variant | " + " | ".join(CALLS) + " | 1:1 exact (of 10) | dailies exact (of 5) | total \\|Δ\\| | DER | count error | glued | ms per call |")
    print("|---|" + "---|" * (len(CALLS) + 7))
    print("| real | " + " | ".join(str(DAILIES.get(c, 1)) for c in CALLS) + " | | | | | | | |")
    for variant in chosen:
        counts, seconds = {}, []
        for call in CALLS:
            started = time.perf_counter()
            timeline = variant_timeline(calls[call], variant)
            seconds.append(time.perf_counter() - started)
            counts[call] = len(set(assigned_speakers(sentences[call], timeline)))
        row = benchmark_row(bench, variant)
        print(f"| {name(variant)} | " + " | ".join(str(counts[c]) for c in CALLS)
              + f" | {sum(counts[c] == 1 for c in ONE_ON_ONE)} | {sum(counts[c] == DAILIES[c] for c in DAILIES)} | "
              f"{sum(abs(counts[c] - DAILIES.get(c, 1)) for c in CALLS)} | {row['der']:.3f} | {row['count_error']:.2f} | {row['glued']} | "
              f"{1000 * np.median(seconds):.0f} |")
    print()

    print("## One speaker or more: mean window-to-centroid cosine\n")
    print("| call or file | real | windows | mean cos to centroid | eigengap k |")
    print("|---|---|---|---|---|")
    for key, dump, real in [*((c, calls[c], DAILIES.get(c, 1)) for c in CALLS),
                            *((f, bench[f], benchmark_score(f, bench[f]["timeline"])[2]) for f in BENCHMARK),
                            *((path.stem.removeprefix("bench_"), json.loads(path.read_text()),
                               benchmark_score(path.stem.removeprefix("bench_"), [])[2]) for path in sorted(CHUNKS.glob("bench_call_*.json")))]:
        _, k, mean_cos = spectral(np.array([c["embedding"] for c in dump["chunks"]], dtype=float), None)
        print(f"| {key} | {real} | {len(dump['chunks'])} | {mean_cos:.3f} | {k} |")


if __name__ == "__main__":
    main()
