# Mid-instruction interruptibility: what the pages require, and what it would cost

A scoping study. No RTL was changed. Its purpose is to decide whether the
work is safe to authorise, so the parts the pages do **not** settle are marked
as such rather than resolved by the most plausible reading — that gap is
itself part of the answer.

Line numbers are as of the working tree while tranche two lands, and
`v60_seq.sv` is under active edit — the **construct** named beside each line is
the durable reference if a number has drifted.

Throughout: **Page** = quoted or directly stated in a source held under
`docs/reference/`. **Inferred** = a narrow conclusion from those quotes, with
the reasoning shown. **Unknown** = not in either book.

---

## 0. Scoping correction: it is eighteen instructions, not thirteen

**Page.** Two different sentences carry interruptibility, and counting only
one of them undercounts the group.

**Sentence A — "To minimize the interrupt latency time …"** appears on
**thirteen** pages:

`MOVBS` `NOTBS` `ANDBS` `ANDNBS` `ORBS` `ORNBS` `XORBS` `XORNBS` `SCH0BS`
`SCH1BS` — the bit-string group — and `CMPC` `CMPCF` `CMPCS`.

**Sentence B — "This instruction is interruptable and resumable with registers
R28 and R27 …"** appears on **five more**:

`MOVC` `MOVCF` `MOVCS` `SCHC` `SKPC`.

So the affected set is **eighteen**. The five in sentence B are the ones
`docs/v60/CHARACTER-STRING.md` already recorded, and they carry the *stronger*
wording — "interruptable and resumable" as a property of the instruction,
where sentence A describes a latency optimisation. Nothing in either book says
the two mean different things, and both name R28/R27 as the mechanism, so
**Inferred:** they are one property stated twice. Any budget for this work
should be sized on eighteen.

---

## 1. What the pages require

### The sentence, in full

**Page**, `CMPC` §7 (the same paragraph appears verbatim on all thirteen
sentence-A pages, with only the mnemonic changing):

> To minimize the interrupt latency time, the CMPC instruction allows the
> service of **interrupts and faults following the completion of a bus cycle**.
> After servicing the interrupt or correction of the fault condition,
> **instruction execution continues from the point of interruption**.

**Page**, `MOVC` §7 (sentence B, all five):

> This instruction is **interruptable and resumable** with registers R28 and
> R27 used to maintain the source and destination addresses respectively.
> Following the execution of the MOVC instruction, these registers contain the
> address of the next logical character to be transferred.

**Page**, `MOVBS` §7, which says the same thing about the registers during
execution rather than after it — and this is the one that matters most:

> **During the execution of the MOVBS instruction, registers R28 and R27
> contain pointers to the bytes within the source and destination bit strings
> to be processed next.**

Two things are pinned by those three quotes:

1. **The boundary is the completion of a bus cycle** — not an instruction
   boundary, and not an arbitrary clock.
2. **The progress lives in R28 and R27**, and it is live there *during*
   execution, not only at the end.

### The state that must be preserved is architectural, not hidden

**Page**, §3, General Purpose Registers:

> In addition to the AP, FP, and SP registers, **other general purpose
> registers are required by string instructions to allow the instruction to
> \[be\] resumed following an interrupt or exception. In this case, registers
> are reserved for use starting from R28 and allocated in a downward
> direction.**

That is the architecture stating outright that the resume state is *general
purpose registers*, allocated R28, R27, R26, …, and nothing else. Across all
eighteen pages the only registers ever named are **R28**, **R27** and **R26**,
and R26 is only ever the fill or stop **character** — an input, never
progress.

### The exception frame confirms it: nothing else is saved

**Page**, §8:

> The value of the PC placed on the stack varies depending on the type of
> exception as follows:
> • **An exception during the execution of an instruction stacks the PC of the
>   instruction causing the exception (Current PC).**
> • An exception following the execution of an instruction stacks the PC of
>   the instruction immediately following the instruction which caused the
>   exception (Next PC).

