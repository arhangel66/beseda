"""BESEDA-79: where the extra `them` speakers of 1:1 calls come from. Reads hyp/extra/*.json (extra_speakers.sh)
and the calls' them.asr.json (a copy), replays the app's per-sentence assignment on the t0.70 diarizer timeline,
and prints markdown tables: per call and speaker, and the same stats for the benchmark's real speakers."""

import json
import shutil
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).parent
EXTRA = ROOT / "hyp" / "extra"
STORE = Path.home() / "Library" / "Application Support" / "Beseda" / "calls"
ONE_ON_ONE = ["20260925-114649", "20260925-111702", "20260924-173649", "20260924-173310", "20260924-133358",
              "20260924-110157", "20260923-125419", "20260923-101613", "20260922-115609", "20260922-084404"]
DAILY = "20260923-130021"
DAILIES = {"20260925-125945": 3, "20260924-130017": 4, "20260923-130021": 4, "20260922-125838": 4, "20260921-125925": 4}
LONGEST_SEGMENT_LIMITS = [4, 5, 6, 7, 8]
EDGE_SECONDS = 30
SILENCE_SECONDS = 5


def cosine(a: np.ndarray, b: np.ndarray) -> float:
    return float(a @ b / (np.linalg.norm(a) * np.linalg.norm(b)))


def centroid(segments: list[dict]) -> np.ndarray | None:
    vectors = [np.array(s["embedding"]) for s in segments if s["embedding"]]
    return np.mean([v / np.linalg.norm(v) for v in vectors], axis=0) if vectors else None


def overlap(start: float, end: float, intervals: list[list[float]]) -> float:
    return sum(max(0.0, min(end, b) - max(start, a)) for a, b in intervals)


def assigned_speakers(sentences: list[dict], timeline: list[dict]) -> list[str]:
    # the app's SentenceSpeakerAssignment: most-overlapping diarizer segment, else the nearest one
    speakers = []
    for sentence in sentences:
        overlaps = [min(t["end"], sentence["end"]) - max(t["start"], sentence["start"]) for t in timeline]
        best = int(np.argmax(overlaps))
        if overlaps[best] <= 0:
            best = min(range(len(timeline)), key=lambda i: min(abs(timeline[i]["start"] - sentence["end"]),
                                                               abs(sentence["start"] - timeline[i]["end"])))
        speakers.append(timeline[best]["speaker"])
    return speakers


def level(segments: list[dict], decibels: list[float]) -> float:
    # median 100 ms level over the speaker's diarizer segments
    frames = [decibels[i] for s in segments for i in range(int(s["start"] * 10), min(int(s["end"] * 10), len(decibels)))]
    return float(np.median(frames)) if frames else float("nan")


def load_sentences(call: str) -> list[dict]:
    with tempfile.TemporaryDirectory() as work:
        copy = shutil.copy(STORE / call / "them.asr.json", work)
        return json.loads(Path(copy).read_text())["segments"]


def call_rows(call: str) -> list[dict]:
    # one row per `them` speaker the app shows, biggest first; the first row is the main speaker
    dump = json.loads((EXTRA / f"{call}.json").read_text())
    timeline = sorted(dump["system"], key=lambda s: s["start"])
    sentences = load_sentences(call)
    labels = assigned_speakers(sentences, timeline)
    duration = len(dump["systemDb"]) / 10
    mic_own = [s for s in dump["mic"] if overlap(s["start"], s["end"], dump["ownSpeech"]) >= 0.5 * (s["end"] - s["start"])]
    mikhail = centroid(mic_own)
    shown = sorted(set(labels), key=lambda sp: -sum(s["end"] - s["start"] for s, l in zip(sentences, labels) if l == sp))
    main = [s for s in timeline if s["speaker"] == shown[0]]
    main_centroid, main_level = centroid(main), level(main, dump["systemDb"])
    rows = []
    for speaker in shown:
        own = [s for s in timeline if s["speaker"] == speaker]
        own_sentences = [s for s, l in zip(sentences, labels) if l == speaker]
        diar_seconds = sum(s["end"] - s["start"] for s in own)
        others = [[t["start"], t["end"]] for t in timeline if t["speaker"] != speaker]
        after_silence = 0
        for s in own:
            previous_end = max((t["end"] for t in timeline if t["start"] < s["start"] and t is not s), default=0.0)
            after_silence += s["start"] - previous_end >= SILENCE_SECONDS
        me = centroid(own)
        rows.append({
            "speaker": speaker,
            "sentence_seconds": sum(s["end"] - s["start"] for s in own_sentences),
            "sentences": len(own_sentences),
            "words": sum(len(s["text"].split()) for s in own_sentences),
            "diar_seconds": diar_seconds,
            "segments": len(own),
            "segment_lengths": sorted(round(s["end"] - s["start"], 1) for s in own),
            "edge": sum(s["start"] < EDGE_SECONDS or s["end"] > duration - EDGE_SECONDS for s in own),
            "after_silence": after_silence,
            "mic_share": sum(overlap(s["start"], s["end"], dump["ownSpeech"]) for s in own) / max(diar_seconds, 1e-9),
            "overlap_share": sum(overlap(s["start"], s["end"], others) for s in own) / max(diar_seconds, 1e-9),
            "level_vs_main": level(own, dump["systemDb"]) - main_level,
            "cos_main": cosine(me, main_centroid) if me is not None else float("nan"),
            "cos_mikhail": cosine(me, mikhail) if me is not None and mikhail is not None else float("nan"),
            "sentences_outside_diar": sum(
                overlap(s["start"], s["end"], [[t["start"], t["end"]] for t in own]) <= 0 for s in own_sentences),
            "duration": duration,
            "longest": max(s["end"] - s["start"] for s in own),
        })
    return rows


