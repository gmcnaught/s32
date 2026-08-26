#!/usr/bin/env python3
"""The debug word's field layout is written down twice.  Make them agree.

    verif/common/check_hud_layout.py

`assign dbg_bus = {...}` in rtl/s32_core.sv packs the fields; FIELDS in
tools/decode_hud.py unpacks them.  Nothing connects the two, and no simulator
can catch the drift: a HUD build with a shifted field paints a perfectly valid
band and the decoder reads a perfectly plausible wrong pc.  That is the worst
possible failure for this tool, because it is only ever used when nothing else
in the system can be trusted.

So this derives the packing from the RTL -- item order, widths from the
declarations -- and compares it to the decoder's table.  Adding a debug field
without updating the decoder fails the gate.

Exit 0 pass, 1 mismatch, 2 cannot evaluate.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORE = os.path.join(ROOT, "rtl", "s32_core.sv")
DECODER = os.path.join(ROOT, "tools", "decode_hud.py")

# rtl identifier -> decoder field name.  A rule rather than a table, so a new
# field needs no edit here.
def field_name(ident):
    for prefix in ("v60_dbg_", "dbg_"):
        if ident.startswith(prefix):
            return ident[len(prefix):]
    return ident


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def declared_width(src, ident):
    """Width of a reg/wire/output declaration, or 1 if it is declared bare."""
    m = re.search(r"\b(?:reg|wire|output|input)\b[^;,\n]*?\[\s*(\d+)\s*:\s*(\d+)\s*\]"
                  r"[^;,\n]*?\b" + re.escape(ident) + r"\b", src)
    if m:
        return int(m.group(1)) - int(m.group(2)) + 1
    if re.search(r"\b(?:reg|wire|output|input)\b[^;,\n]*?\b" + re.escape(ident) + r"\b", src):
        return 1
    return None


def rtl_layout():
    src = strip_comments(open(CORE).read())
    m = re.search(r"assign\s+dbg_bus\s*=\s*\{(.*?)\}\s*;", src, flags=re.S)
    if not m:
        return None, "no `assign dbg_bus = {...}` in rtl/s32_core.sv"

    items = [i.strip() for i in m.group(1).split(",") if i.strip()]
    widths = []
    for item in items:
        lit = re.fullmatch(r"(\d+)'[bdhoBDHO][0-9a-fA-FxzXZ_]+", item)
        if lit:                                   # padding literal, unnamed
            widths.append((None, int(lit.group(1))))
            continue
        part = re.fullmatch(r"(\w+)\s*\[\s*(\d+)\s*:\s*(\d+)\s*\]", item)
        if part:
            widths.append((part.group(1), int(part.group(2)) - int(part.group(3)) + 1))
            continue
        if re.fullmatch(r"\w+", item):
            w = declared_width(src, item)
            if w is None:
                return None, "cannot find a declaration for `%s`" % item
            widths.append((item, w))
            continue
        return None, "cannot parse concatenation item `%s`" % item

    total = sum(w for _, w in widths)
    if total != 64:
        return None, "dbg_bus packs %d bits, not 64" % total

    layout, lsb = {}, 64
    for ident, w in widths:
        lsb -= w
        if ident is not None:
            layout[field_name(ident)] = (lsb, w)
    return layout, None


def decoder_layout():
    src = open(DECODER).read()
    m = re.search(r"^FIELDS\s*=\s*\{(.*?)^\}", src, flags=re.S | re.M)
    if not m:
        return None, "no FIELDS table in tools/decode_hud.py"
    out = {}
    for name, lsb, width in re.findall(r'"(\w+)"\s*:\s*\((\d+)\s*,\s*(\d+)\)', m.group(1)):
        out[name] = (int(lsb), int(width))
    return out, None


def main():
    rtl, err = rtl_layout()
    if err:
        print("HUD LAYOUT CHECK: CANNOT EVALUATE -- %s" % err)
        return 2
    dec, err = decoder_layout()
    if err:
        print("HUD LAYOUT CHECK: CANNOT EVALUATE -- %s" % err)
        return 2

    bad = []
    for name in sorted(set(rtl) | set(dec)):
        a, b = rtl.get(name), dec.get(name)
        if a != b:
            bad.append("  %-10s rtl=%s decoder=%s" % (name, a, b))
    if bad:
        print("HUD LAYOUT CHECK: FAIL -- rtl/s32_core.sv and tools/decode_hud.py disagree")
        print("\n".join(bad))
        return 1
    print("HUD LAYOUT CHECK: PASS (%d fields, 64 bits)" % len(rtl))
    return 0


if __name__ == "__main__":
    sys.exit(main())
