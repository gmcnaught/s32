# BRK, TRAP and TRAPFL

Three exception-pushers, and the one conflict in the book that actually
matters. `BRKV` is already in and is not re-derived here
(`docs/v60/TRANCHE-ONE.md`); it appears only where it is the control that makes
a `BRK` finding legible.

**One constraint on this doc, stated up front.** The Programmer's Reference
**PDF is not held** in `docs/reference/` — only `NEC_V60pgmRef_djvu.txt`, its
OCR text layer. So *neither* side of the `BRK` conflict can be read at 600 dpi:
both Figure 8-5 and `BRK`'s §7 page are in that book. The conflict is settled
below anyway, and from plates — but from the **databook's**, which is held, and
from a third Reference passage that does not depend on reading a figure. Where
a claim rests only on the Reference's OCR it says so.

Sources: databook **p. 3.269** (exception stack format and the recognition
sequence), **p. 3.270** (the System Base Table), **p. 3.272** (the exception
codes) — all three read at 600 dpi; Programmer's Reference §7 for the
instruction pages, §8 for Figure 8-5 and the per-exception prose, §3 for the
PSW and TKCW.

---

## 0. What the databook settles that the Reference only draws

Databook **p. 3.269**, read on the plate, carries two things §8 spreads over
several figures. Both are directly implementable and neither needed the
Reference at all.

### The generic exception stack format

```
             Exception Stack Format
 31                                          0
+---------------------------------------------+
|             Exception Parameter             |
+----------------------+----------------------+
|    Exception Code    |   Parameter Count    |
+---------------------------------------------+
|                    PSW                      |
+---------------------------------------------+
|                    PC                       |  <- SP
+---------------------------------------------+

          Interrupt Stack Format
+---------------------------------------------+
|                    PSW                      |
+---------------------------------------------+
|                    PC                       |  <- SP (ISP)
+---------------------------------------------+
```

Three consequences:

1. **There is one exception frame, not several.** Every frame Figure 8-5 draws
   is this one with the parameter slot present or absent. The tree already
   reads it that way (`docs/v60/EXCEPTIONS.md`); this is the plate that says so.
2. **The code word is split in half** — `Exception Code` in bits 31:16,
   `Parameter Count` in bits 15:0. That is why the Reference draws the word as
   `Exception Code | 4` or `Exception Code | 8`.
3. **The count discriminates.** Count `4` = the code word alone, no parameter.
   Count `8` = the code word plus one parameter. So `count = 4 × (parameters +
   1)`, and `RETIS #count` pops exactly the right number of words. Checked
   across every group in Figure 8-5: `4` on #12, #13, #48-63 and #28-29 (which
   have no parameter drawn) and `8` on #14, #21/22/23 and #24-27 (which do).

### The interrupt/exception recognition sequence

Quoted whole from the plate, because it is the specification for whatever
enters an exception:

> "When an interrupt or exception is recognized, the following actions are
> performed and control is transferred to the specified interrupt/exception
> handler.
>
> (i)  PSW.EL ← 00
>      (If a CHLVL instruction exception or an Asynchronous Task Trap then the
>      specified execution level is set.)
>
> (ii) PSW.IE flag modification
>      • interrupt ……… PSW.IE ← 0 (maskable interrupts disabled)
>      • exception ……… **PSW.IE unchanged** (bus error and stack invalid
>        exceptions disable interrupts)
>
> (iii) PSW.TE ← 0 / PSW.TP ← 0 / PSW.AE ← 0
>
> (iv) PSW.EM ← 0 (native mode)
>
> (v)  PSW.ASA ← 1 (If an ATT occurs then AST are enabled.)
>
> (vi) temp ← SBT[ vector ]
>
> (vii) interrupt/exception information is stored on the stack
>      • interrupt ……… IS (interrupt stack)
>      • exception ……… **L0SP** (IS if the previous stack was the interrupt
>        stack or LnSP if a change execution level or ATT exception occurs)
>
> (viii) PC ← temp"

Two items in that are load-bearing for `BRK`, `TRAP` and `TRAPFL` and are easy
to miss:

- **(ii): a synchronous exception leaves `PSW.IE` alone.** Only *interrupts*
  disable interrupts. `BRK`, `TRAP`, `TRAPFL`, `BRKV` and `CHLVL` must not
  clear it.
