"""BESEDA-131: score nemotron_switch.sh — the old offline t0.70 diarizer and Nemotron-3, each with and without the
app's 6 s short-reply rule, on the 15 truth calls (shown `them` speakers after the per-sentence assignment) and the
real benchmark (DER, speaker-count error, glued), plus time and peak memory per file. Prints markdown."""

from other_diarizers import BENCHMARK, CALLS, DAILIES, OTHER, audio_seconds, processing_seconds, raw_timeline, row

VARIANTS = ["offline-t0.7", "nemotron3-offline"]


def main() -> None:
    rows = [row(f"{variant}{' + 6 s' if merge else ''}", lambda f, v=variant: raw_timeline(v, f), variant, merge)
            for variant in VARIANTS for merge in (False, True)]

    print("| approach | 1:1 correct (of 10) | dailies correct (of 5) | total \\|Δ\\| calls | benchmark DER / count error / glued | bench shown/real | × realtime |")
    print("|---|---|---|---|---|---|---|")
    for r in rows:
        delta = sum(abs(r["counts"][c] - DAILIES.get(c, 1)) for c in CALLS)
        print(f"| {r['name']} | {r['one_on_one']} | {r['dailies']} | {delta} | {r['der']:.3f} / {r['count_error']:.2f} / {r['glued']} | {r['bench']} | {r['speed']:.0f} |")
    print()

    print("| call | real | " + " | ".join(r["name"] for r in rows) + " |")
    print("|---|---|" + "---|" * len(rows))
    for call in CALLS:
        print(f"| {call} | {DAILIES.get(call, 1)} | " + " | ".join(str(r["counts"][call]) for r in rows) + " |")
    print()

    memory = {}
    for line in (OTHER / "memory.log").read_text().splitlines():
        variant, file_id, gigabytes, _ = line.split()
        memory[variant, file_id] = float(gigabytes)
    print("| file | min | " + " | ".join(VARIANTS) + " |")
    print("|---|---|" + "---|" * len(VARIANTS))
    for f in CALLS + BENCHMARK:
        cells = [f"{processing_seconds(v, f):.1f} s / {memory[v, f]:.2f} GB" for v in VARIANTS]
        print(f"| {f} | {audio_seconds(f) / 60:.0f} | " + " | ".join(cells) + " |")


if __name__ == "__main__":
    main()
