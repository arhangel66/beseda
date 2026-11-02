# Reference labels for speaker names

Goal: for one call, say which real person each diarizer label `them-N` is, from the transcript text alone.
No audio, no ground truth. Be strict: a name needs a concrete line in the text; "unknown" is a valid and
common answer.

## Input

`data/transcripts/<call-id>.tsv`, tab-separated: `order_idx`, `start_sec`, `speaker`, `text`.

- `me` is Mikhail's microphone (always Mikhail; use it as context only).
- `them-1`, `them-2`, … are the diarizer's distinct remote voices on the system channel.
- Text is local ASR: recognition errors, garbled names (see `data/people.json` for known garbles), mixed
  ru/en. "Michael"/"Michail" is Mikhail.
- Multi-person calls are mostly a team daily: each person gives an update in turn, others react.
  `data/roster.txt` lists the team. Other people may appear; name them if the text names them.

## How to decide a label's name

Evidence, strongest first:
1. Addressed, then answers: `me: "Sergei, what about X?"` → the next remote voice that answers is Sergei.
2. Hand-over: `them-3: "Mohammed, you can go"` → the next remote voice to give an update is Mohammed
   (the one *saying* it is not Mohammed).
3. Thanks after an update: `me: "Thank you, Sergei"` → the voice that just finished is Sergei.
4. Self-introduction: `them-2: "this is Lucas"`.
5. Greeting: `me: "Hi Rustam"` followed by a reply from one voice — only if it is clear which voice replied.
6. Being talked about, then reacting: `them-2: "Pixel was sick"` → `them-3: "I was down, guys"` → them-3 is Pixel.

Topics, roles and speaking order are NOT evidence on their own. They may raise or lower confidence of an
evidence-based name, never create one. A label that never gets any of 1–6 is `unknown`, even if "it must
be Gus by elimination". Elimination is not evidence.

Always say who speaks and who is addressed: "Rustam, your turn" names the next speaker, not the speaker of
that line.

## Statuses

- `named` — a person, with evidence lines.
- `unknown` — the text does not say (backchannel-only voices, or nobody uses the name).
- `echo` — the label is Mikhail's own voice coming back on the system channel: its lines repeat `me` lines
  ~0.5 s later, nearly word for word.
- `mixed` — two people under one label (one voice's lines clearly belong to someone already named under
  another label). Name the majority person, say so in `notes`.

One name may sit on two labels (the diarizer split one person): name both, mark `split` in notes.

## Output

Write `refs/<call-id>.json`:

```json
{
  "call_id": "20261102-125941",
  "call_kind": "daily|one-to-one|other",
  "language": "en|ru|mixed",
  "labels": {
    "them-1": {"name": "Sergei", "status": "named", "confidence": "high",
               "evidence": [{"idx": 329, "line": "me: Thank you very much, Sergei.", "why": "thanks right after them-1's update (327-328)"}]},
    "them-2": {"name": "unknown", "status": "unknown", "confidence": "high", "evidence": []}
  },
  "speaking_order": ["them-1", "them-3", "them-2"],
  "topics_per_label": {"them-1": "merged ~30 PRs, TMC attack, API keys"},
  "people_named_in_text": ["Sergei", "Fish", "Rustam", "Pixel", "Mohammed"],
  "notes": "2-3 sentences: what made the call easy or hard; splits, echo, mixed labels."
}
```

- `name`: a canonical key of `data/people.json`, a new person's name as the text gives it, or `"unknown"`.
- `confidence`: `high` = evidence 1–4 unambiguous; `medium` = one indirect clue (5–6) or garbled name;
  `low` = you would not bet on it. A `low` name is allowed but will be checked again.
- `evidence`: every cited `idx` must exist in the file; for a `named` label at least one cited line must
  contain the name (or a known garble of it). Quote the line.
- `speaking_order`: labels in the order of their first substantive update (not backchannel).
- `topics_per_label`: one short line per label, what that voice talked about.
- `people_named_in_text`: every person name that appears in the text, canonical where known.

Write the file with the Write tool; valid JSON, nothing else.