The frame is `PC`, `PSW`, and — depending on the exception — a code word and
parameters. **There is no microstate word.** So a mid-instruction exception
stacks the address of the interrupted instruction itself, and `RETIS` pops it
and re-enters *that same instruction*.

### Answering the crux question

The lead's question was: *does the V60 resume mid-instruction, or restart from
a saved intermediate state held in registers?*

**Inferred, and the inference is tight:** it **re-executes the instruction
from its own Current PC**, with the architectural working registers as the
resume point. Three page facts force it and nothing contradicts them:

- the frame carries the Current PC and no microstate (§8);
- the working registers exist explicitly "to allow the instruction to be
  resumed" (§3);
- they hold the byte "to be processed next" *during* execution (`MOVBS` §7).

There is a fourth supporting fact. **Page**, §3, PSW bit 26:

> **IP** — The IP (instruction pending) flag indicates whether or not an
> instruction has been interrupted and should be resumed.
> IP = \[0\] no, instruction pending / IP = 1 instruction pending

A re-entered instruction needs to know it is a continuation rather than a
fresh start, and `PSW.IP` is the bit that tells it — carried through the
exception frame like every other PSW bit.

And a fifth, from §9, which distinguishes the two cases explicitly:

> The other exceptions that can occur can be classified into those which
> **restart or resume** instruction execution and those which occur after the
> execution of the instruction is completed.

> When an exception occurs that requires the instruction to \[be\] restarted or
> resumed, the TP field in the PSW image pushed onto the stack is cleared and
> the instruction trace exception is delayed until the instruction completes
> execution.

So `PSW.TP` handling is a second piece of machinery that already assumes
re-entry.

**This is the load-bearing conclusion for the whole study: the architecture
does not require the machine to freeze and thaw an in-flight bus access. It
requires the instruction to stop cleanly at a bus-cycle boundary, leave its
progress in R28/R27, and be re-run.**

### What the pages do NOT settle — and this is the part that decides safety

