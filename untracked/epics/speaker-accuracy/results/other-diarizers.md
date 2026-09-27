# Other local diarizers on real calls and the benchmark (BESEDA-115, 2026-09-27)

Research only, no app change. Question: can a different local diarizer or a stronger embedding get the number
of people right by itself? The app today: FluidAudio 0.15.6 offline (pyannote community-1 segmentation +
WeSpeaker ResNet34 + VBx, t0.70) plus the BESEDA-84 rule that merges speakers whose longest segment is under 6 s.

**Caveat: the real-call truth ([real-calls-truth.md](real-calls-truth.md)) is participant counts that an LLM
inferred from transcripts. Nobody labelled it by hand.** 10 calls are 1:1 (truth 1). The 5 dailies have 3–4
people; the confidence is medium or low.

## How it was run

- `other_diarizers.sh` loops over the system channel (`them.asr.wav`) of the 15 truth calls. For each call it
  makes a clone copy in a temp dir, runs each call alone, then deletes the copy. After the calls it runs the 5
  real benchmark files (VoxConverse ×3, AMI ×2).
- Every run goes through `nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock /usr/bin/time -l`, and a run starts
  only when at least 20 % of memory is free.
- The FluidAudio 0.17.4 variants run through `diarization/Diarize`. Its new variant `nemotron3-offline` is
  Nemotron-3 Diarization with the `offline` preset. The runner writes `hyp/other/<variant>/`.
- `embed_segments.py` (sherpa-onnx, CPU, venv of this folder) re-embeds every `offline-t0.7` segment with 4
  models. Segments of 0.5 s or longer each get one vector; shorter segments take the speaker of the nearest
  embedded segment. It writes `hyp/other/emb-<model>/`.
- `other_diarizers.py` scores everything:
  - Calls: shown `them` speakers after the app's per-sentence assignment (`SentenceSpeakerAssignment` replay).
  - Benchmark: DER (collar 0.25 s), speaker-count error, and glued people. Glued = reference speakers whose
    most-overlapping hypothesis speaker is also another reference speaker's. This is stricter than the glued
    count in [short-reply-merge.md](short-reply-merge.md), which counted only people that a merge glued. Here a
    diarizer that finds too few speakers counts as glued too, so the baseline scores 4, not 0.
  - "One speaker or more" check: per call, the share of sentence-seconds that is not on the main speaker. The
    margin is the lowest daily minus the highest 1:1 call. Above 0 means one threshold separates 1:1 calls
    from dailies. For the embedding models there is also the cosine distance of the last average-linkage merge.
- Raw per-file outputs, peak memory per run (`hyp/other/memory.log`) and the full score dump are in `hyp/`
  (gitignored).

## Summary

| approach | 1:1 correct (of 10) | dailies correct (of 5) | benchmark DER / count error / glued | 1:1 vs daily margin | speed, × realtime | peak memory | model size | license (sold app?) | ship path |
|---|---|---|---|---|---|---|---|---|---|
| **now**: offline t0.70 (0.17.4, same models as the app) | 0 | 1 | 0.119 / 0.60 / 4 | +0.067 | 134 | 0.62 GB | 21 MB | Apache-2.0 code, CC BY 4.0 weights: yes | in the app |
| now + 6 s rule (app today) | 9 | 3 | 0.118 / 0.80 / 4 | +0.040 | 134 | 0.62 GB | 21 MB | yes | in the app |
| Sortformer 4 spk v2 | 2 | 3 | 0.138 / 0.60 / 3 | +0.302 | 14 | 0.58 GB | 229 MB | CC BY 4.0 / NVIDIA Open Model: yes | Core ML, in FluidAudio 0.17.4 |
| Sortformer + 6 s rule | 10 | 3 | 0.228 / 1.80 / **9** | +0.455 | 14 | | | | |
| LS-EEND DIHARD3 | 7 | 0 | 0.726 / 2.40 / 15 | −0.136 | 28 | 0.72 GB | 85 MB (both) | MIT: yes | Core ML, in FluidAudio 0.17.4 |
| LS-EEND CALLHOME | 4 | 0 | 0.680 / 2.80 / 16 | −0.131 | 30 | 0.71 GB | | MIT: yes | Core ML, in FluidAudio 0.17.4 |
| **Nemotron-3 Diarization, offline preset** | **10** | 2 | 0.127 / **0.00** / 2 | **+0.455** | **304** | 0.57 GB | 190 MB | OpenMDW-1.1: yes (permissive) | Core ML, in FluidAudio 0.17.4 |
| Nemotron-3 + 6 s rule | 10 | 3 | 0.223 / 1.80 / **9** | +0.455 | 304 | | | | |
| offline segments + WeSpeaker ResNet34 re-embedded (control) | 4 | 1 | 0.201 / 2.80 / 5 | +0.220 | 51 | 2.18 GB (all 4 models) | 27 MB | CC BY 4.0: yes | ONNX (sherpa-onnx has a Swift API) |
| + 3D-Speaker CAM++ | 0 | 0 | 0.367 / 5.00 / 9 | −0.247 | 77 | | 30 MB | Apache-2.0: yes | ONNX; FluidAudio 0.17.4 ships a Core ML CAM++ (beta) |
| + 3D-Speaker ERes2NetV2 (zh-cn common) | 1 | 0 | 0.123 / 2.00 / 3 | +0.255 | 31 | | 71 MB | Apache-2.0: yes | ONNX |
| + WeSpeaker ResNet293 | 10 | 0 | 0.323 / 3.00 / 10 | +0.000 | 11 | | 114 MB | CC BY 4.0: yes | ONNX |
| pyannote community-1 / 3.1 (Python) | skipped | | | | | | | CC BY 4.0 / MIT | see below |
| DiariZen (WavLM) | stopped | | | | | | | **CC BY-NC 4.0: no** | see below |

