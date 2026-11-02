# Remove remote lines that are Mikhail's own voice echoed back on the system channel from the stored calls
# (same rule as MicEchoFilter.swift). Dry run prints what would go; apply backs up first.
import json
import re
import shutil
import sqlite3
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path.home() / "Library/Application Support/Beseda"
DB = ROOT / "calls.sqlite"
BACKUP_SUFFIX = ".before-mic-echo.backup"
MIN_DISTINCT_WORDS = 3
MIN_SHARE = 0.8
WORD_LAG = (0.3, 1.5)
ECHO_SPEAKER_SHARE = 0.25


def normalize(text: str) -> str:
    return "".join(ch for ch in text.lower() if ch.isalnum())


def tokens(text: str) -> list[str]:
    return [t for t in (normalize(w) for w in text.split()) if t]


def asr_words(segment: dict) -> list[tuple[str, float]]:
    return [(normalize(w["text"]), w["start"]) for w in segment.get("words") or [] if normalize(w["text"])]


def is_echo_by_words(sentence: dict, mic_words: list[tuple[str, float]]) -> bool:
    words = asr_words(sentence)
    if len({t for t, _ in words}) < MIN_DISTINCT_WORDS:
        return False
    nearby = [w for w in mic_words if sentence["start"] - 4 <= w[1] <= sentence["end"] + 2]
    matcher = SequenceMatcher(None, [t for t, _ in words], [t for t, _ in nearby], autojunk=False)
    lags = sorted(words[b.a + k][1] - nearby[b.b + k][1] for b in matcher.get_matching_blocks() for k in range(b.size))
    if len(lags) < MIN_SHARE * len(words):
        return False
    return WORD_LAG[0] <= lags[len(lags) // 2] <= WORD_LAG[1]


def echo_segment_ids(rows: list[tuple], folder: Path) -> set[str]:
    # rows: (id, speaker, start, end, text)
    mine = [(r[2], r[3] or r[2], r[4]) for r in rows if r[1] == "me"]
    remote = [r for r in rows if r[1].startswith("them")]
    me_json, them_json = folder / "me.asr.json", folder / "them.asr.json"
    has_words = me_json.exists() and them_json.exists() and any(
        s.get("words") for s in json.loads(them_json.read_text())["segments"]
    )
    if not has_words:
        # May–June calls: no word times and no echo gate yet, duplicates go both ways
        return set()
    # kept mic words only: the stored "me" lines are what the echo gate left
    mic_words = [
        w for s in json.loads(me_json.read_text())["segments"] for w in asr_words(s)
        if any(start - 0.01 <= w[1] <= end + 0.01 for start, end, _ in mine)
    ]
    echo_sentences = [s for s in json.loads(them_json.read_text())["segments"] if is_echo_by_words(s, mic_words)]
    keys = {(round(s["start"], 2), s["text"]) for s in echo_sentences}
    echo_ids = {r[0] for r in remote if (round(r[2], 2), r[4]) in keys}
    # a speaker this much made of echo is Mikhail himself: its short leftover lines go too
    for speaker in {r[1] for r in remote if r[1] != "them"}:
        spoken = [r for r in remote if r[1] == speaker]
        echo_words = sum(len(tokens(r[4])) for r in spoken if r[0] in echo_ids)
        if echo_words >= ECHO_SPEAKER_SHARE * sum(len(tokens(r[4])) for r in spoken):
            echo_ids |= {r[0] for r in spoken}
    return echo_ids


def renumbered(speakers_in_order: list[str]) -> dict[str, str]:
    # them-N follow the order people first speak, as SpeakerAssignment numbers them
    mapping: dict[str, str] = {}
    for speaker in speakers_in_order:
        if speaker.startswith("them-") and speaker not in mapping:
            mapping[speaker] = f"them-{len(mapping) + 1}"
    return mapping


def speaker_name(speaker: str) -> str:
    # SpeakerNaming.defaultName for the Russian UI; these calls have no renames
    if speaker == "me":
        return "Вы"
    return "Собеседник" if speaker == "them" else f"Собеседник {speaker[5:]}"


def rewrite_dialogue(transcript: Path, segments: list[tuple[str, float, str]]) -> None:
    # the ## Dialogue block from the stored segments, as TranscriptMerger.rewriteDialogue writes it
    text = transcript.read_text()
    head, rest = text.split("## Dialogue\n\n", 1)
    tail = rest[rest.index("## Channels"):]
    dialogue = "".join(
        f"**{speaker_name(speaker)}** [{int(start + 0.5) // 60:02d}:{int(start + 0.5) % 60:02d}] {line}\n\n"
        for speaker, start, line in segments
    )
    transcript.write_text(head + "## Dialogue\n\n" + dialogue + tail)


def main(apply: bool) -> None:
    db = sqlite3.connect(DB)
    if apply:
        backup = DB.with_name(DB.name + BACKUP_SUFFIX)
        db.execute(f"VACUUM INTO '{backup}'")
        print("backup", backup)
    calls = db.execute("select id, audio_dir, transcript_path from calls where status='ready' order by id").fetchall()
    total = 0
    for call_id, audio_dir, transcript_path in calls:
        rows = db.execute(
            "select id, speaker, start_sec, end_sec, text from transcript_segments where call_id=? order by order_idx", (call_id,)
        ).fetchall()
        echo_ids = echo_segment_ids(rows, Path(audio_dir))
        if not echo_ids:
            continue
        kept = [r for r in rows if r[0] not in echo_ids]
        removed = [(r[1], r[4]) for r in rows if r[0] in echo_ids]
        mapping = renumbered([r[1] for r in kept])
        before = sorted({r[1] for r in rows if r[1].startswith("them")})
        after = sorted({mapping.get(r[1], r[1]) for r in kept if r[1].startswith("them")})
        total += len(removed)
        print(f"{call_id}: -{len(removed)} of {len(rows)} lines, remote labels {before} -> {after}")
        for speaker, text in removed[:5]:
            print(f"    {speaker}: {text[:90]}")
        if not apply:
            continue
        if db.execute("select count(*) from call_speakers where call_id=?", (call_id,)).fetchone()[0] or \
                db.execute("select count(*) from call_speaker_merges where call_id=?", (call_id,)).fetchone()[0]:
            print("    skipped: has manual speaker edits")
            continue
        with db:
            db.executemany("delete from transcript_segments where id=?", [(i,) for i in echo_ids])
            for order, r in enumerate(kept):
                db.execute(
                    "update transcript_segments set order_idx=?, speaker=? where id=?", (order, mapping.get(r[1], r[1]), r[0])
                )
        if transcript_path and Path(transcript_path).exists():
            transcript = Path(transcript_path)
            shutil.copy2(transcript, transcript.with_name(transcript.name + BACKUP_SUFFIX))
            rewrite_dialogue(transcript, [(mapping.get(r[1], r[1]), r[2], r[4]) for r in kept])
    print("total lines", total)


if __name__ == "__main__":
    main(apply=False)


def redo_dialogue_from_backup(call_ids: list[str]) -> None:
    # first apply matched lines by text and removed two wrong ones: rebuild from the backup and the stored rows
    db = sqlite3.connect(DB)
    for call_id in call_ids:
        transcript = ROOT / "calls" / call_id / "transcript.md"
        shutil.copy2(transcript.with_name(transcript.name + BACKUP_SUFFIX), transcript)
        rows = db.execute(
            "select speaker, start_sec, text from transcript_segments where call_id=? order by order_idx", (call_id,)
        ).fetchall()
        rewrite_dialogue(transcript, rows)
