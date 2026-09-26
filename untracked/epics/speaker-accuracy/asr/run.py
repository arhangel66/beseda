"""Transcribe the system channel of the synthetic calls with local ASR alternatives, score WER/CER by language."""

import json
import subprocess
import sys
import tempfile
import time
from collections.abc import Callable
from pathlib import Path

import gigaam
import mlx.core as mx
import mlx_whisper
import numpy as np
import soundfile
import torch
from mlx_whisper.audio import N_SAMPLES, log_mel_spectrogram, pad_or_trim
from mlx_whisper.decoding import detect_language
from mlx_whisper.load_models import load_model
from parakeet_mlx import from_pretrained
from silero_vad import get_speech_timestamps, load_silero_vad

sys.path.insert(0, str(Path(__file__).parent.parent))
import score  # noqa: E402

RATE = 16000
VAD = load_silero_vad()
HYP = score.ROOT / "hyp"
WHISPER_TURBO = "mlx-community/whisper-large-v3-turbo"
PARAKEET_MLX = "mlx-community/parakeet-tdt-0.6b-v3"
# Beseda's current engines, from ../baseline/README.md (WER ru, CER ru, WER mixed, CER mixed)
BASELINE = {"Parakeet v3 (app)": (0.128, 0.077, 0.389, 0.327), "GigaAM v3 RNNT (app)": (0.100, 0.063, 0.448, 0.262)}

Segment = dict
Transcriber = Callable[[np.ndarray], list[Segment]]


def system_segment(start: float, end: float, text: str) -> Segment:
    return {"start": round(start, 2), "end": round(end, 2), "speaker": "them", "channel": "system", "text": text.strip()}


def speech_chunks(samples: np.ndarray) -> list[tuple[int, int]]:
    # silero VAD spans, capped at 20 s so GigaAM's 25 s limit and one-language-per-chunk both hold
    spans = get_speech_timestamps(torch.from_numpy(samples), VAD, max_speech_duration_s=20,
                                  min_silence_duration_ms=300, speech_pad_ms=100)
    return [(span["start"], span["end"]) for span in spans]


def write_wav(samples: np.ndarray) -> str:
    path = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
    soundfile.write(path, samples, RATE)
    return path


def per_chunk(transcribe_chunk: Callable[[np.ndarray], str]) -> Transcriber:
    def transcribe(samples: np.ndarray) -> list[Segment]:
        return [system_segment(start / RATE, end / RATE, transcribe_chunk(samples[start:end]))
                for start, end in speech_chunks(samples)]
    return transcribe


def whisper_turbo_whole_file() -> Transcriber:
    # one pass over the file; Whisper detects the language once, on the first 30 s
    def transcribe(samples: np.ndarray) -> list[Segment]:
        result = mlx_whisper.transcribe(samples, path_or_hf_repo=WHISPER_TURBO, condition_on_previous_text=False)
        return [system_segment(s["start"], s["end"], s["text"]) for s in result["segments"]]
    return transcribe


def whisper_turbo_text(samples: np.ndarray, language: str | None = None) -> str:
    return mlx_whisper.transcribe(samples, path_or_hf_repo=WHISPER_TURBO, language=language,
                                  condition_on_previous_text=False)["text"]


def whisper_language_ru_or_en() -> Callable[[np.ndarray], str]:
    # Whisper turbo's language ID on one chunk, restricted to the two languages of the set
    model = load_model(WHISPER_TURBO, dtype=mx.float16)
    return lambda samples: detect_ru_or_en(model, samples)


def detect_ru_or_en(model: mlx_whisper.whisper.Whisper, samples: np.ndarray) -> str:
    mel = log_mel_spectrogram(pad_or_trim(samples, N_SAMPLES), n_mels=model.dims.n_mels)
    _, probabilities = detect_language(model, mel.astype(mx.float16))
    return "ru" if probabilities["ru"] >= probabilities["en"] else "en"


def gigaam_ctc_text() -> Callable[[np.ndarray], str]:
    model = gigaam.load_model("v3_e2e_ctc", device="cpu")
    return lambda samples: model.transcribe(write_wav(samples)).text


def parakeet_mlx_text() -> Callable[[np.ndarray], str]:
    model = from_pretrained(PARAKEET_MLX)
    return lambda samples: model.transcribe(write_wav(samples)).text


def gigaam_ctc() -> Transcriber:
    return per_chunk(gigaam_ctc_text())