- The speed column is total audio over total processing time, model load excluded. The 15 calls plus the
  benchmark are about 5.5 h of audio.
- The embedding rows show the threshold with the lowest benchmark DER. Their speed is the diarizer and the
  embedding together.
- Target: 10/10 1:1 calls, 5/5 dailies, 0 glued. **No candidate meets it.**

## Embedding swap: threshold sweep

Each cell is benchmark DER / count error / glued; 1:1 calls exact; dailies exact. The segments come from the
offline t0.70 run and are clustered by average linkage on cosine distance.

| model | 0.3 | 0.35 | 0.4 | 0.45 | 0.5 | 0.55 | 0.6 | 0.65 | 0.7 | 0.75 | 0.8 | 0.85 | 0.9 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| resnet34 | 0.201/2.8/5; 4; 1 | 0.271/2.4/8; 7; 0 | 0.358/2.8/10; 9; 0 | 0.363/2.8/11; 10; 0 | 0.363/2.8/11; 10; 0 | 0.365/2.8/12; 10; 0 | 0.430/3.0/13; 10; 0 | 0.430/2.8/13; 10; 0 | 0.449/2.8/14; 10; 0 | 0.454/3.0/15; 10; 0 | 0.483/3.2/16; 10; 0 | 0.483/3.2/16; 10; 0 | 0.483/3.2/16; 10; 0 |
| resnet34 top merge distance: 1:1 max 0.426, dailies min 0.479, margin +0.054 |
| campplus | 0.369/5.4/7; 0; 0 | 0.367/5.0/9; 0; 0 | 0.369/4.4/10; 0; 0 | 0.371/3.6/10; 0; 0 | 0.394/2.8/12; 0; 0 | 0.400/2.4/12; 0; 0 | 0.395/1.8/12; 0; 0 | 0.431/1.6/13; 0; 0 | 0.420/1.4/14; 0; 1 | 0.421/1.4/14; 2; 3 | 0.411/2.0/14; 7; 1 | 0.396/2.6/14; 10; 1 | 0.433/2.8/15; 10; 0 |
| campplus top merge distance: 1:1 max 0.847, dailies min 0.780, margin -0.067 |
| eres2netv2 | 0.156/4.6/2; 0; 0 | 0.137/3.4/2; 0; 0 | 0.123/2.0/3; 1; 0 | 0.165/1.4/5; 6; 0 | 0.195/1.4/6; 7; 0 | 0.267/1.6/9; 8; 1 | 0.383/2.2/13; 9; 2 | 0.478/2.8/15; 9; 1 | 0.483/3.2/16; 9; 1 | 0.483/3.2/16; 9; 0 | 0.483/3.2/16; 9; 0 | 0.483/3.2/16; 10; 0 | 0.483/3.2/16; 10; 0 |
| eres2netv2 top merge distance: 1:1 max 0.807, dailies min 0.734, margin -0.072 |
| resnet293 | 0.323/3.0/10; 10; 0 | 0.365/3.0/11; 10; 0 | 0.366/3.0/12; 10; 0 | 0.366/3.0/12; 10; 0 | 0.431/3.0/13; 10; 0 | 0.451/2.8/14; 10; 0 | 0.455/2.8/15; 10; 0 | 0.454/3.0/15; 10; 0 | 0.483/3.2/16; 10; 0 | 0.483/3.2/16; 10; 0 | 0.483/3.2/16; 10; 0 | 0.483/3.2/16; 10; 0 | 0.483/3.2/16; 10; 0 |
| resnet293 top merge distance: 1:1 max 0.268, dailies min 0.287, margin +0.020 |

