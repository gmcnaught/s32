# Tranche two: PUSH, POP, PUSHM, POPM, PREPARE, DISPOSE, XCH, CHLVL, TASI, CAXI

Ten instructions that between them want four things this sequencer does not
have: a register-list loop, a two-destination write, a bus lock, and an
execution-level change. What each one actually does, and which of the four it
really needs.

Sources: databook pp. 3.296, 3.298, 3.299 for the summary rows, p. 3.293 for
the formats, **p. 3.236** for `BLOCK*`, **p. 3.270** for the vectors and
**p. 3.272** for the exception codes — the last three read on the plate;
Programmer's Reference §7 for the per-instruction pages, §3 for the register
set and the PSW, §8 for the exception frames. Summary exception numbers are
decoded with `docs/v60/INSTRUCTION-SUMMARY-LEGEND.md`, **including its caveat
on entry 2**, which bites once here.

**Status: all ten implemented, 2026-08-28.** This file is the research that
preceded them and is left as written. Three things implementation settled or
corrected, recorded at the point of decision in the RTL rather than edited in
above:

* **`CHLVL`'s operand widths were `(1, 4)` in `insn_table.py`; both are bytes.**
  The zero-extension to word length is a property of the push, not of the
  operand fetch.
* **The `XCH` format disagreement is now recorded** in `DISAGREEMENTS` rather
  than left silent — the databook prints `I, II` and the Reference `Format I`.
* **Whether a failing `CAXI` issues its write cycle is not settled by any page**
  and is now an explicit decision: it does, so the bus pattern stays
  read-modify-write either way.

The interlock discussion in §"Is anything short of adding the pin faithful?"
was acted on in full: the pin exists *and* `v60_bus_arb` holds the prefetch
unit off across the gap, which is the half that actually makes it indivisible.

---

## A format-letter problem across the whole stack block

The encodings are confirmed and agree with `tools/v60x/insn_table.py`. The
*format letters* do not, and the disagreement is systematic.

| | p. 3.298 / p. 3.296 prints | Programmer's Reference prints | opcode has a trailing `-` |
|---|---|---|---|
| `PUSH` | II | **Format III** | yes |
| `POP` | II | **Format III** | yes |
| `PUSHM` | II | **Format III** | yes |
| `POPM` | II | **Format III** | yes |
| `PREPARE` | II | **Format III** | yes |
| `DISPOSE` | V | Format V | no |
| `XCH` | I, II | **Format I** | no |
| `CHLVL` | I, II | Format I, II | no |
| `TASI` | III | Format III | yes |
| `CAXI` | I | Format I | no |

Two independent reasons the Reference wins on the first five:

1. **The trailing `-`.** `insn_table.py`'s own header states the rule —
   "Format III opcodes occupy bits 7:1, so both byte values with bit 0 set and
   clear belong to the same instruction". p. 3.293 draws Format III as
   `[mod] [op | m]` with `op` in bits 7:1 and the addressing-mode bit `m` in
   bit 0; Format II's `op` is a full eight bits. A row printed `1110111-` is a
   seven-bit opcode plus a don't-care, which is Format III's shape and cannot
   be Format II's. The plate's own opcode column contradicts its own format
   column, on the same row.
2. **`TASI` on p. 3.299 prints `1110000-` and format `III`** — the same shape,
   correctly labelled, one page later. So the notation is not being used
   loosely; the stack block's column is wrong.

`XCH` is a smaller and less certain case. p. 3.296 prints `I, II`; the
Reference prints a clean, undamaged `Format I` line. It is coherent either way,
but `CAXI`'s page says of *its* near-identical shape "This instruction is not
allowed to use Format II and furthermore, the Format I direction field must be
zero", and `XCH` has the same reason to forbid it — its first operand must be a
register (below), and Format II is the encoding that gives operand 1 a full
`mod` field. Recorded as a discrepancy, not resolved.

## PUSH and POP

```
push  src.w.r    Push Word   EE/F
pop   dst.w.w    Pop Word    E6/7
```

**Operation:** `[-SP] ← src` and `dst ← [SP+]`.

> "The stack pointer (R31) is decremented by four and the contents of the
> source operand are copied onto the stack.
>
> The PUSH instruction is a shorter encoding of the more general instruction
> `mov.w src, [ -sp ]`"

and, for `POP`:

> "The word data located on the top of the stack is copied to the destination
> operand. The stack pointer (R31) is then incremented by four.
>
> The POP instruction is a shorter encoding of the more general instruction
> `mov.w [ sp+ ], dst`"

