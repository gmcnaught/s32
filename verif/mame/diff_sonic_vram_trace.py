#!/usr/bin/env python3
"""Diff the final VRAM content two ordered write-traces converge to.

Both MAME (verif/mame/sonic_vram_name_trace.lua) and the RTL harness
(tb_core_romboot's `+TRACELO=/+TRACEHI=` `[memtrace]` lines) log every write to
an address range in temporal order.  The address that matters is the LAST
value written before the window closes -- earlier writes in the same burst are
overwritten (this game clears, index-fills, then finally re-writes the same
VRAM page in three separate passes; only the third value is ever displayed).

This script reduces each trace to {address: final_value} and reports every
address where the two final values differ, which is the RTL ground truth for
"what should this VRAM word contain" independent of frame-timing offsets.
"""

from __future__ import annotations

import argparse
import re
from pathlib import Path

MAME_RE = re.compile(r"^f=\d+ pc=([0-9a-f]+) a=([0-9a-f]+) d=([0-9a-f]+) mask=([0-9a-f]+)$")
RTL_RE = re.compile(
    r"^\[memtrace\] f=(\d+) pc=([0-9a-f]+) a=([0-9a-f]+) d=([0-9a-f]+) be=([01]+) op=([0-9a-f]+) st=(\d+)$"
)


def final_state_mame(path: Path) -> dict[int, tuple[int, int, str]]:
    """address -> (final_data, write_count, last_pc)"""
    state: dict[int, list] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = MAME_RE.match(line.strip())
        if not m:
            continue
        pc, addr, data, _mask = m.groups()
        a = int(addr, 16)
        rec = state.setdefault(a, [0, None])
        rec[0] += 1
        rec[1] = (int(data, 16), pc)
    return {a: (v[1][0], v[0], v[1][1]) for a, v in state.items()}


def final_state_rtl(path: Path, frame_lo: int, frame_hi: int) -> dict[int, tuple[int, int, str]]:
    state: dict[int, list] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        m = RTL_RE.match(line.strip())
        if not m:
            continue
        frame, pc, addr, data, be, _op, _st = m.groups()
        f = int(frame)
        if f < frame_lo or f > frame_hi:
            continue
        a = int(addr, 16)
        rec = state.setdefault(a, [0, None])
        rec[0] += 1
        rec[1] = (int(data, 16), pc)
    return {a: (v[1][0], v[0], v[1][1]) for a, v in state.items()}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--mame", type=Path, required=True)
    ap.add_argument("--rtl", type=Path, required=True)
    ap.add_argument("--rtl-frame-lo", type=int, default=0)
    ap.add_argument("--rtl-frame-hi", type=int, default=1_000_000)
    ap.add_argument("--limit", type=int, default=40,
                    help="max mismatching addresses to print in detail")
    args = ap.parse_args()

    mame = final_state_mame(args.mame)
    rtl = final_state_rtl(args.rtl, args.rtl_frame_lo, args.rtl_frame_hi)

    print(f"MAME final-state addresses: {len(mame)}")
    print(f"RTL  final-state addresses: {len(rtl)} "
          f"(frames {args.rtl_frame_lo}..{args.rtl_frame_hi})")

    all_addrs = sorted(set(mame) | set(rtl))
    mismatches = []
    only_mame = only_rtl = 0
    for a in all_addrs:
        m = mame.get(a)
        r = rtl.get(a)
        if m is None:
            only_rtl += 1
            continue
        if r is None:
            only_mame += 1
            continue
        if m[0] != r[0]:
            mismatches.append((a, m, r))

    print(f"addresses written by MAME only: {only_mame}")
    print(f"addresses written by RTL only:  {only_rtl}")
    print(f"addresses with different final value: {len(mismatches)} / "
          f"{len(set(mame) & set(rtl))} shared")

    if mismatches:
        print(f"\nFirst {min(args.limit, len(mismatches))} mismatches "
              f"(address ascending):")
        for a, m, r in mismatches[: args.limit]:
            print(f"  a={a:06x}  MAME d={m[0]:04x} (n={m[1]}, last_pc={m[2]})  "
                  f"RTL d={r[0]:04x} (n={r[1]}, last_pc={r[2]})")

    return 0 if not mismatches and not only_mame and not only_rtl else 1


if __name__ == "__main__":
    raise SystemExit(main())
