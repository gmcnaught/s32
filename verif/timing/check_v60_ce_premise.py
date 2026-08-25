#!/usr/bin/env python3
"""Keep s32.sdc's V60 multicycle exception honest.

s32.sdc relaxes every s32_v60 register-to-register path to a two-cycle setup
requirement.  Its justification is that the V60 runs on an execution enable
that never fires on adjacent clk_sys edges, so there is always an idle edge
between register updates.

That premise is false for any always block inside s32_v60 that runs on the RAW
clk_sys.  Such blocks exist on purpose -- the NMI pin synchroniser has to see
pulses shorter than one enable period, and the external-master write detector
has to see writes that land between enabled edges -- but every register they
drive must be carved back out to a single-cycle requirement, or the fitter is
told those paths have twice the time they really do.

Nothing in a simulator can catch that: it is a property of the constraints, not
of the RTL.  So it is checked here, structurally.

Contract:
  * Every synthesised `always @(posedge clk)` block in s32_v60.sv that is not
    wholly gated by `ce` must carry a marker naming the registers it drives:

        // synthesis-timing: ungated-registers <name> [<name> ...]

  * The union of those names must equal the `v60_ungated` collection in the
    SDC.

Exempt: the main microsequencer block (identified by `case (st)`), whose only
ungated part is the reset branch, and which the SDC handles via `-from
$v60_ungated`; and anything inside `ifndef SYNTHESIS`, which is not synthesised.

Exit 0 if the two agree, 1 with a diagnosis otherwise.
"""
import re
import sys
import pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
RTL = ROOT / "rtl" / "cpu" / "v60" / "s32_v60.sv"
SDC = ROOT / "Arcade-SegaSystem32.sdc"

MARKER = re.compile(r"//\s*synthesis-timing:\s*ungated-registers\s+(.+)")


def strip_sim_only(text):
    """Drop `ifndef SYNTHESIS ... `endif regions, keeping line numbering."""
    out, depth = [], 0
    for line in text.splitlines():
        bare = line.strip()
        if depth == 0 and re.match(r"`ifndef\s+SYNTHESIS\b", bare):
            depth = 1
            out.append("")
            continue
        if depth:
            if re.match(r"`if(n?def|)\b", bare):
                depth += 1
            elif re.match(r"`endif\b", bare):
                depth -= 1
            out.append("")
            continue
        out.append(line)
    return "\n".join(out)


PREAMBLE = 10   # comment lines above an always block that count as its header


def blocks(text):
    """Yield (start_line, header, body) for each always @(posedge clk) block.

    The marker comment sits ABOVE the always line, where a reader looking at
    the block will see it, so the preceding comment lines are part of what is
    searched.
    """
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if not re.search(r"always\s*@\s*\(\s*posedge\s+clk\s*\)", line):
            continue
        header = "\n".join(lines[max(0, i - PREAMBLE):i])
        depth, body, started = 0, [], False
        for l in lines[i:]:
            body.append(l)
            # count begin/end outside comments
            code = re.sub(r"//.*", "", l)
            for tok in re.findall(r"\b(begin|end|case|endcase)\b", code):
                if tok in ("begin", "case"):
                    depth += 1
                    started = True
                else:
                    depth -= 1
            if started and depth <= 0:
                break
        yield i + 1, header, "\n".join(body)


def is_ce_gated(body):
    """True when every assignment in the block sits under an `if (ce)`."""
    head = re.sub(r"//.*", "", body)
    # `if (ce)` or `... else if (ce)` immediately guarding the body
    return bool(re.search(r"\bif\s*\(\s*ce\s*\)", head.split("case", 1)[0]))


def assigned_regs(body):
    names = set()
    for l in body.splitlines():
        code = re.sub(r"//.*", "", l)
        for m in re.finditer(r"(\w+)\s*(?:\[[^\]]*\])?\s*<=", code):
            names.add(m.group(1))
    return names


def sdc_ungated():
    text = SDC.read_text()
    m = re.search(
        r"set v60_ungated \[get_registers -nowarn \{\*\|s32_v60:v60\|(\w+)\*\}\]"
        r".*?foreach pat \{([^}]*)\}",
        text,
        re.S,
    )
    if not m:
        return None
    return {m.group(1)} | set(m.group(2).split())


def main():
    src = strip_sim_only(RTL.read_text())
    declared, problems = set(), []

    for line_no, header, body in blocks(src):
        if is_ce_gated(body):
            continue
        if "case (st)" in body:            # the microsequencer; see docstring
            continue
        m = MARKER.search(header) or MARKER.search(body)
        if not m:
            problems.append(
                f"{RTL.relative_to(ROOT)}:{line_no}: ungated `always @(posedge clk)` "
                f"block with no `// synthesis-timing: ungated-registers ...` marker.\n"
                f"    It drives: {' '.join(sorted(assigned_regs(body))) or '(none found)'}\n"
                f"    Add the marker and list these in the SDC's v60_ungated collection,\n"
                f"    or the fitter is told they have two clk_sys cycles when they have one."
            )
            continue
        named = set(m.group(1).split())
        drives = assigned_regs(body)
        missing = drives - named
        if missing:
            problems.append(
                f"{RTL.relative_to(ROOT)}:{line_no}: marker omits {' '.join(sorted(missing))}"
            )
        declared |= named

    in_sdc = sdc_ungated()
    if in_sdc is None:
        problems.append(
            f"{SDC.name}: could not find the `set v60_ungated` collection. "
            f"If the carve-out was removed, the two-cycle exception is now "
            f"covering raw-clk_sys registers again."
        )
    else:
        for name in sorted(declared - in_sdc):
            problems.append(
                f"{SDC.name}: `{name}` runs on the raw clk_sys but is not in v60_ungated"
            )
        for name in sorted(in_sdc - declared):
            problems.append(
                f"{SDC.name}: v60_ungated lists `{name}`, which no ungated always "
                f"block drives any more -- stale carve-out, remove it"
            )

    if problems:
        print("V60 CE-PREMISE CHECK: FAIL")
        for p in problems:
            print(f"  {p}")
        return 1

    print(
        f"V60 CE-PREMISE CHECK: PASS "
        f"({len(declared)} raw-clk_sys registers, all carved out of the "
        f"two-cycle exception)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
