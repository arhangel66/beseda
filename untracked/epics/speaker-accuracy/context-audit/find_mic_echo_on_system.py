# Find remote (them-*) lines that repeat one of Mikhail's mic lines a moment later: his voice echoed back
# on the system channel.
import re
import sqlite3
from collections import defaultdict
from difflib import SequenceMatcher
from pathlib import Path

DB = Path.home() / "Library/Application Support/Beseda/calls.sqlite"
MAX_LAG = 1.5
MIN_SHARE = 0.8
MIN_DISTINCT_WORDS = 3


def tokens(text: str) -> list[str]:
    return re.findall(r"\w+", text.lower())


def share_of_turn_in_mic(turn_tokens: list[str], mic_tokens: list[str]) -> float:
    # share of the turn's words found in the mic line in the same order
    matcher = SequenceMatcher(None, turn_tokens, mic_tokens, autojunk=False)
    return sum(b.size for b in matcher.get_matching_blocks()) / len(turn_tokens)


def main() -> None:
    db = sqlite3.connect(DB)
    calls = [r[0] for r in db.execute("select id from calls where status='ready' order by id")]
    for call_id in calls:
        rows = db.execute(
            "select speaker, start_sec, text from transcript_segments where call_id=? order by order_idx", (call_id,)
        ).fetchall()
        mine = [(start, text, tokens(text)) for speaker, start, text in rows if speaker == "me"]
        words_per_label = defaultdict(int)
        echo_words_per_label = defaultdict(int)
        echoed = []
        for speaker, start, text in rows:
            if not speaker.startswith("them"):
                continue
            turn_tokens = tokens(text)
            words_per_label[speaker] += len(turn_tokens)
            if len(set(turn_tokens)) < MIN_DISTINCT_WORDS:
                continue
            for mic_start, mic_text, mic_tokens in mine:
                lag = start - mic_start
                if 0 <= lag <= MAX_LAG and share_of_turn_in_mic(turn_tokens, mic_tokens) >= MIN_SHARE:
                    echo_words_per_label[speaker] += len(turn_tokens)
                    echoed.append((speaker, start, lag, text, mic_text))
                    break
        if echoed:
            labels = {s: f"{echo_words_per_label[s]}/{words_per_label[s]}" for s in echo_words_per_label}
            print(call_id, len(echoed), labels)
            for speaker, start, lag, text, mic_text in echoed[:3]:
                print(f"    {speaker} {start:.1f} +{lag:.1f}s {text[:70]!r} <= {mic_text[:70]!r}")


if __name__ == "__main__":
    main()