- None of the models gets both 1:1 calls and dailies right at any one threshold. Where the 1:1 calls come out
  at 1, every daily falls to 1–2 people and the benchmark glues 10–16 people.
- The ResNet34 control does not reproduce the app's pipeline: DER 0.20 or more, against 0.119. So re-clustering
  whole segments is much weaker than FluidAudio's windowed embeddings with PLDA/VBx. This test is therefore a
  lower bound for the stronger models. Still, the "one speaker or more" distances do not separate the calls
  either: ResNet293 margin +0.020, ResNet34 +0.054, CAM++ −0.067, ERes2NetV2 −0.072. That is the same thin
  margin BESEDA-114 found with WeSpeaker (0.03).
- A fair swap would feed the new model FluidAudio's per-window chunks (the RealCalls `chunks` mode from
  BESEDA-114) and keep VBx. That needs a PLDA for the new embedding, and none is shipped. Not done.

## Per call: shown `them` speakers

`now (t0.70)` and `6 s rule` are copied from [short-reply-merge.md](short-reply-merge.md) (0.15.6). The
0.17.4 `offline-t0.7` run here gives the same counts.

| call | real | now (t0.70) | 6 s rule | Sortformer | Sortformer + 6 s | LS-EEND DIHARD3 | LS-EEND CALLHOME | **Nemotron-3** | Nemotron-3 + 6 s | CAM++ t0.35 | ERes2NetV2 t0.4 | ResNet293 t0.3 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 20260925-114649 | 1 | 2 | 1 | 3 | 1 | 1 | 1 | **1** | 1 | 10 | 1 | 1 |
| 20260925-111702 | 1 | 2 | 1 | 1 | 1 | 2 | 2 | **1** | 1 | 5 | 2 | 1 |
| 20260924-173649 | 1 | 2 | 1 | 3 | 1 | 1 | 1 | **1** | 1 | 11 | 5 | 1 |
| 20260924-173310 | 1 | 2 | 1 | 2 | 1 | 1 | 1 | **1** | 1 | 8 | 4 | 1 |
| 20260924-133358 | 1 | 3 | 1 | 1 | 1 | 1 | 1 | **1** | 1 | 4 | 2 | 1 |
| 20260924-110157 | 1 | 3 | 1 | 3 | 1 | 1 | 2 | **1** | 1 | 11 | 4 | 1 |
| 20260923-125419 | 1 | 2 | 2 | 2 | 1 | 1 | 2 | **1** | 1 | 12 | 2 | 1 |
| 20260923-101613 | 1 | 3 | 1 | 3 | 1 | 1 | 2 | **1** | 1 | 21 | 4 | 1 |
| 20260922-115609 | 1 | 2 | 1 | 3 | 1 | 2 | 2 | **1** | 1 | 17 | 4 | 1 |
| 20260922-084404 | 1 | 2 | 1 | 2 | 1 | 2 | 2 | **1** | 1 | 17 | 2 | 1 |
| 20260925-125945 | 3 | 4 | 3 | 4 | 3 | 1 | 2 | **3** | 3 | 20 | 6 | 1 |
| 20260924-130017 | 4 | 4 | 2 | 3 | 2 | 1 | 2 | **2** | 2 | 26 | 3 | 1 |
| 20260923-130021 | 4 | 7 | 5 | 4 | 4 | 2 | 2 | **6** | 5 | 50 | 18 | 2 |
| 20260922-125838 | 4 | 6 | 4 | 4 | 4 | 1 | 2 | **4** | 4 | 40 | 9 | 1 |
| 20260921-125925 | 4 | 5 | 4 | 4 | 3 | 2 | 2 | **5** | 4 | 37 | 11 | 3 |

