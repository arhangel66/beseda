"""BESEDA-115: stronger speaker embeddings for the FluidAudio offline-t0.7 segments (hyp/other/offline-t0.7/) of every
<id>.system.wav in $AUDIO_DIR, via sherpa-onnx (ONNX, CPU). Writes hyp/other/emb-<model>/<id>.json:
{"segments": [{"start", "end", "embedding"}], "processing_seconds"}. other_diarizers.py clusters them."""

import json
import os
import time
from pathlib import Path

import sherpa_onnx
import soundfile

ROOT = Path(__file__).parent
OTHER = ROOT / "hyp" / "other"
MODELS = {
    "resnet34": "wespeaker_en_voxceleb_resnet34_LM.onnx",
    "campplus": "3dspeaker_speech_campplus_sv_en_voxceleb_16k.onnx",
    "eres2netv2": "3dspeaker_speech_eres2netv2_sv_zh-cn_16k-common.onnx",
    "resnet293": "wespeaker_en_voxceleb_resnet293_LM.onnx",
}
MIN_SECONDS = 0.5


def embed_file(extractor: sherpa_onnx.SpeakerEmbeddingExtractor, wav: Path, segments: list[dict]) -> list[dict]:
    # one embedding per diarizer segment; segments under MIN_SECONDS get none
    samples, rate = soundfile.read(wav, dtype="float32")
    embedded = []
    for segment in segments:
        vector = []
        if segment["end"] - segment["start"] >= MIN_SECONDS:
            stream = extractor.create_stream()
            stream.accept_waveform(rate, samples[int(segment["start"] * rate):int(segment["end"] * rate)])
            stream.input_finished()
            vector = extractor.compute(stream)
        embedded.append({"start": segment["start"], "end": segment["end"], "embedding": list(vector)})
    return embedded


def main(audio_dir: Path) -> None:
    for name, model in MODELS.items():
        config = sherpa_onnx.SpeakerEmbeddingExtractorConfig(model=str(OTHER.parent / "models" / model), num_threads=4)
        extractor = sherpa_onnx.SpeakerEmbeddingExtractor(config)
        (OTHER / f"emb-{name}").mkdir(parents=True, exist_ok=True)
        for wav in sorted(audio_dir.glob("*.system.wav")):
            file_id = wav.name.removesuffix(".system.wav")
            out = OTHER / f"emb-{name}" / f"{file_id}.json"
            if out.exists():
                continue
            segments = json.loads((OTHER / "offline-t0.7" / f"{file_id}.json").read_text())["segments"]
            started = time.monotonic()
            embedded = embed_file(extractor, wav, segments)
            out.write_text(json.dumps({"segments": embedded, "processing_seconds": time.monotonic() - started}))
            print(f"{name} {file_id}: {time.monotonic() - started:.1f} s")


if __name__ == "__main__":
    main(Path(os.environ["AUDIO_DIR"]))
