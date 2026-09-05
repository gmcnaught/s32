#!/usr/bin/env python3
"""
Which V60 instructions does a game actually execute, and does the clean-room
core execute them?

Input: the opcode trace tb_core_romboot.sv writes with +OPTRACE=<file>, one
line per instruction the shipping core decoded:

    <pc:8 hex> <opcode byte:2 hex> <second byte:2 hex>

Output: one line per mnemonic, most executed first, with the count, the share,
and whether rtl/cpu/v60x executes it (EXEC_OP / EXEC_OP_ESCAPE / CTRL_OP in
insn_table.py are the authority) -- then a summary of how much of the trace the
clean-room core covers.  That number is what docs/v60/NEXT-STEPS.md's ordering
of the remaining instruction groups should rest on, instead of a guess.

    python3 tools/v60x/exposure.py roms/sim/ga2/optrace.txt

Escape opcodes 58-5F carry their instruction in the second byte's low five bits
(p.3.293, Format VII); everything else is the opcode byte alone.  A byte the
table does not name is reported as `?` -- a reserved opcode, or a mode byte
the trace caught mid-instruction if the bench's boundary was wrong.
"""
import sys, os, collections, importlib.util, io, contextlib

_here = os.path.dirname(os.path.abspath(__file__))


def load_table():
    spec = importlib.util.spec_from_file_location('insn_table', os.path.join(_here, 'insn_table.py'))
    t = importlib.util.module_from_spec(spec)
    with contextlib.redirect_stdout(io.StringIO()):
        spec.loader.exec_module(t)
    return t


def build_decoder(t):
    """(opcode, second byte) -> mnemonic, from the table."""
    plain = {}          # opcode -> mnemonic (no sub-op)
    escape = {}         # (opcode, subop low 5 bits) -> mnemonic
    for mnemonic, op_pat, sub_pat, fmt, page in t.TABLE:
        for op in t.expand(op_pat):
            if sub_pat is None:
                plain.setdefault(op, mnemonic)
            else:
                for sub in t.expand(sub_pat):
                    escape.setdefault((op, sub & 0x1F), mnemonic)
    executed = set(t.EXEC_OP) | {k[0] for k in t.EXEC_OP_ESCAPE} | set(t.CTRL_OP)

    def decode(op, b1):
        if (op, b1 & 0x1F) in escape:
            return escape[(op, b1 & 0x1F)]
        return plain.get(op, '?')

    return decode, executed


def count(lines, decode):
    counts = collections.Counter()
    for line in lines:
        parts = line.split()
        if len(parts) < 3:
            continue
        try:
            op, b1 = int(parts[1], 16), int(parts[2], 16)
        except ValueError:
            continue
        counts[decode(op, b1)] += 1
    return counts


def report(counts, executed, out=sys.stdout):
    total = sum(counts.values())
    covered = sum(n for m, n in counts.items() if m in executed)
    out.write('%-10s %10s %7s  %s\n' % ('mnemonic', 'count', 'share', 'clean-room'))
    for m, n in counts.most_common():
        out.write('%-10s %10d %6.2f%%  %s\n' % (m, n, 100.0 * n / total, 'executes' if m in executed else 'STOPS'))
    missing = [(m, n) for m, n in counts.most_common() if m not in executed]
    out.write('\n%d instructions, %d mnemonics; the clean-room executes %.2f%% of them\n'
              % (total, len(counts), 100.0 * covered / total if total else 0.0))
    if missing:
        out.write('not executed, by exposure: %s\n' % ', '.join('%s (%d)' % mn for mn in missing))
    return total, covered, missing


def main():
    if len(sys.argv) < 2:
        sys.stderr.write(__doc__)
        return 2
    t = load_table()
    decode, executed = build_decoder(t)
    with open(sys.argv[1]) as f:
        counts = count(f, decode)
    report(counts, executed)
    return 0


if __name__ == '__main__':
    sys.exit(main())
