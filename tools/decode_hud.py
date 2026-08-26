#!/usr/bin/env python3
"""Decode the s32 debug HUD out of a MiSTer screenshot.

The core paints a 64-bit debug word into the top rows of the picture when it
is built with -DS32_DEBUG_HUD (see rtl/s32_debug_hud.sv).  This reads it back.

    tools/decode_hud.py shot.png [shot2.png ...]

Two screenshots a few seconds apart are the useful measurement: a heartbeat
that does not move means clk_sys is dead, a pc that does not move means the
V60 is wedged, and bus_txns that does not move means the external bus is idle.
"""
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow: pip install pillow")

CELL_W, ROWS = 4, 6


def decode(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    px = im.load()

    # The red rule under the band confirms this really is a HUD build and
    # tells us the sample row without hard-coding it.
    rule = None
    for y in range(min(16, h)):
        r, g, b = px[2, y]
        if r > 180 and g < 70 and b < 70:
            rule = y
            break
    if rule is None:
        return None

    y = max(0, rule // 2)          # middle of the band, away from its edges
    bits = []
    for i in range(64):
        x = i * CELL_W + CELL_W // 2
        if x >= w:
            return None
        r, g, b = px[x, y]
        bits.append(1 if (r > 128 and g > 128 and b > 128) else 0)

    v = 0
    for bit in bits:
        v = (v << 1) | bit
    return {
        "raw":       v,
        "heartbeat": (v >> 56) & 0xFF,
        "bus_txns":  (v >> 40) & 0xFFFF,
        "pc":        (v >> 16) & 0xFFFFFF,
        "st":        (v >> 9) & 0x7F,
        "halted":    (v >> 8) & 1,
        "ce_viol":   (v >> 7) & 1,
    }


def main(paths):
    rows = []
    for p in paths:
        d = decode(p)
        if d is None:
            print(f"{p}: no HUD band found "
                  f"(not a -DS32_DEBUG_HUD build, or video is dead)")
            continue
        rows.append((p, d))
        print(f"{p}:")
        print(f"    pc        = 0x{d['pc']:06x}")
        print(f"    st        = {d['st']}    halted={d['halted']}")
        print(f"    heartbeat = {d['heartbeat']}")
        print(f"    bus_txns  = {d['bus_txns']}")
        print(f"    ce_viol   = {d['ce_viol']}"
              f"{'   <-- SDC two-cycle premise VIOLATED' if d['ce_viol'] else ''}")

    if len(rows) >= 2:
        (_, a), (_, b) = rows[0], rows[-1]
        print("\nbetween first and last:")
        for k in ("heartbeat", "pc", "bus_txns"):
            moved = "moving" if a[k] != b[k] else "STUCK"
            print(f"    {k:10s} {moved}")
        if a["heartbeat"] == b["heartbeat"]:
            print("    -> clk_sys is not running (or the core is held in reset)")
        elif a["pc"] == b["pc"] and not b["halted"]:
            print("    -> clk_sys runs but the V60 is wedged, not halted")
        elif a["bus_txns"] == b["bus_txns"]:
            print("    -> V60 advances but issues no bus cycles")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    main(sys.argv[1:])
