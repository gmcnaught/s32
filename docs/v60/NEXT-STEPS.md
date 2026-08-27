# What is open, in the order it is worth doing

**Rewritten 2026-08-27**, after the three items this file opened with — control
flow, wiring `v60_exc` in, and the three recorded gaps — all closed. What they
were and what closing them turned up is at the bottom, under *What this
replaced*. `rtl/cpu/v60x/README.md` is the boundary statement: what is
verified, against which page, by which bench. This file is the other half.

The rules every item below inherits, from that README: a claim carries the page
it came from, every bench runs under both simulators, every bench is
mutation-checked and what survives is closed rather than noted, and anything not
from a page is marked at the point of decision.

---

## 1. The two return pairs

`BSR` and `JSR` pair with `RSR`, which is implemented. The other two pairs are
not, and each is a pair because neither half is useful alone:

- **`CALL` and `RET`**, which pass the argument pointer: `RET`'s operation is
  `tmp1 <- num ; tmp2 <- [SP+] ; AP <- [SP+] ; SP <- SP + tmp1 ; PC <- tmp2`
  (§7). `AP` is R30 in the register file already; what is missing is the
  sequencing and `CALL`'s side of the frame.
- **`RETIU` and `RETIS`**, which restore the PSW as well as the PC and are how
  a handler returns. They are the other end of `v60_exc`, which pushes exactly
  the frame they pop: the return PC on top, the PSW under it, the parameters
  under that, and the parameter count in the exception code word says how many
  to discard — "it is used by exception handlers to determine the number of
  bytes to discard from the stack following the processing of the exception".

`RETIU` and `RETIS` differ in which stack they return to, so they also need
the register file's stack switch, which `v60_seq` already drives on the way
*in*.

## 2. The externally raised exceptions

`v60_biu` has `ready_n`, `bmode` and `hldrq_n`, and no `berr`, `int` or `nmi`.
The bus error, NMI and maskable interrupt families therefore cannot be driven
end to end whatever the units above them do — `v60_exc` takes `is_interrupt`
and `disable_ie` as inputs precisely so the behaviour could be built and
benched before the pins exist, and `tb_v60_exc` does both.

Adding them is a bus-unit change and a sequencer change: a pin, the
recognition point (between instructions, which is where `v60_seq` already
raises), and the vector. System 32 raises interrupts, so nothing in this tree
can run that machine's code until this is done.

## 3. The rest of the instruction set

In rough order of how much machinery each needs:

- **`MUL`, `MULU`, `DIV`, `DIVU`, `REM`, `REMU` and the `X` forms.** Not one
  cycle of combinational logic, so they need a multi-cycle unit and a sequencer
  state to hold it. The generated table already reports `ALU_NONE` for them and
  `v60_seq` stops rather than inventing an answer.
- **The bit-string group.** All ten subops are read (see
  `docs/v60/INSTRUCTION-DECODE.md`) and none is executed. They are the first
  instructions here that are *interruptible mid-execution* — "to minimize the
  interrupt latency time, the ORNBS instruction ..." — which is a sequencer
  property, not an ALU one.
- **The floating point group**, the MMU, task and context switching, address
  traps and emulation mode. Each is its own subsystem.

## 4. A doubleword operand is a register PAIR

`v60_ea` takes `rn_val` as 32 bits and warns when it is asked for an
eight-byte register-direct operand, because "a doubleword operand is a
register pair, low register first" (§3). `v60_regfile` already has `ra_pair`
for this; nothing uses it. It matters for `MOV.D`, the `X` multiplies and
divides, and the doubleword floating point.

---

## Two things not on the list, and why

**Synthesis.** Nothing in `rtl/cpu/v60x/` has been through Quartus. Area and
timing are unknown, on a core whose *existing* V60 already sits at the edge of
closure and whose placement marginality is an open problem. Any claim about
whether this could replace `rtl/cpu/v60/` starts with a fit, not with more RTL.

**A co-simulation oracle.** The clean-room decoder can consume the same
instruction stream as the shipping core and assert instruction boundaries and
lengths against it. That needs no new RTL, carries no integration risk, and
tests `s32_v60.sv` in a way nothing currently does — the cheapest useful thing
on this page, and the only one that pays off for the shipping core rather than
for this one.

---

## What this replaced

Three items, all closed, and each one turned up something that was not the
work itself:

**Control flow** — `Bcc`, `BSR`, `JMP`, `JSR`, `RSR`, `DBcc`, `TB`, with
`docs/v60/CONTROL-FLOW.md` for the pages. Two defects in already-benched code
came out of it: an addressing mode's register writeback was read only in the
cycle the access *finished*, and `v60_ea` raises it when the access *starts*,
so every mode that reached memory lost it; and `ea_addr_only`, once set by a
`JMP`, was never cleared, so the next instruction computed its destination
address and never wrote to it.

**`v60_exc` wired in** — three Instruction Exceptions raised instead of
stopped on, through `v60_dmux` rather than a third arbiter port, with
`docs/v60/EXCEPTIONS.md` for the vectors, codes and frame. `v60_exc` turned
out to push `param1` for a single-parameter frame, which no bench had asked
for.

**The three recorded gaps** — the shift group (`docs/v60/SHIFTS.md`), the
extending moves, and the five PSW fields of the recognition sequence. The
first turned up an instruction-table defect: the shift group's two operand
widths were the wrong way round, which nothing could notice while nothing
executed them. The last two turned up a habit worth keeping: **when a page in
one book is illegible, look for the same material in the other one before
recording it as unread.** Three digits of the recognition sequence and three
bit-string subops were both recorded as unreadable, and both were printed
plainly in the other book.
