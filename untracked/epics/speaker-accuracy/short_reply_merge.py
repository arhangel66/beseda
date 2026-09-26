"""BESEDA-82: score "merge speakers with no long turn" variants on the 15 real calls (count vs real-calls-truth.md)
and the real benchmark files (DER, speaker-count error, real people glued). Reads hyp/extra/*.json
(extra_speakers.sh, t0.70 in `system`, t0.80 in `system80`) and, for the FluidAudio 0.17.4 row, hyp/fluid0174/."""

import json
from pathlib import Path

import numpy as np
from pyannote.core import Segment, Timeline
from pyannote.metrics.diarization import DiarizationErrorRate

import score
from extra_speakers import DAILIES, EXTRA, ONE_ON_ONE, assigned_speakers, centroid, cosine, load_sentences
from score_sweep import annotation

FLUID_0174 = score.ROOT / "hyp" / "fluid0174"
BENCHMARK = ["ami_ES2004a", "ami_IS1009a", "vox_asxwr", "vox_azisu", "vox_gzvkx"]
CALLS = ONE_ON_ONE + list(DAILIES)


def longest_per_speaker(timeline: list[dict]) -> dict[str, float]:
    longest: dict[str, float] = {}
    for s in timeline:
        longest[s["speaker"]] = max(longest.get(s["speaker"], 0.0), s["end"] - s["start"])
    return longest


def merged_timeline(timeline: list[dict], limit: float, target: str, min_cosine: float | None = None) -> list[dict]:
    # speakers whose longest segment is under `limit` s are relabelled to a kept speaker: per segment the nearest
    # in time (`time`) or, per speaker, the one with the closest mean embedding (`embedding`)
    longest = longest_per_speaker(timeline)
    kept = {sp for sp, value in longest.items() if value >= limit}
    if not kept:
        seconds = {sp: sum(s["end"] - s["start"] for s in timeline if s["speaker"] == sp) for sp in longest}
        kept = {max(seconds, key=seconds.get)}
    centroids = {sp: centroid([s for s in timeline if s["speaker"] == sp]) for sp in longest}
    closest = {}
    for sp in longest.keys() - kept:
        cosines = {k: cosine(centroids[sp], centroids[k]) for k in kept
                   if centroids[sp] is not None and centroids[k] is not None}
        best = max(cosines, key=cosines.get) if cosines else None
        if min_cosine is None or (best is not None and cosines[best] >= min_cosine):
            closest[sp] = best
    kept_segments = [s for s in timeline if s["speaker"] in kept]
    relabelled = []
    for s in timeline:
        speaker = s["speaker"]
        if speaker in closest:
            if target == "embedding" and closest[speaker] is not None:
                speaker = closest[speaker]
            else:
                speaker = min(kept_segments, key=lambda k: max(k["start"] - s["end"], s["start"] - k["end"], 0.0))["speaker"]
        relabelled.append({**s, "speaker": speaker})
    return relabelled


VARIANTS = {
    "now t0.70": ("system", None),
    "now t0.80": ("system80", None),
    **{f"<{limit} s, time, t0.{t}": (key, (limit, "time", None)) for t, key in (("70", "system"), ("80", "system80"))
       for limit in (6, 7)},
    "<6.5 s, time, t0.70": ("system", (6.5, "time", None)),
    **{f"<{limit} s, embedding, t0.{t}": (key, (limit, "embedding", None)) for t, key in (("70", "system"), ("80", "system80"))
       for limit in (6, 7)},
    **{f"<7 s + cos ≥ {c}, time, t0.70": ("system", (7, "time", c)) for c in (0.1, 0.2, 0.3)},
}


def timeline_of(dump: dict, key: str, rule: tuple | None) -> list[dict]:
    timeline = sorted(dump[key], key=lambda s: s["start"])
    return merged_timeline(timeline, *rule) if rule else timeline


def call_count(call: str, timeline: list[dict]) -> int:
    return len(set(assigned_speakers(load_sentences(call), timeline)))


def benchmark_scores(file_id: str, timeline: list[dict], original: list[dict]) -> tuple[DiarizationErrorRate, int, int]:
    # DER, hyp speakers, and how many reference speakers lost their own diarizer speaker to a merge
    reference = json.loads((score.REFS / f"{file_id}.json").read_text())
    ref_segments = [s for s in reference["segments"] if s["channel"] == "system"]
    der = DiarizationErrorRate(collar=score.COLLAR)
    der(annotation(ref_segments), annotation(timeline), uem=Timeline([Segment(0, reference["duration"])]))
    # each original speaker is "real" for the reference speaker it overlaps most, if it is the biggest such piece
    owner, seconds = {}, {}
    for sp in {s["speaker"] for s in original}:
        spans = [[s["start"], s["end"]] for s in original if s["speaker"] == sp]
        per_ref: dict[str, float] = {}
        for r in ref_segments:
            per_ref[r["speaker"]] = per_ref.get(r["speaker"], 0) + sum(max(0, min(r["end"], b) - max(r["start"], a)) for a, b in spans)
        owner[sp], seconds[sp] = max(per_ref, key=per_ref.get), sum(b - a for a, b in spans)
    real = {sp for sp in owner if seconds[sp] == max(seconds[o] for o in owner if owner[o] == owner[sp])}
    after = {}
    for before, now in zip(sorted(original, key=lambda s: s["start"]), timeline):
        if before["speaker"] in real:
            after.setdefault(now["speaker"], set()).add(owner[before["speaker"]])
    glued = sum(len(refs) - 1 for refs in after.values())
    return der, len({s["speaker"] for s in timeline}), glued


