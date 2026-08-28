# What is open, in the order it is worth doing

**Rewritten 2026-08-27**, after the three items this file opened with — control
flow, wiring `v60_exc` in, and the three recorded gaps — all closed, and
updated the same day when item 2 below closed too. What they
were and what closing them turned up is at the bottom, under *What this
replaced*. `rtl/cpu/v60x/README.md` is the boundary statement: what is
verified, against which page, by which bench. This file is the other half.

The rules every item below inherits, from that README: a claim carries the page
it came from, every bench runs under both simulators, every bench is
mutation-checked and what survives is closed rather than noted, and anything not
from a page is marked at the point of decision.

`docs/v60/GOALS.md` is this list in the form the work is started in — four
paste-ready goal texts, each carrying its own pages and acceptance criteria.
Its order differs from this file's on purpose, and its Goal 1 — item 2 below,
the externally raised exceptions — is **done**; see *What this replaced*.

---

## 1. What is left of the return pairs

All three pairs are **done** — see *What this replaced*. What is left of them
is what their own pages say they also do and this tree has nothing to do it
with: both `RETIS` and `RETIU` "check for the occurrence of the Asynchronous
System and Asynchronous Task Traps", and there is no AST or ATT here. That is
part of the asynchronous-trap subsystem in item 3, not a gap in the pair.

## 2. What is left of the externally raised group

The bus error, NMI and maskable interrupt families are **done** — see *What
this replaced*. Four things around them are not, each small and each with its
page:

- **The bus freeze interrupt**, vector 1. `v60_biu` has no `BFREZ` pin, and the
  BFREZ side of `RT/EP*` — "restart instruction execution (RT/EP* = 1) or cause
  an exception (RT/EP* = 0)" on release, p. 3.237 — is documented and
  unreachable.
- **The double bus error.** "When a bus error involves the interrupt stack or a
  second bus error occurs during the processing of the initial bus error ...
  the processor will halt" (§8). Nothing here halts, and the machine fault
  acknowledge status the databook says accompanies it (p. 3.234) is never
  issued. It needs a halt state, which is also what `HALT` and the halt
  acknowledge status would want.
- **NMI's own masking.** "Additional non-maskable interrupts will not be
  acknowledged until the processing of the first NMI completes and the RETIS
  instruction is executed" (p. 3.271). It needs RETIS, which is item 1.
- **`BLOCK*`**, which "is also asserted for the duration of an interrupt
  acknowledge bus cycle" (p. 3.236). Its other users, TASI and CAXI, are not
  implemented, so the pin would be half of itself.

## 3. The rest of the instruction set

**Tranche one is done** — all twenty-three of it, 2026-08-28. `NOP` `HALT`
`BRK` `BRKV` `TRAP` `TRAPFL` `GETPSW` `UPDPSW.H` `UPDPSW.W` `LDPR` `STPR`
`MOVEA` `SETF` `INC` `DEC` `RVBIT` `RVBYT` `TEST1` `SET1` `CLR1` `NOT1`
`IN` `OUT`, each with its pages cited at the point of decision, each
mutation-checked, both simulators. `docs/v60/TRANCHE-ONE.md` and
`docs/v60/BREAK-AND-TRAP.md` are the research; what implementing it turned up
that the research did not is in the commit messages and summarised in
*What this replaced*.

Three things it added that later tranches inherit:

- **The privileged register port is wired into `v60_seq`** (`rf_pr_id`,
  `rf_pr_wr`, `rf_pr_wdata`, `rf_pr_rdata`). `LDPR`, `STPR` and `TRAPFL` use
  it; the MMU group in the last tranche will.
- **The I/O address space is reachable.** `v60_ea` takes `io` as an input and
  `v60_dmux` carries `a_io`, so `MRQ*,ST2-ST0 = 1011` appears on the pins and
  `bst_needs_io_recovery()` is no longer unreachable code. Nothing but `IN` and
  `OUT` can produce it.
- **`exc_kind` is three bits and has five values.** `EK_TRAP` was the addition:
  Figure 8-5's Software Traps frame is `EK_INSN`'s shape with the Next PC
  instead of the Current one, and that one difference is load-bearing — a
  software trap returns PAST the instruction and an instruction exception
  returns TO it.