def benchmark_rows(file_id: str) -> list[dict]:
    # every diarizer speaker of a benchmark file, mapped to the reference speaker it overlaps most;
    # `real` = the biggest diarizer speaker of that reference speaker, the others are splits of it
    dump = json.loads((EXTRA / f"bench_{file_id}.json").read_text())
    reference = [s for s in json.loads((ROOT / "data" / "refs" / f"{file_id}.json").read_text())["segments"]
                 if s["channel"] == "system"]
    by_speaker: dict[str, list[dict]] = {}
    for s in dump["system"]:
        by_speaker.setdefault(s["speaker"], []).append(s)
    rows = []
    for speaker, own in by_speaker.items():
        per_ref = {}
        for r in reference:
            per_ref[r["speaker"]] = per_ref.get(r["speaker"], 0) + overlap(r["start"], r["end"], [[s["start"], s["end"]] for s in own])
        rows.append({"file": file_id, "speaker": speaker, "ref": max(per_ref, key=per_ref.get),
                     "seconds": sum(s["end"] - s["start"] for s in own), "segments": len(own), "centroid": centroid(own),
                     "longest": max(s["end"] - s["start"] for s in own)})
    for row in rows:
        row["real"] = row is max((r for r in rows if r["ref"] == row["ref"]), key=lambda r: r["seconds"])
        others = [r for r in rows if r is not row and r["centroid"] is not None and row["centroid"] is not None]
        row["max_cos_other"] = max((cosine(row["centroid"], r["centroid"]) for r in others), default=float("nan"))
        bigger = [r for r in others if r["seconds"] > row["seconds"]]
        row["max_cos_bigger"] = max((cosine(row["centroid"], r["centroid"]) for r in bigger), default=float("nan"))
    return rows


def fmt(value: float, digits: int = 2) -> str:
    return "–" if value != value else f"{value:.{digits}f}"


def main() -> None:
    lines = ["| call | speaker | sentence s | sentences | words | diar s | segments | segment lengths s | "
             "in first/last 30 s | after ≥5 s silence | during mic speech | overlapped | level vs main dB | "
             "cos main | cos Mikhail | sentences off diar |", "|" + "---|" * 16]
    for call in ONE_ON_ONE + [DAILY]:
        for index, row in enumerate(call_rows(call)):
            lengths = row["segment_lengths"]
            shown = ", ".join(map(str, lengths)) if len(lengths) <= 6 else f"median {np.median(lengths):.1f}, max {max(lengths)}"
            lines.append(
                f"| {call if index == 0 else ''} | {'main' if index == 0 else row['speaker']} | {row['sentence_seconds']:.0f} | "
                f"{row['sentences']} | {row['words']} | {row['diar_seconds']:.0f} | {row['segments']} | {shown} | {row['edge']} | "
                f"{row['after_silence']} | {row['mic_share']:.0%} | {row['overlap_share']:.0%} | "
                f"{fmt(row['level_vs_main'], 1)} | {fmt(row['cos_main'])} | {fmt(row['cos_mikhail'])} | {row['sentences_outside_diar']} |")
    print("\n".join(lines))
    print()
    print("| file | diarizer speaker | reference | real or split | seconds | segments | longest segment s | max cos to another | max cos to a bigger |")
    print("|---|---|---|---|---|---|---|---|---|")
    for path in sorted(EXTRA.glob("bench_*.json")):
        for row in sorted(benchmark_rows(path.stem.removeprefix("bench_")), key=lambda r: -r["seconds"]):
            print(f"| {row['file']} | {row['speaker']} | {row['ref']} | {'real' if row['real'] else 'split'} | "
                  f"{row['seconds']:.0f} | {row['segments']} | {row['longest']:.1f} | {fmt(row['max_cos_other'])} | {fmt(row['max_cos_bigger'])} |")

    print()
    print("| call | real | now | " + " | ".join(f"longest < {limit} s merged" for limit in LONGEST_SEGMENT_LIMITS) + " |")
    print("|---|---|---|" + "---|" * len(LONGEST_SEGMENT_LIMITS))
    for call in ONE_ON_ONE + list(DAILIES):
        longest = [row["longest"] for row in call_rows(call)]
        after = [max(1, sum(value >= limit for value in longest)) for limit in LONGEST_SEGMENT_LIMITS]
        print(f"| {call} | {DAILIES.get(call, 1)} | {len(longest)} | " + " | ".join(map(str, after)) + " |")
    print()
    print("| benchmark | real speakers | now | " + " | ".join(f"longest < {limit} s merged" for limit in LONGEST_SEGMENT_LIMITS) + " |")
    print("|---|---|---|" + "---|" * len(LONGEST_SEGMENT_LIMITS))
    for path in sorted(EXTRA.glob("bench_*.json")):
        file_id = path.stem.removeprefix("bench_")
        rows = benchmark_rows(file_id)
        references = {s["speaker"] for s in json.loads((ROOT / "data" / "refs" / f"{file_id}.json").read_text())["segments"]
                      if s["channel"] == "system"}
        after = [max(1, sum(r["longest"] >= limit for r in rows)) for limit in LONGEST_SEGMENT_LIMITS]
        print(f"| {file_id} | {len(references)} | {len(rows)} | " + " | ".join(map(str, after)) + " |")


if __name__ == "__main__":
    main()
