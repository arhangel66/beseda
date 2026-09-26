"""Fetch the pinned sources and build the eval set: data/audio/*.wav (gitignored) and data/refs/* (committed)."""

import csv
import hashlib
import io
import itertools
import json
import re
import subprocess
import tarfile
import urllib.request
import zipfile
from pathlib import Path

import numpy as np
import soundfile

ROOT = Path(__file__).parent
DATA = ROOT / "data"
CACHE = DATA / "cache"
AUDIO = DATA / "audio"
REFS = DATA / "refs"
BUILT_HASHES = DATA / "built.sha256"
RATE = 16000
FRAME = RATE // 50  # 20 ms


class HttpRangeFile:
    # read-only seekable file over HTTP Range requests, so zipfile pulls one member out of a 2 GB zip
    def __init__(self, url: str):
        self.url = url
        self.position = 0
        head = urllib.request.urlopen(urllib.request.Request(url, method="HEAD"))
        self.size = int(head.headers["Content-Length"])

    def seekable(self) -> bool:
        return True

    def tell(self) -> int:
        return self.position

    def seek(self, offset: int, whence: int = 0) -> int:
        self.position = {0: offset, 1: self.position + offset, 2: self.size + offset}[whence]
        return self.position

    def read(self, size: int = -1) -> bytes:
        if size < 0:
            size = self.size - self.position
        if size == 0:
            return b""
        request = urllib.request.Request(self.url, headers={"Range": f"bytes={self.position}-{self.position + size - 1}"})
        chunk = urllib.request.urlopen(request).read()
        self.position += len(chunk)
        return chunk


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for block in iter(lambda: file.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def download(url: str, path: Path, sha256: str | None = None) -> Path:
    # download once into the cache, then check the pinned hash on every run
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        partial = path.with_suffix(path.suffix + ".part")
        with urllib.request.urlopen(url) as response, partial.open("wb") as file:
            while block := response.read(1 << 20):
                file.write(block)
        partial.rename(path)
    if sha256 and sha256_of(path) != sha256:
        raise ValueError(f"{path} sha256 differs from the manifest")
    return path


def fetch_real_source_audio(item: dict, sources: dict) -> Path:
    path = CACHE / f"{item['source']}_{item['source_id']}.wav"
    if item["source"] == "ami":
        return download(sources["ami"]["audio"].format(id=item["source_id"]), path, item["source_sha256"])
    if not path.exists():
        archive = zipfile.ZipFile(HttpRangeFile(sources["voxconverse"]["audio_zip"]))
        path.write_bytes(archive.read(f"audio/{item['source_id']}.wav"))
    if sha256_of(path) != item["source_sha256"]:
        raise ValueError(f"{path} sha256 differs from the manifest")
    return path


def read_rttm(text: str) -> list[tuple[float, float, str]]:
    turns = []
    for line in text.splitlines():
        fields = line.split()
        if fields and fields[0] == "SPEAKER":
            start = float(fields[3])
            turns.append((start, start + float(fields[4]), fields[7]))
    return turns


def write_reference(file_id: str, duration: float, segments: list[dict], sources: list[str]) -> None:
    segments = sorted(segments, key=lambda segment: (segment["start"], segment["speaker"]))
    rttm = "".join(
        f"SPEAKER {file_id} 1 {s['start']:.3f} {s['end'] - s['start']:.3f} <NA> <NA> {s['speaker']} <NA> <NA>\n"
        for s in segments
    )
    (REFS / f"{file_id}.rttm").write_text(rttm)
    reference = {"duration": duration, "sources": sources, "segments": segments, "processing_seconds": None}
    (REFS / f"{file_id}.json").write_text(json.dumps(reference, ensure_ascii=False, indent=1) + "\n")


def build_real(item: dict, sources: dict) -> list[Path]:
    # crop a VoxConverse/AMI recording and its reference RTTM to the manifest window
    source_audio = fetch_real_source_audio(item, sources)
    rttm_url = sources[item["source"]]["rttm"].format(id=item["source_id"])
    rttm = download(rttm_url, CACHE / f"{item['source']}_{item['source_id']}.rttm").read_text()
    start, end = item["start"], item["start"] + item["duration"]
    samples, rate = soundfile.read(source_audio, dtype="int16", start=start * RATE, stop=end * RATE)
    assert rate == RATE and samples.ndim == 1, f"{source_audio} is not 16 kHz mono"
    audio_path = AUDIO / f"{item['id']}.system.wav"
    soundfile.write(audio_path, samples, RATE, subtype="PCM_16")
    segments = [
        {"start": round(max(s, start) - start, 3), "end": round(min(e, end) - start, 3),
         "speaker": speaker, "channel": "system", "text": ""}
        for s, e, speaker in read_rttm(rttm) if e > start and s < end
    ]
    write_reference(item["id"], item["duration"], segments, [rttm_url])
    return [audio_path]


def load_fleurs(lang: str, fleurs: dict) -> dict[str, dict]:
    # FLEURS dev utterances of one language: file name -> {text, raw, audio}
    tsv = download(fleurs["tsv"].format(lang=lang), CACHE / f"{lang}.dev.tsv").read_text()
    rows = {row[1]: {"raw": row[2], "text": row[3]} for row in csv.reader(tsv.splitlines(), delimiter="\t", quoting=csv.QUOTE_NONE)}
    archive_path = download(fleurs["audio"].format(lang=lang), CACHE / f"{lang}.dev.tar.gz", fleurs["sha256"][f"{lang}/dev.tar.gz"])
    with tarfile.open(archive_path) as archive:
        for member in archive:
            name = Path(member.name).name
            if name in rows:
                samples, rate = soundfile.read(io.BytesIO(archive.extractfile(member).read()), dtype="float32")
                assert rate == RATE
                rows[name]["audio"] = samples
    return {name: row for name, row in sorted(rows.items()) if "audio" in row}


def split_at_pauses(samples: np.ndarray) -> list[tuple[int, int]]:
    # sample bounds of the speech runs of an utterance separated by pauses >= 0.25 s, leading/trailing silence trimmed
    frames = samples[: len(samples) // FRAME * FRAME].reshape(-1, FRAME)
    energy_db = 10 * np.log10((frames**2).mean(axis=1) + 1e-10)
    voiced = energy_db > energy_db.max() - 35
    runs, start, silent = [], None, 0
    for index, is_voiced in enumerate(voiced):
        if is_voiced:
            if start is None:
                start = index
            silent, last_voiced = 0, index
        elif start is not None:
            silent += 1
            if silent == 13:
                runs.append((start, last_voiced + 1))
                start = None
    if start is not None:
        runs.append((start, last_voiced + 1))
    return [(a * FRAME, b * FRAME) for a, b in runs if b - a >= 10]


def split_utterance_into_turns(utterance: dict) -> list[tuple[np.ndarray, str]] | None:
    # FLEURS has no speaker ids, so one recording is one voice: cut it into turns at the pauses that best fit
    # its clause punctuation by speech rate; recordings with no plausible fit are not used
    runs = split_at_pauses(utterance["audio"])
    clauses = [clause for clause in re.split(r"[,;:]", utterance["raw"]) if clause.strip()]
    counts = [len(clause.split()) for clause in clauses]
    words = utterance["text"].split()
    if len(clauses) < 2 or len(runs) < len(clauses) or sum(counts) != len(words):
        return None
    best, best_spread = None, None
    # ponytail: brute force over pause choices, fine for FLEURS sentences (a handful of pauses each)
    for cuts in itertools.combinations(range(1, len(runs)), len(clauses) - 1):
        bounds = list(zip((0, *cuts), (*cuts, len(runs))))
        rates = [(runs[b - 1][1] - runs[a][0]) / RATE / count for (a, b), count in zip(bounds, counts)]
        spread = max(rates) / min(rates)
        if all(0.25 <= rate <= 0.9 for rate in rates) and (best_spread is None or spread < best_spread):
            best, best_spread = bounds, spread
    if best is None or best_spread > 1.6:
        return None
    turns, offset = [], 0
    for (a, b), count in zip(best, counts):
        turns.append((utterance["audio"][runs[a][0]: runs[b - 1][1]], " ".join(words[offset: offset + count])))
        offset += count
    return turns


def degrade_like_a_call(samples: np.ndarray) -> np.ndarray:
    # band-limit and push through Opus 20 kbps and back, like the remote side of a VoIP call
    encode = ["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "pipe:",
              "-af", "highpass=f=100,lowpass=f=7000", "-c:a", "libopus", "-b:a", "20k",
              "-flags", "+bitexact", "-fflags", "+bitexact", "-f", "ogg", "pipe:"]
    opus = subprocess.run(encode, input=samples.astype("<f4").tobytes(), capture_output=True, check=True).stdout
    decode = ["ffmpeg", "-v", "error", "-i", "pipe:", "-ar", str(RATE), "-ac", "1", "-f", "f32le", "pipe:"]
    decoded = np.frombuffer(subprocess.run(decode, input=opus, capture_output=True, check=True).stdout, dtype="<f4")
    return np.pad(decoded, (0, max(0, len(samples) - len(decoded))))[: len(samples)]


def build_call(call: dict, fleurs: dict[str, dict[str, dict]], used: set[str], rng: np.random.Generator,
               synthetic: dict) -> list[Path]:
    # mix one two-channel synthetic call: remote speakers on `system`, "me" plus echo on `mic`
    speakers = [(f"spk{index + 1}", lang, "system") for index, lang in enumerate(call["remote"])]
    speakers.append(("me", call["me"], "mic"))
    turns_by_speaker, sources = {}, []
    for speaker, lang, _ in speakers:
        candidates = [name for name in fleurs[lang] if name not in used]
        for name in rng.permutation(candidates):
            turns = split_utterance_into_turns(fleurs[lang][name])
            if turns:
                used.add(name)
                sources.append(f"fleurs/{lang}/dev/{name}")
                turns_by_speaker[speaker] = turns
                break
    channel_of = {speaker: channel for speaker, _, channel in speakers}

    order, previous = [], None
    while any(turns_by_speaker.values()):
        waiting = [s for s, turns in turns_by_speaker.items() if turns and s != previous] or [previous]
        previous = waiting[rng.integers(len(waiting))]
        order.append((previous, *turns_by_speaker[previous].pop(0)))

    placed, cursor, previous_start = [], 0.5, 0.0
    for speaker, samples, text in order:
        # a quarter of turn changes overlap the previous turn, the rest leave a pause
        gap = -rng.uniform(0.2, 0.8) if placed and rng.random() < 0.25 else rng.uniform(0.2, 1.0)
        start = round(max(cursor + gap, previous_start + 0.5), 2)
        samples = samples * (0.07 / (np.sqrt((samples**2).mean()) + 1e-9))  # about -23 dBFS
        placed.append((start, speaker, samples, text))
        previous_start, cursor = start, start + len(samples) / RATE
    duration = round(max(start + len(s) / RATE for start, _, s, _ in placed) + 0.5, 2)

    tracks = {"system": np.zeros(int(duration * RATE), dtype=np.float32), "mic": np.zeros(int(duration * RATE), dtype=np.float32)}
    segments = []
    for start, speaker, samples, text in placed:
        offset = int(start * RATE)
        tracks[channel_of[speaker]][offset: offset + len(samples)] += samples
        segments.append({"start": start, "end": round(start + len(samples) / RATE, 3), "speaker": speaker,
                         "channel": channel_of[speaker], "text": text})

    noise_gain = 10 ** (-50 / 20)
    system = degrade_like_a_call(tracks["system"]) + rng.normal(0, noise_gain, len(tracks["system"]))
    delay = synthetic["echo"]["delay_ms"] * RATE // 1000
    echo = np.pad(system, (delay, 0))[: len(system)] * 10 ** (synthetic["echo"]["gain_db"] / 20)
    mic = tracks["mic"] + echo + rng.normal(0, noise_gain, len(system))

    paths = []
    for channel, samples in (("system", system), ("mic", mic)):
        path = AUDIO / f"{call['id']}.{channel}.wav"
        soundfile.write(path, np.clip(samples, -1, 1), RATE, subtype="PCM_16")
        paths.append(path)
    write_reference(call["id"], duration, segments, sources)
    return paths


def build() -> None:
    # rebuild every audio file and reference, then compare the audio with the committed hashes
    manifest = json.loads((DATA / "manifest.json").read_text())
    for directory in (CACHE, AUDIO, REFS):
        directory.mkdir(parents=True, exist_ok=True)
    built = []
    for item in manifest["real"]:
        built += build_real(item, manifest["sources"])
    synthetic = manifest["synthetic"]
    fleurs = {lang: load_fleurs(lang, manifest["sources"]["fleurs"]) for lang in ("ru_ru", "en_us")}
    rng, used = np.random.default_rng(synthetic["seed"]), set()
    for call in synthetic["calls"]:
        built += build_call(call, fleurs, used, rng, synthetic)

    hashes = "".join(f"{sha256_of(path)}  {path.name}\n" for path in built)
    if BUILT_HASHES.exists() and BUILT_HASHES.read_text() != hashes:
        # ponytail: libopus/ffmpeg version changes can shift the synthetic bytes; refs stay valid, audio differs slightly
        print(f"warning: built audio differs from {BUILT_HASHES.name}; rewritten, check `git diff`")
    BUILT_HASHES.write_text(hashes)
    total = sum(json.loads(path.read_text())["duration"] for path in REFS.glob("*.json"))
    print(f"built {len(built)} audio files, {total / 60:.1f} min of recordings")


if __name__ == "__main__":
    build()
