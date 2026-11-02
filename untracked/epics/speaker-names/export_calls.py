# exports the diarized calls with >= 30 segments from calls.sqlite: data/transcripts/<id>.tsv and data/calls.json
import json, sqlite3
from collections import Counter
from pathlib import Path

DB = Path.home() / "Library/Application Support/Beseda/calls.sqlite"
HERE = Path(__file__).parent


def main() -> None:
    db = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    (HERE / "data/transcripts").mkdir(parents=True, exist_ok=True)
    calls = []
    for call_id, started_at, duration_sec, app_name in db.execute(
        "select id, started_at, duration_sec, app_name from calls where diarizer is not null order by started_at"
    ):
        rows = db.execute("select order_idx, start_sec, speaker, text from transcript_segments where call_id=? order by order_idx",
                          (call_id,)).fetchall()
        if len(rows) < 30:
            continue
        with open(HERE / f"data/transcripts/{call_id}.tsv", "w") as out:
            for order_idx, start_sec, speaker, text in rows:
                out.write(f"{order_idx}\t{start_sec:.1f}\t{speaker}\t{text.replace(chr(9), ' ').replace(chr(10), ' ')}\n")
        per_label = Counter(speaker for _, _, speaker, _ in rows if speaker != "me")
        labels = sorted(per_label)
        group = "multi" if len(labels) >= 3 else "two" if len(labels) == 2 else "one"
        calls.append({"id": call_id, "started_at": started_at, "minutes": round((duration_sec or 0) / 60, 1),
                      "app": app_name, "group": group, "labels": labels, "segments_per_label": dict(per_label),
                      "segments": len(rows)})
    multi = [c for c in calls if c["group"] == "multi"]
    for i, c in enumerate(multi):
        c["split"] = "tune" if i < len(multi) // 2 else "test"
    for c in calls:
        c.setdefault("split", "other")
    (HERE / "data/calls.json").write_text(json.dumps(calls, ensure_ascii=False, indent=1))
    print(len(calls), "calls;", Counter(c["group"] for c in calls), Counter(c["split"] for c in calls))


if __name__ == "__main__":
    main()