- **(vii): the frame goes on `L0SP`, not the current level's stack.** Step (i)
  has already forced `PSW.EL ← 00`, so the push happens at level 0 — which
  means these three, like `CHLVL`, need `v60_regfile`'s stack switch. `CHLVL`
  is the exception to the exception: it sets its own target level in step (i)
  and pushes on `LnSP`, which is exactly what its own page calls "the target
  execution level stack" (`docs/v60/TRANCHE-TWO.md`).

The databook also confirms the SBT geometry: "The SBT consists of 256 entries
… located in the memory address space aligned on a page (4KB) boundary by the
SBR (system base register). The first 64 SBT entries (0-63) are reserved for
use by µPD70616 interrupts and exceptions."

---

## 1. BRK — and which source wins

```
brk        Opcode C8        Format V        one byte
```

**Operation** (Reference §7, OCR):

```
[-SP] ← Exception Code
[-SP] ← PSW
[-SP] ← NextPC
PC ← [ Exception Vector 13 ]
```

> "The breakpoint trap is asserted and program control is transferred to the
> breakpoint trap exception handler."

**Condition Codes:** all four Unchanged. **Exceptions:** Breakpoint Trap.
**Not privileged** — absent from p. 3.299's Privileged Instructions block, and
its summary row's Exceptions cell is blank.

### The conflict, stated exactly

Figure 8-5's Software Debug Exceptions row-group lists three exceptions and
three frames, in matching order:

| | frame |
|---|---|
| **#12 Instruction Trace Exception** | `+8 Exception Code \| 4` / `+4 PSW` / `PC (Next PC)` |
| **#13 Instruction Breakpoint Exception** | `+8 Exception Code \| 4` / `+4 PSW` / **`PC (Current PC)`** |
| **#14 Address Trap** | `+12 PC (Current PC)` / `+8 Exception Code \| 8` / `+4 PSW` / `PC (Next PC)` |

Three names, three frames, one-to-one — so the pairing is not a reading, it is
the figure's own layout, and #12 and #13 genuinely differ. Against that,
`BRK`'s Operation block pushes `NextPC`.

### Figure 8-5 wins. `BRK`'s Operation block is the error.

Three independent reasons, none of which is "the figure looks more official":

**1. §8's prose names `BRK` and states the frame's contents in words.** Under
Software Debug Exceptions:

> "**Instruction Breakpoint**
>
> An instruction breakpoint exception occurs when the **BRK instruction** is
> executed.
>
> The PC image in the exception information contains the address of the
> **instruction breakpoint**. This allows the exception handler to **restart
> the instruction following the removal of the breakpoint**."

That is a third passage, in a third place, and it does two things at once. Its
first sentence establishes that the *only* source of exception #13 is the `BRK`
instruction — so Figure 8-5's #13 row is `BRK`'s frame and there is no other
mechanism it could be describing. Its second sentence says the pushed PC is
"the address of the instruction breakpoint", i.e. the address of the `BRK`
itself, which is the **Current PC**.

**2. The stated rationale is incompatible with `NextPC`.** "This allows the
exception handler to restart the instruction following the removal of the
breakpoint" describes the standard software-breakpoint cycle: patch `C8` over
an instruction, trap, restore the original byte, return, re-execute. That works
only if the saved PC is the patched address. With `NextPC` the handler would
have to know the length of the instruction it just removed and rewind by hand —
and it cannot, because the byte it replaced is gone by the time the length
would be needed. The Reference does not merely assert Current PC; it gives the
reason, and the reason forbids the alternative.

**3. §8's general rule agrees.** From §8 (also quoted in
`docs/v60/BIT-STRING.md`): "An exception during the execution of an instruction
stacks the PC of the instruction causing the exception (Current PC). An
exception following the execution of an instruction stacks the PC of the
instruction immediately following the instruction which caused the exception
(Next PC)." `BRK`'s whole effect *is* the exception, so it occurs during
execution. `#12 Instruction Trace` is the paired case and its own §8 prose says
so from the other side: trace exceptions "occur **following** the execution of
each instruction" — which is why #12 gets `Next PC` and #13 does not. The
adjacent-but-different frames are the rule being applied, not an inconsistency.