**Unknown 1 — the residual count.** R28/R27 hold *where*. Nothing holds *how
much is left*. `CMPC`'s lengths are its `ext`/`ext'` extension fields, read
from the instruction stream; `MOVBS`'s `blen` likewise. On re-entry the
instruction re-reads the **original** lengths from its own encoding and finds
R28/R27 part-way through — and no page says how the remaining count is
reconstructed. Deriving it as `end − R28` requires the original start address,
which is exactly what R28 has overwritten. **No register beyond R28/R27/R26 is
ever named in any of the eighteen pages, and R26 is a character.**

**Unknown 2 — operand re-evaluation on resume.** Re-entering the instruction
means re-decoding its operands. Several of the eighteen permit `[Rn+]` and
`[-Rn]` on their string operands (`MOVC`'s table marks both `O`). Re-executing
would step `Rn` a second time. Either the resumed instruction skips operand
evaluation and uses R28/R27 directly — in which case Unknown 1 bites harder,
because the lengths come from the same decode — or it re-evaluates and the
autoincrement side effect happens twice. **No page describes either.**

**Unknown 3 — who writes and clears `PSW.IP`.** §3 defines the bit. Nothing
in either book says the hardware sets it on a mid-instruction exit, or clears
it on completion, or what a resumed instruction does if it finds it clear.

**Unknown 4 — nesting.** If a resumed instruction is interrupted again, R28/R27
are simply overwritten with the newer progress, which is fine — but nothing
says what happens if a handler *modifies* R28/R27, or whether an instruction
that was never interruptible can find `PSW.IP` set.

These four are not academic. **Unknown 1 alone means a conformant
implementation cannot be written from the pages held.** That is the finding
that should govern whether this work is authorised now.

---

## 2. What would break here

### The invariant, and where it is written down

**`rtl/cpu/v60x/v60_dmux.sv`**, header:

> It is a mux and NOT a third port on `v60_bus_arb`, which is a decision the
> execution-stage plan records and this module is the reason for: `tb_v60_pfu`
> asserts continuously that bus ownership does not change between BCY* and the
> ack, and that an ack reaches exactly one master. A third arbiter port would
> put that proof back on the table for nothing — **the two masters here are
> never live at once, because an exception is raised between operand accesses
> and never during one.**

### The four things a mid-instruction exception entry would invalidate

**B1 — `v60_dmux`'s unconditional priority steal.**
`v60_dmux.sv:78`, `always_comb begin if (b_req) begin dx_req = 1'b1; dx_addr =
b_addr; … end else begin dx_req = a_req; … end end`.

`b_req` (the exception unit) wins **combinationally and absolutely**. If an
operand access were in flight — `a_req` high, waiting on `dx_done` — and
`b_req` rose, `dx_addr`, `dx_nbytes`, `dx_we` and `dx_wdata` would all change
under `v60_dxu` mid-access, and `a_done = dx_done && !b_req` would suppress the
address unit's completion while `b_done` fired. The in-flight operand access is
not aborted; it is *silently redirected*.

What it buys: a nine-line combinational mux instead of an arbiter, with no
state, no fairness question and no ownership register.

`v60_dmux` already exposes `overlap = a_req && b_req` "for a bench to hold the
invariant to", so the module was written expecting this question.

**B2 — `v60_bus_arb`'s single-bit owner.**
`v60_bus_arb.sv:103`, `own_pfu`, and `d_ack = biu_ack && !own_pfu` /
`p_ack = biu_ack && own_pfu`.

The arbiter has exactly **two** ports — data and prefetch — and ownership is
one bit. The exception unit is not a port: it reaches the bus *through*
`v60_dmux` and `v60_dxu`, inside the `d_*` port. Making `v60_dmux` a real
arbiter port turns `own_pfu` into a two-bit owner and changes the derivation of
both acks and of `biu_lock` (currently `assign biu_lock = d_lock;`, a single
source).

What it buys: the grant-hold logic at `:85`–`:95` is provably correct against
one sentence — *"there is no way to abort a bus cycle, and the ack has to reach
whoever asked for that one"* — and the correctness argument is a two-case
analysis rather than an N-case one.

**B3 — `tb_v60_pfu`'s two continuous assertions.**
`verif/v60x/tb_v60_pfu.sv:149`–`:173`, an `always @(posedge clk)` block holding
two properties over the whole run:

```
if (in_cycle && (own_pfu !== own_at_start))   -> "the bus changed owner while a cycle was running"
if (biu_ack) begin
    if (d_ack && p_ack)                       -> "one ack reached both masters"
    if (d_ack && own_pfu)                     -> "a prefetch cycle acked the data unit"
    if (p_ack && !own_pfu)                    -> "a data cycle acked the prefetch unit"
