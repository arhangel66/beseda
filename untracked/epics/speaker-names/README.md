# Speaker names: can a small local model name `them-N`?

Status: plan, reviewed (astra, 2026-11-02), smoke-tested on one call. Research only, no app code.

## Goal

After a call, Beseda shows remote speakers as `them-1`, `them-2`, … (Nemotron-3 labels; the count is right
in 14 of 16 audited calls, see `../speaker-accuracy/context-audit/`). We want a small local model, run
through the app's own `llama-server`, to turn each label into a name — `them-1 → Rustam` — or say
"unknown". The team on the dailies is stable (Rustam, Fish, Pixel, Sergei, Gus, Mohammed), so the model
may get context the app can accumulate: a roster of known people and notes from earlier calls ("Rustam
usually reports second, runs the daily").

Success criterion: a fixed eval set with a reference built by Opus agents on bb, one scorer, and a table
that says — per model × context × prompt — label accuracy, wrong-name rate and time per call. From it we
pick the config to ship and know which context actually helps.

## What is already here

- 116 Nemotron-3 calls in `calls.sqlite`; 109 have ≥ 30 segments: 34 with 3+ remote labels (dailies and
  a few meetings), 7 with 2, 68 with one (1:1 calls). No calendar events are linked, `participants` is null
  everywhere, so the roster cannot come from the calendar today.
- `../speaker-accuracy/context-audit/`: 16 of those calls (12 dailies) already have agent-written
  `label_map`s in `judgments/*.json`, plus `RUBRIC.md`. They are the seed of the reference and a
  cross-check for the new Opus pass.
- Models on disk: Gemma 4 E4B Q4_0 under the app's `llama-server` b10819
  (`~/Library/Application Support/Beseda/runtime/`). Homebrew `llama-server` is older (b10621): the eval
  uses the app's binary, which is also what ships.
- Pattern to copy: `../summary-quality/run_check.py` (starts the installed llama-server read-only on a
  free port, posts `chat/completions`), `../speaker-accuracy/score.py` (hyp dir → `results/*.md|json`).

## Design

**Task shape.** Input: the call's transcript as `[mm:ss] speaker: text` lines built from the raw
`transcript_segments.speaker` keys (never `TranscriptCopy.render`, which substitutes stored renames), `me`
kept as context. Output: JSON `{"them-1": "Rustam", "them-2": "unknown", ...}`, forced valid with
llama-server's `json_schema` response format (no `enum` of names — that would smuggle the roster into the
`none` variant), temperature 0, `finish_reason` and the exact label set checked. One request per call.