**The rule that governs every remaining instruction that can fault**, learned
here and worth stating once: *the frame decides whether writebacks stand.* An
Instruction Exception carries the Current PC, so the handler restarts the
instruction and nothing may have been committed — which is why `LDPR`'s and
`STPR`'s id checks, the bit group's offset check, `IN`'s port check and
`MOVEA`'s source check all raise at the earliest state that has the value,
before any access. The zero divide, `BRKV` and `TRAP` carry the Next PC, do not
restart, and their addressing-mode writebacks must stand. Same tree, opposite
rules, and the frame is the only thing that says which.

What is left, in rough order of how much machinery each needs:

- **The `X` forms of the multiplies and divides** — `MULX`, `MULUX`, `DIVX`,
  `DIVUX`. The other six are done (see *What this replaced*); these four are
  waiting on item 4 below, because their destination is a doubleword. `DIVX`
  is the one that needs it most visibly: it writes a quotient into the low word
  of its destination and a remainder into the high word.
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

**A co-simulation oracle.** Built — `verif/v60x/tb_v60_cosim.sv`, with
`docs/v60/COSIM.md` for what it found. It is the one item here that paid off for
the *shipping* core rather than for this one.

---

## What this replaced

Three items, all closed, and each one turned up something that was not the
work itself:

**The co-simulation oracle** — the two cores on one instruction stream,
compared on instruction boundaries. It found one divergence on its first run and
it is now closed **in the shipping core's favour of the pages**: opcodes `6B`
and `7B` are Bcc with the "False / Never" condition that p. 3.295 prints and
p. 3.298's row does not exclude, not reserved opcodes. `s32_v60.sv` raised
vector 8 on them — a hole in MAME's dispatch table read as an absent encoding —
and `tb_v60_audit` asserted that it did; both moved. Two things around it were
also wrong:
`fmt_base_bytes` had no caller at all, and `insn_table.py`'s operand-access
cross-check silently did not run when the tool was invoked from the directory
the generator is invoked from.

**The multiplies and divides** — `MUL`, `MULU`, `DIV`, `DIVU`, `REM` and
`REMU` in `v60_muldiv`, with `docs/v60/MULTIPLY-DIVIDE.md` for the pages, and
the Integer Arithmetic Exception as `v60_exc`'s second raise site — the first
that is not a decode failure. Two divergences from MAME came out of it, both
where the pages are explicit and the emulator is not: a divide by zero raises,
and `MUL`'s overflow is a signed fit. And the exhaustive byte sweep passed on
the first run while the word boundaries did not: a shift-add multiplier's
accumulator needs 65 bits, and the defect was invisible at exactly the width
that was checked most.

**The two return pairs** — `CALL`/`RET` and `RETIU`/`RETIS`, on one stack
engine, with `docs/v60/RETURN-PAIRS.md` for the pages. Three of the four claims
`GOALS.md` started them with were wrong, and the pages say so: the count is an
**operand** and not something read out of the frame; `RETIU` and `RETIS` differ
by **privilege** and not by stack; and this file said AP was R30 where RET's own
Description says R29. A table defect came out with them — both RETIs had a word
operand where their pages print a halfword — which is the shift group's defect
for the third time.

**The externally raised exceptions** — `BERR*`, `RT/EP*`, `NMI*` and `INT` on
`v60_biu`, the interrupt acknowledge pair in `v60_exc`, and the recognition
point in `v60_seq`, with `docs/v60/EXCEPTIONS.md` and
`docs/v60/BUS-CYCLE-TIMING.md` for the pages. Three things came out of it that
were not the work:

- **A defect in already-benched code.** `rf_stack_switch` is a registered
  output, so `S_EXC_REQ` sampled R31 a cycle before the switch landed and
  pushed the frame on the stack being switched *away from*. It could not be
  seen while every exception in the tree switched to the entry it was already
  on, which the register file makes a no-op.
- **The databook contradicting itself, and the plate winning.** The `BERR*` pin
  prose says the decision is made "at the rising edge of the T4 state"; the AC
  table's four setup and hold parameters and the p. 3.243 waveform both put it
  on the falling edge. Two renderings with numbers against one sentence.
- **The goal text being wrong about a vector it warned would be.** `GOALS.md`
  said NMI's entry is `+12`, vector 3, *and* said to read the low end of
  Figure 8-2 off the plate before using it. The plate says `+8`, vector 2;
  `+12` is the Serious System Fault, which is where the bus error goes.

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
