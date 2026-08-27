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

# name -> (lsb, width), matching the `assign dbg_bus` concatenation in
# rtl/s32_core.sv.  Machine-readable on purpose: verif/common/check_hud_layout.py
# derives the same table from the RTL and fails the gate if the two drift.
# A silently shifted field here would report a confident wrong pc during the
# one kind of investigation where nothing else is trustworthy.
FIELDS = {
    "heartbeat": (56, 8),
    "bus_txns":  (40, 16),
    "pc":        (16, 24),
    "st":        (9, 7),
    "halted":    (8, 1),
    "ce_viol":   (7, 1),
}


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
    out = {"raw": v}
    # Cells 57..63 carry a counter clocked inside the overlay itself, painted
    # on every band row.  Sample them on each row: the rows are a scanline
    # apart, so a running clock cannot paint the same value twice.  Equal on
    # every row means the overlay is frozen and NOTHING else it reports can be
    # believed -- which is exactly how a set of readings was taken at face
    # value on 2026-08-26 from builds whose debug bus was static.
    beats = []
    for row in range(rule):
        b = 0
        for i in range(57, 64):
            xx = i * CELL_W + CELL_W // 2
            if xx >= w:
                break
            r, g, bl = px[xx, row]
            b = (b << 1) | (1 if (g > 128 and r < 128) else 0)
        beats.append(b)
    out["alive"] = len(set(beats)) > 1
    out["beats"] = beats
    for name, (lsb, width) in FIELDS.items():
        out[name] = (v >> lsb) & ((1 << width) - 1)
    return out


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
        if not d["alive"] and not any(d["beats"]):
            print(f"    LIVENESS  = all zero {d['beats']}")
            print("    -> cells 57..63 read zero on every row. Either this shot predates")
            print("       the liveness cells (they were the word's zero padding), or the")
            print("       overlay is frozen. Rebuild with the current HUD to tell them")
            print("       apart; until then treat the fields above as unverified.")
        elif not d["alive"]:
            print(f"    LIVENESS  = FROZEN {d['beats']}")
            print("    -> the overlay's own counter is identical on every band row,")
            print("       which one running clock cannot produce. The debug bus is")
            print("       static: every field above is stale and means nothing.")
        else:
            print(f"    liveness  = ok {d['beats']}")

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
