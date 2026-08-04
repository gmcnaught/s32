#!/usr/bin/env python3
"""Diff two full VRAM word dumps (one word per line, hex, 0x300000 base).

Both MAME's dump_video_state() (verif/mame/sonic_gameplay_raw.lua,
S32_DUMP_STATE_AT) and tb_core_romboot's +DUMPSPRAT sim_vram.hex use this
exact format, so the files compare directly with no address translation.
"""

from __future__ import annotations

import argparse
from pathlib import Path

BASE = 0x300000


def load(path: Path) -> list[int]:
    return [int(line.strip(), 16) for line in
            path.read_text(encoding="ascii").splitlines() if line.strip()]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("mame", type=Path)
    ap.add_argument("rtl", type=Path)
    ap.add_argument("--lo", type=lambda s: int(s, 0), default=BASE,
                    help="lowest address to compare (default whole VRAM)")
    ap.add_argument("--hi", type=lambda s: int(s, 0), default=BASE + 0x1FFFF,
                    help="highest address to compare (inclusive)")
    ap.add_argument("--limit", type=int, default=40)
    args = ap.parse_args()

    mame = load(args.mame)
    rtl = load(args.rtl)
    if len(mame) != len(rtl):
        print(f"WARNING: length mismatch mame={len(mame)} rtl={len(rtl)}")
    n = min(len(mame), len(rtl))

    lo_word = max(0, (args.lo - BASE) // 2)
    hi_word = min(n - 1, (args.hi - BASE) // 2)

    mismatches = [i for i in range(lo_word, hi_word + 1) if mame[i] != rtl[i]]
    total = hi_word - lo_word + 1
    print(f"compared words {lo_word}..{hi_word} "
          f"(addr {BASE + lo_word*2:06x}..{BASE + hi_word*2:06x}): "
          f"{len(mismatches)} / {total} differ")

    if mismatches:
        # collapse into contiguous runs for a readable summary
        runs = []
        start = prev = mismatches[0]
        for i in mismatches[1:]:
            if i == prev + 1:
                prev = i
                continue
            runs.append((start, prev))
            start = prev = i
        runs.append((start, prev))
        print(f"{len(runs)} contiguous mismatching run(s):")
        for s, e in runs[: args.limit]:
            a0, a1 = BASE + s * 2, BASE + e * 2
            print(f"  a={a0:06x}..{a1:06x}  ({e - s + 1} words)  "
                  f"MAME[{s}]={mame[s]:04x} RTL[{s}]={rtl[s]:04x}")
        if len(runs) > args.limit:
            print(f"  ... {len(runs) - args.limit} more runs")

    return 0 if not mismatches else 1


if __name__ == "__main__":
    raise SystemExit(main())
