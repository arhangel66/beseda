"""Score the baseline hypothesis dirs with the epic scorer, plus ru / mixed WER and system-only DER."""

import json
import sys
from pathlib import Path

from pyannote.core import Annotation, Segment
from pyannote.metrics.diarization import DiarizationErrorRate

sys.path.insert(0, str(Path(__file__).parent.parent))
import score  # noqa: E402

HYPOTHESES = ["baseline-parakeet", "baseline-gigaam", "baseline-diarizer-raw"]


def remote_speakers(path: Path) -> Annotation:
    # system-channel speakers only: "me" and the mic channel left out
    annotation = Annotation()
    for segment in json.loads(path.read_text())["segments"]:
        if segment["channel"] == "system" and segment["end"] > segment["start"]:
            annotation[Segment(segment["start"], segment["end"])] = segment["speaker"]
    return annotation


def system_only_der(call_ids: list[str], hyp_dir: Path) -> float:
    # DER inside the system channel of the synthetic calls, same collar as score.py
    metric = DiarizationErrorRate(collar=0.5)
    for call_id in call_ids:
        metric(remote_speakers(score.REFS / f"{call_id}.json"), remote_speakers(hyp_dir / f"{call_id}.json"))
    return abs(metric)


def main() -> None:
    call_ids = sorted(path.stem for path in score.REFS.glob("call_*.json"))
    groups = {
        "ru": [c for c in call_ids if c.startswith("call_ru_")],
        "mixed ru-en": [c for c in call_ids if not c.startswith("call_ru_")],
    }
    lines = ["| hypothesis | WER ru | CER ru | WER mixed | CER mixed | DER system channel only (synthetic) |",
             "|---|---|---|---|---|---|"]
    for name in HYPOTHESES:
        hyp_dir = score.ROOT / "hyp" / name
        score.main(f"hyp/{name}")
        by_language = {group: score.score_group(ids, hyp_dir)[0] for group, ids in groups.items()}
        ru, mixed = by_language["ru"], by_language["mixed ru-en"]
        lines.append(f"| {name} | {ru['wer']:.3f} | {ru['cer']:.3f} | {mixed['wer']:.3f} | {mixed['cer']:.3f} "
                     f"| {system_only_der(call_ids, hyp_dir):.3f} |")
    table = "\n".join(lines) + "\n"
    (score.ROOT / "results" / "baseline-extra.md").write_text(table)
    print(table)


if __name__ == "__main__":
    main()
