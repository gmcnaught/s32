#!/usr/bin/env python3
"""Gate a build on the STA summary -- all corners, not just the first screen.

    check_timing_gate.py output_files/Arcade-SegaSystem32.sta.summary

Why this exists
---------------
tools/build.sh ran `quartus_sta || echo ...`, swallowing the exit code, on the
documented grounds that this revision is "NOT YET TIMING-CLOSED".  That is true
of ONE path -- the vendored HDMI/ascal setup path, which main itself misses and
ships anyway -- but it made every other violation invisible too, including
fatal ones.  On 2026-08-25 two builds shipped to hardware with HOLD violations
on the core clock domains, both reported by CI as "RBF ... pass", and both
blacked out every game:

    PR #14  4 hold violations on emu|pll general[0] (clk_ram), worst -0.304
    PR #15  7 hold violations on emu|pll general[1] (clk_sys), worst -0.537

while main, which renders, has exactly one negative check: pll_hdmi setup.

Policy
------
HOLD, any domain                 FATAL.  A hold violation is data racing the
                                 clock.  It is not "marginal", it does not
                                 improve at a slower clock, and it fails at
                                 every corner.  There is no such thing as an
                                 acceptable one.
SETUP on a core domain           FATAL.  emu|pll (clk_sys/clk_ram), SDRAM_CLK,
                                 and the HPS bridge clock carry the game.
SETUP on the vendored HDMI path  WARN.  main ships with pll_hdmi setup at
                                 -0.132 ns; the scaler degrades visibly at
                                 worst, and gating on it would block every
                                 build including known-good ones.
RECOVERY / REMOVAL / MPW         FATAL on any domain.

Pass --allow-hdmi-setup-ns N to tighten or loosen the one tolerated class.
"""
import argparse
import re
import sys

CORE_DOMAIN = re.compile(r"emu\|pll|SDRAM_CLK|h2f_user0_clk")
HDMI_DOMAIN = re.compile(r"pll_hdmi")
BLOCK = re.compile(r"Type  : (.*?)\nSlack : (-?[\d.]+)\nTNS   : (-?[\d.]+)")


def classify(kind, domain, slack, tol):
    if "Hold" in kind:
        return "FATAL", "hold violation on a core clock" if CORE_DOMAIN.search(domain) \
            else "hold violation"
    if "Setup" in kind:
        if HDMI_DOMAIN.search(domain):
            if slack >= -tol:
                return "WARN", f"vendored HDMI/ascal setup, within the {tol} ns allowance"
            return "FATAL", f"HDMI setup worse than the {tol} ns allowance"
        return "FATAL", "setup violation on a core clock"
    return "FATAL", f"{kind.split()[-2] if len(kind.split())>1 else kind} violation"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("summary")
    ap.add_argument("--allow-hdmi-setup-ns", type=float, default=0.25)
    args = ap.parse_args()

    try:
        text = open(args.summary, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        print(f"TIMING GATE FAIL: cannot read {args.summary}: {exc}", file=sys.stderr)
        return 2

    blocks = BLOCK.findall(text)
    if not blocks:
        print(f"TIMING GATE FAIL: no timing checks parsed from {args.summary} -- "
              "STA did not run, or the format changed", file=sys.stderr)
        return 2

    fatal, warn = [], []
    for raw, slack_s, tns_s in blocks:
        slack = float(slack_s)
        if slack >= 0:
            continue
        # "Slow 1100mV 100C Model Hold 'domain'"
        m = re.match(r"(.*Model (?:Setup|Hold|Recovery|Removal|Minimum Pulse Width))\s+'(.*)'$",
                     raw.strip())
        kind, domain = (m.group(1), m.group(2)) if m else (raw.strip(), raw.strip())
        verdict, why = classify(kind, domain, slack, args.allow_hdmi_setup_ns)
        (fatal if verdict == "FATAL" else warn).append(
            (slack, float(tns_s), kind, domain, why))

    print(f"TIMING GATE: {len(blocks)} checks, "
          f"{len(fatal)} fatal, {len(warn)} tolerated")
    for slack, tns, kind, domain, why in sorted(warn):
        print(f"  WARN   {slack:+.3f} TNS {tns:+.3f}  {kind}\n"
              f"         {domain}\n         -> {why}")
    for slack, tns, kind, domain, why in sorted(fatal):
        print(f"  FATAL  {slack:+.3f} TNS {tns:+.3f}  {kind}\n"
              f"         {domain}\n         -> {why}")

    if fatal:
        print("\nTIMING GATE FAIL: this bitstream must not be flashed.", file=sys.stderr)
        print("A hold violation or a core-domain setup violation makes the design "
              "functionally wrong, not merely slow.", file=sys.stderr)
        print("If the RTL is right, the next move is a fitter-seed exploration -- "
              "see the seed history in Arcade-SegaSystem32.qsf.", file=sys.stderr)
        return 1

    print("TIMING GATE PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
