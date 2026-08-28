# The next four goals, ready to set

**Written 2026-08-27.** `docs/v60/NEXT-STEPS.md` says what is open and why.
This file says it in the form the work is actually started in: four
self-contained goal texts, each carrying its own pages, its own acceptance
criteria and the standing rules, so none of them depends on the conversation
that produced it.

The order is not the order `NEXT-STEPS.md` lists its items in, and the
difference is deliberate. The return pairs are listed first there because they
finish a group; they gate nothing, since `BSR`/`JSR` already pair with `RSR`.
**Goal 1 is what blocks running System 32 code at all** — that machine raises
interrupts and `v60_biu` cannot receive one. Goal 4 pays off outside this tree
rather than inside it and can run at any point.

---

## Goal 1 — the externally raised exceptions — **DONE**

**Two corrections to the goal text below, left in place rather than edited out
because the second is the reason the first was caught.**

The text says NMI's "SBT entry is +12, so vector 3". It is not. The plate at
databook p. 3.270 prints the vector number in its own column beside the offset,
and reads `+8` / vector **2** for the Non-Maskable Interrupt and `+12` /
vector 3 for the **Serious System Fault**, which is where a bus error goes. The
Programmer's Reference's Figure 8-2 agrees. `docs/v60/EXCEPTIONS.md` carries
the plate reading.

That is exactly what the text's own instruction — *"Read the bus-error and
stack-invalid entries off Figure 8-2 before using them: the low end of that
figure OCRs ambiguously in both books, so check the plate"* — was there to
catch, and it caught it. A goal that says which of its own claims to verify is
worth more than one that is right.

The second: the databook's `BERR*` pin prose says the retry-or-raise decision
is made "at the rising edge of the T4 state", and its own AC table and its own
p. 3.243 waveform plate both put it on the **falling** edge. The plate wins;
see `docs/v60/BUS-CYCLE-TIMING.md`.

What landed: the four pins on `v60_biu`, the interrupt acknowledge pair in
`v60_exc` with the Invalid Interrupt substitution, and the recognition point in
`v60_seq`, with 18 mutations checked and the whole suite green under both
simulators. `docs/v60/NEXT-STEPS.md` item 2 is now what is *left* of the group:
the bus freeze interrupt, the double bus error, NMI's own masking rule, and
`BLOCK*`.

```
Add the externally raised exceptions to the clean-room V60 in
~/MisterFPGA-Projects/s32-v60-cleanroom (branch v60/cleanroom): the NMI*, INT
and BERR* pins on v60_biu, and their recognition in v60_seq.

What the pages give: NMI* is "an active low interrupt input that cannot be
masked ... at the completion of the current instruction, the PC and PSW are
pushed" (databook §1), and its SBT entry is +12, so vector 3. INT is "an
active high interrupt input that can be masked by the IE bit", and when it is
taken "the uPD70616 will perform a pair of back-to-back interrupt acknowledge
cycles. On the second interrupt acknowledge cycle, an 8-bit interrupt vector is
read from the external uPD71059" — BST_INTERRUPT_ACK already exists in
v60_bus_pkg and nothing issues it. BERR* "indicates the presence of a fault in
the current bus cycle and requests a retry", and its family's exception codes
are 0300-031E. Read the bus-error and stack-invalid entries off Figure 8-2
before using them: the low end of that figure OCRs ambiguously in both books,
so check the plate.

Recognition happens between instructions, which is where v60_seq already
raises. An interrupt's frame is the PSW and the PC and nothing else, which
v60_exc already builds. Done when: a bench drives each pin and the handler
runs, INT is held off while PSW.IE is clear and taken when it is set, the
vector comes off the second acknowledge cycle, and tb_v60_pfu's continuous
bus-ownership assertions still hold with a third kind of cycle on the bus.

Follow the rules in rtl/cpu/v60x/README.md. Stop only on an issue you cannot
solve yourself.
```

## Goal 2 — the two return pairs — **DONE**

**Three corrections to the goal text below**, all from the Programmer's
Reference §7 pages for the four instructions, and all recorded in
`docs/v60/RETURN-PAIRS.md`:

1. *"read it off the frame rather than being told"* — no. Both pages print
   `retis count.h.r` / `retiu count.h.r`: the count is an **operand**, and both
   Descriptions say it "allows the interrupt or exception handler to specify
   the number of bytes to be automatically discarded". §8's sentence is about
   what the **handler** does with the frame's count field — it reads it and
   passes it in.
2. *"The two differ in which stack they return to"* — no. Their Operation,
   Condition Codes and Addressing Modes blocks are identical. RETIS's
   Exceptions list begins "Privileged Instruction" and RETIU's does not, and
   that is the whole difference: System against User.
3. The paragraph above this one, and `NEXT-STEPS.md`, disagreed about the
   argument pointer. RET's own Description settles it: **R29**.

A table defect came out with them: `RETIU` and `RETIS` had a word operand where
both pages print a halfword. Nothing could notice while nothing executed them.

What landed: one stack engine under all three pairs, `RETIS`'s privilege check,
the Illegal Data Field check for a return to a more privileged level, 15
mutations checked, and the suite green under both simulators.