**So: `BRK` pushes three words — `Exception Code | 4`, `PSW`, `Current PC` —
vectors through SBT entry 13, and a plain `RETIS #4` re-executes the `BRK`.**
A handler that does not first remove the breakpoint loops forever, which is the
intended behaviour and not a defect.

**Exception code.** Databook p. 3.272, Software Debug Exceptions block, read at
600 dpi:

```
0C00   instruction trace
0D00   instruction breakpoint
0E01   address trap 0
0E02   address trap 1
0E03   address traps 0 and 1
```

**`BRK`'s code word is `0x0D00_0004`** — code `0x0D00`, parameter count 4.

**Vector 13**, confirmed on the databook p. 3.270 SBT plate
(`13 Instruction Breakpoint Exception`), and by `BRK`'s own Operation line.

### What is still not settled

The Operation block is wrong on this one line, and **nothing explains why**. It
is a one-token error in a book whose figures and prose agree against it, so it
is recorded as an error rather than reconciled. Anyone who reads only §7 will
implement `NextPC` and get a plausible-looking core that cannot host a
debugger.

---

## 2. TRAP

```
trap cond&vector.b.r      Opcode F8/9      Format III      1 + mod bytes
```

**Operation:**

```
if ( condition ) then
    [-SP] ← Exception Code
    [-SP] ← PSW
    [-SP] ← NextPC
    PC ← [ Exception Vector( 48 + vector ) ]
```

> "If the specified condition is satisfied by the integer condition codes, the
> specified trap handler is entered. The upper four bit field of the operand
> contains the condition code field which indicates under what circumstances
> the trap will be taken. The lower four bit field contains the vector offset
> from the software trap base vector."

`docs/v60/TRANCHE-ONE.md` established the nibble split (`{cond[3:0],
vector[3:0]}`, condition in the **upper** nibble — the opposite of `SETF`).
What follows is the rest.

### The vector mapping, from the page rather than the arithmetic

**Databook p. 3.270's System Base Table figure, read at 600 dpi**, prints the
entries individually rather than as a range:

```
63  Software Trap 15
...
57  Software Trap 9
56  Software Trap 8
55  Software Trap 7
54  Software Trap 6
53  Software Trap 5
52  Software Trap 4
51  Software Trap 3
50  Software Trap 2
49  Software Trap 1
48  Software Trap 0
47  ) RFU
33  )
32  Emulation Mode Exception
```

So **SBT entry `48 + n` is Software Trap `n`**, enumerated on a plate for
`n = 0 … 15`, with entry 47 and below explicitly RFU. `TRAP`'s Operation line
`Exception Vector( 48 + vector )` and the figure agree, and the figure is not
an arithmetic inference from a range label — it lists them. The byte offsets
into the SBT are `4 × (48+n)`, i.e. `0xC0` through `0xFC` from the page-aligned
base in `SBR`.

### The exception code

**Databook p. 3.272, Software Traps block**, read at 600 dpi:

```
3000   software trap 0
3100   software trap 1
3200   software trap 2
  ⋮
3F00   software trap 15
```

**The trap number occupies bits 11:8 — the second nibble — not the low byte.**
So the code is `0x3000 + (n << 8)`, and the full code word is
**`0x3n00_0004`**.

That mapping is worth stating loudly because the *other* indexed code group on
the same plate has the same shape and this tree already got one of them wrong:
Change Execution Level is `1800 / 1900 / 1A00 / 1B00`, also second-nibble, and
`docs/v60/TRANCHE-TWO.md` records `s32_v60.sv` building `0x1800 + level`
instead. **NEC indexes exception codes in bits 11:8 in both groups.** There is
no group in the table indexed in the low byte.

### The frame

Figure 8-5, `#48-63 Software Traps`, disposition `Continue`:

```
   +8    Exception Code  |  4
   +4    PSW
    0    PC (Next PC)
```

Three words, count 4, no parameter — and **`Next PC`**, which is what `TRAP`'s
own Operation block pushes. **`TRAP` has no conflict**: figure and Operation
block agree, so a software trap returns *past* the `trap` instruction on a
plain `RETIS #4`. That is also the right answer for a system call, which is
what §8 says software traps are for: "Software traps are an implementation
dependent method of implementing user traps."