- On the 1:1 calls Nemotron-3 alone shows 1 on all 10, with no merge rule.
- The dailies are what is left: 20260924-130017 4 → 2 (no candidate gets above 3 there), 20260923-130021
  4 → 6, 20260921-125925 4 → 5. BESEDA-82 read the 20260924-130017 transcript: two of the four people are
  already inside the main two speakers of the WeSpeaker clustering. The end-to-end models glue them the same
  way.
- Adding the 6 s rule on top of Sortformer or Nemotron-3 fixes one more daily but glues 9 benchmark people:
  AMI 4 → 1. These models give long turns to a real person only when that person talks long, and AMI turns
  are short. So the rule must not stay if the diarizer changes.

## Time and peak memory per call (processing seconds / peak RSS)

| file | min | offline-t0.7 | sortformer | lseend-dihard3 | lseend-callhome | nemotron3-offline | 4 embedding models (s total / GB) |
|---|---|---|---|---|---|---|---|
| 20260925-114649 | 4 | 1.2 s / 0.31 GB | 17.2 s / 0.39 GB | 7.0 s / 0.14 GB | 9.1 s / 0.13 GB | 2.2 s / 0.50 GB | 16 s / 0.67 GB |
| 20260925-111702 | 1 | 0.6 s / 0.28 GB | 5.5 s / 0.11 GB | 2.7 s / 0.09 GB | 2.2 s / 0.08 GB | 0.8 s / 0.08 GB | 4 s / 0.54 GB |
| 20260924-173649 | 9 | 3.5 s / 0.37 GB | 35.1 s / 0.18 GB | 17.8 s / 0.18 GB | 18.2 s / 0.18 GB | 1.7 s / 0.15 GB | 62 s / 1.02 GB |
| 20260924-173310 | 3 | 1.3 s / 0.29 GB | 10.4 s / 0.12 GB | 5.4 s / 0.10 GB | 5.2 s / 0.10 GB | 0.8 s / 0.09 GB | 12 s / 0.92 GB |
| 20260924-133358 | 5 | 2.0 s / 0.31 GB | 19.5 s / 0.14 GB | 8.7 s / 0.13 GB | 8.4 s / 0.13 GB | 1.3 s / 0.12 GB | 36 s / 1.71 GB |
| 20260924-110157 | 4 | 2.3 s / 0.32 GB | 18.7 s / 0.14 GB | 15.2 s / 0.12 GB | 8.9 s / 0.12 GB | 1.1 s / 0.11 GB | 22 s / 0.76 GB |
| 20260923-125419 | 5 | 1.7 s / 0.30 GB | 21.0 s / 0.14 GB | 10.1 s / 0.13 GB | 10.8 s / 0.13 GB | 1.5 s / 0.11 GB | 27 s / 0.64 GB |
| 20260923-101613 | 26 | 10.7 s / 0.45 GB | 119.1 s / 0.30 GB | 78.1 s / 0.40 GB | 92.6 s / 0.39 GB | 4.7 s / 0.31 GB | 151 s / 0.77 GB |
| 20260922-115609 | 13 | 3.9 s / 0.39 GB | 50.6 s / 0.22 GB | 23.3 s / 0.25 GB | 26.1 s / 0.24 GB | 2.5 s / 0.19 GB | 63 s / 0.72 GB |
| 20260922-084404 | 23 | 7.2 s / 0.44 GB | 89.3 s / 0.32 GB | 46.0 s / 0.36 GB | 43.1 s / 0.36 GB | 3.7 s / 0.30 GB | 133 s / 0.70 GB |
| 20260925-125945 | 29 | 11.0 s / 0.46 GB | 121.0 s / 0.38 GB | 47.5 s / 0.44 GB | 54.0 s / 0.44 GB | 5.3 s / 0.35 GB | 234 s / 0.98 GB |
| 20260924-130017 | 33 | 9.6 s / 0.56 GB | 125.2 s / 0.42 GB | 52.8 s / 0.49 GB | 55.0 s / 0.49 GB | 5.8 s / 0.39 GB | 230 s / 1.08 GB |
| 20260923-130021 | 51 | 21.9 s / 0.51 GB | 207.4 s / 0.58 GB | 116.5 s / 0.72 GB | 91.8 s / 0.71 GB | 8.9 s / 0.57 GB | 431 s / 1.80 GB |
| 20260922-125838 | 48 | 28.7 s / 0.62 GB | 197.0 s / 0.57 GB | 86.5 s / 0.68 GB | 83.5 s / 0.68 GB | 8.4 s / 0.53 GB | 384 s / 1.39 GB |
| 20260921-125925 | 31 | 20.0 s / 0.41 GB | 141.6 s / 0.38 GB | 66.2 s / 0.47 GB | 64.0 s / 0.47 GB | 7.3 s / 0.39 GB | 258 s / 1.40 GB |
| ami_ES2004a | 6 | 2.3 s / 0.34 GB | 23.6 s / 0.16 GB | 11.2 s / 0.15 GB | 10.1 s / 0.14 GB | 1.1 s / 0.13 GB | 34 s / 0.91 GB |
| ami_IS1009a | 6 | 2.7 s / 0.35 GB | 23.6 s / 0.15 GB | 11.3 s / 0.15 GB | 10.8 s / 0.14 GB | 1.1 s / 0.13 GB | 43 s / 0.90 GB |
| vox_asxwr | 4 | 3.1 s / 0.29 GB | 19.6 s / 0.13 GB | 19.1 s / 0.12 GB | 7.7 s / 0.12 GB | 0.7 s / 0.11 GB | 37 s / 1.60 GB |
| vox_azisu | 3 | 1.8 s / 0.31 GB | 12.5 s / 0.13 GB | 6.0 s / 0.11 GB | 4.6 s / 0.11 GB | 0.7 s / 0.10 GB | 32 s / 1.29 GB |
| vox_gzvkx | 4 | 1.7 s / 0.32 GB | 14.4 s / 0.13 GB | 13.2 s / 0.12 GB | 5.3 s / 0.12 GB | 0.7 s / 0.11 GB | 39 s / 2.18 GB |

