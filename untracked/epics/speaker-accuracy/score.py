"""Score a hypothesis dir against data/refs: DER, speaker count, WER/CER, me/them attribution, speed."""

import json
import re
from pathlib import Path

import jiwer
from pyannote.core import Annotation, Segment, Timeline
from pyannote.metrics.diarization import DiarizationErrorRate

from make_eval import AUDIO, REFS, ROOT, build, read_rttm

COLLAR = 0.25


def normalize(text: str) -> str:
    text = re.sub(r"[^\w\s]|_", " ", text.lower().replace("ё", "е"))
    return " ".join(text.split())


def load_hypothesis(hyp_dir: Path, file_id: str) -> tuple[Annotation, dict]:
    # a missing file counts as an empty hypothesis, so it scores as all missed speech
    annotation = Annotation(uri=file_id)
    rttm_path, json_path = hyp_dir / f"{file_id}.rttm", hyp_dir / f"{file_id}.json"
    if rttm_path.exists():
        for index, (start, end, speaker) in enumerate(read_rttm(rttm_path.read_text())):
            annotation[Segment(start, end), index] = speaker
    hypothesis = json.loads(json_path.read_text()) if json_path.exists() else {"segments": []}
    return annotation, hypothesis


def speech_on_channel(segments: list[dict], channel: str) -> Timeline:
    return Timeline([Segment(s["start"], s["end"]) for s in segments if s["channel"] == channel]).support()


def overlap_seconds(timeline: Timeline, other: Timeline) -> float:
    return timeline.crop(other, mode="intersection").support().duration() if other else 0.0


def channel_text(segments: list[dict], channel: str) -> str:
    ordered = sorted((s for s in segments if s["channel"] == channel), key=lambda s: s["start"])
    return normalize(" ".join(s["text"] for s in ordered))


def score_attribution(reference: list[dict], hypothesis: list[dict]) -> dict:
    # reference speech heard only on the wrong channel, and hyp mic words spoken while "me" was silent (echo)
    misattributed = total = 0.0
    for channel, other in (("mic", "system"), ("system", "mic")):
        ref_speech = speech_on_channel(reference, channel)
        hyp_right, hyp_wrong = speech_on_channel(hypothesis, channel), speech_on_channel(hypothesis, other)
        wrong_only = ref_speech.crop(hyp_wrong, mode="intersection").support() if hyp_wrong else Timeline()
        misattributed += wrong_only.duration() - overlap_seconds(wrong_only, hyp_right)
        total += ref_speech.duration()
    me_speech = speech_on_channel(reference, "mic")
    bleed_words = 0.0
    for segment in hypothesis:
        words = len(normalize(segment["text"]).split())
        if segment["channel"] == "mic" and words and segment["end"] > segment["start"]:
            span = Timeline([Segment(segment["start"], segment["end"])])
            outside_me = 1 - overlap_seconds(span, me_speech) / span.duration()
            bleed_words += words * outside_me
    return {"misattributed_seconds": misattributed, "speech_seconds": total, "bleed_words": bleed_words,
            "system_words": len(channel_text(reference, "system").split())}


def score_group(file_ids: list[str], hyp_dir: Path) -> tuple[dict, list[dict]]:
    der, der_no_overlap = DiarizationErrorRate(collar=COLLAR), DiarizationErrorRate(collar=COLLAR, skip_overlap=True)
    per_file, refs_text, hyps_text = [], [], []
    attribution = {"misattributed_seconds": 0.0, "speech_seconds": 0.0, "bleed_words": 0.0, "system_words": 0}
    audio_seconds = processing_seconds = 0.0
    for file_id in file_ids:
        reference = json.loads((REFS / f"{file_id}.json").read_text())
        ref_annotation, _ = load_hypothesis(REFS, file_id)
        hyp_annotation, hypothesis = load_hypothesis(hyp_dir, file_id)
        uem = Timeline([Segment(0, reference["duration"])])
        row = {
            "file": file_id,
            "der": der(ref_annotation, hyp_annotation, uem=uem),
            "der_no_overlap": der_no_overlap(ref_annotation, hyp_annotation, uem=uem),
            "ref_speakers": len(ref_annotation.labels()),
            "hyp_speakers": len(hyp_annotation.labels()),
        }
        ref_text = channel_text(reference["segments"], "system")
        if ref_text:
            refs_text.append(ref_text)
            hyps_text.append(channel_text(hypothesis["segments"], "system"))
            row["wer"] = jiwer.wer(ref_text, hyps_text[-1])
        if any(s["channel"] == "mic" for s in reference["segments"]):
            for key, value in score_attribution(reference["segments"], hypothesis["segments"]).items():
                attribution[key] += value
        if hypothesis.get("processing_seconds"):
            audio_seconds += reference["duration"]
            processing_seconds += hypothesis["processing_seconds"]
        per_file.append(row)

    summary = {
        "files": len(file_ids),
        "der": abs(der),
        "der_no_overlap": abs(der_no_overlap),
        "speaker_count_error": sum(abs(r["hyp_speakers"] - r["ref_speakers"]) for r in per_file) / len(per_file),
        "wer": jiwer.wer(refs_text, hyps_text) if refs_text else None,
        "cer": jiwer.cer(refs_text, hyps_text) if refs_text else None,
        "me_them_error": attribution["misattributed_seconds"] / attribution["speech_seconds"] if attribution["speech_seconds"] else None,
        "bleed_duplicate_word_rate": attribution["bleed_words"] / attribution["system_words"] if attribution["system_words"] else None,
        "x_realtime": audio_seconds / processing_seconds if processing_seconds else None,
    }
    return summary, per_file


def markdown_table(summaries: dict[str, dict]) -> str:
    columns = ["files", "der", "der_no_overlap", "speaker_count_error", "wer", "cer", "me_them_error",
               "bleed_duplicate_word_rate", "x_realtime"]
    lines = ["| set | " + " | ".join(columns) + " |", "|---" * (len(columns) + 1) + "|"]
    for name, summary in summaries.items():
        cells = ["-" if summary[c] is None else f"{summary[c]:.3f}" if isinstance(summary[c], float) else str(summary[c])
                 for c in columns]
        lines.append(f"| {name} | " + " | ".join(cells) + " |")
    return "\n".join(lines) + "\n"


def main(hyp_dir: str) -> dict:
    # fetch and build the eval set unless its audio is already here, score hyp_dir into results/<hyp name>.md/.json
    hyp_path = ROOT / hyp_dir
    if not AUDIO.exists():
        build()
    file_ids = sorted(path.stem for path in REFS.glob("*.json"))
    groups = {
        "real (VoxConverse+AMI)": [f for f in file_ids if not f.startswith("call_")],
        "synthetic calls (FLEURS)": [f for f in file_ids if f.startswith("call_")],
        "all": file_ids,
    }
    summaries, per_file = {}, []
    for name, ids in groups.items():
        summaries[name], rows = score_group(ids, hyp_path)
        if name == "all":
            per_file = rows
    table = markdown_table(summaries)
    results = ROOT / "results"
    results.mkdir(exist_ok=True)
    (results / f"{hyp_path.name}.md").write_text(table)
    (results / f"{hyp_path.name}.json").write_text(json.dumps({"summary": summaries, "files": per_file}, indent=1) + "\n")
    print(table)
    return summaries


if __name__ == "__main__":
    main("data/refs")