### When the condition is false

Nothing happens. The Operation block's entire body is inside `if ( condition )
then`, so with the condition false there is no push, no vector fetch and no PC
change — execution falls through to the next instruction. The instruction is
still fetched and its operand still addressed, so it costs its length and
whatever operand fetch the addressing mode implies, but it has no architectural
effect. §8 says the same from the exception side: "When the condition field in
a TRAP instruction and the PSW is satisfied, the specified software trap will
occur."

**Condition Codes:** the page prints "Unaffected" for all four where every
neighbouring page prints "Unchanged"; nothing suggests a difference.
**Not privileged.** **Length:** Format III is `[mod] [op | m]`, so one opcode
byte plus the mod field — the operand can be immediate-quick (one byte total)
or any addressed form.

---

## 3. TRAPFL

```
trapfl        Opcode CB        Format V        one byte
```

**Operation:**

```
if ( TKCW[8:4] ∧ PSW[12:8] ) ≠ 0 then
    Floating Point Operation Exception
```

> "The bit-wise AND of floating point trap mask field in the TKCW register and
> the floating point condition codes in the PSW is computed and if the result
> is non-zero, a floating point operation trap will occur."

### Which flags it tests, and where the enables live

`PSW[12:8]` is `{FIV, FZD, FOV, FUD, FPR}` read MSB-down
(`docs/v60/TRANCHE-ONE.md`'s PSW map, §3 pp. 3-3/3-4):

| PSW bit | flag | meaning | TKCW enable |
|---|---|---|---|
| 12 | `FIV` | invalid floating point operation | TKCW bit 8 |
| 11 | `FZD` | floating point zero divide | TKCW bit 7 (`FZT`) |
| 10 | `FOV` | floating point overflow | TKCW bit 6 (`FOT`) |
| 9 | `FUD` | floating point underflow | TKCW bit 5 (`FUT`) |
| 8 | `FPR` | floating point precision (inexact) | TKCW bit 4 (`FPT`) |

The AND is bit-for-bit after a shift of four, so the correspondence above is
forced by the Operation block itself.

**The enables are in the TKCW — the Task Control Word**, §3: "The Task Control
Word (TKCW) contains task specific information and is swapped in and out as
part of the task context." It is a **privileged register**, id 8, reached by
`LDPR`/`STPR`; `docs/v60/FLOATING-POINT.md` has its layout (bit 0-1 `RD`
rounding mode, bit 2 `RDI`, bit 3 RFU, bit 4 `FPT`, bit 5 `FUT`, …).

§8 names four of the five enables explicitly, each in its own paragraph:

> "Floating point zero divide exceptions are enabled by the **TKCW.FZT** bit."
>
> "…the **TKCW.FOT** bit is set or will be delayed and an infinite result will
> be placed in the destination operand."
>
> "…immediately if the **TKCW.FUT** bit is set or will be delayed and a
> denormal result will be placed in the destination operand."
>
> "When a precision exception occurs, the PSW.FPR bit is set and the exception
> will occur if the **TKCW.FPT** bit is set."

The fifth — the invalid-operation enable, TKCW bit 8 by position — is **never
named** in the material held; its paragraph says only "If the exception is
enabled, the destination operand remains unchanged."

**So yes: the test is gated by enable bits, and they are in a privileged
register, not in the PSW.** `TRAPFL` is the *deferred* half of a two-part
design — an FP instruction sets a sticky PSW flag and (per those paragraphs)
may "delay" the trap; `TRAPFL` is how software forces the delayed trap to
happen at a point of its choosing.

### Vector and frame

`TRAPFL` raises a **Floating Point** exception, which Figure 8-5 places in the
Arithmetic Exceptions group as `#22 Floating Point Exceptions` (listing Zero
Divide, Overflow, Underflow, Precision, Invalid Floating Point Operation,
Reserved Floating Point Operand), sharing one frame with `#21 Integer` and
`#23 Decimal`, disposition `Abort / Continue`:

```
   +12   PC (Current PC)
   +8    Exception Code  |  8
   +4    PSW
    0    PC (Next PC)
```

