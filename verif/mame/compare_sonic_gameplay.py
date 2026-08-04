#!/usr/bin/env python3
"""Compare a SegaSonic RTL gameplay sweep against the MAME raw-pixel reference.

MAME counts machine frames from the start of emulation; tb_core_romboot counts
vblanks from reset release.  The offset is a constant +5 measured across the
whole attract run (the 416->320 mode switch is the anchor), so RTL frame N is
compared with MAME frame N + offset.

The RTL PPM is always 416 wide; in 320-wide mode it carries all-black right
padding, which is cropped only after being verified black.  Nothing is
rescaled, and no x/y offset is applied — the attract comparison established
that none is needed.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from PIL import Image, ImageChops


def load_rtl(path: Path) -> Image.Image:
    return Image.open(path).convert("RGB")


def crop_padding(rtl: Image.Image, width: int, height: int) -> Image.Image:
    if rtl.size == (width, height):
        return rtl
    if rtl.height != height or rtl.width < width:
        raise ValueError(f"unexpected RTL geometry {rtl.size} vs {(width, height)}")
    pad = rtl.crop((width, 0, rtl.width, rtl.height))
    if ImageChops.difference(
        pad, Image.new("RGB", pad.size, "black")
    ).getbbox() is not None:
        raise ValueError("RTL right padding is not black; geometry is wrong")
    return rtl.crop((0, 0, width, height))


def compare(mame: Image.Image, rtl: Image.Image) -> tuple[int, int]:
    delta = ImageChops.difference(mame, rtl)
    differing = sum(1 for p in delta.get_flattened_data() if p != (0, 0, 0))
    return differing, mame.width * mame.height


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rtl-dir", type=Path, default=Path("scratch/sonic-gameplay"))
    ap.add_argument("--mame-dir", type=Path, default=Path("scratch/mame_sonic_play"))
    ap.add_argument("--offset", type=int, default=5,
                    help="MAME frame = RTL frame + offset")
    ap.add_argument("--scan", type=int, default=0, metavar="N",
                    help="on a mismatch, also try MAME frames +/-N around the "
                         "nominal one and report the best.  A frame that "
                         "matches at a DIFFERENT offset is timing drift; one "
                         "that matches nowhere is a content defect.")
    ap.add_argument("--json", type=Path, help="write the per-frame result table")
    args = ap.parse_args()

    rtl_frames = sorted(
        int(m.group(1))
        for m in (re.match(r"dump(\d+)\.ppm$", p.name)
                  for p in args.rtl_dir.glob("dump*.ppm"))
        if m
    )
    if not rtl_frames:
        print(f"SONIC GAMEPLAY COMPARE FAIL: no RTL frames in {args.rtl_dir}")
        return 2

    rows = []
    exact = 0
    for frame in rtl_frames:
        mame_frame = frame + args.offset
        mame_path = args.mame_dir / f"frame_{mame_frame:06d}.ppm"
        if not mame_path.is_file():
            rows.append({"rtl": frame, "mame": mame_frame, "status": "no-reference"})
            continue
        mame = Image.open(mame_path).convert("RGB")
        rtl = crop_padding(load_rtl(args.rtl_dir / f"dump{frame}.ppm"),
                           mame.width, mame.height)
        differing, total = compare(mame, rtl)
        pct = 100.0 * differing / total
        if differing == 0:
            exact += 1
        row = {
            "rtl": frame, "mame": mame_frame, "differing": differing,
            "pixels": total, "percent": round(pct, 4),
            "size": [mame.width, mame.height],
        }
        note = ""
        if differing and args.scan:
            best = (differing, mame_frame)
            for candidate in range(mame_frame - args.scan, mame_frame + args.scan + 1):
                path = args.mame_dir / f"frame_{candidate:06d}.ppm"
                if candidate == mame_frame or not path.is_file():
                    continue
                other = Image.open(path).convert("RGB")
                if other.size != (mame.width, mame.height):
                    continue
                d, _ = compare(other, rtl)
                if d < best[0]:
                    best = (d, candidate)
            row["best_differing"], row["best_mame"] = best
            row["best_offset"] = best[1] - frame
            if best[1] != mame_frame:
                note = (f"   best match MAME {best[1]} "
                        f"({best[0]} differing, offset {best[1] - frame:+d})")
        rows.append(row)
        print(f"  RTL {frame:5d} vs MAME {mame_frame:5d}: "
              f"{differing:7d} / {total} differing ({pct:8.4f}%){note}")

    compared = [r for r in rows if "differing" in r]
    print(f"SONIC GAMEPLAY COMPARE: {exact}/{len(compared)} frames exact")
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(json.dumps(rows, indent=2), encoding="utf-8")
    return 0 if compared and exact == len(compared) else 1


if __name__ == "__main__":
    raise SystemExit(main())
