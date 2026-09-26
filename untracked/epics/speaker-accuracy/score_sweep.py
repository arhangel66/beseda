"""DER and speaker-count error of each diarizer variant in hyp/sweep/ (RealCalls on every <id>.system.wav),
system channel only, against data/refs. BESEDA-69."""

import json
from pathlib import Path

from pyannote.core import Annotation, Segment, Timeline
from pyannote.metrics.diarization import DiarizationErrorRate

import score

SWEEP = score.ROOT / "hyp" / "sweep"


def annotation(segments: list[dict]) -> Annotation:
    annotated = Annotation()
    for index, segment in enumerate(segments):
        annotated[Segment(segment["start"], segment["end"]), index] = segment["speaker"]
    return annotated


def main(sweep: Path) -> None:
    # one row per variant: DER and mean |hyp - ref| speaker count, real and synthetic sets separately
    timelines = {path.stem: [json.loads(line) for line in path.read_text().splitlines()] for path in sorted(sweep.glob("*.jsonl"))}
    variants = [row["variant"] for row in next(iter(timelines.values()))]
    lines = ["| variant | DER real | speaker-count error real | DER synthetic system | speaker-count error synthetic |",
             "|---|---|---|---|---|"]
    for variant in variants:
        cells = []
        for synthetic in (False, True):
            der, count_errors = DiarizationErrorRate(collar=score.COLLAR), []
            for file_id, rows in timelines.items():
                if file_id.startswith("call_") != synthetic:
                    continue
                reference = json.loads((score.REFS / f"{file_id}.json").read_text())
                ref = annotation([s for s in reference["segments"] if s["channel"] == "system"])
                hyp = annotation(next(row["segments"] for row in rows if row["variant"] == variant))
                der(ref, hyp, uem=Timeline([Segment(0, reference["duration"])]))
                count_errors.append(abs(len(hyp.labels()) - len(ref.labels())))
            cells += [f"{abs(der):.3f}", f"{sum(count_errors) / len(count_errors):.2f}"]
        lines.append(f"| {variant} | " + " | ".join(cells) + " |")
    table = "\n".join(lines) + "\n"
    (score.ROOT / "results" / "threshold-sweep-benchmark.md").write_text(table)
    print(table)


if __name__ == "__main__":
    main(SWEEP)