**Vector 22**, confirmed on the databook p. 3.270 SBT plate
(`22 Floating Point Arithmetic Exception`). Four words, count **8** — the
Current PC is the parameter — and the return address on top is the **Next** PC,
so a handler returns past the `trapfl`. Identical in shape to the frame
`BRKV` and the zero divide already use (`docs/v60/MULTIPLY-DIVIDE.md`).

**Exception code.** Databook p. 3.272, Arithmetic Exceptions block, read at
600 dpi:

```
1601   floating point precision      ⎫
1602   floating point underflow      ⎬ "these exception codes can
1604   floating point overflow       ⎭  combine in the case of
1608   floating point zero divide        simultaneous exceptions"
1610   invalid floating point operation
1680   reserved floating point operand
```

The bracket and its note are printed on the plate, and they matter here more
than anywhere else in the table: `TRAPFL` ANDs a five-bit mask against a
five-bit flag field, so **more than one condition can be live at once**, and
the codes are chosen to OR together — `0x1601`, `0x1602`, `0x1604`, `0x1608`
are one-hot in the low nibble precisely so `0x1606` means "underflow and
overflow". `TRAPFL`'s code word is the OR of the codes for the enabled flags
that are set, with count `8`.

**Condition Codes:** `CY OV S Z` all Unchanged **and** `FIV FZD FOV FUD FPR`
all Unchanged — the page prints a nine-line block. `TRAPFL` reads the flags and
never clears them; they stay sticky for the handler.

**Exceptions block:** Floating Point Zero Divide, Invalid Floating Point
Operation, Floating Point Overflow, Floating Point Underflow, Floating Point
Precision. `docs/v60/TRANCHE-ONE.md` already showed the plate's `1, 3, 6, 7, 9`
to be a summary-column defect on a no-operand instruction. **Not privileged.**

### Is it implementable here?

**Yes, completely, and without an FPU.** Everything it reads already exists in
the clean-room tree:

- `PSW[12:8]` are ordinary PSW bits. They are in the **lower** halfword, so
  they are writable by the non-privileged `UPDPSW.H` as well as by
  `UPDPSW.W` — nothing privileged is needed to set them.
- `TKCW` is privileged register **id 8**, and `rtl/cpu/v60x/v60_regfile.sv`
  already carries it: `localparam int PR_TKCW = 8`, present in `PR_PRESENT`,
  readable by `STPR` and writable by `LDPR`.

So `TRAPFL` is a five-bit AND of two registers this tree has, plus the
Arithmetic-Exceptions frame it already builds for `BRKV` and the zero divide,
plus vector 22. No floating point datapath is touched: it never reads an FP
operand, never rounds and never writes a result.

**But it is not a no-op, and calling it one would be a defect.** With no FP
instruction implemented, nothing in *hardware* ever sets `PSW[12:8]` — so the
AND is zero and `TRAPFL` falls through. That is a *default*, not a property:
software can set both operands by hand (`LDPR` into TKCW, `UPDPSW.H` into the
PSW) and make `TRAPFL` trap on a machine with no FPU at all. The correct
implementation is the real one — read both, AND, branch — which costs almost
nothing and is right in both cases. An unconditional fall-through would be
wrong for any program that arms it.

---

## 4. Privilege and length, all three

| | privileged | format | length | vector | code word |
|---|---|---|---|---|---|
| `BRK` | no | V | **1 byte** | 13 | `0x0D00_0004` |
| `TRAP` | no | III | **1 + mod field** | `48 + n` | `0x3n00_0004` |
| `TRAPFL` | no | V | **1 byte** | 22 | OR of `16xx`, count `8` |

None of the three appears in p. 3.299's Privileged Instructions block or
carries a `12`. That is deliberate: all three are how *user* code asks for the
supervisor's attention, and the protection is in the SBT the supervisor owns,
not in an execution-level check on the instruction. Note the asymmetry with
their effect — every one of them enters the handler at `PSW.EL = 00` on
`L0SP` (p. 3.269, steps (i) and (vii)).