end
```

Every one of the four is written in terms of `own_pfu` as a **boolean**. A
third master makes all four ill-typed, not merely weaker.

What they buy: `tb_v60_pfu.sv:410`–`:413` says it — *"The arbiter's two
invariants — ownership does not change between BCY\* and the ack, and an ack
reaches exactly one master — are about the GRANT and hold over whatever status
is on the pins"* — i.e. they are the reason a new bus-cycle *kind* (the
interrupt acknowledge) could be added without re-proving anything.

**B4 — `v60_seq`'s single recognition point.**
`v60_seq.sv:1213`, `S_IDLE`, comment: *"The recognition point. 'At the
completion of the current instruction' (NMI, p.3.237) is here, which is also
where the three instruction exceptions are raised from — so an externally
raised one is taken instead of starting the next instruction, and **the frame's
PC is the one that has not run yet**."*

That last clause is the interesting one. `S_IDLE` raises with the **Next PC**
semantics, because at `S_IDLE` the previous instruction has retired and `pc`
already points at the next. §8 requires a mid-instruction exception to stack
the **Current PC**. So even the *existing* recognition point is the wrong shape
for a resumable exception, independently of any bus question.

What it buys: one place in a 2 760-line module where `berr_r`, `nmi_pending`
and `int_pending` are tested, in Figure 8-2's priority order, with `run &&
!stopped` gating and `HALT` parking on the same three tests.

---

## 3. What it would cost

### Option (a) — break the invariant: `v60_dmux` becomes an arbiter port

**Scope:** `v60_dmux.sv` (rewritten as a requesting port rather than a mux),
`v60_bus_arb.sv` (three-way owner, ack derivation, `biu_lock` source),
`v60_seq.sv` (exception entry from inside operand states), `tb_v60_pfu.sv`
(all four continuous assertions retyped), plus whatever holds the new
ownership proof.

**What it does to `tb_v60_pfu`:** invalidates all four assertions as written.
They would have to be re-expressed over a 2-bit owner, and the "an ack reaches
exactly one master" property becomes a three-way mutual exclusion — a strictly
larger proof obligation, on the module the tree treats as its bus foundation.

**What the architecture says about it:** nothing requires it. §8's frame has no
microstate; the boundary the pages name is *"following the completion of a bus
cycle"*, which is a point at which no cycle is in flight. **Option (a) solves a
problem the architecture does not pose.**

**Verdict: do not do this.** It is the largest change, it weakens the strongest
proof in the tree, and it buys a capability the pages never ask for.

### Option (b) — keep the invariant: check at an iteration boundary

**Scope:** `v60_seq.sv` only, plus a new iterating unit if the string engine is
factored out (see option (c2) below). No change to `v60_dmux`, `v60_bus_arb`,
`v60_biu`, `v60_dxu` or `tb_v60_pfu`.

**Shape:** an interruptible instruction, at its own iteration boundary — after
one element's accesses have completed and before the next begins — tests the
same three conditions `S_IDLE` already tests. If any is set it:

1. writes its progress to R28/R27 through the normal register writeback,
2. sets `PSW.IP`,
3. **does not advance `pc`**, and
4. returns to `S_IDLE`.

`S_IDLE` then raises with `pc` still pointing at the interrupted instruction,
which is §8's Current PC — so the *only* change to the existing exception path
is that `pc` is not advanced first. On `RETIS` the same instruction is
re-fetched, sees `PSW.IP`, and continues from R28/R27.

**What it does to `tb_v60_pfu`:** **nothing.** No cycle is in flight at the
boundary, `a_req` is low, `b_req` rises with the mux idle, `own_pfu` never
changes mid-cycle, and every one of the four assertions holds unmodified. This
is the whole argument for it.

**What the architecture says about it:** this *is* what the architecture
describes. The page's own words name the boundary — *"following the completion
of a bus cycle"* — and §3 names the state. Option (b) is a transcription of the
pages rather than a design.

**Verdict: this is the one to build**, subject to the Unknowns in §1.

### The cost that is actually load-bearing

Neither option's RTL is the expensive part. **The expensive part is Unknown 1.**
Whichever mechanism carries the interrupt out of the instruction, the resumed
instruction must know how much work is left, and the pages held do not say how
it knows. Any implementation must therefore invent one of:

- **an extra hidden register** holding the residual count — which contradicts
  §3's "registers are reserved … starting from R28 and allocated in a downward
  direction", because a hidden one is not a GPR and would not survive a context
  switch that `LDTASK`/`STTASK` save R0–R30 for;
- **R26 (or R25) as a count register** — consistent with §3's "downward
  direction" and with nothing else, since R26's only documented role is the
  fill/stop character and using it for both is impossible on `MOVCF`/`CMPCS`;
- **deriving the residue from R28 and a re-decoded operand** — which needs the
  original start address that R28 has overwritten, unless operand
  re-evaluation is *also* defined (Unknown 2).

None of the three is supported by a page. Building option (b) without settling
this means picking one and living with a silent divergence in the exact case
the feature exists for.

### What I cannot determine

I have not estimated person-time and will not: the RTL shape is clear but the
verification is not, because the bench would have to inject an interrupt at a
chosen bus-cycle boundary inside a multi-element instruction and check
resumption — and there is no such harness in `verif/v60x/` today. The nearest
precedent is `v60_muldiv`'s 32-step iteration, which is *not* comparable: it
holds no bus and cannot be interrupted, so `S_MD`'s wait proves nothing about
this.

---

## 4. A third option, and a fourth

### (c1) — implement the eighteen as non-interruptible, and say so

The pages' sentence A is explicitly a **latency** optimisation: *"To minimize
the interrupt latency time…"*. The architectural consequence of not doing it is
that a long string operation delays interrupt service — observable as timing,
not as a wrong result, **provided no fault occurs during the instruction.**
That proviso is the catch: sentence A covers "interrupts **and faults**", and a
page fault mid-`MOVBS` is a correctness matter, not a latency one. On a
physical-address machine with no MMU (`docs/v60/MMU-AND-TASKS.md`: `SYCW.VM`
is never consumed in this tree) the only fault available is a bus error, which
`v60_seq` already abandons the instruction on.

**Cost: near zero. Risk: a documented, page-visible divergence.** It is the
honest option if the answer to "should this be authorised now" is "not yet",
and it is strictly better than starting option (b) on an unsettled contract.
Precedent exists: the tree stops with `STOP_NO_ALU` rather than inventing
answers. The difference is that non-interruptibility would *not* stop — it
would silently do the right thing for every input this target produces.

### (c2) — a string unit that owns no bus master

An implementation shape rather than an architecture. Factor the iteration into
a unit that drives the **existing** `a_*` path through `v60_ea`/`v60_dxu`,
exactly as `v60_muldiv` iterates without touching the bus, and let `v60_seq`
own the boundary check. Then:

- `v60_dmux`, `v60_bus_arb`, `v60_biu` and `tb_v60_pfu` are untouched;
- the interrupt test lives in one new sequencer state, next to the `S_MD` wait
  that already exists;
- the eighteen instructions share one engine rather than eighteen paths.

This is how I would *build* option (b), and it is worth naming separately
because it bounds the blast radius to two files.

### The option I would reject as a third way

Holding the exception request until the current bus cycle acknowledges — a
one-bit gate in front of `b_req` — looks like a cheap way to have mid-access
exceptions without breaking B1/B3. It is not a third option: it is option (b)
with the boundary moved from "between iterations" to "between bus cycles", and
**the pages put the boundary in exactly that place** (*"following the
completion of a bus cycle"*). The two converge. What it does not do is solve
Unknown 1, which is the actual blocker.

---

## 5. Recommendation

**Inferred, and stated as a recommendation rather than a page fact:**

1. **Do not authorise option (a).** The architecture does not describe it, it
   weakens `tb_v60_pfu`'s continuous assertions — the strongest proof in the
   tree — and it solves a problem the pages do not pose.
2. **Do not start option (b) yet.** Its RTL is small and its bus behaviour is
   safe, but **Unknown 1 means no conformant implementation can be derived
   from the sources held.** Starting it would mean choosing a residual-count
   mechanism that no page supports and then verifying against that choice,
   which produces confidence in the wrong thing.
3. **Ship the eighteen as non-interruptible (c1) and record it**, in the same
   place `docs/v60/CHARACTER-STRING.md` already records that
   `s32_v60.sv` does the same. That unblocks tranche four now at near-zero
   risk on this target, where no MMU exists and the only fault is a bus error
   the sequencer already abandons on.
4. **Reopen it if a source appears that settles Unknown 1.** The specific thing
   to look for is a statement of what a resumed string instruction uses as its
   remaining length — a register beyond R28/R27, or a rule for re-deriving it.
   The Programmer's Reference PDF is not held (only its OCR), and §7's
   Description blocks are where such a sentence would live, so **a plate of any
   one of the eighteen pages could close this.** That is a cheap, bounded
   next step and it should happen before any RTL does.

The one-line answer to "is this work safe to start": **the bus-invariant
question is settled and benign — the architecture's own boundary is the one the
invariant already protects — but the resumption contract is not settled at all,
and that is what makes it unsafe to start today.**