That "shorter encoding of `mov.w`" is the whole specification: whatever
`[-Rn]`/`[Rn+]` do on R31 with a word operand, these do. **Condition Codes:**
all four Unchanged. **Exceptions:** `None`. Not privileged.

(The Reference's V20/V30 **emulation mode** appendix has a "PUSH SP
instruction" note about SP being decremented before or after the copy. That is
about emulation mode and does not describe native `PUSH`. Anyone grepping the
manual will hit it; it is not this instruction.)

## PUSHM and POPM — the register mask

```
pushm  list.w.r   Push Multiple Registers   EC/D
popm   list.w.r   Pop Multiple Registers    E4/5
```

**Operation:** `[-SP] ← registers` and `registers ← [SP+]`.

### Which bit is which register

Both pages print the same diagram. Read as three stacked character rows, each
column is one mask bit, MSB on the left:

```
 P R R R R R R R R R R R R R R R R R R R R R R R R R R R R R R R
 S 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 9 8 7 6 5 4 3 2 1 0
 W 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
```

So:

- **bit `n` selects `Rn`, for `n` = 0 … 30.**
- **bit 31 selects the PSW.**
- **R31 (SP) has no bit at all** — its column is taken by the PSW, and `PUSHM`'s
  Description confirms it in words: "The SP (R31) is not saved".

`PUSHM`'s Description:

> "This instruction permits the programmer to push from 1 to 32 registers on to
> the stack with a single instruction. A register (PSW, Rn) will be saved if
> the corresponding bit in the register list is set.
>
> The register list is searched sequentially from the MSB (PSW) to the LSB (R0)
> with only the designated registers being pushed onto the stack. The SP (R31)
> is not saved and following the execution of the instruction points to the
> last register pushed on the stack.
>
> The register list is extended to zero[-]word length if the immediate quick
> addressing mode is specified."

`POPM`'s:

> "This instruction permits a programmer to pop from 1 to 32 registers from the
> stack with a single instruction. A register will be restored if and only if
> its corresponding bit in the register list is set.
>
> The register list is searched sequentially from the LSB (R0) to the MSB (PSW)
> with only the designated registers being restored from the stack. **If the
> PSW register is specified, only the lower halfword is modified.**
>
> The register list is extended to word length if the immediate quick
> addressing mode is specified."

### Order, and whether the pair round-trips

`PUSHM` walks **MSB → LSB**: PSW first, then R30, R29, … down to R0. Each push
pre-decrements SP by four, so the PSW lands at the **highest** address and R0
at the **lowest**, and SP finishes on the lowest-numbered selected register —
"points to the last register pushed on the stack".

`POPM` walks **LSB → MSB**: R0 first, then upward to the PSW. Each pop reads at
SP and post-increments, so R0 comes off the lowest address and the PSW off the
highest.

**They round-trip exactly.** Same mask, opposite scan directions, opposite
stack directions: a matching `PUSHM`/`POPM` pair restores every selected
register from the slot it was written to, and SP returns to where the `PUSHM`
began. That is the property the two scan-order sentences exist to guarantee,
and it is why the two pages state the directions rather than leaving them
implied.

### The PSW in the mask, and p. 3.298's "R R R R"

Mask **bit 31** is the PSW. On `PUSHM` the whole 32-bit PSW is written to the
stack. On `POPM` **only `PSW[15:0]` is restored** — the page is explicit, and
that is exactly p. 3.248's protection rule (quoted in
`docs/v60/INSTRUCTION-SUMMARY-LEGEND.md`): the lower halfword is accessible to
all programs, the upper halfword only at execution level 0. A `POPM` that
restored the whole PSW would be a privilege escalation, so it restores half.

The four condition-code flags live in the low halfword. That is what p. 3.298's
Flags column means when it prints **`R R R R`** on the `POPM` row with `Note 1`
— "Flags updated if PSW is specified in the register list". `R` is "restored",
not "changed by the operation": the flags take whatever was on the stack. And
because the restore is half-width, `PSW.EL` and `PSW.IS` in bits 25:24 and 28
are **not** touched, so `POPM` cannot switch the stack out from under itself
mid-instruction. `PUSHM`'s row is blank — pushing the PSW does not change it.

**Exceptions:** both print `None`; the summary prints `1, 3`. **Not
privileged** — neither is in p. 3.299's Privileged Instructions block.

## PREPARE and DISPOSE — the frame

```
prepare  num.w.r   Prepare Stack Frame   DE/F
dispose            Dispose Stack Frame   CC
```

**PREPARE's Operation:**

```
tmp  ← num
[-SP] ← FP
FP   ← SP
SP   ← SP - tmp
```