**Window** (how much of the call the model sees) — the smoke test below shows it matters as much as the
model. `edges100` is the main one: consecutive segments of one speaker merged into a turn, each turn cut
to its first 100 and last 100 chars — addressing by name sits at turn edges: greetings and questions open
a turn, hand-overs and thanks close it; 3.6× smaller than `full`. Variants: `edges50` (same, 50 chars,
20 % fewer tokens, on the edge of losing the hand-over line), `names` (lines that mention a known name,
± 3 lines each side, gaps marked `...`), `full` (whole call, the control). `head8k` (first 8000 chars,
what the app's classifier sends today) is dropped: the addressing lines are spread over the call and it
found nothing in six tries.

**Thinking** on/off is a dimension, not a prompt variant: Gemma 4 thinks by default under llama.cpp and
spends the whole `max_tokens` budget in `reasoning_content`; `chat_template_kwargs.enable_thinking=false`
turns it off (9 s vs 60 s on a 3k-token input). Qwen3.5 uses the same switch; the runner stores both
`content` and `reasoning_content` and asserts the latter is empty when thinking is off.

**Eval set.** The 109 calls with ≥ 30 segments, three groups scored separately:
`multi` (3+ labels, 34 calls), `two` (7), `one` (1:1, 68). `two` is too small to rank anything on its own:
it is reported, not decided on. Within `multi` the calls are split by date: `tune` = the earlier half
(prompts, windows and contexts are chosen here), `test` = the later half (reported once, for the chosen
configs only — the headline number). 1:1 calls get only the chosen configs (the question there is
different: nobody is addressed by name, only memory can tell who it was).

**Reference.** One Opus agent per call on bb, reading the transcript with `REFERENCE_RUBRIC.md` (the
context-audit rubric trimmed to the label map), writing `refs/<id>.json`:

```json
{"call_id": "…", "call_kind": "daily|one-to-one|other", "language": "en|ru|mixed",
 "labels": {"them-1": {"name": "Rustam", "confidence": "high|medium|low", "evidence": "…"},
            "them-3": {"name": "unknown", "confidence": "high", "evidence": "only backchannel"}},
 "speaking_order": ["them-1", "them-3", "them-2"], "topics_per_label": {"them-1": "NG engine, Stripe"},
 "people_named_in_text": ["Rustam", "Mustam", "Sergei"]}
```

Names are canonical from `data/people.json` (canonical name + aliases incl. ASR garbles: Mustam, Rustav,
Sergey, Mohamed…); the agent adds a new person when nobody in the roster fits. Every label gets a
`status`: `named`, `unknown` (the text does not say; a speaker who only says "yeah" is unnameable by
anyone), `echo` (Mikhail's own voice back on the system channel, as in `20261016-113955`), `mixed`
(two people under one label; the majority person is named). One name may sit on several labels (a split
speaker). `evidence` must carry the `order_idx` of the lines it relies on and say who speaks and who is
addressed in them ("Rustam, your turn" names the *next* speaker, not the one saying it); a validator checks
that the cited lines exist and contain the name. `speaking_order` and `topics_per_label` feed the notes
context later.

Reference quality guard: a second Opus pass on every `low`/`medium` label, every disagreement with the 16
existing judgments, and a random 10 % of `high` labels; the two passes must agree or the label becomes
`unknown`. `results/reference-check.md` lists what changed. No manual check, as agreed.

**Contexts** (what goes into the system prompt besides the instruction):

| key | content | built from |
|---|---|---|
| `none` | nothing | — |
| `roster` | names and one-line roles, as a user would type them once in Settings | `data/roster.txt`, written by hand from what Mikhail knows, fixed for the whole run; no ASR aliases (those live in the scorer only) |
| `prev` | names present in the most recent earlier call with the same label count class (3+ / 1) — the only series signal the app has without a calendar | refs of earlier calls only |
| `notes` | per person: how many calls, usual position in the daily order, usual topics, name garbles seen, and who is usually *absent* and only mentioned (Fish) — the smoke test shows the model wants to seat every listed name | refs of earlier calls only |
| `roster+notes` | both | |

Strictly chronological: for call *k* the context is built only from calls dated before *k*, as the app
would have it; the builder records the source call of every fact so a leak is a failing check, not a
reading of the text. Notes are first built from the *reference* of earlier calls (the "perfect memory"
upper bound). The rolling variant — the small model writes its own per-person note after each call, capped
at ~5 lines per person, and the next call reads it — is mandatory for the two finalist configs, not
optional: that is the memory the app would actually have, and its errors can compound.

**Models**, all GGUF through the app's `llama-server` b10819, one at a time, `nice -n 19`, 32k context:

| id | file | size | why |
|---|---|---|---|
| `gemma4-e4b` | `gemma-4-E4B-it-Q4_0.gguf` (installed) | 4.6 GB | zero shipping cost |
| `gemma4-12b` | `ggml-org/gemma-4-12B-it-GGUF` `gemma-4-12B-it-Q4_0.gguf` (Google's QAT repo is gated; ggml-org is where the app's E4B comes from too) | 7.2 GB | the colleague's suggestion; Russian |
| `qwen3.5-9b` | `unsloth/Qwen3.5-9B-GGUF` UD-Q4_K_XL | 6.0 GB | strongest reasoning in this size, thinking off |

No ollama, no LM Studio (template and sampling defaults differ from what ships). Before the grid, a smoke
run per model, thinking on and off, Russian and English call, through the schema: the chat template in use
(embedded or a pinned file with its sha256 in `models.json`) is recorded, the "outdated gemma4 chat
template" warning is noted but is not by itself a reason to swap templates. Context size: E4B at the
app's 65536, the others at 32768 if the longest call plus notes fits in memory (measured first on the
longest call: weights + KV + buffers against 32 GB with the Mac in normal use); a call that does not fit is
cut like the app cuts a summary and flagged. Tokens are counted per model tokenizer, not estimated.
Optional ceiling: one cloud model via OpenRouter (not the reference model), only if a decision hangs on it.

**Prompts.** `p1` — instruction + output schema + the hint that on these calls people address each other
by name all the time, with the four clue shapes (greeting, question answered by the next voice, hand-over
names the next voice, thanks names the previous voice) and "topics are only a second hint". `p0` — the
same without the hint (the first smoke prompt; the hint is ~100 tokens and rescued `edges50`). `p2` —
"first list the `order_idx` of every line where a label is addressed or introduces itself, then map"
(evidence field before the map, in the same JSON, line numbers only). Prompts, windows and thinking are
chosen on the `tune` half with all three models (a prompt that only helps Qwen must not be dropped on
E4B numbers). Thinking is off by default; it is run only on `full` and `edges100` × `notes` as a check,
since on `full` it was the only way to 3 of 4 and on `edges` it made the model refuse.

**Metrics** (`score.py`, per group and overall):

Each label's outcome is one of: `correct` (named, equals the reference), `wrong` (named, reference has
another name), `unverified` (named, reference `unknown` — not provably wrong: memory may be right where
the text is silent), `abstain` (answered unknown). `echo` and `mixed` labels are reported in their own
column and left out of the rest.