`BRK` and `TRAPFL` are Format V, which p. 3.293 draws as an opcode byte and
nothing else — one byte, no `mod`, no operand. `TRAP` is Format III,
`[mod] [op | m]`: one opcode byte whose bit 0 is the addressing-mode bit `m`,
plus the `mod` field, so `F8`/`F9` are the same instruction and its length is
1 plus whatever the operand's addressing mode costs (one byte for immediate
quick).

---

## 5. What the pages do not settle

- **Why `BRK`'s Operation block says `NextPC`.** Settled *against*, three ways,
  but unexplained.
- **`TRAPFL`'s exception code when several enabled flags are set at once.** The
  plate's note says the codes "can combine"; it does not say whether the
  hardware ORs all of them or reports one. OR is the only reading under which
  the one-hot low nibble means anything, but it is not stated.
- **The name of TKCW bit 8**, the invalid-operation trap enable. Four of the
  five are named in §8; this one is not.
- **`TRAP` with an immediate-quick operand.** `TRANCHE-ONE.md`'s open item
  stands: the addressing table permits `Immediate.Quick`, which supplies four
  bits, so the condition nibble is `0000` = `V` ("OV = 1"). Whether that is the
  intent is not printed.
- **Whether `BRK` can nest.** Step (iii) clears `PSW.TE`/`TP`/`AE` but nothing
  suppresses a second `BRK`, and the handler runs at level 0 on `L0SP`. What a
  `BRK` inside a breakpoint handler does is not addressed.
- **`PSW.ASA`'s bit position.** Step (v) says `PSW.ASA ← 1`; §3's PSW map as
  transcribed in `docs/v60/TRANCHE-ONE.md` stops at bit 26 and does not name
  ASA. `s32_v60.sv` sets bit 31 on exception entry, which is consistent with
  ASA being bit 31 but is not confirmed by anything held.
- **Timing.** All three rows' Clocks cells are blank, as everywhere.

---

## 6. Cross-check: `rtl/cpu/v60/s32_v60.sv`

### TRAP is correct — all of it

`8'hf8, 8'hf9` in `exec_op`:

```verilog
if (cond_true(op1[7:4])) begin
    exc_vector   <= 9'd48 + {5'b0, op1[3:0]};
    exc_code     <= {4'h3, op1[3:0], 8'h00, 16'h0004};
    exc_pushval  <= psw;
    exc_retpc    <= pc + 5'd1 + len1;
    exc_has_code <= 1'b1;
    st <= S_EXC_PUSH1;
end
else begin
    total_len <= 5'd1 + len1;
    st <= S_NEXT;
end
```

Condition from the **high** nibble ✓; vector `48 + n` ✓ against the p. 3.270
plate; code `0x3n00` with the trap number in bits 11:8 ✓ against the p. 3.272
plate; count `0x0004` ✓ against Figure 8-5; `exc_retpc = pc + 1 + len1`, the
**Next** PC ✓; `exc_has_extra` left clear, so three words ✓; clean fall-through
when the condition is false ✓. Nothing to change.

Worth noting for its own sake: MAME's constant here is `0x3000 + 0x100*(n&0xF)`
— the correct second-nibble indexing — while its `CHLVL` constant is `0x1800 +
op1`, the incorrect low-byte indexing (`docs/v60/TRANCHE-TWO.md`). Same table,
same shape, two different readings in one emulator. The plate is the arbiter and
it says second nibble for both.

### The frame plumbing is correct

`S_EXC_PUSH1 → (S_EXC_EXTRA) → S_EXC_CODE → S_EXC_PUSH2 → S_EXC_JMP`, each
pushing at `r[31]-4`, so the stack ends up parameter-highest, then code, then
PSW, then PC at SP — exactly the databook p. 3.269 Exception Stack Format. The
vector fetch is `(sbr & ~32'hfff) + {exc_vector, 2'b00}`, which is the
page-aligned SBR plus `4 × vector` ✓.

### Divergences

**1. `BRK` is not implemented — it is a one-byte no-op.**

```verilog
8'hc8: begin // BRK — MAME skips this opcode (A4)
    $display("V60: BRK skipped at %08x", pc);
    pc <= pc + 1; st <= S_FILL; st_after_fill <= S_DECODE;
end
```

No push, no vector, no PC change. Against the pages it should push three words
(`0x0D00_0004`, PSW, **Current PC**) and vector through SBT entry 13. The
comment is honest that this is MAME's omission rather than a reading of NEC.