> "This instruction is used to dynamically generate a new stack frame upon
> entry into a procedure. First, the contents of the frame pointer (R30) are
> saved on the stack and the updated SP is copied into the FP register.
> Finally, the stack pointer is adjusted by the specified number of bytes to
> allocate storage for local variables for this instance of the procedure."

The ordering matters and the word "updated" carries it: `FP ← SP` uses SP
*after* the push, so FP ends up pointing at the slot holding the old FP.
`num` is a **byte count**, not a word count — "adjusted by the specified number
of bytes".

**DISPOSE's Operation:**

```
SP ← FP
FP ← [SP+]
```

> "The DISPOSE instruction deletes the current stack frame by copying the
> contents of the frame pointer (R30) to the stack pointer (R31) and restoring
> the original frame pointer from the stack."

**Which registers are touched: R30 (FP) and R31 (SP), and nothing else.**
`PREPARE` does **not** touch R29 (AP). §3 assigns AP to a different instruction
entirely — "R29 is called the argument pointer (AP) and is used to point to the
list of procedure arguments by the `CALL` instruction" — so the argument
pointer is `CALL`/`RET`'s business and the frame pointer is `PREPARE`/
`DISPOSE`'s. They are separable, and this pair is the cheap half.

**How DISPOSE works with no operand.** It is Format V, one byte, `CC`, and
p. 3.293 draws Format V as an opcode byte and nothing else. Everything it needs
is in R30: `SP ← FP` discards the local-variable area *whatever size it was* —
which is why `PREPARE`'s `num` never has to be remembered anywhere — and the
word at that address is the saved FP. `DISPOSE` is the exact inverse of
`PREPARE` for any `num`, using one register and one memory read.

**Condition Codes:** both all-Unchanged. **Exceptions:** `PREPARE` `None`
(summary `1, 3`); `DISPOSE` `None` (summary blank). Neither is privileged.

## XCH — two destinations, and the first must be a register

```
xch.b  dst1.b.rw, dst2.b.rw   Exchange Byte       41
xch.h  dst1.h.rw, dst2.h.rw   Exchange Halfword   43
xch.w  dst1.w.rw, dst2.w.rw   Exchange Word       45
```

**Operation:** `dst1 <-> dst2`

**Both operands are `.rw`** — both read and both written. The syntax line names
neither a source: they are `dst1` and `dst2`, which is the page's way of saying
that the two roles are symmetric.

> "The contents of the first destination operand is exchanged with the contents
> of second destination operand.
>
> In the µPD70616 microprocessor, a Reserved Addressing Mode exception will
> occur if the first destination operand is not a general purpose register."

**Does the page define an order?** **No.** The Operation is a single
double-headed arrow, and there is no `tmp` in it — unlike `PREPARE`, whose
Operation block is four sequenced lines with an explicit temporary. Nothing on
the page says which read or which write happens first, and with `dst1`
constrained to a register there is no aliasing case that could make it
observable from outside the CPU. What *is* observable is the bus: an
interrupted or bus-error'd `XCH` could leave one destination written. The page
says nothing about that either.

**`dst1` must be a general purpose register.** The Addressing Modes table makes
it mechanical: `dst1` is `O` for `Rn`, **`A`** for all fourteen memory modes,
and `X` for both immediates. The page's own legend, printed under the table,
gives the letters:

```
X  Illegal Addressing Mode
A  Reserved Addressing Mode
```

So `XCH` is really *exchange a register with an operand* — and that is exactly
p. 3.296's `1, 3` for this row: `X` on the immediates gives the `1`, `A` on the
memory modes gives the `3`. This collapses most of the "two destinations"
problem: only one of them is ever in memory.

**Condition Codes:** all four Unchanged. Not privileged.

## TASI and CAXI — the indivisible pair

```
tasi  dst.b.rwi                 Test and Set Interlocked            E0/1
caxi  Rn.w.rw, dst.w.rwi        Compare and Exchange Interlocked    4C
```

The access type on the memory operand is **`rwi`** — read-modify-write
*interlocked*. `docs/v60/INSTRUCTION-TIMING.md` §4.1 already records that these
two are the *only* instructions in the whole set carrying `rwi`, against
`v60_operand_access.csv`; everything else that reads then writes (`INC`, `DEC`,
`SET1`, `CLR1`, `NOT1`) is plain `rw`. That access-type letter is the
architecture's own list of what needs a lock.

### TASI

**Operation:**

```
lock
flags ← dst - 0FFH
dst   ← 0FFH
unlock
```

