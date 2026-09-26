# BESEDA-95: hyp/echo-gate/*.json (echo_gate_real.sh) -> the per-call table of results/echo-gate-real.md.
# hyp/echo-gate-majority/ is the same run with the rejected "word is own when most of its frames are" rule.
import json
from pathlib import Path

TRUTH_ORDER = """20260925-114649 20260925-111702 20260924-173649 20260924-173310 20260924-133358 20260924-110157
20260923-125419 20260923-101613 20260922-115609 20260922-084404
20260925-125945 20260924-130017 20260923-130021 20260922-125838 20260921-125925""".split()


def main(hyp: Path) -> None:
    print("| call | min | lag ms | echo dB | echo fit | mic floor dB | own share | own while system talks "
          "| mic words | echo repeats | echo kept before → after | own lost before → majority → after "
          "| bounds off before → after |")
    print("|" + "---|" * 13)
    for call in TRUTH_ORDER:
        report = json.loads((hyp / "echo-gate" / f"{call}.json").read_text())
        majority = json.loads((hyp / "echo-gate-majority" / f"{call}.json").read_text())["after"]
        before, after = report["before"], report["after"]
        print(f"| {call} | {report['minutes']} | {report['lagMs']} | {report['echoDb']} | {report['echoFit']} "
              f"| {report['micFloorDb']} | {report['ownShare']:.0%} | {report['ownWhileSystemActive']:.0%} "
              f"| {report['micWords']} | {report['echoWords']} | {before['echoKept']} → {after['echoKept']} "
              f"| {before['ownLost']} → {majority['ownLost']} → {after['ownLost']} "
              f"| {before['boundsOff']} / {before['keptSentences']} → {after['boundsOff']} / {after['keptSentences']} |")


if __name__ == "__main__":
    main(Path(__file__).parent / "hyp")
