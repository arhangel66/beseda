"""Build full hypotheses for each diarization alternative and score them into ../results/diar-*.

Inputs: hyp/baseline-* (baseline/run.sh) and diarization/hyp-system/<variant>/ (the Swift Diarize run).
"""

import json
import sys
import time
from pathlib import Path

import numpy as np
import soundfile

sys.path.insert(0, str(Path(__file__).parent.parent))
sys.path.insert(0, str(Path(__file__).parent.parent / "baseline"))
import score  # noqa: E402
from score_baseline import system_only_der  # noqa: E402

HERE = Path(__file__).parent
BASELINE = score.ROOT / "hyp"
FRAME = 320  # 20 ms at 16 kHz
ECHO_MARGIN = 4.0  # mic energy must beat the predicted echo by 6 dB to count as "me"


def echo_path(mic: np.ndarray, system: np.ndarray) -> tuple[int, float]:
    # delay (samples, 0..500 ms) and gain of system leaking into mic, by FFT cross-correlation + least squares
    size = 1 << int(np.ceil(np.log2(len(mic) + len(system))))
    correlation = np.fft.irfft(np.fft.rfft(mic, size) * np.conj(np.fft.rfft(system, size)), size)[:8000]
    lag = int(np.argmax(np.abs(correlation)))
    shifted = np.concatenate([np.zeros(lag), system[: len(mic) - lag]])
    return lag, float(mic @ shifted / (shifted @ shifted + 1e-12))


def own_speech_frames(mic: np.ndarray, system: np.ndarray) -> np.ndarray:
    # 20 ms frames where the mic carries more than the echo of the system channel predicts
    # ponytail: one delay + one gain fits our synthetic echo exactly; a real room smears it over
    # ~100 ms, where this needs a spread (max over nearby lags) or a real AEC (WebRTC AEC3 / Apple VPIO).
    lag, gain = echo_path(mic, system)
    shifted = np.concatenate([np.zeros(lag), system[: len(mic) - lag]])
    frames = len(mic) // FRAME
    mic_energy = (mic[: frames * FRAME].reshape(frames, FRAME) ** 2).mean(axis=1)
    echo_energy = gain**2 * (shifted[: frames * FRAME].reshape(frames, FRAME) ** 2).mean(axis=1)
    noise_floor = np.percentile(mic_energy, 10)
    own = (mic_energy > ECHO_MARGIN * echo_energy) & (mic_energy > 10 * noise_floor)
    return np.convolve(own, np.ones(11), mode="same") > 0  # bridge 200 ms gaps inside words


def echo_gated_mic(file_id: str, mic_segments: list[dict]) -> tuple[list[dict], float]:
    # mic segments cut down to their runs of own speech (≥ 0.3 s), echo-only ones dropped; returns them and
    # the seconds it took. ASR often glues "me" and echo into one sentence, so a keep/drop per segment fails.
    started = time.perf_counter()
    mic, _ = soundfile.read(score.AUDIO / f"{file_id}.mic.wav")
    system, _ = soundfile.read(score.AUDIO / f"{file_id}.system.wav")
    own = own_speech_frames(mic, system)
    kept = []
    for segment in mic_segments:
        first, last = int(segment["start"] * 50), min(int(np.ceil(segment["end"] * 50)), len(own))
        edges = np.flatnonzero(np.diff(np.concatenate([[0], own[first:last].astype(int), [0]])))
        runs = [(first + a, first + b) for a, b in zip(edges[::2], edges[1::2]) if b - a >= 15]
        if runs:
            # no word times here: the whole text goes on the longest run
            longest = max(runs, key=lambda run: run[1] - run[0])
            kept += [segment | {"start": a / 50, "end": b / 50, "text": segment["text"] if (a, b) == longest else ""}
                     for a, b in runs]
    return kept, time.perf_counter() - started


def with_text_on_timeline(timeline: list[dict], turns: list[dict]) -> list[dict]:
    # the diarizer's own segments as the turns; each ASR turn's text goes to the segment it overlaps most
    segments = [{"start": t["start"], "end": t["end"], "speaker": t["speaker"], "channel": "system", "text": ""}
                for t in timeline]
    for turn in turns:
        overlaps = [min(s["end"], turn["end"]) - max(s["start"], turn["start"]) for s in segments]
        if segments and max(overlaps) > 0:
            target = segments[int(np.argmax(overlaps))]
            target["text"] = f"{target['text']} {turn['text']}".strip()
        elif segments:  # no diarizer speech under the words: keep them, as the nearest segment's speaker
            nearest = min(segments, key=lambda s: min(abs(s["start"] - turn["end"]), abs(turn["start"] - s["end"])))
            segments.append(turn | {"speaker": nearest["speaker"]})
        else:
            segments.append(turn)
    return sorted(segments, key=lambda s: s["start"])