> "This instruction is used to synchronize processes or provide mutual
> exclusion in a multiple processor configuration.
>
> The processor informs the other bus masters in the system that an indivis[i]ble
> operation will take place by asserting the bus lock output. The destination
> operand is then fetched and compared with 0FFH and the result stored in the
> condition codes. The contents of the destination operand is then replaced
> with the value 0FFH and the bus lock output is then negated, allowing other
> bus masters to again access the shared data.
>
> If the register addressing mode is specified for the destination, the
> execution of the instruction is meaningless but the operation is carried
> out."

**Condition Codes** — all four move, and they are a subtract's, not a test's:

```
CY  Set if a borrow is generated, otherwise cleared
OV  Set if integer overflow occurs, otherwise cleared
S   Set if the comparison results are negative, otherwise cleared
Z   Set if the comparison results are zero, otherwise cleared
```

`Z` is therefore set iff the byte was already `0xFF`, i.e. iff the lock was
already held.

### CAXI

**Operation:**

```
lock
flags ← dst - Rn
if ( Z = 1 ) then
    dst ← R28
else
    Rn  ← dst
unlock
```

> "This instruction is used to synchronize processes or provide mutual
> exclusion in a multiple processor configuration. CAXI is a more general form
> of the TASI instruction.
>
> The processor informs other bus masters in the system that an indivisible
> operation will take place by asserting the bus lock output signal. The
> destination operand is then fetched and compared with Rn and if equal, the
> contents of R28 are stored in the destination. Otherwise the destination
> contents are placed in Rn. The bus lock output is then negated, indicating
> that other bus masters may again access the shared data.
>
> If the register addressing mode is specified for the destination, the
> execution of the instruction is meaningless but the operation is carried out.
>
> This instruction is not allowed to use Format II and furthermore, the Format
> I direction field must be zero."

This is compare-and-swap, and **R28 is an implicit third operand** — the new
value comes from R28, which appears nowhere in the syntax line. `Rn` is `.rw`:
on failure it receives the value that was found, so the caller gets the
observed word back for a retry loop.

**Condition Codes:** the same four, from `dst - Rn`.

**Exceptions:** both print `None`; both summary rows print `1`. Neither is
privileged — mutual exclusion is a user-level facility.

### What the pages require of the bus

Databook p. 3.236, read on the plate, in full:

> "**BLOCK\*** [Bus Lock] .......... output
> **MSMAT\*** [Mismatch]
>
> The BLOCK\* output is asserted during a bus cycle to indicate an indivisible
> read-modify-write bus cycle (TASI, CAXI instructions) is taking place. It is
> used by external logic to guarantee the integrity of the bus cycle in a
> multiple bus master system. BLOCK\* is also asserted for the duration of an
> interrupt acknowledge bus cycle."

Three things that paragraph settles:

1. **The signal is an output and its only consumer is external.** "It is used
   by external logic to guarantee the integrity of the bus cycle". The CPU does
   not enforce anything with it; it announces.
2. **`TASI` and `CAXI` are named, and nothing else is** — matching the `rwi`
   access type exactly, from a second book.
3. **It is not only for these two.** It is also asserted "for the duration of
   an interrupt acknowledge bus cycle", which is a separate obligation on
   whatever drives it.

