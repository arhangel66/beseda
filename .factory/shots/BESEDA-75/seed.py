# Seeds demo calls into a Beseda index: python3 seed.py <calls.sqlite> <calls-dir>
import sqlite3, sys, os
from datetime import datetime, timedelta, timezone

db, calls_dir = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
now = datetime.now(timezone.utc)
iso = lambda d: d.strftime("%Y-%m-%dT%H:%M:%S.000Z")

summary = """**О чём говорили**
Сверили план релиза 0.7 и что осталось до выката.

**Главное**
— Запись двух каналов работает стабильно, осталась разметка говорящих.
— Итоги в облаке не включаем по умолчанию.

**Что делать**
— Миша: собрать сборку и проверить на живом звонке, до четверга.
— Ира: проверить старые записи после обновления базы.

**Открытые вопросы**
— Чистить ли исходное аудио сразу после расшифровки."""
older = summary.replace("0.7", "0.6").replace("стабильно", "почти без сбоев")

calls = [
    ("demo-1", now - timedelta(hours=1), 31 * 60, "Планёрка команды", summary, "Созвон команды", "Zoom"),
    ("demo-2", now - timedelta(hours=3), 12 * 60, None, None, None, "Telegram"),
    ("demo-3", now - timedelta(days=1, hours=2), 47 * 60, "Интервью с кандидатом", None, None, "Google Meet"),
    ("demo-4", now - timedelta(days=9), 28 * 60, "Планёрка команды", older, "Созвон команды", "Zoom"),
]
lines = [
    ("them", "Добрый день, слышно меня нормально?"),
    ("me", "Да, всё отлично слышно. Давайте начнём с релиза."),
    ("them", "Релиз переносим на четверг: тестировщики не успели пройти регресс."),
    ("me", "Хорошо. А что с оплатой через новый шлюз?"),
    ("them", "Шлюз подключили, но возвраты пока работают только вручную."),
    ("me", "Тогда возвраты беру на себя, сделаю к среде."),
]
for cid, start, dur, title, text, ctype, app in calls:
    d = os.path.join(calls_dir, cid)
    os.makedirs(d, exist_ok=True)
    con.execute("""INSERT OR REPLACE INTO calls (id, kind, started_at, ended_at, duration_sec, status, audio_dir,
        app_name, summary_text, call_type, event_title, created_at, updated_at)
        VALUES (?, 'dual', ?, ?, ?, 'ready', ?, ?, ?, ?, ?, ?, ?)""",
        (cid, iso(start), iso(start + timedelta(seconds=dur)), dur, d, app, text, ctype, title, iso(start), iso(start)))
    for i, (speaker, line) in enumerate(lines):
        con.execute("INSERT OR REPLACE INTO transcript_segments VALUES (?, ?, ?, ?, ?, ?, ?)",
                    (f"{cid}-{i}", cid, speaker, i * 14.0, i * 14.0 + 12, line, i))
con.commit()
