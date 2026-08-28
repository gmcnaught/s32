# The co-simulation oracle

`verif/v60x/tb_v60_cosim.sv` puts the shipping core and the clean-room decoder
on one instruction stream and asks them the same question: **where does each
instruction end?**

The two were built from different things. `rtl/cpu/v60/s32_v60.sv` is MAME's V60
core transcribed into RTL — its own header says so — and `rtl/cpu/v60x/` is the
databook's format figure on p. 3.293 and its mod-field figure on p. 3.294, read
directly. Neither had ever been asked to agree with the other about anything.

It is also the only thing in this repository that tests `s32_v60.sv`'s length
arithmetic against a second opinion. Its own benches check what it *computes*;
none of them checks where it thinks an instruction *stops*.

## How each side is asked

The clean-room side **decodes**: `v60_pfu` fetches the stream through `v60_biu`
and `v60_idu` reports `insn_pc` and `insn_len` for each instruction in turn.
Nothing executes.

The shipping core **executes**, so the program is straight line — no taken
branch, no trap, no memory operand outside the RAM. Its instruction boundaries
are the values its `pc` register takes, and the bench asserts that reading of
them too: every step has to be forward and no longer than an instruction can
be, so "the PC changed" is a boundary rather than an artefact.

The program covers Format II with each shape of mod field the figure gives a
length to — immediate, immediate quick, register, register indirect, disp8,
disp16, disp32, absolute, PC-relative — then Format I in both directions of its
`d` bit, Format V, Format III, Format VI, and both of Format IV's displacement
widths.

## Two coincidences the program is built to defeat

A boundary comparison can be fooled. If a decoder reads a two-byte immediate
where the instruction has four, the two bytes it skipped are still there, and
the *next* thing it decodes is one of them. With `00` in that position it
decodes a double displacement, swallows exactly the two bytes it skipped, and
arrives at the right total length by accident.

So neither the word immediate nor the absolute address in the program is a
round number: `0x006A0004` and `0x006B0400`, each with a register mod byte in
the position a short read would land on. A decoder that takes two bytes there
finishes two bytes early and the boundary moves.

Both were found by mutation: the first attempt used round numbers and the
mutations passed.

## The divergence it found: opcodes `6B` and `7B` — resolved

The first run of this bench had those two opcodes in the executed program, put
there precisely because a never-taken branch is what a length test wants from a
branch. The shipping core branched to a handler on both: it raised the
reserved-opcode exception, and said why in its own source —

> `0x6B/0x7B are holes in MAME's authoritative primary dispatch table, not`
> `branch-condition encodings.`

### What the plates say

Two pages, and they had to be read off the plates because both books' OCR
mangles the opcode column.

**p. 3.295, Condition Encodings.** Sixteen rows, `c3 c2 c1 c0` against Name and
Condition, and the last two of the middle block are

```
    1 0 1 0    True     Always
    1 0 1 1    False    Never
```

Not one of the sixteen is marked reserved — and the two tables printed beside
it *on the same page* do mark theirs: Integer Data Type Selection prints
`11 reserved`, Bit Field Extension prints `11 reserved`. NEC says "reserved"
when it means reserved. The same page's Branch Displacements table gives
`b = 0` byte, `b = 1` halfword.

**p. 3.298, Control Transfer Instructions.** The Bcc row is

```
    Bcc    0 1 1 b c3 c2 c1 c0    IV
```

with no exclusion, no note, and an empty Exceptions column.

### Why absence of a mnemonic is not absence of an encoding

The Programmer's Reference's Bcc page lists sixteen mnemonics — BGT, BGE, BLT,
BLE, BH, BNL, BL, BNH, BE, BNE, BV, BNV, BN, BP, BC, BNC — and two of those are
aliases (`BL`/`BC` are both `0010`, `BNL`/`BNC` both `0011`). So it names
fourteen distinct conditions and omits exactly two: `1010` and `1011`.

`1010` is "True / Always", which an assembler spells `BR`. This core has always
executed `6A`, and games depend on it. The Reference simply has no *conditional*
mnemonic for a branch that is unconditional, and nothing useful to call one that
never branches — that is an assembler-syntax fact, not an encoding fact.

`1010` and `1011` are adjacent rows of one sixteen-row table. There is no
reading of these pages under which one is a branch and the other is a reserved
opcode.

### What changed

`s32_v60.sv` decodes both `0x60-0x6F` and `0x70-0x7F` whole. Its own
`cond_true()` already returned 0 for `4'hb`, so removing the two carve-outs was
the entire fix: a branch that is never taken, two and three bytes long.

`verif/v60/tb_v60_audit.sv` asserted the old behaviour — "reserved primary
opcodes 6B/7B take vector 8 and push PC/PSW" — and now asserts the new one
through `check_never_branch()`: the core falls through by two and three bytes,
pushes nothing, and does not reach the vector-8 handler. Its `check_clrtlb_length`
test had to change too, and that is worth recording: it filled a six-byte
CLRTLB immediate with `6B` bytes on the grounds that "each immediate byte would
itself be a reserved primary opcode if the operand were incorrectly skipped".
With `6B` no longer reserved, a short skip would have decoded two never-taken
branches and arrived at the same HALT at the same PC — the test would have
passed vacuously. The filler is zero bytes now, which are HALT, so a short skip
halts early and the PC check catches it.

The two opcodes are back in this bench's executed program, which is only
possible because both sides now agree about them.

## What else came out of building it

- **`s32_v60.sv` traps two legal opcodes.** Resolved above — that is what the
  bench was built to find, and it found it on its first run.
- **`fmt_base_bytes` was dead.** `v60_fmt_pkg` carried a helper that added the
  opcode byte, the second base byte and the format's displacement, and nothing
  in the tree called it — which is how a mutation to it passed every bench.
  Removed.
- **`insn_table.py`'s cross-check was not running.** It resolved
  `docs/v60/v60_operand_access.csv` relative to the *working directory*, and
  the generator is run from `tools/v60x/`. From there the file did not exist,
  `cross_check()` returned "skipped", and the tool printed `0 cross-checked`
  underneath a pass. The path is relative to the script now, and the tool
  fails outright if the cross-check did not run — the same lesson as the
  20-clock reset assertion in `v60_biu` that could not fire.

## What it does not claim

Nothing about semantics. Two decoders can agree about where an instruction ends
and disagree about everything it does, and this bench would not notice — that
is what `tb_v60_seq` and `tb_v60_muldiv` are for. What it settles is the one
question both sides answer for every instruction, unambiguously, without either
of them having to implement the same operation.
