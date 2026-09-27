"""BESEDA-121: does removing double-talk from the system channel fold the short overlapped replies into the main
voice? Reads hyp/double-talk/*.json (double_talk.sh) and copies of them/me.asr.json, counts `them` on the 15 truth
calls through the app's per-sentence assignment. Prints the markdown tables of results/double-talk.md."""

import json
import shutil
import tempfile
from pathlib import Path

from extra_speakers import DAILIES, ONE_ON_ONE, STORE, assigned_speakers, load_sentences, overlap
from short_reply_merge import merged_timeline

DUMPS = Path(__file__).parent / "hyp" / "double-talk"
CALLS = ONE_ON_ONE + list(DAILIES)


def relabelled_by_zeroed(now: list[dict], zeroed: list[dict]) -> list[dict]:
    # variant 2: keep today's segments, take each one's speaker from the zeroed run (clustered without double-talk):
    # the most-overlapping zeroed segment, else the nearest in time
    relabelled = []
    for s in now:
        best = max(zeroed, key=lambda z: (min(s["end"], z["end"]) - max(s["start"], z["start"]),
                                          -max(z["start"] - s["end"], s["start"] - z["end"], 0.0)))
        relabelled.append({**s, "speaker": best["speaker"]})
    return relabelled


def count(sentences: list[dict], timeline: list[dict]) -> int:
    return len(set(assigned_speakers(sentences, timeline)))


def with_six_second_rule(timeline: list[dict]) -> list[dict]:
    # the time target reads no embeddings; merged_timeline still builds centroids, so give it none
    return merged_timeline([{**s, "embedding": []} for s in timeline], 6, "time")


def load_mic_sentences(call: str) -> list[dict]:
    with tempfile.TemporaryDirectory() as work:
        return json.loads(Path(shutil.copy(STORE / call / "me.asr.json", work)).read_text())["segments"]


def main() -> None:
    columns = ["now (t0.70)", "6 s rule", "1: zeroed", "1: zeroed + 6 s", "2: embeddings only", "2 + 6 s"]
    counts: dict[str, dict[str, int]] = {}
    stats = []
    for call in CALLS:
        dump = json.loads((DUMPS / f"{call}.json").read_text())
        sentences, mic = load_sentences(call), load_mic_sentences(call)
        now = sorted(dump["now"], key=lambda s: s["start"])
        zeroed = sorted(dump["zeroed"], key=lambda s: s["start"])
        embeddings_only = relabelled_by_zeroed(now, zeroed)
        counts[call] = dict(zip(columns, (count(sentences, t) for t in (
            now, with_six_second_rule(now), zeroed, with_six_second_rule(zeroed),
            embeddings_only, with_six_second_rule(embeddings_only)))))
        own = dump["own"]
        own_seconds = sum(b - a for a, b in own)
        duration = max(s["end"] for s in now + sentences)
        system_seconds = sum(s["end"] - s["start"] for s in now)
        # a sentence's words count in proportion to its time under the zeroed runs (ASR stores no word times)
        words = sum(len(s["text"].split()) for s in sentences)
        words_lost = sum(len(s["text"].split()) * overlap(s["start"], s["end"], own) / max(s["end"] - s["start"], 1e-3)
                         for s in sentences)
        mic_sentence_seconds = sum(s["end"] - s["start"] for s in mic)
        stats.append({
            "call": call, "level": dump["speechLevelDb"], "own": own_seconds / duration,
            "own_in_mic_sentences": sum(overlap(a, b, [[s["start"], s["end"]] for s in mic]) for a, b in own) / max(own_seconds, 1e-3),
            "mic_sentences_covered": sum(overlap(s["start"], s["end"], own) for s in mic) / max(mic_sentence_seconds, 1e-3),
            "double_talk": sum(overlap(s["start"], s["end"], own) for s in now) / max(system_seconds, 1e-3),
            "words": words, "words_lost": words_lost,
        })

    real = {c: DAILIES.get(c, 1) for c in CALLS}
    print("| call | real | " + " | ".join(columns) + " |")
    print("|---|---|" + "---|" * len(columns))
    for call in CALLS:
        print(f"| {call} | {real[call]} | " + " | ".join(str(counts[call][c]) for c in columns) + " |")
    print("| **1:1 correct (of 10)** | | " + " | ".join(f"**{sum(counts[c][k] == 1 for c in ONE_ON_ONE)}**" for k in columns) + " |")
    print("| **dailies correct (of 5)** | | " + " | ".join(f"**{sum(counts[c][k] == real[c] for c in DAILIES)}**" for k in columns) + " |")
    print("| **total \\|Δ\\|** | | " + " | ".join(f"**{sum(abs(counts[c][k] - real[c]) for c in CALLS)}**" for k in columns) + " |")
    print()
    print("| call | mic speech level dB | own share of call | own inside mic ASR sentences | mic ASR sentence time masked | system diarizer speech masked | system words | words under zeroed frames |")
    print("|---|---|---|---|---|---|---|---|")
    for s in stats:
        print(f"| {s['call']} | {s['level']:.1f} | {s['own']:.0%} | {s['own_in_mic_sentences']:.0%} | {s['mic_sentences_covered']:.0%} | "
              f"{s['double_talk']:.0%} | {s['words']} | {s['words_lost']:.0f} ({s['words_lost'] / max(s['words'], 1):.1%}) |")
    total_words, total_lost = sum(s["words"] for s in stats), sum(s["words_lost"] for s in stats)
    print(f"| **all** | | | | | | **{total_words}** | **{total_lost:.0f} ({total_lost / total_words:.1%})** |")


if __name__ == "__main__":
    main()
