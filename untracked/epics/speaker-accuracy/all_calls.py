"""BESEDA-151: every call of Mikhail's — which still has the audio, and on those the `them` speakers stored now
(0.4.0) against Nemotron-3 through the app's per-sentence assignment (all_calls.sh) and the real count an LLM read
from the transcript (truth/<id>.answer.json, written by haiku from truth/<id>.txt). Writes the blind transcripts
the LLM reads, then results/all-calls-nemotron.md once every answer is in."""

import json
import re
import sqlite3
from datetime import datetime
from pathlib import Path

from extra_speakers import assigned_speakers
from other_diarizers import raw_timeline

ROOT = Path(__file__).parent
STORE = Path.home() / "Library" / "Application Support" / "Beseda" / "calls"
COPY = ROOT / "hyp" / "all-calls"
TRUTH = ROOT / "truth"
RESULT = ROOT / "results" / "all-calls-nemotron.md"
AUDIO = ["them.asr.wav", "them.asr.json"]
# app default kept by Mikhail: beseda.normalizedAudioRetention = days30 (rawAudioRetention = immediately)
RETENTION_DAYS = 30


def calls() -> list[dict]:
    with sqlite3.connect(COPY / "calls.sqlite") as db:
        db.row_factory = sqlite3.Row
        rows = [dict(r) for r in db.execute("select * from calls order by started_at")]
        for call in rows:
            speakers = {s for (s,) in db.execute("select distinct speaker from transcript_segments where call_id = ?", (call["id"],))}
            call["stored"] = len(speakers - {"me"})
            call["merges"] = bool(db.execute("select 1 from sqlite_master where name = 'call_speaker_merges'").fetchone()) and bool(
                db.execute("select 1 from call_speaker_merges where call_id = ?", (call["id"],)).fetchone())
    return rows


def missing_reason(call: dict) -> str | None:
    # None = the call has what the rerun needs
    folder = STORE / call["id"]
    if call["status"] == "failed":
        return f"failed: {call['error'].split(' for ')[0]}"
    if call["kind"] == "mic":
        return "mic-only"
    if not folder.is_dir():
        return "no folder"
    if not (folder / "them.asr.json").exists():
        return "no them.asr.json"
    if not (folder / "them.asr.wav").exists():
        age = (datetime.now() - datetime.fromisoformat(call["started_at"]).replace(tzinfo=None)).days
        return f"retention ({RETENTION_DAYS} d) deleted the audio" if age >= RETENTION_DAYS else "audio missing, not by retention"
    return None


def write_blind_transcript(call: dict) -> None:
    # speaker labels collapsed to `other` so the LLM cannot count them
    path = TRUTH / f"{call['id']}.txt"
    if path.exists():
        return
    with sqlite3.connect(COPY / "calls.sqlite") as db:
        lines = [f"{'me' if speaker == 'me' else 'other'}: {text}" for speaker, text in
                 db.execute("select speaker, text from transcript_segments where call_id = ? order by order_idx", (call["id"],))]
    path.write_text("\n".join(lines))


def nemotron_count(call_id: str) -> int:
    sentences = json.loads((COPY / f"{call_id}.them.asr.json").read_text())["segments"]
    timeline = raw_timeline("nemotron3-offline", call_id)
    return len(set(assigned_speakers(sentences, timeline))) if sentences and timeline else min(len(sentences), 1)


def earlier_truth() -> dict[str, dict]:
    # the 15 calls BESEDA-70 already read
    truth = {}
    for line in (ROOT / "results" / "real-calls-truth.md").read_text().splitlines():
        cells = [c.strip() for c in line.strip("|").split("|")]
        if re.fullmatch(r"\d{8}-\d{6}", cells[0]):
            truth[cells[0]] = {"count": int(cells[2]), "names": cells[3], "confidence": cells[4]}
    return truth


def summary_line(name: str, rows: list[dict]) -> str:
    exact_before = sum(r["stored"] == r["count"] for r in rows)
    exact_after = sum(r["nemotron"] == r["count"] for r in rows)
    near_before = sum(abs(r["stored"] - r["count"]) <= 1 for r in rows)
    near_after = sum(abs(r["nemotron"] - r["count"]) <= 1 for r in rows)
    return f"| {name} | {len(rows)} | {exact_before} | {exact_after} | {near_before} | {near_after} |"