```
Implement the V60's two return pairs in ~/MisterFPGA-Projects/s32-v60-cleanroom
(branch v60/cleanroom): RETIU/RETIS, then CALL/RET.

RETIU and RETIS are the other end of v60_exc, which pushes exactly what they
pop: the return PC on top, the PSW under it, then the word holding the
exception code beside the parameter count, then any parameters. The count is
"used by exception handlers to determine the number of bytes to discard from
the stack following the processing of the exception" (§8), so read it off the
frame rather than being told. They restore the PSW as well as the PC, so they
need the register file's stack switch on the way out, which v60_seq already
drives on the way in. The two differ in which stack they return to.

CALL and RET pass the argument pointer, which is R29 (p.3.247). RET's
operation is "tmp1 <- num ; tmp2 <- [SP+] ; AP <- [SP+] ; SP <- SP + tmp1 ;
PC <- tmp2" (§7).

Done when: tb_v60_seq runs an exception handler that returns and the
interrupted program continues, with the stack pointer back where it started;
and a subroutine called with arguments returns and its frame is gone.

Follow the rules in rtl/cpu/v60x/README.md. Stop only on an issue you cannot
solve yourself.
```

## Goal 3 — the multiplies and divides — **DONE** (the six; not the X forms)

The six the goal text names are in `v60_muldiv`; `MULX`, `MULUX`, `DIVX` and
`DIVUX` are not, and the paragraph below says why they would need something
this tree does not have — a doubleword register pair, which is
`docs/v60/NEXT-STEPS.md`'s own item 4. They are still decoded and addressed and
stopped on, which `tb_v60_seq` checks.

What the work found, in `docs/v60/MULTIPLY-DIVIDE.md`:

- **Two divergences from MAME**, both where the pages are explicit. A divide by
  zero **raises** — every one of the four divide pages lists Zero Divide, Table
  8-1 gives it code 1500 and Figure 8-2 puts vector 21 at +84 — where MAME
  leaves the destination alone and does not trap. And `MUL`'s overflow is the
  **signed** fit its page describes, where MAME's test is an unsigned one that
  reports overflow for `MUL.W -1, 1`.
- **The exhaustive byte sweep passed and the word boundaries did not.** A
  shift-add multiplier's accumulator needs 65 bits, and the missing one was
  invisible at exactly the width that was checked most.

The first execution unit here that is not one cycle of combinational logic,
and the first exception raised by something other than a decode failure.

```
Add MUL, MULU, DIV, DIVU, REM and REMU to the clean-room V60 in
~/MisterFPGA-Projects/s32-v60-cleanroom (branch v60/cleanroom).

These are not one cycle of combinational logic, so they need a unit with a
busy/done handshake and a sequencer state that waits on it -- v60_alu stays
combinational. The generated table already reports ALU_NONE for them and
v60_seq stops rather than inventing an answer, so the table is where they get
switched on. The X forms (MULX, MULUX, DIVX, DIVUX) produce a doubleword,
which is a register PAIR, low register first (§3): v60_regfile has ra_pair and
nothing uses it, and v60_ea only warns when asked for one.

A zero divide is the Integer Arithmetic Exception -- vector 21, which BRKV's
page and Figure 8-2's +84 confirm each other on -- with its own code from the
Arithmetic Exceptions group. That is a second raise site for v60_exc and the
first that is not a decode failure.

Done when: byte width is checked exhaustively against integer arithmetic in
the bench (as ADD and SUB are), halfword and word at their boundaries, the
signed/unsigned pairs disagree where they should, and a divide by zero reaches
its handler through v60_exc.

Follow the rules in rtl/cpu/v60x/README.md. Stop only on an issue you cannot
solve yourself.
```

## Goal 4 — the co-simulation oracle

The cheapest thing on the list, and the only one that pays off for the
*shipping* core rather than for this one.

```
Build the co-simulation oracle described in docs/v60/NEXT-STEPS.md in
~/MisterFPGA-Projects/s32-v60-cleanroom (branch v60/cleanroom): feed the same
instruction stream to rtl/cpu/v60/s32_v60.sv and to the clean-room decoder,
and assert that they agree on instruction boundaries and lengths.

It needs no new RTL and carries no integration risk, and it tests s32_v60.sv
in a way nothing currently does. Where they disagree, the databook page
decides: report each disagreement with the opcode, both lengths, and the page,
and do not "fix" either side without one.

While there: tools/v60x/insn_table.py resolves the operand-access CSV relative
to the working directory, so a hand-run from tools/v60x/ silently skips its
66-row cross-check and still prints a pass. Make the path relative to the
script.

Follow the rules in rtl/cpu/v60x/README.md. Stop only on an issue you cannot
solve yourself.
```

---

## What is deliberately not a goal yet

**Synthesis**, because area and timing on this tree are unknown and any claim
about replacing `rtl/cpu/v60/` starts with a fit rather than with more RTL.
**The bit-string group, the floating point group, the MMU, task and context
switching, address traps and emulation mode**, each of which is its own
subsystem. `NEXT-STEPS.md` carries the reasoning for both.