def gigaam_ctc_loudnorm() -> Transcriber:
    # front-end trick: EBU R128 loudness normalisation of the call audio before the same GigaAM CTC
    transcribe = gigaam_ctc()

    def normalized(samples: np.ndarray) -> list[Segment]:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", write_wav(samples), "-af", "loudnorm=I=-16:TP=-1.5",
                              "-ar", str(RATE), "-ac", "1", "-f", "f32le", "-"], capture_output=True, check=True).stdout
        return transcribe(np.frombuffer(raw, dtype=np.float32))
    return normalized


def whisper_turbo_per_chunk() -> Transcriber:
    # Whisper detects the language again on every VAD chunk
    return per_chunk(whisper_turbo_text)


def routed_gigaam_ru_parakeet_en() -> Transcriber:
    # Whisper language ID per chunk, then the specialist: GigaAM for Russian, Parakeet for English
    language, gigaam_text, parakeet_text = whisper_language_ru_or_en(), gigaam_ctc_text(), parakeet_mlx_text()
    return per_chunk(lambda samples: gigaam_text(samples) if language(samples) == "ru"
                     else parakeet_text(samples))


ENGINES: dict[str, Callable[[], Transcriber]] = {
    "asr-whisper-turbo": whisper_turbo_whole_file,
    "asr-whisper-turbo-per-chunk": whisper_turbo_per_chunk,
    "asr-gigaam-ctc": gigaam_ctc,
    "asr-gigaam-ctc-loudnorm": gigaam_ctc_loudnorm,
    "asr-route-gigaam-ru-parakeet-en": routed_gigaam_ru_parakeet_en,
}


def call_ids() -> list[str]:
    return sorted(path.stem for path in score.REFS.glob("call_*.json"))


def transcribe_calls(name: str) -> None:
    # write hyp/<name>/<call>.json with system-channel segments; processing_seconds covers this channel only
    transcribe = ENGINES[name]()
    transcribe(np.zeros(RATE, dtype=np.float32) + 1e-4)  # warm-up: model loads are not timed
    hyp_dir = HYP / name
    hyp_dir.mkdir(parents=True, exist_ok=True)
    for call_id in call_ids():
        samples, _ = soundfile.read(score.AUDIO / f"{call_id}.system.wav", dtype="float32")
        started = time.perf_counter()
        segments = transcribe(samples)
        elapsed = time.perf_counter() - started
        (hyp_dir / f"{call_id}.json").write_text(json.dumps(
            {"segments": segments, "processing_seconds": round(elapsed, 3)}, ensure_ascii=False, indent=1))
        print(name, call_id, f"{elapsed:.1f}s", flush=True)


def score_table(names: list[str]) -> str:
    groups = {"ru": [c for c in call_ids() if c.startswith("call_ru_")],
              "mixed": [c for c in call_ids() if not c.startswith("call_ru_")]}
    lines = ["| alternative | WER ru | CER ru | WER mixed | CER mixed | Δ WER ru vs GigaAM app | "
             "Δ WER mixed vs Parakeet app | × realtime (system channel) |", "|---" * 8 + "|"]
    for label, (wer_ru, cer_ru, wer_mixed, cer_mixed) in BASELINE.items():
        lines.append(f"| {label} | {wer_ru:.3f} | {cer_ru:.3f} | {wer_mixed:.3f} | {cer_mixed:.3f} | | | — |")
    for name in names:
        if not (HYP / name).exists():
            lines.append(f"| {name} | not measured | | | | | | |")
            continue
        ru, mixed = (score.score_group(ids, HYP / name)[0] for ids in groups.values())
        speed = score.score_group(call_ids(), HYP / name)[0]["x_realtime"]
        lines.append(f"| {name} | {ru['wer']:.3f} | {ru['cer']:.3f} | {mixed['wer']:.3f} | {mixed['cer']:.3f} "
                     f"| {ru['wer'] - BASELINE['GigaAM v3 RNNT (app)'][0]:+.3f} "
                     f"| {mixed['wer'] - BASELINE['Parakeet v3 (app)'][2]:+.3f} | {speed:.1f} |")
    return "\n".join(lines) + "\n"


def main(names: list[str], transcribe: bool) -> None:
    if not score.AUDIO.exists():
        score.build()
    if transcribe:
        for name in names:
            transcribe_calls(name)
    table = score_table(list(ENGINES))
    (Path(__file__).parent / "results.md").write_text(table)
    print(table)


if __name__ == "__main__":
    main(list(ENGINES), transcribe=True)