Everything stays under 2.2 GB, far below the ~12 GB limit. The Mac was shared with BESEDA-114 under the same
lock, so the timings are rough.

## Candidates that were not run, and what shipping them would cost

- **pyannote community-1 / 3.1 in Python.** Both are gated on Hugging Face ("auto" gate: accept the conditions
  with a token), and this Mac has no token, so skipped. The weights themselves allow a sold app:
  community-1 is CC BY 4.0 (the same weights FluidAudio already runs in Core ML, 21 MB, 134× realtime above),
  3.1 is MIT (segmentation-3.0 plus WeSpeaker ResNet34). Shipping the Python pipeline would mean bundling a
  Python runtime with PyTorch, several hundred MB. The Core ML route already exists: it is what the app runs
  now, so a Python run would mostly measure PyTorch against Core ML.
- **DiariZen (BUT-FIT, WavLM + pyannote).** Stopped on the license: the weights on Hugging Face
  (`diarizen-wavlm-{base,large}-s80-md`) are **CC BY-NC 4.0**, so no commercial use, and the app is sold. If
  the license allowed it, shipping would mean converting WavLM Base+ (~95 M parameters, ~380 MB in fp32,
  ~190 MB in fp16) to Core ML, plus the pyannote-style clustering in Swift. Not measured on the M2 Max.

## Recommendation

**Nemotron-3 Diarization (offline preset), already in FluidAudio 0.17.4, is the best candidate and the only
one that gets the 1:1 calls right by itself.**

- 10/10 1:1 calls without the 6 s rule.
- Benchmark speaker count exact on all 5 files; DER 0.127 against 0.119.
- The widest margin between 1:1 calls and dailies (+0.455).
- 300× realtime, 0.6 GB RAM, 190 MB model.
- OpenMDW-1.1 license (permissive, commercial use allowed); native Core ML.

It does not fix the dailies: 2 of 5, against 3 of 5 for the app today. 20260924-130017 stays at 2, and
another 20260923-130021 plus 20260921-125925 show one or two people too many. The truth for those calls is an
LLM's medium- or low-confidence guess.

Next step, if taken:
1. Move the app from 0.15.6 to 0.17.4.
2. Run Nemotron-3 offline as the after-call diarizer.
3. Drop the 6 s rule for it (with it, AMI glues).
4. Check whether 190 MB more to download is acceptable.

None of the stronger embeddings helps in this form. Sortformer and LS-EEND are worse than the current pipeline.