**2. `BRKV`'s parameter count is 4 and it pushes a parameter.**

```verilog
exc_code  <= 32'h1501_0004;   // EXCEPTION_CODE_AND_SIZE(0x1501,4)
exc_extra <= pc;
exc_has_extra <= 1'b1;
```

The code `0x1501` is right — databook p. 3.272 prints `1501 integer overflow`,
plate-confirmed. The **count is not**: the low half says `4`, meaning "no
parameter", while `exc_has_extra` pushes the Current PC as a parameter. Figure
8-5's Arithmetic frame has both — a `PC (Current PC)` parameter *and* count
`8` — and `docs/v60/MULTIPLY-DIVIDE.md` already documents count 8 for this
frame from the divide side. A handler doing `RETIS #4` on this frame returns
with the stack one word out. It should be `32'h1501_0008`.

The same `4`-vs-`8` question does **not** arise for `TRAP`, whose frame really
has no parameter, or for `CHLVL`, which already uses `16'h0008`. `BRKV` is the
one place where the count and the pushed words disagree.

**3. `TRAPFL` uses vector 15, which is RFU.**

```verilog
8'hcb: begin // TRAPFL
    if ((tkcw & 32'h0000_01f0) & ((psw & 32'h0000_1f00) >> 4)) begin
        exc_vector <= 8'd15; exc_pushval <= psw; st <= S_EXC_PUSH1;
    end else begin pc <= pc + 1; st <= S_FILL; st_after_fill<=S_DECODE; end
```

The **test is exactly right** — `tkcw & 0x1F0` is TKCW[8:4], `(psw & 0x1F00) >>
4` brings PSW[12:8] onto the same bits, and the AND is the Operation block
verbatim. Three things after it are not:

- **Vector 15 is RFU.** The databook p. 3.270 SBT plate reads `15 RFU`,
  `14 Address Trap`, and the floating point exception is **22**.
- **No exception code and no parameter.** `exc_has_code` and `exc_has_extra`
  are both left clear from the decode preamble, so this builds the two-word
  *interrupt* frame (PSW, PC) rather than the four-word Arithmetic frame
  (parameter, code|8, PSW, PC) Figure 8-5 requires.
- **`exc_retpc` is left at its decode-preamble default of `pc`**, the Current
  PC, where the frame's top word must be the **Next** PC (`pc + 1`, `TRAPFL`
  being one byte).

The fall-through path is correct.

**4. Synchronous exceptions clear `PSW.IE`, and should not.** `S_EXC_PUSH1`
does `newpsw[18] = 0` unconditionally, and PSW bit 18 is `IE`. Databook p.
3.269 step (ii) is explicit that only *interrupts* clear it and that on an
exception "PSW.IE unchanged". This affects every synchronous pusher in the core
— `BRKV`, `TRAP`, `CHLVL`, `TRAPFL`, the zero divide — not just this tranche,
and it is invisible until an exception handler is expected to remain
interruptible.

The rest of `S_EXC_PUSH1` matches p. 3.269: `newpsw[16]=0` (`TE`),
`newpsw[27]=0` (`TP`), `newpsw[17]=0` (`AE`) are step (iii); `newpsw[29]=0`
(`EM`) is step (iv); `newpsw[25:24] = exc_target_level` with a default of zero
is step (i); `if (exc_is_interrupt) newpsw[28] = 1` (`IS`) is step (vii)'s
interrupt half. `newpsw[31] = 1` is presumably step (v)'s `PSW.ASA ← 1`, which
is consistent but unconfirmed — see the open item above.

**5. Nothing switches to `L0SP`.** Step (vii) says an exception's frame goes on
the level-0 stack, and step (i) has already forced `PSW.EL ← 00`. The
MAME-derived core has a single flat R31 and no per-level stack pointers, so it
pushes wherever R31 happened to point. The clean-room `v60_regfile.sv` *does*
have the five-pointer cache and a `stack_switch` input
(`docs/v60/TRANCHE-TWO.md`), so this is the same missing-consumer problem
`CHLVL` has — and it turns out to belong to **every** exception, not just
`CHLVL`.
