# Context audit of speaker labels

Goal: estimate, from transcript content alone, how well the diarizer splits the remote side of a call.
No audio, no ground truth — judge by meaning.

## Input

`transcripts/<call-id>.tsv`, tab-separated: `order_idx`, `start_sec`, `speaker`, `text`.

- `me` is Mikhail's microphone channel (always correct — a separate channel; ignore it except as context).
- `them-1`, `them-2`, … are the diarizer's guesses at distinct remote people on the system channel.
- Text is from local ASR: expect recognition errors, garbled names ("Rustav" may be "Rustam"), mixed ru/en.
- Most multi-person calls are a team daily: each person gives an update in turn, others react.

## What to do per call

1. Read the whole transcript.
2. Work out the real remote participants: names used in address ("thanks, X", "X, your turn"),
   self-introductions, who reports which work, voice/style continuity of long monologues, Q&A structure.
3. Map each `them-N` to a real person (or "mixed" / "unknown").
4. Go through every `them-*` segment and mark it:
   - `ok` — fits the person its label maps to;
   - `wrong` — clearly said by another remote person (give whom and why: e.g. the line answers a question
     addressed to that person, continues that person's monologue mid-sentence, someone is addressed by name
     inside their own label, the "label" thanks itself, etc.);
   - `unclear` — short backchannel ("yeah", "okay", "mm") or not decidable.
   Be strict: only mark `wrong` when the context gives a concrete reason. Short ambiguous lines are `unclear`.
5. Also flag any `me` segment that is obviously someone else's speech (echo) — rare, note only if clear.

## Output

Write `judgments/<call-id>.json`:

```json
{
  "call_id": "...",
  "language": "en|ru|mixed",
  "call_kind": "daily|one-to-one|other",
  "labels_found": 4,
  "true_remote_people": 3,
  "true_remote_people_confidence": "high|medium|low",
  "people": [{"name": "Rustam", "evidence": "..."}],
  "label_map": {"them-1": "Rustam", "them-2": "Fish", "them-3": "Rustam (split)"},
  "count_error_kind": "exact|split|glued|split+glued",
  "wrong_segments": [{"idx": 57, "label": "them-2", "actually": "Rustam", "reason": "..."}],
  "unclear_segments": [12, 13],
  "me_echo_segments": [],
  "notes": "2-4 sentences: the main failure patterns in this call"
}
```

Count every `them-*` segment as exactly one of ok / wrong / unclear (ok = the rest).
A label that is a split of one person is not itself "wrong" per segment — that is captured by `label_map`
and `count_error_kind`. A segment is `wrong` only when its label maps to a different person than who spoke.
When one label is a mix of two people, map it to its majority person and mark the minority segments `wrong`.
