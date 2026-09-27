# Summary quality: agreements and assignees (BESEDA-94)

Does the default local summary (Gemma 4 E4B Q4_0, the installed built-in llama-server b10819) keep what a
call agreed and who does what? Checked on one synthetic call, hand-scored against a key written with the
transcript. This is not a human-labelled benchmark of real calls; it is one sample, three runs per variant.

- `transcript.txt` — a made-up Russian release-planning call, ~1200 words (~9 min of speech), five
  speakers, in the `Имя: текст` shape `SummarizationService` sends. No recap at the end: agreements and
  assignments are said in passing, as in real calls.
- `run_check.py` — starts the installed llama-server read-only on port 8791 and writes `run-N.md` per variant.
- `runs-before/` — the old default prompt, temperature 0.3.
- `runs-v1/` — the new default prompt (shipped), temperature 0.1.
- `runs-v2/` — a variant that also pushes plans into «Договорились»; not better, not shipped.

## Key

Agreements (6): only СБП in 2.4, Apple Pay moved to 2.5; onboarding cut to 3 steps; beta for 200 people
from 3 October, one week; release moved to 17 October; phased rollout from 10%; mailing only after the
App Store review passes.

Assignments (9, five people): Сергей — СБП with refunds on the test bank environment by 1 October;
Сергей — hand onboarding layout to Лёша; Ольга — onboarding mock-ups by Wednesday; Дима — regression
plan; Дима — beta invites and feedback form; Дима — send the beta build on the 2nd; Анна — tester list
by Friday; Анна — mailing text and post with the lawyer, draft by 14 October; Вы — tell the client and
update the roadmap today.

## Result

| variant | agreements kept (of 6) | assignments kept (of 9) | assignees named |
|---|---|---|---|
| before, run 1/2/3 | 5 / 6 / 5 — 16 of 18 | 7 / 7 / 7 — 21 of 27 | 5 of 5 every run |
| v1 (shipped), run 1/2/3 | 5 / 5 / 5 — 15 of 18 | 8 / 7 / 8 — 23 of 27 | 5 of 5 every run |
| v2, run 1/2/3 | 5 / 6 / 4 — 15 of 18 | 8 / 7 / 7 — 22 of 27 | 5 of 5 every run |

What this shows:
- On this sample the old prompt did not lose assignees: every run named all five people. The Processing
  screen's «редко называет исполнителей» is not reproduced here.
- The new prompt writes one task per line with the name first and keeps deadlines like «сегодня до
  вечера», which the old one dropped in all three runs; it caught Сергей → Лёша, which the old one never did.
- Agreements stay at 5 of 6 either way. The one lost most often is the beta plan: the model files it
  under Дима's task instead of «Договорились». Nobody ever caught «send the beta build on the 2nd».
- The difference between variants is within run-to-run noise on one sample. A real-call benchmark is
  still the way to prove it.
