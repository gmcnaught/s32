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

## The one divergence, and what to do about it

**Opcodes `6B` and `7B`.**

The clean-room table decodes them as Format IV branches. The databook's row for
Bcc is `011 b cccc` (p. 3.298) with no exclusion, and the Condition Encodings
table on p. 3.295 prints `1011` as a real condition — "False / Never" — so they
are two and three bytes long and never branch.

`s32_v60.sv` raises the reserved-opcode exception on both, and says why in its
own source:

> `0x6B/0x7B are holes in MAME's authoritative primary dispatch table, not`
> `branch-condition encodings.`

A dispatch table with no entry for a branch that can never be taken is not the
same statement as an encoding that does not exist, and NEC's two tables both
print one.

The bench measures the clean-room side, quotes the shipping side, and reports it
as `KNOWN` rather than failing: it is a disagreement about what an encoding
*means*, which no length test can settle. It is recorded here so that neither
side is "fixed" against the other without a page.

The first run of this bench found it, with those two opcodes in the executed
program — they were chosen precisely because a never-taken branch is what a
length test wants. They are out of the program now, because the shipping core
branches to a handler on them and a straight-line comparison cannot survive
that.

## What else came out of building it

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
