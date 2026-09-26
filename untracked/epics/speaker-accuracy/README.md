# Speaker accuracy: eval set and scorer

Epic BESEDA-6 measures, locally, how well Beseda tells speakers apart ("who spoke when", "me" vs "them")
and how well it transcribes the remote side. This folder is the fixed, reproducible yardstick every
measurement uses: a small eval set with reference labels and one scorer. Research only, no app code.

| file | what |
|---|---|
| `data/manifest.json` | the set, pinned: source URLs (git commits, HF revision), file ids, crop windows, sha256, licences, synthetic seed |
| `make_eval.py` | fetch the sources into `data/cache/`, build `data/audio/` (both gitignored) and `data/refs/` (committed) |
| `score.py` | score a hypothesis dir against `data/refs/`, write `results/<dir name>.md` and `.json` |
| `sanity_check.py` | scores the reference against itself and a one-speaker hypothesis, asserts the numbers below |
| `data/built.sha256` | sha256 of every built audio file; a rebuild warns if the bytes differ |
| `results/` | committed score tables |
| `baseline/` | Beseda's current pipeline: what it does (with code references), the adapter that runs it on this set, its numbers — [baseline/README.md](baseline/README.md) |
| `diarization/` | local diarization and me/them alternatives on FluidAudio 0.17.4 + an echo gate, compared to the baseline — [diarization/README.md](diarization/README.md) |
| `asr/` | local remote-speech ASR alternatives (Whisper turbo, GigaAM CTC, loudnorm, ru/en routing) vs the baseline engines, WER/CER by language — [asr/README.md](asr/README.md) |

## What is in the set (28 min, 13 recordings)

**Real diarization** (single `system` channel, no reference text):

| id | source | window | speakers |
|---|---|---|---|
| `vox_azisu` | VoxConverse dev `azisu` | whole, 194 s | 4 |
| `vox_asxwr` | VoxConverse dev `asxwr` | whole, 238 s | 3 |
| `vox_gzvkx` | VoxConverse dev `gzvkx` | whole, 225 s | 6 |
| `ami_ES2004a` | AMI `ES2004a` Mix-Headset | 60–420 s | 4 |
| `ami_IS1009a` | AMI `IS1009a` Mix-Headset | 60–420 s | 4 |

References: VoxConverse RTTM (joonson/voxconverse), AMI "only_words" RTTM (pyannote/AMI-diarization-setup),
cropped to the window and shifted to start at 0.

**Synthetic calls** (8 calls, 28–49 s each, FLEURS dev, mostly Russian, three with English remote speakers,
one where "me" speaks English): 2–4 remote speakers take turns with pauses of 0.2–1.0 s and a quarter of
turn changes overlapping by 0.2–0.8 s. Two channels, like Beseda records them:

- `<id>.system.wav` — the remote speakers, degraded like a call: 100–7000 Hz band, libopus 20 kbps and back,
  white noise at −50 dBFS.
- `<id>.mic.wav` — "me" (speaker `me`), plus the degraded system channel bleeding in at −20 dB, 60 ms late
  (echo), plus the same noise floor.

FLEURS has no speaker ids, so one FLEURS recording is one voice: each speaker's recording is cut into
2–4 turns at the pauses that best fit its clause punctuation (commas, `;`, `:`) by speech rate, and the
normalized transcription is split at the same clauses. Recordings with no plausible fit are skipped. Turns
are therefore short (1–6 s) and each speaker has 2–4 of them. Reference text is FLEURS' normalized
transcription. A fixed seed makes the mix byte-reproducible with the same ffmpeg/libopus
(checked: two clean builds give identical `built.sha256`).

Licences: VoxConverse CC BY 4.0, AMI CC BY 4.0, FLEURS CC BY 4.0. Audio is not committed; the manifest
pins where to get it.

## Rerun the whole benchmark

```
untracked/epics/speaker-accuracy/run_all.sh
```

Baseline (both app engines) → diarization variants → ASR engines, each heavy run alone under
`nice -n 19 lockf /tmp/beseda-speaker-accuracy.lock`. First run downloads ~6 GB of models; hours on a busy Mac.