def fluid_timeline(name: str) -> list[dict] | None:
    path = FLUID_0174 / f"{name}.json"
    # no embeddings in the Diarize output, so only the `time` target applies
    return sorted(({**s, "embedding": []} for s in json.loads(path.read_text())["segments"]), key=lambda s: s["start"]) if path.exists() else None


def main() -> None:
    dumps = {call: json.loads((EXTRA / f"{call}.json").read_text()) for call in CALLS}
    bench = {f: json.loads((EXTRA / f"bench_{f}.json").read_text()) for f in BENCHMARK}
    counts = {name: {call: call_count(call, timeline_of(dumps[call], key, rule)) for call in CALLS}
              for name, (key, rule) in VARIANTS.items()}
    fluid = {call: fluid_timeline(call) for call in CALLS}
    if all(fluid.values()):
        for name, rule in (("0.17.4 t0.70", None), ("0.17.4 t0.70 <6 s, time", (6, "time", None))):
            counts[name] = {call: call_count(call, merged_timeline(fluid[call], *rule) if rule else fluid[call]) for call in CALLS}
    names = list(counts)
    print("| call | real | " + " | ".join(names) + " |")
    print("|---|---|" + "---|" * len(names))
    for call in CALLS:
        print(f"| {call} | {DAILIES.get(call, 1)} | " + " | ".join(str(counts[n][call]) for n in names) + " |")
    print("| **total \\|Δ\\|** | | " + " | ".join(
        f"**{sum(abs(counts[n][c] - DAILIES.get(c, 1)) for c in CALLS)}**" for n in names) + " |")
    print("| 1:1 exact (of 10) | | " + " | ".join(str(sum(counts[n][c] == 1 for c in ONE_ON_ONE)) for n in names) + " |")
    print()

    print("| variant | DER real | speaker-count error real | real people glued | per file: shown / real |")
    print("|---|---|---|---|---|")
    rows = [(name, {f: timeline_of(bench[f], key, rule) for f in BENCHMARK}, {f: sorted(bench[f][key], key=lambda s: s["start"]) for f in BENCHMARK})
            for name, (key, rule) in VARIANTS.items()]
    fluid_bench = {f: fluid_timeline(f"bench_{f}") for f in BENCHMARK}
    if all(fluid_bench.values()):
        rows.append(("0.17.4 t0.70", fluid_bench, fluid_bench))
        rows.append(("0.17.4 t0.70 <6 s, time", {f: merged_timeline(fluid_bench[f], 6, "time") for f in BENCHMARK}, fluid_bench))
    for name, timelines, originals in rows:
        total = DiarizationErrorRate(collar=score.COLLAR)
        count_errors, glued_total, cells = [], 0, []
        for f in BENCHMARK:
            der, shown, glued = benchmark_scores(f, timelines[f], originals[f])
            for component, value in der.accumulated_.items():
                total.accumulated_[component] += value
            reference = {s["speaker"] for s in json.loads((score.REFS / f"{f}.json").read_text())["segments"] if s["channel"] == "system"}
            count_errors.append(abs(shown - len(reference)))
            glued_total += glued
            cells.append(f"{f} {shown}/{len(reference)}")
        print(f"| {name} | {abs(total):.3f} | {np.mean(count_errors):.2f} | {glued_total} | {', '.join(cells)} |")
    print()

    print("| call or file | short speaker | longest s | seconds | best kept by cosine | cos | nearest-in-time target of most seconds |")
    print("|---|---|---|---|---|---|---|")
    for name, dump in [*dumps.items(), *((f"bench_{f}", d) for f, d in bench.items())]:
        timeline = sorted(dump["system"], key=lambda s: s["start"])
        longest = longest_per_speaker(timeline)
        kept = [sp for sp, value in longest.items() if value >= 7]
        merged = merged_timeline(timeline, 7, "time")
        for sp in sorted(longest.keys() - set(kept)):
            own = [s for s in timeline if s["speaker"] == sp]
            cosines = {k: cosine(centroid(own), centroid([s for s in timeline if s["speaker"] == k])) for k in kept}
            best = max(cosines, key=cosines.get) if cosines else "–"
            targets: dict[str, float] = {}
            for before, after in zip(timeline, merged):
                if before["speaker"] == sp:
                    targets[after["speaker"]] = targets.get(after["speaker"], 0) + before["end"] - before["start"]
            print(f"| {name} | {sp} | {longest[sp]:.1f} | {sum(s['end'] - s['start'] for s in own):.0f} | {best} | "
                  f"{cosines.get(best, float('nan')):.2f} | {max(targets, key=targets.get)} |")


if __name__ == "__main__":
    main()