def main() -> None:
    TRUTH.mkdir(exist_ok=True)
    everything = calls()
    usable = [c for c in everything if missing_reason(c) is None]
    for call in usable:
        write_blind_transcript(call)
    truth = earlier_truth()
    unanswered = [c["id"] for c in usable if c["id"] not in truth and not (TRUTH / f"{c['id']}.answer.json").exists()]
    if unanswered:
        print(f"{len(unanswered)} calls wait for an answer: {' '.join(unanswered)}")
        return

    rows = []
    for call in usable:
        answer = truth.get(call["id"]) or json.loads((TRUTH / f"{call['id']}.answer.json").read_text())
        rows.append({**call, **answer, "nemotron": nemotron_count(call["id"])})

    reasons: dict[str, list[str]] = {}
    for call in everything:
        if reason := missing_reason(call):
            reasons.setdefault(reason, []).append(call["id"])

    out = ["# Nemotron-3 on all of Mikhail's calls (BESEDA-151, 2026-09-27)", "",
           "`them` speakers on every call that still has `them.asr.wav` + `them.asr.json`: stored now (`Было 0.4.0`: the "
           "distinct non-`me` labels in `transcript_segments`, as whichever pre-Nemotron build processed the call left "
           "them; `calls.diarizer` is empty on all 123) against Nemotron-3 offline (`all_calls.sh`, the same FluidAudio 0.17.4 preset "
           "and weights as `Diarizer.swift`) with the app's per-sentence assignment (`SpeakerAssignment.remoteTurns`, "
           "no 6 s rule). The echo gate only trims the mic side, so it does not change the `them` count. Copies only: "
           "the store copy and `cp -c` clones, one call at a time.", "",
           "Real count (`Людей по смыслу`) = people besides Mikhail, read by claude-haiku from the transcript with every "
           "remote label replaced by one `other` (prompts and answers in `truth/`, gitignored); the 15 calls of "
           "[real-calls-truth.md](real-calls-truth.md) are reused. An LLM reading, not hand labels.", "",
           f"## Calls ({len(everything)}): {len(usable)} with audio, {len(everything) - len(usable)} without", "",
           "| reason no audio | calls | ids |", "|---|---|---|"]
    out += [f"| {reason} | {len(ids)} | {' '.join(ids)} |" for reason, ids in reasons.items()]

    out += ["", "## Summary: calls where the shown count is right", "",
            "| calls | n | exact 0.4.0 | exact Nemotron | ±1 0.4.0 | ±1 Nemotron |", "|---|---|---|---|---|---|"]
    for name, pick in [("all", lambda r: True), ("1:1", lambda r: r["count"] == 1), ("multi-person", lambda r: r["count"] > 1),
                       ("nobody else spoke (0)", lambda r: r["count"] == 0)]:
        for confidence, keep in [("", lambda r: True), (", high confidence", lambda r: r["confidence"] == "high")]:
            out.append(summary_line(name + confidence, [r for r in rows if pick(r) and keep(r)]))

    merged = [r["id"] for r in rows if r["merges"]]
    with sqlite3.connect(COPY / "calls.sqlite") as db:
        has_table = bool(db.execute("select 1 from sqlite_master where name = 'call_speaker_merges'").fetchone())
    out += ["", "## Manual merges", "",
            f"Calls with `call_speaker_merges` rows (a rerun would drop them): {' '.join(merged) or 'none'}"
            + ("" if has_table else " — the store (schema v3, app 0.4.0) has no `call_speaker_merges` table yet") + ".",
            "", "## Per call", "",
            "| Звонок | Длит. | Людей по смыслу | Уверенность | Было 0.4.0 | Nemotron | merges? |", "|---|---|---|---|---|---|---|"]
    for r in rows:
        local_time = datetime.strptime(r["id"], "%Y%m%d-%H%M%S").strftime("%Y-%m-%d %H:%M")
        title = " · ".join(filter(None, [local_time, r["event_title"], r["app_name"]]))
        names = f" ({r['names']})" if r["names"] else ""
        out.append(f"| {r['id']} {title} | {r['duration_sec'] / 60:.0f} мин | {r['count']}{names} | {r['confidence']} "
                   f"| {r['stored']} | {r['nemotron']} | {'yes' if r['merges'] else '—'} |")
    RESULT.write_text("\n".join(out) + "\n")
    print("\n".join(out[:40]))


if __name__ == "__main__":
    main()
