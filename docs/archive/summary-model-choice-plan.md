# Summary model choice

Date: 2026-09-06

Goal: decide whether a model small enough to ship inside the app (2–5 GB) writes
acceptable four-section Russian summaries, so the app can stop depending on
LM Studio. Long term the summary provider becomes a choice — built-in model,
LM Studio, OpenRouter with a key — and this experiment tells us what the
built-in option is worth.

## Setup

Four real calls exported from `calls.sqlite` the way the app feeds them to the
model (`TranscriptCopy.render(.clean)`: `"<name>: <text>"` per line). Scripts
and raw outputs in `untracked/scripts/summary-bench/`.

| call | length | Gemma tokens | note |
| --- | ---: | ---: | --- |
| 20260715-140740 | 17 min | 3.4k | daily standup, English |
| 20260902-174018 | 58 min | 14k | incident call, mixed |
| 20260626-121302 | 80 min | 23k | 1:1, Russian |
| 20260622-065841 | 87 min | 45k | onboarding, Russian |

Candidates, all Q4_0 GGUF from `ggml-org`, pinned by revision and sha256 in
`download.sh`:

| model | file | size |
| --- | --- | ---: |
| Gemma 4 E2B | `gemma-4-E2B-it-Q4_0.gguf` | 2.84 GB |
| Gemma 4 E4B | `gemma-4-E4B-it-Q4_0.gguf` | 4.59 GB |

Runtime: `llama-server` from Homebrew (build 10621), flags `-ngl 99 -fa on
--jinja`, context sized per transcript (tokens + 2.5k, rounded up to 1k). The
request is byte-for-byte what `LocalModelProvider` sends: system prompt, user
transcript, temperature 0.3.

Reference ceiling: `anthropic/claude-opus-5` through OpenRouter with the same
prompt. The planned 26B-A4B reference was deleted from disk mid-experiment, so
the ceiling is the cloud model — which is also the third provider we intend to
offer.

Quality was scored by Opus as a judge reading transcript plus all three
summaries, listing hallucinations, wrong owners in «Что делать», missed
agreements and language problems, then scoring 0–2 on format, language, facts,
attribution, coverage. Findings were spot-checked by hand against the
transcripts.

## Measurements

### Speed and memory on this M2 Max, 32 GB

| model | call | prompt tok | prompt tok/s | gen tok/s | cold start | total | peak RSS |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| E2B | 17 min | 3.4k | 1253 | 83 | 1.5 s | 19 s | 3.0 GB |
| E2B | 58 min | 14k | 990 | 71 | 1.5 s | 31 s | 3.0 GB |
| E2B | 80 min | 23k | 781 | 63 | 1.5 s | 49 s | 3.1 GB |
| E2B | 87 min | 45k | 528 | 53 | 2.0 s | 111 s | 3.3 GB |
| E4B | 17 min | 3.4k | 669 | 46 | 2.0 s | 40 s | 4.8 GB |
| E4B | 58 min | 14k | 574 | 42 | 2.0 s | 56 s | 5.0 GB |
| E4B | 80 min | 23k | 513 | 40 | 2.0 s | 91 s | 5.1 GB |
| E4B | 87 min | 45k | 335 | 32 | 2.5 s | 172 s | 5.4 GB |

Cold start is process launch to `/health` with the model mmapped; it stays
around 2 s for both. Opus through OpenRouter: 30–53 s per call, $0.06–0.40 each
($0.85 for the four). The old LM Studio path with the 26B model took 24 s just
to load and ~500 s for a 97k-token transcript.

### Quality, judge scores 0–2

