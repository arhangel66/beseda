# Speaker names: can a small local model name `them-N`?

Status: in progress (2026-11-02 evening): reference done, scorer and runner done, night loop done (see Night loop). Research
only, no app code. The loop log is at the end of this file.

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

## Loop log (2026-11-02)

**Reference.** 109 calls labelled by Opus agents on bb with `REFERENCE_RUBRIC.md`: 130 named labels,
85 unknown (71 high-confidence unknown, mostly 1:1 calls where nobody says the name). Validator clean.
Against the 16 earlier context-audit judgments: 44 labels agree, 0 name conflicts, 6 named there but
unknown now (stricter rubric). `results/reference-check.md`.

**Fast loop set** (`FAST` in `score.py`): 8 tune dailies, 34 named labels, ~8 min per E4B iteration.
The first grid attempt over all 17 tune calls × 62 configs was stopped at 125 runs: `full` windows cost
30–50 s a call and thinking minutes (Qwen3.5 with thinking blew a 4000-token budget in 451 s). Hashed
results are kept.

**Rules baseline** (`rules.py`, no model): from the `clues` lines — a vocative name ("Rustam, can you
continue?", "...my side, Mohammed", "Mohammed?") votes for the next remote voice, "thank you, Sergei"
for the previous one, a voice saying a name is penalized one vote for being that person; greedy one name
per label. Versions: v1 keyword list → v2 vocative positions + new garbles (Fisher, Tish, Rustama, Goth,
Gosh) → v3 self-mention as a penalty instead of a veto. v4 (strict winner on ties, greeting half-vote,
tighter openers) lost coverage without removing the errors; dropped.

| rules | fast cov / prec | tune cov / prec / wrong | test cov / prec / wrong |
|---|---|---|---|
| v1 | 0.44 / 0.94 | 0.44 / 0.97 / 0.014 | 0.38 / 0.83 / 0.078 |
| v2 | 0.62 / 0.91 | 0.62 / 0.94 / 0.043 | 0.59 / 0.91 / 0.062 |
| **v3** | **0.65 / 1.00** | **0.61 / 0.96 / 0.029** | **0.61 / 0.91 / 0.062** |

Remaining rule errors are genuine text ambiguity: "Gus, can you please continue?" followed by Rustam
interrupting; "Hello Muhammad" answered by someone else; "We cannot hear you, Mohammed" with another
voice speaking next. The labels the rules leave unknown are named in the reference by indirect clues
("Pixel was sick" → "I was down"), a self-mentioned email, or garbles.

**Gemma 4 E4B** on the fast set, no thinking (stale table, old scorer): every config loses to the rules.
Best coverage 0.37–0.40 at precision 0.45–0.6, i.e. every second name wrong; the hint prompt (`p1`)
with a roster makes it bolder and worse (wrong 0.6–0.8). The structured `clues` window is a near-total
failure for E4B: 0–0.18 coverage, mostly "unknown". Conclusion: E4B cannot do the matching the rules do.
Calls that were 4/4 in the smoke test (today's) are the easy ones.

**Merge** (`merge.py`): the rules' names stay, the model fills only the labels the rules left
`unknown` and may not reuse a person the rules placed. This is the first setup that beats the rules.

## Night loop (2026-11-02 → 03)

**Scoring fixes** (from astra's review): a label unknown in the reference that the system also leaves
unknown is now `skip`, not an abstain in the coverage denominator (it deflated coverage and inflated
nothing else); an invalid model reply in a merge falls back to the rules' answer instead of failing the
call; merge compares canonical names. All numbers below use the fixed scorer; old tables are stale.
Rules v3 with the fixed scorer: tune 0.70 / wrong 0.033, test 0.71 / wrong 0.073.

**Round 1, finalists on all 17 tune calls** (`results/tune.md`):

| config (merged with rules3) | coverage | wrong |
|---|---|---|
| rules3 alone | 0.700 | 0.033 |
| 12B edges100 / roster+notes / p1 | 0.817 | 0.133 |
| 12B edges100 / roster / p2 | 0.783 | 0.067 |
| 12B edges100 / none / p1 | 0.767 | 0.050 |
| E4B clues / roster+notes / p1 | 0.783 | 0.083 |
| E4B edges100 / roster+notes / p2 | 0.783 | 0.100 |
| E4B names / roster / p1 | 0.783 | 0.100 |

Qwen3.5 9B on the fast set (merged): edges100/roster/p1 0.78 / wrong 0.16, p2 0.75 / 0.06 — no better
than Gemma 12B, slower than E4B; not pursued.

**Voting** (`vote.py`, `search_votes.py`, no new inference): an open label gets a name only if k of n
configs agree; a name the rules already placed needs all n (one person split over two labels). Best on
tune: 2 of 3 over the three 12B configs above, repeat on 3 of 3 — **0.817 coverage, wrong 0.050**
(3 wrong of 60, two of them the rules' own). Chosen on tune, so optimistic until test.

**Round 2, clue-line gating** (`p4`, `gate.py`): names restricted by schema to the team, each with a
cue type and the line index; code keeps a name only if that line says it and the label speaks next to
it. The models' line indices are mostly wrong, so the gate strips nearly every model name and the merge
falls back to the rules (fast 0.69–0.72, wrong 0). Ungated `p4` is an ordinary voter (E4B names/roster
0.81 / wrong 0.03 on fast). Dead end for small models.

**Round 3, more 12B voters** on tune (names, clues, edges50, full windows): every 2-4-config vote tops
out at 0.817 / wrong 0.05; the remaining labels are hard, not under-voted. A single 12B config,
full / none / p1, merged with the rules reaches 0.80 / wrong 0.05 alone.

**Rounds 4-5, finalists on test, once** (`final.py`, `results/final.md`):

| system | tune cov / wrong | test cov / wrong | test cov CI |
|---|---|---|---|
| rules3 alone | 0.700 / 0.033 | 0.709 / 0.073 | 0.60–0.81 |
| rules3 + E4B vote 2 of 2 | 0.767 / 0.050 | 0.745 / 0.091 | 0.63–0.85 |
| rules3 + 12B vote 2 of 3, repeat on 3 of 3 | 0.817 / 0.050 | 0.782 / 0.073 | 0.68–0.88 |
| ... + veto on 3 of 3 (added after seeing test) | 0.800 / 0.033 | 0.782 / 0.055 | 0.68–0.88 |
| rules3 + 12B full / none / p1 | 0.800 / 0.050 | 0.745 / 0.073 | 0.63–0.85 |
| rules3 + 12B names / none / p1 | 0.783 / 0.050 | 0.727 / 0.073 | 0.62–0.82 |

E4B voters: edges100/roster+notes/p2 and clues/roster+notes/p1. 12B voters: edges100 with none/p1,
roster/p2, roster+notes/p1. On test every wrong name of the 12B vote is one the rules made; the model
adds coverage without adding errors. The veto (all three 12B voters name someone else → the rules'
name becomes unknown) removes one of them; it was designed after looking at test, so test is now
partly development data and a fresh held-out set is needed for a clean number.

What is still missed on test: Fish four times (the founder is talked about, rarely addressed, the
reference names him from indirect clues), a Rustam/Gus swap where "Gus, can you continue?" is answered
by Rustam, and labels whose only clue is a garble.

**Round 6, one-to-one calls** (70 calls, 7 named labels in the reference; 5 two-remote calls): the risk
here is inventing names. 12B edges100 / roster+notes / p1 gives 56 names the reference cannot verify
(Rustam 36, Sergei 13, Gus 6) — it leans on the roster line "speaks Russian with Mikhail in 1:1 calls",
i.e. guesses by elimination. Without context only 6 unverifiable names, all odd ones (leo, надежда,
миша). The rules give 2. The finalist vote is not defined there (the roster/p2 voter was not run on
those calls). Whether "the 1:1 Russian call is Rustam" is a feature or a bug is a product decision.

**Conclusions of the night**

- Best system: rules3, then a 2-of-3 vote of Gemma 4 12B (edges100: none/p1, roster/p2,
  roster+notes/p1) for the labels the rules leave open. Test 0.78 coverage, wrong 0.073 (all the
  rules' own) or 0.055 with the unanimous veto. Three 12B requests per call, ~40–60 s each.
- With the built-in E4B only: rules3 + a 2-of-2 vote reaches test 0.745 / wrong 0.091 — worse than
  rules alone on errors; E4B is not worth adding unless the error budget is relaxed.
- Rules alone are the cheapest strong baseline: 0.71 / 0.073 on test with no model.
- Dead ends: clue-line gating (small models cite wrong lines), Qwen3.5 9B, more voters, `full` windows.
- The rules' own errors now cap precision; the next step is a fresh held-out month of calls, since
  test was looked at while designing the veto.

**Jev router on OpenRouter** (`typesafe/jev-router`, 2026-11-03, fast set only, 16 requests, $0.44).
The router picks a model per request: Grok 4.7, DeepSeek v4.1 flash, Meta Muse Spark, Claude Sonnet 5.5.
Three of 16 replies were invalid: DeepSeek flash ran into the 16 000-token cap. Alone, roster/p2:
0.77 coverage, 0 wrong on the 22 labels of the valid calls — about as good as rules + 12B, and far
above any local model alone (12B alone 0.41). Merged with rules3: 0.78 / wrong 0, the same as rules +
12B (0.81 / 0). 5–135 s per request. Not run on tune or test.

**Jev 1.13** (`typesafe/jev-1.13`, a System One decision model, not a chat model; OpenRouter
`/api/v1/systemone`, `jev.py`, `jev_threshold.py`). One request per call, one Choice question per label
(team names + `unknown`), each answer with probabilities and a confidence; a name is kept only above a
confidence threshold. Fast set, 32 requests, under 1 s each, $0.01 in total.

| window | alone, no threshold: cov / wrong | alone, confidence ≥ 0.5 | merged with rules3 |
|---|---|---|---|
| full | 0.50 / 0.094 | 0.44 / 0.031 | 0.72 / 0 |
| edges100 | 0.41 / 0.031 | 0.38 / 0.031 | 0.72 / 0 |
| names | 0.38 / 0.062 | 0.31 / 0.062 | 0.72 / 0 |
| clues | 0.13 / 0 | 0.09 / 0 | 0.69 / 0 |

Alone it is about Gemma 12B's level (0.41 / 0.031) at a fraction of the time; with the rules it adds
one label over rules alone (0.69 → 0.72), against 0.81 for rules + 12B. It answers `unknown` a lot:
TypeSafe's own notes say jev-1.13 is literal and weak at indirection, and "the next voice that
answers is the person addressed" is exactly one hop of indirection. A better fit would be literal
per-line questions (is this name said to someone? is this a thanks?) with the next-voice step in
code, i.e. Jev replacing the rules' regexes. Not run.

**Prompt p5** (Mikhail's, 2026-11-03: main rule "people say other people's names", per-rule direction,
evidence written before the name). Fast set, edges100, no context:

| model | alone: cov / wrong | merged with rules3 |
|---|---|---|
| 12B p5 | 0.41 / 0.188 | 0.69 / 0.094 |
| 12B p1 (before) | 0.41 / 0.031 | 0.75 / 0 |
| E4B p5 | 0.07 / 0.2, 4 of 8 calls invalid | 0.69 / 0.031 |

On the example call (`results/example-gemma12b-miss.txt`) p5 fixed 12B's Gus. Across the fast set it
made 12B bolder: it reads every name as a clue and keeps garbles as new people ("Sean", "Leo Mayo",
"Tim", "Мухаммад"), and on 20260910 it applies "being talked about" to "Rustam told that..." E4B quotes
whole lines as evidence and runs out of its 1500-token budget on half the calls.

**Prompt p6** (Mikhail's longer variant of p5: "careful transcript analyst", same rules as numbered
patterns, a 3000-token budget). Fast set, edges100, no context: 12B alone 0.34 / wrong 0.188, merged
0.72 / 0.062; E4B alone 0.03 / 0.125 (no invalid replies now, almost all "unknown"), merged 0.69 / 0.
Worse than p1 for both models.