The plate also shows that **`BLOCK*` and `MSMAT*` share one pin** — `BLOCK*` in
master mode, `MSMAT*` (the FRM checker's mismatch output) in checker mode,
which is why `docs/v60/BUS-CYCLE-TIMING.md` lists it as "`BLOCK*` (MSMAT)".

### Is anything short of adding the pin faithful?

For the **architecture**, no: the pin is part of the external contract and a
core without it cannot express what p. 3.236 describes. `docs/v60/GOALS.md` and
`docs/v60/NEXT-STEPS.md` already carry it as an outstanding item, and
`docs/v60/INSTRUCTION-TIMING.md` §4.1 already has an implementable spec for it
from the µPD70632 document (assert at T1 of the first bus cycle of the
indivisible operation, deassert on the trailing edge of the last clock of the
last bus cycle).

For **this target**, the pin cannot change behaviour and something short of it
is required as well. `docs/v60/BUS-PINS-171-5964D.md` records, from the System
32 schematic 171-5964D sheet 1, that **`/BLOCK` is drawn as an open pin with no
net** — physically unterminated. So no external logic on this board can honour
it, and the hazard the interlock exists for is *internal*: the protection
engines write work RAM through port B of a dual-port BRAM with no arbitration,
so a `TASI` whose read and write are two separately arbitrated transactions is
not atomic against them. Announcing on a no-connect does not fix that.

The honest statement is therefore two-part, and neither part substitutes for
the other:

- **Adding the pin** is what makes the core a faithful µPD70616 and costs
  nothing here. It is describability, not function.
- **An internal hold-off** across the read and the write is what actually makes
  `TASI` and `CAXI` atomic on this hardware, and it is required whether or not
  the pin exists. The RTL already has one; see below.

## CHLVL — the execution-level gateway

```
chlvl  level.b.r, arg.b.r   Change Execution Level   4B
```

**Operation:**

```
[-SP] ← zero_extended( arg )
[-SP] ← Exception Code
[-SP] ← PSW
[-SP] ← NextPC
PC    ← [ Exception Vector ( 24 + level ) ]
```

> "This instruction provides a protected method of accessing more privileged
> execution levels.
>
> The execution level is changed to the new level and the byte argument is zero
> extended to word length pushed on the target execution level stack. The
> change execution level exception processing then pushes the exception code,
> PSW and PC of the next instruction on the stack and transfers control to the
> appropiate exception handler.
>
> An Illegal Data Field exception will occur if the level operand is not in the
> range [0] < level < 3 or the current execution level is less than the level
> operand [:] level < PSW.EL
>
> Operands are zero extended to byte length if the immediate quick addressing
> mode is specified."

### The frame, confirmed

The four `[-SP]` pushes are pre-decrementing and are listed in execution order,
so the first pushed is at the highest address. Reading the resulting frame from
the final SP upward:

```
    0    PC (Next PC)
   +4    PSW
   +8    Exception Code  |  8
  +12    zero_extended( arg )        <- the Parameter
```

**That is the shape you described**: a Parameter word **above** the code word,
parameter count **8**, and the **Next** PC on top. It is the same frame
`docs/v60/MULTIPLY-DIVIDE.md` and `docs/v60/DECIMAL.md` record for the
Arithmetic Exceptions group, with a different occupant of the parameter slot —
there the Current PC, here the instruction's own byte argument. The count `8` is
4 × (1 parameter + 1) in both, so a handler returns with `RETIS #8`, and because
the top word is the Next PC the return lands after the `CHLVL`.

### The vector

**`24 + level`**, from the Operation block, so **24, 25, 26, 27** for target
levels 0, 1, 2, 3. Confirmed on the databook plate: p. 3.270's System Base
Table figure, read at 600 dpi, prints `24 Change to Execution Level 0`,
`25 … Level 1`, `26 … Level 2`, `27 … Level 3` immediately above
`23 Decimal Arithmetic Exception`.

The matching exception codes are on p. 3.272, also read on the plate, under
**Change Execution Level Exceptions**:

```
1800   change to execution level 0
1900   change to execution level 1
1A00   change to execution level 2
1B00   change to execution level 3
```

Note the shape: the level moves the **second nibble**, giving `0x1800`,
`0x1900`, `0x1A00`, `0x1B00` — *not* `0x1800 + level`. This matters below.

### When the level is not permitted

The page gives two failure conditions and one of them is printed in a form that
contradicts its own prose:

- **"the level operand is not in the range `0 ≤ level ≤ 3`"** — unambiguous.
  `level` is a byte, so 4 … 255 fail.
- **"or the current execution level is less than the level operand"**, followed
  by the expression the OCR renders as **`level < PSW.EL`**. Those are
  negations of each other: the prose is `PSW.EL < level`, the expression is
  `level < PSW.EL`.

  §3 numbers level 0 as the most privileged ("EL = 00 execution level [0]
  (privileged)") and §6 calls 1, 2 and 3 non-privileged, and the Description's
  first sentence says the instruction exists "to provide a protected method of
  accessing **more privileged** execution levels". Under the expression as
  OCR'd, requesting a lower-numbered (more privileged) level would raise —
  which forbids the only thing the instruction is for. **The prose is the
  reading that survives**; the printed inequality as transcribed is its
  negation. The Programmer's Reference PDF is not held in `docs/reference/`,
  only its OCR text layer, so this line cannot be checked on a plate. Recorded
  as OCR-suspect rather than resolved.

Either way the failure is an **Illegal Data Field** exception — §8's `#20`,
offset +80 — and not a silent no-op or a Privileged Instruction exception.

**CHLVL is itself not privileged.** It is absent from p. 3.299's Privileged
Instructions block and carries no `12`. That is the point of it: a level-3
program may call *up*, but only through this gate, onto a handler the operating
system installed.

**The summary's exception column is wrong here, in the way the legend warns
about.** p. 3.298 prints `1` for `CHLVL`; the Reference's `Exceptions` block
says `Illegal Data Field`. Per
`docs/v60/INSTRUCTION-SUMMARY-LEGEND.md`'s caveat, that column "is right about
privilege and addressing and unreliable about operand-size faults", and a
level operand out of range is exactly an operand-size fault. This is a fresh
instance of the caveat, on an instruction whose own page names the exception
explicitly.

## Privilege, all ten

**None of the ten is privileged.** p. 3.299's Privileged Instructions block is
`LDPR STPR CLRTLB CLRTLBA GETATE UPDATE GETPTE UPDPTE GETRA IN OUT LDTASK
STTASK RETIS UPDPSW.W HALT`, and none of these appears in it; none carries a
`12`. Two of them touch privileged state anyway and do it through a half-width
or gated path rather than an execution-level check — `POPM` restores only
`PSW[15:0]`, and `CHLVL` changes the level only by vectoring through a handler.

## What the pages do not settle

- **`XCH`'s internal order**, and what a fault mid-exchange leaves behind. The
  Operation is one symmetric arrow with no temporary.
- **`CHLVL`'s permission inequality**, above — the prose and the printed
  expression are negations and the plate is not held.
- **Whether `PSW.IS` interacts with `CHLVL`'s "target execution level stack".**
  The page says the argument goes on the target level's stack; §3 says the SP
  is "a cache of five registers … one for each of the four execution levels and
  an interrupt stack pointer" and that "external events such as interrupt and
  exceptions determine which of the five stack pointers is in use". `CHLVL` is
  neither an interrupt nor an external event, so presumably it selects by level
  and leaves `PSW.IS` alone — but no page says so.
- **Whether `PUSHM`/`POPM` are interruptible.** They are the only instructions
  in this tranche with a loop, and up to 32 memory cycles is a long
  non-interruptible window. Neither page carries the "To minimize the interrupt
  latency time…" paragraph that the bit-string and character-comparison pages
  do (`docs/v60/BIT-STRING.md` — thirteen pages carry it and these are not
  among them), and neither names a resumption register. Absence of the
  paragraph is evidence but not a statement.
- **What `POPM` does to the four flags when bit 31 is clear.** p. 3.298's `R R
  R R` plus Note 1 ("Flags updated if PSW is specified in the register list")
  implies "unchanged otherwise", but the Reference's `POPM` page prints no
  Condition Codes block at all in the material held.
- **The `1, 3` on `PUSH`, `POP`, `PUSHM`, `POPM` and `PREPARE`.** `XCH`'s `3`
  is explained by its own page and its `A` cells. For the five stack rows the
  Reference's `Exceptions` blocks say `None` and their Addressing Modes tables
  are too OCR-damaged in the material held to read the `X`/`A` pattern that
  would explain the numbers.
- **Timing.** The Clocks column is blank for all ten, as for every row in the
  summary (`docs/v60/INSTRUCTION-TIMING.md`).

## Cross-check: `tools/v60x/insn_table.py`

The **encodings are all correct** — `PUSH 1110111{-}`, `POP 1110011{-}`,
`PUSHM 1110110{-}`, `POPM 1110010{-}`, `PREPARE 1101111{-}`, `DISPOSE
11001100`, `XCH 01000{siz}1`, `CHLVL 01001011`, `TASI 1110000{-}`, `CAXI
01001100` — and every one is corroborated by the Reference's Opcode block
(`EE/F`, `E6/7`, `EC/D`, `E4/5`, `DE/F`, `CC`, `41`/`43`/`45`, `4B`, `E0/1`,
`4C`).

Two discrepancies, both in the **format** column and both inherited from the
plate:

1. **`PUSH`, `POP`, `PUSHM`, `POPM`, `PREPARE` are recorded `'II'`; the
   Programmer's Reference says Format III for all five** (p. 7-55, 7-38, 7-54,
   7-39 and the `PREPARE` page). The table's own `{-}` in those five patterns
   is the Format III marker its header defines, so the file disagrees with
   itself: a `{-}` row labelled `II` cannot be right under its own rule. p.
   3.298 is where the `II` came from and p. 3.298's opcode column contradicts
   p. 3.298's format column.
2. **`XCH` is recorded `'I,II'`; the Reference says `Format I`.** Less certain
   than the first — p. 3.296 does print `I, II` — but `XCH`'s first operand is
   register-only, which is the same constraint that makes `CAXI` explicitly
   "not allowed to use Format II".

The operand widths are right: `'PUSH': (4, None)` and the rest of the stack
group at word width matches `src.w.r`/`dst.w.w`/`list.w.r`/`num.w.r`;
`'XCH': ('siz','siz')` matches the three `.b`/`.h`/`.w` syntax lines;
`'CHLVL': (1, 4)` matches `level.b.r, arg.b.r` on its first element — the
second is `4` where the syntax says `arg.**b**.r`, which is a **third
discrepancy**, small: `CHLVL`'s argument is a byte that the instruction
zero-extends, not a word. `'TASI': (1, None)` matches `dst.b.rwi`, and
`'CAXI': (4, 4)` matches `Rn.w.rw, dst.w.rwi` (its implicit R28 has no slot,
as `pat` and `blen` have none elsewhere).

## Cross-check: `rtl/cpu/v60/s32_v60.sv`

### PUSHM/POPM order matches the page

`pushm_index()` scans `i = 0 … 31` and lets the last hit win, so it returns the
**highest** set bit; `S_PUSHM` pushes that first and clears it. `S_POPM`'s
inline loop scans `i = 31 … 0` letting the last hit win, so it returns the
**lowest** set bit and pops that first. **PSW-down for the push and R0-up for
the pop — both directions correct.**

The PSW handling is also correct and non-obvious: `S_PUSHM` writes `psw` rather
than `r[31]` when the index is 31 (mask bit 31 is the PSW, not the SP), and
`S_POPM` does `write_psw((psw & 32'hffff_0000) | (bus_rdata & 32'h0000_ffff))`
— the low-halfword-only restore the page requires, with a comment noting that
preserving the high half is what keeps `IS`/`EL` out of it. Both match.

**One documentation defect, not a behaviour one.** `S_PUSHM` carries the
comment "`push highest set register first (MAME pushes from r31 down? actual:
PUSHM pushes ascending list to stack)`" immediately followed by "`idx = lowest
set bit; push in increasing register order`". `pushm_index()` returns the
highest set bit, so the second comment describes the opposite of what the code
does. The code is right and the comment is wrong; anyone reading the comment to
decide what the clean-room core should do would get the order backwards.

### PREPARE and DISPOSE match

`PREPARE` (`8'hde/df`) writes `r[30]` to `r[31]-4`, then `S_PREP1` sets
`FP ← r[31]-4` and `SP ← r[31]-4-op1`. That is the page's `[-SP]←FP; FP←SP;
SP←SP-tmp` with the "updated SP" correctly used for FP. `DISPOSE` (`8'hcc`)
sets `SP ← r[30]` and reads `mem[r[30]]`, then `S_DISP1` sets `FP ← ` that word
and `SP ← r[31]+4`. Correct **provided** the queued `SP ← r[30]` has committed
before `S_DISP1` reads `r[31]`; the two are in different states so it should
have, but the dependency is implicit and worth knowing about.

### XCH implements a case the page forbids

The core has two `XCH` paths: `S_XCH1`/`S_XCH2` for register↔memory, and
`S_XCH_MMRD1`/`MMRD2`/`MMWR1`/`MMWR2` for **memory↔memory**, commented as "the
V60 F12 sequence: load operand 1, load operand 2, store operand 1, store
operand 2". The page says a memory `dst1` raises a **Reserved Addressing Mode**
exception, and the Addressing Modes table marks all fourteen memory modes `A`.
So the memory↔memory path executes something the µPD70616 refuses, and there is
no check anywhere that `dst1` is a register.

Two secondary notes on the same paths. `S_XCH1`/`S_XCH2` write the register
first and memory second (`mem → reg`, then `reg → mem`), which the page does
not order and so cannot contradict. And both paths drop `dbus_req` for a cycle
between transactions — a deliberate fix, per the comment, for a real-ROM
deadlock in Golden Axe's "`XCH.W` lock idiom", which is worth noting because
`XCH` is not on the `rwi` list and is *not* supposed to be indivisible: a game
using it as a lock is relying on something the architecture does not promise.

### TASI has an internal lock; CAXI is not implemented

`bus_lock` **is** an output of this module and `bus_lock_r` is raised at the
`8'he0/e1` dispatch and cleared in `S_TASI2` after the write acknowledges — "the
first physical cycle of the operation to the completion of the last", which is
the span p. 3.236 describes. The comment block at the declaration is accurate
about scope and honest about what it is not: it records the measured hazard
(read and write are "two independently arbitrated transactions … measured gap
≥ 7 execute cycles, about 290 ns" against unarbitrated protection-engine writes
on port B), cites `rwi` as the architectural list, and separates the µPD70632's
*semantics* from its *timing*.

**`CAXI` (`0x4C`) is not implemented.** It is absent from `is_f12_primary()`'s
opcode list — which contains `4b`, `4d`, `4e`, `4f` but not `4c` — and falls to
the reserved-opcode path. The declaration comment says so explicitly and adds
the right instruction for whoever adds it: "When it is added it must set this
lock too."

### CHLVL: the frame is right, two checks and one code are not

`8'h4b` in `exec_op` builds the frame correctly — `exc_extra` (the argument) is
pushed first by `S_EXC_EXTRA`, then the code, then the PSW, then
`exc_retpc <= pc + 5'd2 + len1 + len2`, which is the **Next** PC. `exc_vector
<= 8'd24 + op1[1:0]` matches `24 + level`, and `exc_target_level <= op1[1:0]`
reaches `newpsw[25:24]` in `S_EXC_PUSH1`, so `PSW.EL` becomes the target.

Three divergences:

1. **The exception code is wrong against the p. 3.272 plate.** The RTL builds
   `exc_code <= {8'h18, 6'b0, op1[1:0], 16'h0008}`, i.e. `0x18000008`,
   `0x18010008`, `0x18020008`, `0x18030008` for levels 0-3, and its comment
   attributes this to MAME's `EXCEPTION_CODE_AND_SIZE(0x1800 + op1, 8)`. The
   databook's Change Execution Level Exceptions block prints **`1800`, `1900`,
   `1A00`, `1B00`** — the level moves the second nibble, not the low byte. The
   correct words are `0x18000008`, `0x19000008`, `0x1A000008`, `0x1B000008`.
   Only level 0 agrees. The comment records that an earlier version of this
   line *did* put the level in bits [27:24] and was "fixed" to [17:16]; the
   plate says the earlier placement was the right one and the audit item that
   changed it was wrong. This is MAME's arithmetic against a printed table.
2. **The `PSW.EL` permission check is missing entirely.** The RTL tests only
   `op1 > 32'd3`. The page's second condition — that the requested level must
   be more privileged than the current one, however the inequality is finally
   read — is not implemented, so a program at any level can `CHLVL` to any
   level 0-3, including level 0. On a machine that enforced protection this
   would be an escalation; on System 32 nothing runs at a non-zero level, so it
   is latent.
3. **The out-of-range case raises the wrong vector.** `op1 > 3` gives
   `exc_vector <= 8'd8`, the core's reserved-opcode catch-all, where the page
   says **Illegal Data Field** — §8's `#20`, plate-confirmed on p. 3.270. Same
   pattern as the bit-field and bit-string groups.

A fourth, smaller: the argument is taken as `flag2 ? rf_rdata_b : (op2val_v ?
op2val : op2)` and is **not masked to a byte** on the register path, where the
page says `zero_extended( arg )` from `arg.b.r`. A register holding more than
eight significant bits pushes the wrong parameter word.

## What these ten need that this tree does not have

Four things, in increasing cost.

1. **A byte mask on `CHLVL`'s argument and an `#20` vector for its range
   check.** Trivial; no new machinery.
2. **A register-list loop for `PUSHM`/`POPM`** — a 32-bit mask register, a
   priority encoder that can pick the highest set bit *and* the lowest, and a
   PSW path that is full-width on the push and low-halfword-only on the pop.
   `v60_seq` has no multi-cycle register-file walk today. The MAME-derived core
   shows the shape and gets the order and the half-width restore right, so this
   is a known quantity.
3. **A two-destination write for `XCH`** — but far cheaper than it looks. `dst1`
   is architecturally register-only, so the general case is one register write
   and one memory write, not two memory writes, and the memory↔memory sequencing
   the MAME-derived core implements is a case the V60 refuses. What is
   genuinely new is that one instruction retires with two writebacks pending;
   what is *not* needed is a second memory write port. `XCH` also needs a
   `dst1`-is-a-register check that raises **Reserved Addressing Mode** (`#18`),
   which nothing in this tree raises yet.
4. **`CHLVL` needs the execution-level stack switch**, and this is the one that
   exercises real machinery — but the machinery **already exists**.
   `rtl/cpu/v60x/v60_regfile.sv` is built for it: it carries the five stack
   pointers behind R31 (`L0SP`-`L3SP`, `ISP`), takes `psw_el` and a
   `stack_switch` strobe, and saves-then-reloads "in the order the page gives".
   What is missing is a **consumer** — an instruction that changes `PSW.EL` and
   pulses `stack_switch`. `CHLVL` is that instruction, and it is the only
   non-privileged one that is. So this is wiring plus a permission check, not
   new datapath.

And one thing that is **not** needed, despite appearances: `TASI` and `CAXI` do
**not** require the mid-instruction interrupt machinery that
`docs/v60/BIT-STRING.md` found the bit-string group needs. They require the
opposite — a guarantee that nothing intervenes — which a sequencer that already
retires one instruction at a time provides for free, plus an internal hold-off
against the *other* master on this board (the protection engine on port B of
the work RAM), plus the `BLOCK*` output pin for describability. None of that
touches the data-unit mux.

`CAXI` additionally needs an implicit R28 read, which is the same kind of
architectural-register dependency the bit-string group has on R28/R27 — so
whatever names R28 for those names it here too.
