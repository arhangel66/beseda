# App code path check (BESEDA-84, 2026-09-26)

`app_merge.sh`: each truth call through the app's own `Diarizer` + `SpeakerAssignment` (short-reply merge). Every count matches the winner column (<6 s, time, t0.70) of [short-reply-merge.md](short-reply-merge.md).

```
Build of product 'AppMerge' complete! (91.07s)
{"call": "20260925-114649", "diarizer": 2, "them": 1}
{"call": "20260925-111702", "diarizer": 2, "them": 1}
{"call": "20260924-173649", "diarizer": 2, "them": 1}
{"call": "20260924-173310", "diarizer": 2, "them": 1}
{"call": "20260924-133358", "diarizer": 3, "them": 1}
{"call": "20260924-110157", "diarizer": 3, "them": 1}
{"call": "20260923-125419", "diarizer": 2, "them": 2}
{"call": "20260923-101613", "diarizer": 3, "them": 1}
{"call": "20260922-115609", "diarizer": 2, "them": 1}
{"call": "20260922-084404", "diarizer": 2, "them": 1}
{"call": "20260925-125945", "diarizer": 4, "them": 3}
{"call": "20260924-130017", "diarizer": 5, "them": 2}
{"call": "20260923-130021", "diarizer": 7, "them": 5}
{"call": "20260922-125838", "diarizer": 6, "them": 4}
{"call": "20260921-125925", "diarizer": 6, "them": 4}
```
