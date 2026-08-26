#!/usr/bin/env python3
"""Score the four-title hardware gate from its screenshots.

    tools/hwgate_score.py <dir>          # dir/<title>/<shot>.png, two per title

Why this is not `ls -l`
-----------------------
The gate has been decided on file size, and file size lies in both directions:

    pure black                ~1034 B
    frozen flat olive frame   ~1464 B, and byte-identical between samples
    legitimate dark attract   ~12 KB of real content

A flat frame is "100% lit" by any brightness test yet contains no picture, and
a dark attract frame is dim yet perfectly healthy.  What separates them is
whether the pixels VARY.  So the verdict is built from three measurements:

    mean luma        how bright (the number the A/B tables already quote:
                     ga2 92.5 -> 112.4 is exactly this measurement)
    stdev of luma    whether there is a picture at all  <- the discriminator
    identical?       whether the two samples differ, i.e. whether it animates

A title that renders shows real spatial variation.  A blackout shows none and
no brightness.  A freeze shows variation but two identical frames -- reported
separately, because a static title screen can legitimately do that too and it
is a signal to look at, not a verdict to trust.
"""
import hashlib
import os
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("needs Pillow: pip install pillow")

# Below this stdev the frame carries no picture, only a wash.  A flat fill is
# 0.0; the dimmest real attract frames measured on this gate are well above 8.
FLAT_STDEV = 4.0
BLACK_MEAN = 2.0


def measure(path):
    im = Image.open(path).convert("L")
    px = im.tobytes()
    n = len(px)
    mean = sum(px) / n
    var = sum((p - mean) ** 2 for p in px) / n
    return {
        "path": path,
        "bytes": os.path.getsize(path),
        "size": im.size,
        "mean": mean,
        "stdev": var ** 0.5,
        "digest": hashlib.md5(px).hexdigest(),
    }


def verdict(shots):
    if not shots:
        return "NO SHOTS", "nothing was captured -- the core may not have loaded"
    flat = [s for s in shots if s["stdev"] < FLAT_STDEV]
    if len(flat) == len(shots):
        if all(s["mean"] < BLACK_MEAN for s in shots):
            return "BLACK", "no picture and no light"
        return "FLAT", "uniform fill, no picture -- a wedged frame, not a game"
    if len(shots) >= 2 and len({s["digest"] for s in shots}) == 1:
        return "STATIC", "renders, but both samples are identical -- check it animates"
    return "RENDERS", "picture present and changing between samples"


def main(root):
    titles = sorted(d for d in os.listdir(root)
                    if os.path.isdir(os.path.join(root, d)))
    if not titles:
        sys.exit("no per-title directories under %s" % root)

    worst = 0
    for title in titles:
        d = os.path.join(root, title)
        pngs = sorted(f for f in os.listdir(d) if f.lower().endswith(".png"))
        shots = [measure(os.path.join(d, f)) for f in pngs]
        v, why = verdict(shots)
        print("%-10s %-8s %s" % (title, v, why))
        for s in shots:
            print("             %6d B  %dx%d  mean %6.2f  stdev %6.2f  %s"
                  % (s["bytes"], s["size"][0], s["size"][1], s["mean"],
                     s["stdev"], os.path.basename(s["path"])))
        if v in ("BLACK", "FLAT", "NO SHOTS"):
            worst = 2
        elif v == "STATIC" and worst < 1:
            worst = 1

    print()
    if worst == 2:
        print("HW GATE: FAIL -- at least one title has no picture")
    elif worst == 1:
        print("HW GATE: INCONCLUSIVE -- every title renders, but one did not change")
    else:
        print("HW GATE: PASS -- all four titles render and animate")
    return worst


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    raise SystemExit(main(sys.argv[1]))
