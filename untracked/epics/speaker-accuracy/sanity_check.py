"""Scorer sanity: the reference scores DER 0 / WER 0, a one-speaker-for-everything hypothesis scores a high DER."""

import json

from make_eval import REFS, ROOT
from score import main as score

ONE_SPEAKER = ROOT / "hyp" / "one_speaker"


def write_one_speaker_hypothesis() -> None:
    # every reference turn relabelled to one speaker on the system channel, text kept
    ONE_SPEAKER.mkdir(parents=True, exist_ok=True)
    for path in REFS.glob("*.json"):
        reference = json.loads(path.read_text())
        segments = [{**s, "speaker": "all", "channel": "system"} for s in reference["segments"]]
        (ONE_SPEAKER / path.name).write_text(json.dumps({"segments": segments, "processing_seconds": None}))
        rttm = "".join(" ".join([*line.split()[:7], "all", "<NA>", "<NA>"]) + "\n"
                       for line in (REFS / f"{path.stem}.rttm").read_text().splitlines())
        (ONE_SPEAKER / f"{path.stem}.rttm").write_text(rttm)


if __name__ == "__main__":
    reference = score("data/refs")["all"]
    assert reference["der"] == 0 and reference["wer"] == 0 and reference["me_them_error"] == 0, reference
    write_one_speaker_hypothesis()
    one_speaker = score("hyp/one_speaker")["all"]
    assert one_speaker["der"] > 0.2, one_speaker
    print("sanity ok")
