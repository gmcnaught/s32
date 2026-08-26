#!/usr/bin/env python3
"""Every timing exception is a claim. Flag the ones whose rule is wider than it.

    verif/timing/check_sdc_exceptions.py

Two real defects were found in this file on 2026-08-26.  This catches ONE of
the two shapes; be clear about which.

  CAUGHT -- the clk_ram adapter exception named a bare `-to $v60_bus_regs`,
  while every word of its justification was about the clk_sys boundary.  It
  therefore also covered clk_ram -> clk_ram paths from sources that were not
  the adapter, including the timebase register that drives its clock enable.
  Verified: run this against main before that fix and it reports four unscoped
  rules.

  NOT CAUGHT -- the raw-clk_sys carve-out named `-from $v60_ungated -to
  $v60_regs` and never the reverse, so the broad two-cycle exception still
  covered paths INTO the external-write detector.  That rule names both ends,
  so it is scoped by this file's definition; it was simply incomplete.  A
  carve-out that undoes a broad rule in only one direction needs a checker that
  knows what the broad rule was, which is what
  verif/timing/check_v60_ce_premise.py does for that specific collection.
  There is no general check for that shape yet.

Neither failed STA.  A relaxed requirement never does -- that is what it is
for.  Both were found by reading, which does not scale and did not happen for
two years.

So: a `set_multicycle_path` that names only one endpoint collection asserts
something about EVERY path reaching or leaving it, from anywhere in the design.
That is almost never what the comment above it says.  A rule is considered
scoped if it names both ends, or if the unnamed end is a clock (which is a
statement about a domain crossing, and is usually exactly right).

Exceptions that are deliberately broad are declared in ALLOW below, with the
reason.  Adding to that list is a decision; leaving a rule unscoped by accident
is not.

Exit 0 clean, 1 if an unscoped rule is not declared.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SDC = os.path.join(ROOT, "Arcade-SegaSystem32.sdc")

# Rules that are broad on purpose. Keyed by the collection or pattern they
# name, with the reason they are allowed to be one-sided.
ALLOW = {
    "*_osd|pixcnt*":
        "vendored MiSTer OSD constraint, carried verbatim from the framework",
    "*_osd|multiscan*":
        "vendored MiSTer OSD constraint, carried verbatim from the framework",
}

MC = re.compile(r"^\s*set_multicycle_path\b(?P<args>.*)$")
CONT = re.compile(r"\\\s*$")


def logical_lines(text):
    """Join backslash continuations, keeping the first line's number."""
    out, buf, start = [], "", None
    for n, line in enumerate(text.splitlines(), 1):
        if start is None:
            start = n
        buf += CONT.sub(" ", line)
        if CONT.search(line):
            continue
        out.append((start, buf))
        buf, start = "", None
    return out


def endpoints(args):
    """The -from / -to operands, or None when absent."""
    def grab(flag):
        m = re.search(r"%s\s+(\[[^\]]*\]|\{[^}]*\}|\$\w+)" % flag, args)
        return m.group(1) if m else None
    return grab("-from"), grab("-to")


def is_clock(operand):
    return operand is not None and "get_clocks" in operand


def main():
    try:
        text = open(SDC, encoding="utf-8").read()
    except OSError as exc:
        print("SDC EXCEPTION CHECK: CANNOT EVALUATE -- %s" % exc)
        return 2

    problems, checked = [], 0
    for lineno, line in logical_lines(text):
        if line.lstrip().startswith("#"):
            continue
        m = MC.match(line)
        if not m:
            continue
        checked += 1
        frm, to = endpoints(m.group("args"))

        if frm is not None and to is not None:
            continue                       # both ends named: scoped
        if is_clock(frm) or is_clock(to):
            continue                       # names a domain crossing: scoped

        named = frm or to
        if named is None:
            problems.append((lineno, "names neither -from nor -to", line.strip()))
            continue
        key = named.strip("{}").strip()
        if key in ALLOW:
            continue
        side = "-from" if frm else "-to"
        problems.append((
            lineno,
            "one-sided %s %s: this relaxes EVERY path %s it, from anywhere in "
            "the design. Name both ends, or name the clock on the other side if "
            "the claim is about a domain crossing." % (
                side, named, "leaving" if frm else "reaching"),
            line.strip()))

    if problems:
        print("SDC EXCEPTION CHECK: FAIL (%d of %d rules unscoped)"
              % (len(problems), checked))
        for lineno, why, src in problems:
            print("  %s:%d" % (os.path.basename(SDC), lineno))
            print("    %s" % src)
            print("    %s" % why)
        return 1

    print("SDC EXCEPTION CHECK: PASS (%d multicycle rules, all scoped or declared)"
          % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