| column | how |
|---|---|
| `coverage` | correct / labels the reference names |
| `precision` | correct / (correct + wrong) — accuracy among the names the model dared to give |
| `wrong_rate` | wrong / labels the reference names — the costly error: a wrong name on screen is worse than no name |
| `unverified_rate` | unverified / labels the reference leaves unknown |
| `seg_coverage` | `coverage` weighted by segments per label — big speakers count more |
| `call_clean` | calls with no `wrong` label / calls; `call_exact` — every named label correct |
| `invalid` | responses that failed the schema, were cut by `max_tokens`, or missed a label / calls |
| `sec_per_call`, `prompt_tokens`, `cache_hit` | from llama-server timings; cached-prefix runs are flagged |

Decision rule, fixed now: among configs with `wrong_rate` ≤ 5 % on `tune`, take the highest `coverage`;
ties go to the cheaper one (no thinking, smaller window). Uncertainty is quoted per call (bootstrap over
calls), not per label — labels of one call are not independent.

Sanity: reference vs itself → `coverage` 1, `precision` 1, `wrong_rate` 0, `invalid` 0; all-`abstain`
hypothesis → `coverage` 0, `wrong_rate` 0.

**Run budget**, measured on E4B (today's 36-min daily): `full` 10.8k tokens ~27 s without thinking,
~80–120 s with; `names` 3.8k tokens 7 s; `edges100` 3.3k tokens 4 s; `edges50` 2.7k tokens 3.5 s.
Stage A1 (tune, 17 calls), thinking off: 4 windows × 5 contexts × 3 prompts = 60 configs on E4B
(~1000 runs, ~2 h), plus 2 thinking-on checks (34 runs, ~1 h); then the other two models over the 10
configs that won on E4B (~340 runs, ~1–2 h each with slower prefill). Stage A2 (test half, chosen
4 configs × 3 models × 17 calls) ~200 runs. Stage B (68 1:1 calls × 4 configs) ~270 runs, ~30 min.
A1 fits one night, A2 + B + the rolling-memory pass a second. Each model's speed is measured on a short,
a median and the longest call before its share is scheduled. The runner is resumable by a key that
hashes transcript, window, context text, prompt, schema, model file, template and sampling params — a
changed prompt never reuses an old result.

**How a night runs.** `night.sh` is started by hand in the evening (`nohup`, `nice -n 19`,
`lockf /tmp/beseda-speaker-names.lock` so it never overlaps the nightly `full_check.sh` or another run).
It goes model by model: start that model's `llama-server` on a free port, run every pending
(call, config) pair in call order so the server's prefix cache is reused across configs of one call,
write each reply as it arrives (`hyp/<key>/<id>.json`, atomic), stop the server, next model. One model in
memory at a time; the app's own server may be running next to it — 32 GB holds both. Any error is logged
and skips that pair, the script goes on; a crash or a kill at any point loses nothing, rerunning the
script picks up the missing pairs. At the end it runs `score.py`, writes `results/stage-a1.md` and sends
Mikhail a digest notification with the headline table and the count of failed pairs. In the morning:
read the table and the per-config failure list, decide the pruned set, start the next night.

## Steps

Each step ends with its check green and a commit.

- [ ] **0. Scaffold.** `.gitignore`: `!untracked/epics/speaker-names/` (the folder is ignored today) plus
  a local ignore for `models/`, `hyp/`, `data/transcripts/`. `pyproject.toml` (uv; stdlib + `tabulate`),
  `export_calls.py` → `data/transcripts/<id>.tsv` (`order_idx`, `start_sec`, `speaker`, `text`, raw keys)
  and `data/calls.json` (id, started_at, duration, app, labels, segments per label, group, tune/test).
  Check: 109 transcripts, groups 34/7/68, tune/test 17/17 by date.
- [ ] **1. Roster and aliases.** `data/roster.txt` (what a user would type: 6 names, one-line roles — the
  product input, fixed) and `data/people.json` (canonical names + aliases for the scorer and the reference
  agents only). Check: every name in the 16 `label_map`s resolves to a canonical entry or to
  `unknown`/`echo`.
- [ ] **2. Reference.** `REFERENCE_RUBRIC.md`; Opus agents on bb, ~8 in parallel, one call each (the
  transcript file path and `people.json` in the brief), writing `refs/<id>.json`; a validator rejects a
  ref with a label missing, a non-canonical name, a status missing, or evidence whose cited lines do not
  contain the name. Second pass as above. Check: 109 valid refs; `results/reference-check.md` with the
  agreement against the 16 judgments and what the second pass changed.
- [ ] **3. Scorer.** `score.py` (hyp dir → `results/<name>.md|json`, per group and tune/test, bootstrap CI
  over calls), `sanity_check.py` asserting the sanity numbers above. Check: sanity passes.
- [ ] **4. Contexts and windows.** `contexts.py`: the five builders, chronological, each fact tagged with
  its source call; `windows.py`: `full`, `names`, `head8k`. Check: notes for the first call are empty; an
  assertion that every fact's source call is dated before the target; print the notes for the last daily
  and read them once by eye; the `names` window of today's call contains the four addressing lines.
- [ ] **5. Runner.** `run_local.py` + `night.sh` as above: starts the model's llama-server on a free
  port, loops calls × configs, writes `hyp/<key>/<id>.json` with the raw reply, `reasoning_content`,
  timings, prompt tokens, cache hits and the config hash; atomic writes; resumable by hash. Models in
  `models/` (12B and Qwen downloaded 2026-11-02, E4B is the app's copy) with sha256 pinned in
  `models.json`. Smoke per model: thinking on/off, a Russian and an English call, the longest call for
  memory and context fit. Check: 3 calls × 1 config on each model produce valid JSON and score; memory
  figure per model recorded; `night.sh` survives a kill mid-run and resumes.
- [ ] **6. Stage A1 — tune.** E4B over the whole grid, then the other two over the pruned set, overnight.
  `results/stage-a1.md` + per-config failure list (label, reference, prediction, call) read by eye;
  choose the configs by the decision rule.
- [ ] **7. Stage A2 — test.** Chosen configs × 3 models on the `test` half: the headline table in
  `results/stage-a2.md`, with CI.
- [ ] **8. Stage B — 1:1 calls.** Chosen model(s) × `none/roster/notes/prev` on the 68 1:1 calls.
  Question answered: can memory name the recurring 1:1 partner, and how often does it invent one
  (`unverified_rate` is the number to watch — there is no reference name to confirm it).
- [ ] **9. Stage C — rolling memory.** The two finalists with self-written notes over the calls in date
  order, same empty start, note length capped; compared to reference-built notes on `test`. Optional on
  top, only if a decision hangs on it: a cloud ceiling; permuted `them-N` numbering.
- [ ] **10. Write-up.** This README becomes the results doc: tables, what helps and what does not, failure
  patterns, recommended model + window + context + prompt, and what the app needs to ship it (a roster
  setting, a per-person notes store, `call_speakers` rows written by the model). The BESEDA-156 rule
  (`them-N` keys never carry across calls) stays as is: names come from content, not from the keys. A
  `docs/decisions/speaker-names.md` is proposed only then.

Commits: Python only, under `untracked/`, outside SwiftPM's paths; the repo check (`swift test --jobs 2`)
is unaffected and is run once in a worktree before the first commit that touches `.gitignore`.

## Smoke test, 2026-11-02 (`smoke.py`)

Today's daily `20261102-125941` (36 min, 385 segments, 10.8k tokens), Gemma 4 E4B Q4_0 through the app's
llama-server, prompt `p1`, schema-forced JSON, temperature 0. Reference from the context audit:
them-1 Sergei, them-2 Rustam, them-3 Pixel, them-4 Mohammed. The text names them only in four places:
"Sergei, last week I asked you…" (start), "Rustam, can you please continue?" → them-2 speaks next,
"I believe Pixel was sick" → them-3 "I was down, guys", "maybe Mohammed, you can go" (said by them-3) →
them-4 speaks next.

| window | context | thinking | right | abstain | wrong | s |
|---|---|---|---|---|---|---|
| full | none | off | 2 | 2 | 0 | 27 |
| full | none | on | 2 | 2 | 0 | 78 |
| full | roster | off | 1 | 0 | **3** | 27 |
| full | roster | on | 1 | 3 | 0 | 80 |
| full | notes | off | 1 | 0 | **3** | 27 |
| full | notes | on | **3** | 0 | 1 | 117 |
| head8k | any | any | 0 | 3–4 | 0–3 | 8–55 |
| names | roster | off | 2 | 2 | 0 | 7 |
| names | roster | on | 2 | 2 | 0 | 47 |
| names | notes | off | 1 | 0 | **3** | 6 |
| names | notes | on | 2 | 2 | 0 | 35 |
| edges | none | off | 2 | 2 | 0 | 4 |
| edges | none | on | 2 | 2 | 0 | 16 |
| edges | roster | off | 3 | 0 | 1 | 4 |
| edges | roster | on | 1 | 3 | 0 | 48 |
| edges | notes | off | **4** | 0 | 0 | **4.5** |
| edges | notes | on | 1 | 3 | 0 | 57 |

What one call already says: Sergei and Rustam (addressed by Mikhail right before they speak) are found in
most variants; Pixel and Mohammed (named by *another remote speaker*, the hint is "the next voice") are
found by full + notes + thinking (3 of 4, 117 s, the fourth wrong by elimination: "if Pixel is them-3,
them-2 must be Gus" — the model never saw "Rustam, can you please continue?") and by **edges + notes
without thinking: 4 of 4 in 4.5 s**. On `full`, a roster or notes *without* thinking makes the model fill
every label with a name — three wrong on four, the worst outcome for the product; on `edges` the same
notes give 4 of 4, and the roster alone 3 of 4 with one wrong. The first 8k chars never suffice: the
addressing lines are spread over the call. Thinking on `edges` makes the model over-cautious (three
unknowns). One call is not a result; it sets the grid above — `edges` is the window to beat.

## Ideas from the smoke test, for the grid and later

- `edges` as the main window; `edges50` as the cheap variant; test turn-edge sizes 100/50 only — 4 s per
  call leaves nothing worth saving below that.
- Prompt hint: "people here address each other by name all the time; look for greeting / question →
  next voice / hand-over → next voice / thanks → previous voice first; topics second". Free, rescued
  `edges50`.
- Notes must say who is usually absent and only mentioned (Fish): with a bare roster the model seated
  Fish on a label in 4 of 6 runs.
- Thinking off on short windows; on the full call it is the only thing that works, at 25× the time.
- The label the model gets wrong is the one named by *another remote speaker* ("Mohammed, you can go")
  or by illness small-talk ("Pixel was sick" → "I was down"); worth a line in the hint if the grid shows
  the same.
- Elimination is the failure mode to watch: "if Pixel is them-3, them-2 must be Gus". The schema could
  allow the same name on two labels and the prompt should say "unknown beats a guess by elimination".
- Later, in the app: the `edges` view is cheap enough (4 s on E4B) to run right after every call, with
  the name written to `call_speakers` only when the model's answer is a listed person.

## Review notes (astra, 2026-11-02)

Taken into the plan: unverified ≠ wrong (point 1); tune/test split by date and per-call CI (2); roster as
a fixed user input without ASR aliases, facts tagged with their source call (3); rolling self-written notes
mandatory for the finalists, `prev` keyed by label count class (4); line-numbered evidence with speaker vs
addressee, second Opus pass (5); `echo`/`mixed` statuses (6); precision/coverage with a fixed decision
rule, corrected sanity numbers (7); prompt choice on all three models (8); budget recomputed from measured
times (9); thinking switched explicitly and verified in the reply (10); template pinned by hash, warning
not acted on blindly (11); no `enum` in the schema, `finish_reason` checked (12); memory and tokens
measured, E4B at the app's 65536 context (13); result key by hash (14); raw keys instead of
`TranscriptCopy`, `.gitignore` entry, BESEDA-156 left as is (15). Not taken: masking the addressing line
to test memory (changes the task), permuted labels and a cloud ceiling (kept optional).

## Assumptions and risks

- The reference is text-only and Opus-only, as agreed. Labels nobody can name from text are `unknown` by
  design; `nameable_acc` keeps them out of the headline number.
- Rosters let a model name by elimination ("the daily is always these four") — that is the intended
  product behaviour, not leakage; the chronological rule keeps real leakage out.
- Three models in sequence, each alone in memory; the 12B's footprint is measured in step 5, not assumed.
- Runs are Python only, no SwiftPM — they can live in the main checkout under `untracked/`, like the other
  epics; still under `nice` and a lock so they never collide with a full check.
- Model downloads (~13 GB) are the first cost; 140 GB free.
