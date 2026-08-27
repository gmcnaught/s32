#!/usr/bin/env python3
"""Keep the V25 asynchronous clock group honest about what it cuts.

    verif/timing/check_v25_crossings.py

Arcade-SegaSystem32.sdc declares:

    set_clock_groups -asynchronous -group $v25_clk

That is not a relaxation, it is a removal: every path between clk_v25 and the
rest of the design leaves timing analysis entirely, with infinite slack, and
nothing will ever report on it again.  Its justification is:

    "Its two crossings -- the SDRAM p5 line fetch and the V60-side mailbox port
     -- are handled in RTL by two-flop toggle synchronisers and a true-dual-
     port RAM, so STA must NOT time those paths."

That justification is an ENUMERATION.  Enumerations rot: the day a third
crossing appears it is cut too, silently, and no report in the build will
mention it.  This walks the RTL and refuses to let that happen.

What it does
------------
Finds every register assigned in a clk_v25-clocked always block and every
register assigned in a clk-clocked one, then reports signals written in one
domain and read in the other.  Each such crossing must appear in CROSSINGS
below with its protection stated.  A crossing the RTL grows and this file does
not know about is an error.

The two protection kinds are not interchangeable:

  synchroniser -- a 1-bit control toggle feeding a multi-flop chain.  Cutting
                  it is correct; that is what a synchroniser is for.

  handshake    -- a data bus with NO synchroniser, held stable by a control
                  toggle that IS synchronised.  Functionally sound, but the
                  path still exists in silicon, and with the group cut the
                  fitter may spread those bits anywhere on the die at zero
                  cost.  These are the ones that want a bounded delay rather
                  than no constraint at all.

Exit 0 if the RTL and this file agree, 1 otherwise, 2 if it cannot evaluate.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RTL = os.path.join(ROOT, "rtl", "cpu", "v25", "s32_v25_cpu.sv")
SDC = os.path.join(ROOT, "Arcade-SegaSystem32.sdc")

# signal -> (direction, protection, note)
CROSSINGS = {
    "req_tgl_v25": ("v25->sys", "synchroniser",
                    "1-bit request toggle into req_s1/s2/s3"),
    "req_addr_v25": ("v25->sys", "handshake",
                     "13-bit line address, stable while the cache holds the miss"),
    "ack_tgl_clk": ("sys->v25", "synchroniser",
                    "1-bit ack toggle into ack_s1/s2/s3"),
    "br_data_r": ("sys->v25", "handshake",
                  "64-bit fetched line, stable when cache_rom_ack pulses"),
}

BLOCK = re.compile(r"always\s*@\(\s*posedge\s+(\w+)(?:\s+or\s+posedge\s+\w+)?\s*\)")
ASSIGN = re.compile(r"^\s*(\w+)\s*(?:\[[^\]]*\])?\s*<=")


def blocks(text):
    """(clock, body) for every always @(posedge ...) block.

    The body runs to the next construct that starts at column 0 -- another
    always, an assign/wire/reg declaration, or endmodule.  An earlier version
    matched begin/end pairs and stopped at the FIRST `end`, which truncated
    every block at its reset branch and hid every crossing in the else branch,
    so the check passed by finding nothing.  Simpler and correct here beats
    clever and wrong.
    """
    stops = re.compile(r"^(always|assign|endmodule|wire|reg|localparam|"
                       r"s32_\w+|`ifdef|`endif)\b", re.M)
    out = []
    for m in BLOCK.finditer(text):
        clk = m.group(1)
        rest = text[m.end():]
        nxt = stops.search(rest)
        out.append((clk, rest[:nxt.start()] if nxt else rest))
    return out


def strip_comments(t):
    t = re.sub(r"/\*.*?\*/", "", t, flags=re.S)
    return re.sub(r"//[^\n]*", "", t)


def main():
    try:
        text = strip_comments(open(RTL, encoding="utf-8").read())
        sdc = open(SDC, encoding="utf-8").read()
    except OSError as exc:
        print("V25 CROSSING CHECK: CANNOT EVALUATE -- %s" % exc)
        return 2

    if "set_clock_groups -asynchronous -group $v25_clk" not in sdc:
        print("V25 CROSSING CHECK: the asynchronous group is gone from the SDC.")
        print("  If the crossings are constrained explicitly now, retire this check")
        print("  deliberately rather than leaving it passing vacuously.")
        return 1

    written = {}          # signal -> set of clocks that assign it
    for clk, body in blocks(text):
        dom = "v25" if clk == "clk_v25" else ("sys" if clk == "clk" else clk)
        for line in body.splitlines():
            m = ASSIGN.match(line)
            if m:
                written.setdefault(m.group(1), set()).add(dom)

    problems = []
    found = set()
    for sig, doms in sorted(written.items()):
        if "v25" not in doms and "sys" not in doms:
            continue
        # Read in the other domain?
        for clk, body in blocks(text):
            dom = "v25" if clk == "clk_v25" else ("sys" if clk == "clk" else clk)
            if dom not in ("v25", "sys"):
                continue
            if dom in doms:
                continue
            if re.search(r"\b%s\b" % re.escape(sig), body):
                found.add(sig)
                if sig not in CROSSINGS:
                    problems.append(
                        "%s crosses %s -> %s and is not declared. The SDC cuts "
                        "it with infinite slack and nothing will report on it."
                        % (sig, "/".join(sorted(doms)), dom))
                break

    # A declared crossing may leave its domain through a continuous assign or a
    # module port rather than another always block -- br_data_r reaches the
    # clk_v25 side as `assign cache_rom_data = br_data_r`, consumed inside an
    # instantiated cache.  Detecting that by inference would mean resolving the
    # clock of every instance; instead, a declared crossing counts as live if
    # it is referenced anywhere outside the blocks that write it.  The
    # authoritative direction stays the declaration's.
    outside = text
    for clk, body in blocks(text):
        outside = outside.replace(body, "")
    for sig in sorted(set(CROSSINGS) - found):
        if re.search(r"\b%s\b" % re.escape(sig), outside):
            continue
        problems.append(
            "%s is declared as a crossing but the RTL no longer references it "
            "outside its own clock domain -- stale entry, remove it" % sig)

    if problems:
        print("V25 CROSSING CHECK: FAIL")
        for p in problems:
            print("  %s" % p)
        return 1

    syncs = sum(1 for v in CROSSINGS.values() if v[1] == "synchroniser")
    hands = sum(1 for v in CROSSINGS.values() if v[1] == "handshake")
    print("V25 CROSSING CHECK: PASS (%d crossings: %d synchronised, %d handshake-only)"
          % (len(CROSSINGS), syncs, hands))
    for sig, (d, prot, note) in sorted(CROSSINGS.items(), key=lambda kv: kv[1][1]):
        print("    %-14s %-9s %-13s %s" % (sig, d, prot, note))
    return 0


if __name__ == "__main__":
    sys.exit(main())