def write_hypothesis(name: str, file_id: str, segments: list[dict], processing_seconds: float) -> None:
    directory = HERE / "hyp" / name
    directory.mkdir(parents=True, exist_ok=True)
    (directory / f"{file_id}.json").write_text(json.dumps({"segments": segments, "processing_seconds": processing_seconds}))
    (directory / f"{file_id}.rttm").write_text("".join(
        f"SPEAKER {file_id} 1 {s['start']:.3f} {s['end'] - s['start']:.3f} <NA> <NA> {s['speaker']} <NA> <NA>\n"
        for s in segments if s["end"] > s["start"]))


def baseline(engine: str, file_id: str) -> dict:
    return json.loads((BASELINE / f"baseline-{engine}" / f"{file_id}.json").read_text())


def build_hypotheses(file_ids: list[str], variants: list[str]) -> list[str]:
    # every alternative as a full hypothesis dir; returns their names
    names = []
    for file_id in file_ids:
        has_mic = (score.AUDIO / f"{file_id}.mic.wav").exists()
        parakeet = baseline("parakeet", file_id)
        mic = [s for s in parakeet["segments"] if s["channel"] == "mic"]
        theirs = [s for s in parakeet["segments"] if s["channel"] == "system"]
        gated_mic, gate_seconds = echo_gated_mic(file_id, mic) if has_mic else ([], 0.0)
        raw_system = [s for s in baseline("diarizer-raw", file_id)["segments"] if s["channel"] == "system"]

        # the app pipeline as is, only the mic echo gated (time: the gate alone)
        write_hypothesis("diar-echo-gate-parakeet", file_id, gated_mic + theirs, gate_seconds)
        # the app pipeline, turns = the diarizer's timeline instead of per-word speakers (no timing: no new work)
        write_hypothesis("diar-timeline-parakeet", file_id, mic + with_text_on_timeline(raw_system, theirs), None)
        write_hypothesis("diar-timeline-echo-gate-parakeet", file_id,
                         gated_mic + with_text_on_timeline(raw_system, theirs), gate_seconds)
        for variant in variants:
            system = json.loads((HERE / "hyp-system" / variant / f"{file_id}.json").read_text())
            timeline = [s | {"channel": "system", "text": ""} for s in system["segments"]]
            # diarizer alone (+ gated mic as "me"), time: the diarizer alone
            write_hypothesis(f"diar-{variant}", file_id, gated_mic + with_text_on_timeline(timeline, theirs),
                             system["processing_seconds"])
    names += ["diar-echo-gate-parakeet", "diar-timeline-parakeet", "diar-timeline-echo-gate-parakeet"]
    return names + [f"diar-{v}" for v in variants]


def main(variants: list[str]) -> None:
    file_ids = sorted(path.stem for path in score.REFS.glob("*.json"))
    call_ids = [f for f in file_ids if f.startswith("call_")]
    names = build_hypotheses(file_ids, variants)
    rows = ["| hypothesis | DER real | DER real no overlap | DER synthetic both channels | DER synthetic system only "
            "| speaker-count error real / synthetic | me/them | bleed | x realtime |", "|---" * 9 + "|"]
    for name in ["baseline-parakeet", "baseline-diarizer-raw"] + names:
        hyp_dir = BASELINE / name if name.startswith("baseline") else HERE / "hyp" / name
        summary = json.loads((score.ROOT / "results" / f"{name}.json").read_text())["summary"] \
            if name.startswith("baseline") else score.main(str(hyp_dir.relative_to(score.ROOT)))
        real, synthetic = summary["real (VoxConverse+AMI)"], summary["synthetic calls (FLEURS)"]
        speed = summary["all"]["x_realtime"]
        rows.append(
            f"| {name} | {real['der']:.3f} | {real['der_no_overlap']:.3f} | {synthetic['der']:.3f} "
            f"| {system_only_der(call_ids, hyp_dir):.3f} | {real['speaker_count_error']:.2f} / "
            f"{synthetic['speaker_count_error']:.2f} | {synthetic['me_them_error']:.3f} "
            f"| {synthetic['bleed_duplicate_word_rate']:.3f} | {'-' if speed is None else f'{speed:.0f}'} |")
    table = "\n".join(rows) + "\n"
    (HERE / "results.md").write_text(table)
    print(table)


if __name__ == "__main__":
    main(sorted(p.name for p in (HERE / "hyp-system").glob("*") if len(list(p.glob("*.json"))) == 13))