| part | measured (2026-09-26) | not measured yet |
|---|---|---|
| `baseline/` | Parakeet v3, GigaAM v3, raw diarizer timeline | — |
| `diarization/` | echo gate, diarizer timeline, both, FluidAudio 0.17.4 t=0.5 | Sortformer, LS-EEND ×2, t=0.6/0.7/0.8, embedding min 0.3 s, known speaker count |
| `asr/` | — (baseline engines only) | all 5 engines |

## Rerun the eval set alone

```
uv run score.py        # fetch + build if data/audio/ is missing, then score the dir set in `main(...)` at the bottom
uv run make_eval.py    # force a rebuild (first run downloads ~430 MB, takes a few minutes)
uv run sanity_check.py # reference and one-speaker sanity numbers
```

To score an engine, write its hypothesis dir (e.g. `hyp/<engine>/`, gitignored) and change the argument of
`main(...)` at the bottom of `score.py` to that path, relative to this folder.

## Hypothesis format

One dir, two files per recording id (the ids are the `data/refs/*.json` stems; a missing file scores as
an empty hypothesis):

`<id>.rttm` — standard RTTM, one line per speaker turn, used for DER:

```
SPEAKER <id> 1 <start seconds> <duration seconds> <NA> <NA> <speaker label> <NA> <NA>
```

`<id>.json` — UTF-8 JSON, used for WER/CER, me/them and speed:

```json
{
  "segments": [
    {"start": 1.25, "end": 3.9, "speaker": "S1", "channel": "system", "text": "привет всем"},
    {"start": 4.1, "end": 5.0, "speaker": "me", "channel": "mic", "text": "да"}
  ],
  "processing_seconds": 12.7
}
```

- `start`, `end`: seconds from the start of the recording (both channels share one clock).
- `speaker`: any label; DER maps labels to the reference optimally. For real recordings put every segment
  on `"channel": "system"`.
- `channel`: `"system"` or `"mic"` — the channel the engine assigned the speech to (Beseda's "them"/"me").
- `text`: the transcript of the segment, raw; the scorer normalizes it. `""` if the engine only diarizes.
- `processing_seconds`: wall-clock seconds the engine took for this recording (both channels), or `null`.
  The RTTM and the segments should describe the same turns.

The reference in `data/refs/` is in exactly this format (plus `duration` and `sources`), so it is a
valid hypothesis itself.

## Metrics

| column | how |
|---|---|
| `der` | pyannote.metrics DER, collar 0.25 s, overlap scored, over the whole recording, all speakers incl. `me` |
| `der_no_overlap` | same, overlapping reference speech excluded |
| `speaker_count_error` | mean over files of \|hypothesis speakers − reference speakers\| |
| `wer`, `cer` | jiwer, corpus-level over synthetic calls, `system` channel only: text of segments in start order; normalized lowercase, ё→е, punctuation stripped |
| `me_them_error` | share of reference speech time (both channels) that the hypothesis has only on the other channel |
| `bleed_duplicate_word_rate` | words of hypothesis `mic` segments said while the reference "me" is silent (echo transcribed twice), divided by reference `system` words; a segment's words count in proportion to its time outside "me" |
| `x_realtime` | audio seconds / `processing_seconds`, over files that report it (higher is faster) |

Groups: `real (VoxConverse+AMI)`, `synthetic calls (FLEURS)`, `all`. Per-file DER/WER are in the JSON.

## Sanity numbers

| hypothesis | DER all | DER real | DER synthetic | WER | me/them |
|---|---|---|---|---|---|
| reference itself | 0.000 | 0.000 | 0.000 | 0.000 | 0.000 |
| one speaker for everything, all on `system` | 0.499 | 0.461 | 0.671 | 0.343 | 0.266 |

Full tables: [results/refs.md](results/refs.md), [results/one_speaker.md](results/one_speaker.md). The
one-speaker WER is not 0 because "me"'s words land on the system channel.