| call | model | format | language | facts | attribution | coverage |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 87 min | E2B | 2 | 1 | 0 | 0 | 1 |
| 87 min | E4B | 2 | 1 | 1 | 1 | 1 |
| 87 min | Opus | 2 | 1 | 2 | 2 | 2 |
| 80 min | E2B | 2 | 1 | 1 | 0 | 1 |
| 80 min | E4B | 2 | 1 | 1 | 1 | 1 |
| 80 min | Opus | 2 | 1 | 2 | 2 | 2 |
| 58 min | E2B | 2 | 1 | 1 | 1 | 1 |
| 58 min | E4B | 2 | 1 | 1 | 0 | 1 |
| 58 min | Opus | 2 | 1 | 2 | 2 | 2 |
| 17 min | E2B | 2 | 1 | 1 | 1 | 1 |
| 17 min | E4B | 2 | 1 | 1 | 1 | 1 |
| 17 min | Opus | 2 | 1 | 2 | 1 | 2 |

What the scores mean in practice:

- **Facts.** E2B invents or garbles roughly five statements per long call:
  «графовые базы данных» for Grafana, «off-token платежи» for alpha-token
  payouts, «данные о выбросах» for token emission, «Установлено, что критически
  важны логи Elasticsearch/Datadog» where the transcript only mentions them as
  someone's past experience. E4B garbles one to four per call and sometimes
  inverts the meaning: «PR включающий SSH install можно развертывать» where the
  PR removes the SSH install, «reset слишком рискован для валидатора» where the
  risk was giving it to the renter, «TMC Pay отключён из-за ошибки» where the
  key was swapped on purpose. Opus has interpretation nits only.
- **Attribution.** Neither small model reliably says who does what. E2B assigns
  tasks to «Собеседник 2» and to a «бизнес-девелопмент-менеджер» that does not
  exist; E4B mostly drops the owner. Opus infers names from the speech itself
  («Rustam», «Pixel», «Борис») and gets them right.
- **Coverage.** Both small models keep the theme and the top three or four
  points and lose the rest: the deployment process, the standup time, the memory
  leak in the inspector PR, the concrete numbers (18% → 4% deploy errors, ~95%
  of revenue from server GPUs, Mortex $50k → $500). Opus keeps them.
- **Language.** All three, including Opus, lean on transliterated English
  («флоу», «фидбэк», «эстимейт»). The small models add nonsense words from ASR
  noise («вижен-аппликейсной», «redon access», «скрипт Liu»).

Side by side on the 58-minute incident call, Opus names the attack scheme,
the amounts, the 13 blocked accounts, the bug that zero balance did not stop
rentals, and who does what tomorrow. E4B has the shape of that with no numbers
and mostly no owners. E2B has the shape plus a few invented details.

### Prompt finding: «только жирный текст» makes everything bold

With the app's current `defaultPrompt`, 4 of 8 small-model summaries came out
with every line bold and no «—» bullets — the phrase «только жирный текст и
переносы» reads as «make it all bold». Rewording to «Жирным выделяй только
названия четырёх разделов, остальной текст обычный» and adding «строка
начинается с «—»» fixed it in 8 of 8 reruns. This is worth shipping regardless
of model; the reworded prompt is in `run_prompt_v2.py`.

## Verdict

**A shippable small model is not good enough to be the default.** Both Gemma 4
sizes follow the format, run fast and fit in 3–5 GB of memory, but they miss
about half the agreements, do not say who owns an action, and E2B fabricates.
For a summary whose whole point is «what did we agree and who does what», that
is the wrong trade.

E4B is the better of the two and usable as «better than nothing»: the theme
and the top points are right, but every call had one or two sentences that
say the opposite of what was agreed. E2B is not worth shipping: it saves
1.75 GB and pays with invented facts on top of that.

So the provider picker matters more than bundling:

1. **OpenRouter** with the user's key is the quality option: ~$0.20 per hour
   of call, 30–50 s, no local memory. Same OpenAI-compatible request as today
   plus an `Authorization` header and a base URL.
2. **LM Studio** stays for people who already run a big local model.
3. **Built-in Gemma 4 E4B** (4.59 GB, ~5 GB RAM while running) is the offline
   fallback, clearly labelled as the rough option. E2B is dropped.

Next plan: the provider picker and the `llama-server` bundling for option 3,
sketched in the earlier assessment (subprocess started on demand, killed after
an idle timeout, model downloaded through the existing `RuntimeInstaller`
catalogue).
