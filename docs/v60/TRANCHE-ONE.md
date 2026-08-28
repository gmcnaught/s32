# Tranche one: the twenty-three that need no new subsystem

Semantics for `NOP` `HALT` `BRK` `BRKV` `TRAP` `TRAPFL` `GETPSW` `UPDPSW.H`
`UPDPSW.W` `LDPR` `STPR` `MOVEA` `SETF` `INC` `DEC` `RVBIT` `RVBYT` `TEST1`
`SET1` `CLR1` `NOT1` `IN` `OUT`.

Encodings are already confirmed against pp. 3.296/3.297/3.298/3.299 and against
`tools/v60x/insn_table.py`; every Opcode line quoted below is the Programmer's
Reference §7 page's own, and where the two books differ it is called out.
Exception numbers are decoded with `docs/v60/INSTRUCTION-SUMMARY-LEGEND.md`.
Operand notation is the Reference's `name.size.access`.

Read **"Two things that bite before you start"** first — one of them changes
what `SETF` and `TRAP` decode, and the other changes what every exception
column in this document means.

---

## Two things that bite before you start

### 1. `SETF` and `TRAP` put the condition in opposite nibbles

Both take a one-byte operand carrying a 4-bit condition code, and they do
**not** agree on where it lives.

**`TRAP`** (§7, `TRAP`):

> The **upper four bit field** of the operand contains the condition code field
> which indicates under what circumstances the trap will be taken. The lower
> four bit field contains the vector offset from the software trap base vector.

**`SETF`** (§7, `SETF`):

> The condition code field is found in the **lower four bits** of the condition
> operand. The upper four bits are ignored and have no effect on this
> instruction.

So `trap` is `{cond[3:0], vector[3:0]}` and `setf` is `{ignored, cond[3:0]}`.
Sharing one condition-evaluator between them is right; sharing the nibble
extraction is a bug. Both use p. 3.295's Condition Encodings table (each page
reprints it in full, and both reprints match p. 3.295 row for row).

### 2. The databook's exception legend cannot name the exception these pages do

Eight of the twenty-three name **Illegal Data Field** in their Exceptions
block. The Reference's §8 defines it and places it:

> An illegal data field exception occurs when an error is detected in the size
> of an operand.

It is **`#20 Illegal Data Field`** in the Instruction Exceptions list (`#16
Reserved Opcode`, `#17 Privileged Instruction`, `#18 Reserved Addressing
Mode`, `#19 Illegal Addressing Mode / Illegal Instruction Format`, `#20
Illegal Data Field`), at vector-table offset **+80** = 4 × 20.

p. 3.299's legend has no entry for it. Its twelve codes are the ones in
`INSTRUCTION-SUMMARY-LEGEND.md`, and code 2 is "Illegal Data Type" — a name
that **appears nowhere in the Programmer's Reference** except in the appendix
where the Reference reprints the databook's own legend verbatim (same twelve
entries, same "Undeflow" typo, so it is the same table, not a second source).

The evidence that code 2 *is* Illegal Data Field:

| | plate | Reference Exceptions block |
|---|---|---|
| `TEST1` `SET1` `CLR1` `NOT1` | `1, 2` | Illegal Data Field |
| `LDPR` | `2, 12` | Privileged Instruction, Illegal Data Field |
| `STPR` | `1, 2, 12` | Privileged Instruction, Illegal Data Field |

Three groups, and under the identification `2 = Illegal Data Field` all three
line up exactly, with `1` accounted for by the `X Illegal Addressing Mode`
cells in each page's Addressing Modes table and `12` by Privileged
Instruction.

The evidence against: the character manipulation group (`MOVC` … `SKPC`) also
names Illegal Data Field on every page and the plate prints **`1, 3`** there,
not `1, 2` — verified at 600 dpi on both plates, the glyphs are unambiguous
(`docs/v60/CHARACTER-STRING.md`).

**Decision, and it is a decision:** treat the Reference's per-instruction
Exceptions blocks as authoritative, and treat the plate's number column as a
coarse summary that is right about privilege and addressing and unreliable
about operand-size faults. Every "Exceptions" line below is the Reference's,
with the plate's number given alongside so the disagreement is visible rather
than smoothed over.

---

## Group 1 — no operands, no flags

### NOP — No Operation

```
nop                                     Opcode CD        Format V
```

Operation:

> `PC ← PC + 1`

> No action is taken. The NOP instruction can be used to secure a place in the
> code stream or to create a program delay.

Condition Codes: `CY Unchanged / OV Unchanged / S Unchanged / Z Unchanged`.

Exceptions: **None**. Plate: blank. Privileged: **no**.

The Operation line is the implementation, and it is worth noting it says
`+ 1` — `NOP` is a one-byte instruction, not a two-byte Format V with a
padding byte.

### HALT — Halt

```
halt                                    Opcode 00        Format V
```

Operation: `halt`

> The processor halts and waits for an interrupt. Following the execution of
> the interrupt handler, program execution will continue with the instruction
> following the HALT instruction.

Condition Codes: all four Unchanged.

Exceptions: **Privileged Instruction** (#17). Plate: `12`. Privileged:
**yes** — p. 3.299's Privileged Instructions block and the Reference's own
Exceptions block agree.

The sentence settles the resume point: the saved PC is `HALT + 1`, not `HALT`,
so the processor does not re-halt on return. Note also that the databook's
p. 3.233 bus-status table has a **Halt Acknowledge** cycle (`MRQ*,ST2-ST0 =
1101`), which is how a halted V60 announces itself; nothing on the `HALT` page
mentions it.

### TRAPFL — Trap on Floating Point Exception

```
trapfl                                  Opcode CB        Format V
```

Operation:

> `if ( TKCW[8:4] ∧ PSW[12:8] ) ≠ 0 then`
> `    Floating Point Operation Exception`

> The bit-wise AND of floating point trap mask field in the TKCW register and
> the floating point condition codes in the PSW is computed and if the result
> is non-zero, a floating point operation trap will occur.

Condition Codes: `CY OV S Z` all Unchanged, **and** `FIV FZD FOV FUD FPR` all
Unchanged. `TRAPFL` reads the floating point flags and does not touch them.

Exceptions (Reference): Floating Point Zero Divide (11), Invalid Floating
Point Operation (10), Floating Point Overflow (6), Floating Point Underflow
(7), Floating Point Precision (8).

Plate: **`1, 3, 6, 7, 9`** — verified at 600 dpi. **This one is a plate
defect, and demonstrably so:** `TRAPFL` is Format V with no operands at all,
so codes 1 (Illegal Addressing Mode) and 3 (Reserved Addressing Mode) cannot
arise; and the column omits 8, 10 and 11 while adding 9 (Reserved Floating
Point Operand), which is a *source-operand* condition that a no-operand
instruction cannot produce. Take the Reference.

Privileged: **no**. Neither book puts it in the privileged block.

`PSW[12:8]` is `{FIV, FZD, FOV, FUD, FPR}` MSB-down — see the PSW map below —
and `TKCW[8:4]` is the matching enable field (`docs/v60/FLOATING-POINT.md`
has TKCW's layout: bit 4 FPT, bit 5 FUT, and the rest of the mask).

---

## Group 2 — the three that push an exception frame

All three are Format V, one byte, no operands, and leave `CY OV S Z`
unchanged. What separates them is **which vector**, **whether it is
conditional**, and **how many words go on the stack**.

### BRK — Break

```
brk                                     Opcode C8        Format V
```

Operation:

```
[-SP] ← Exception Code
[-SP] ← PSW
[-SP] ← NextPC
PC ← [ Exception Vector 13 ]
```

> The breakpoint trap is asserted and program control is transferred to the
> breakpoint trap exception handler.

Condition Codes: all four Unchanged. Exceptions: **Breakpoint Trap**. Plate:
blank. Privileged: **no**.

**Three pushes**, unconditionally.

### BRKV — Break on Overflow

```
brkv                                    Opcode C9        Format V
```

Operation:

```
[-SP] ← CurrentPC
[-SP] ← Exception Code
[-SP] ← PSW
[-SP] ← NextPC
PC ← [ Exception Vector 21 ]
```

> The OV flag is tested and if set, an Integer Overflow Exception occurs.
> Otherwise, instruction execution continues witht the next instruction.

Condition Codes: all four Unchanged. Exceptions: **Integer Overflow**. Plate:
blank. Privileged: **no**.

**Four differences from `BRK`, all of them load-bearing:**

1. It is **conditional on `PSW.OV`**. With OV clear it is a one-byte no-op and
   nothing is pushed.
2. Vector **21**, not 13.
3. It pushes a **fourth** word, `CurrentPC`, *above* the Exception Code — the
   Arithmetic Exceptions frame of Figure 8-5, which `docs/v60/MULTIPLY-DIVIDE.md`
   already documents from the divide side:

   ```
      +12   PC (Current PC)
      +8    Exception Code  |  8
      +4    PSW
       0    PC (Next PC)
   ```

   The parameter count in the code word is 8 = 4 × (1 parameter + 1), so a
   handler returns with `RETIS #8`. `BRK`'s frame has no parameter.
4. Its return address is `NextPC` on top *and* `CurrentPC` as a parameter, so
   the handler can see both; `BRK` gives only `NextPC`.

`rtl/cpu/v60x/v60_exc.sv`'s header already quotes this Operation block, and it
matches the page word for word.

### TRAP — Trap on Condition

```
trap cond&vector.b.r                    Opcode F8/9      Format III
```

Operation:

```
if ( condition ) then
    [-SP] ← Exception Code
    [-SP] ← PSW
    [-SP] ← NextPC
    PC ← [ Exception Vector( 48 + vector ) ]
```

> If the specified condition is satisfied by the integer condition codes, the
> specified trap handler is entered. The **upper four bit field** of the
> operand contains the condition code field which indicates under what
> circumstances the trap will be taken. The **lower four bit field** contains
> the vector offset from the software trap base vector.

Condition Codes: `CY Unaffected / OV Unaffected / S Unaffected / Z Unaffected`
— this page says "Unaffected" where every other page in the tranche says
"Unchanged"; nothing suggests a difference in meaning.

Exceptions: **Software Trap**. Plate: blank. Privileged: **no**.

**Vector mapping.** The operand's low nibble is 0..15 and the vector is
`48 + vector`, so `TRAP` reaches **vectors 48 through 63** and nothing else.
Those are the SBT (System Base Table) entries at byte offsets `4 × 48 = 192`
(`0xC0`) through `4 × 63 = 252` (`0xFC`), and the SBT is reached through the
`SBR` privileged register (id 5) — a **System Base Table Access** bus cycle,
`MRQ*,ST2-ST0 = 0100` (p. 3.233).

**The frame is `BRK`'s, not `BRKV`'s** — three pushes, no `CurrentPC`
parameter, so the handler's return address is `NextPC` and a software trap
returns *past* the `trap` instruction.

**`s32_v60.sv`'s reading is confirmed**: its `opTRAP` takes the condition from
the operand's high nibble, which is what the page says.

**One thing the page does not settle.** `TRAP`'s Addressing Modes table marks
`Immediate.Quick` as `O` (permitted) for `cond&vector`. Immediate quick is a
4-bit field, so a quick-immediate `trap` supplies only the low nibble and the
condition nibble is `0000` — which p. 3.295 names `V`, "OV = 1". Whether that
is the intent, or whether the quick immediate is placed differently for this
instruction, the page does not say. Nothing here decides it.

---

## Group 3 — PSW access

### The PSW map (Reference §3, pp. 3-3/3-4)

Needed by `GETPSW`, `UPDPSW.H` and `UPDPSW.W`, and quoted here so no one has
to guess a mask.

| bit(s) | name | meaning |
|---|---|---|
| 0 | `Z` | "the results of the operation were zero" |
| 1 | `S` | "the results are negative (signed) or ... the MSB is set (unsigned)" |
| 2 | `OV` | "an overflow occurred" |
| 3 | `CY` | "a carry or borrow was generated" |
| 4:7 | RFU | Reserved for future use |
| 8 | `FPR` | floating point precision (inexact) |
| 9 | `FUD` | floating point underflow |
| 10 | `FOV` | floating point overflow |
| 11 | `FZD` | floating point zero divide |
| 12 | `FIV` | invalid floating point operation |
| 13:15 | RFU | Reserved for future use |
| 16 | `TE` | trace enable |
| 17 | `AE` | address trap enable |
| 18 | `IE` | interrupt enable |
| 19:23 | RFU | Reserved for future use |
| 24:25 | `EL` | execution level (`00` = privileged) |
| 26 | `IP` | "whether or not an instruction has been interrupted and should be resumed" |

Two things fall out of that table:

- `PSW[12:8]` read MSB-down is `{FIV, FZD, FOV, FUD, FPR}`, which is exactly
  what `TRAPFL`'s Operation block ANDs against `TKCW[8:4]`.
- **Bit 26 `IP` is the resume flag** for the interruptible variable-length
  instructions — the ones `docs/v60/CHARACTER-STRING.md` covers. It is not in
  tranche one, but it is in the halfword that `UPDPSW.W` can write, so a
  tranche-one `UPDPSW.W` implementation is already touching state that a later
  tranche depends on.

And the governing rule (§3):

> The PSW is divided into upper and lower halfwords with the **upper halfword
> being modified only by means of the privileged UPDPSW.W instruction**. The
> lower halfword of the PSW has two fields containing the integer and floating
> point condition codes. The upper halfword contains the processor control and
> status fields for the currently executing task.

> **The contents of the PSW can be read regardless of the execution level.**
> The PSW is modified according to the following conditions:
> • the integer and floating point condition codes can be modified using the
>   UPDPSW.H instruction
> • the control and condition code fields can be modified at execution level
>   \[0\] by the privileged UPDPSW.W instruction
> • the status field is modified by the execution of certain instructions such
>   as CHLVL and RETIS

### GETPSW — Get PSW

```
getpsw dst.w.w                          Opcode F6/7      Format III
```

Operation: `dst ← PSW`

> The contents of the Program Status Word (PSW) are copied to the destination
> operand.

Condition Codes: all four Unchanged. Exceptions: **None**. Plate: `1`.
Privileged: **no**, and §3 says so explicitly ("can be read regardless of the
execution level").

One operand, word-wide, write-only. The whole 32 bits are readable including
the privileged upper halfword.

### UPDPSW.H / UPDPSW.W — Update PSW

The Reference prints these on **one page** with one Operation block and one
Exceptions block.

```
updpsw.h newPSW.w.r, mask.w.r           Opcode 4A        Format I, II
updpsw.w newPSW.w.r, mask.w.r           Opcode 13        Format I, II
```

**Both operands are `.w` — full 32-bit words — in both forms.** The `.h` in
`updpsw.h` names *which half of the PSW it may modify*, not the operand size.
That is the single most likely place to get this wrong.

Operation, and this one line is the implementation:

> `PSW ← ( PSW ∧ ¬mask ) ∨ ( newPSW ∧ mask )`

> The contents of the PSW are updated with the contents of the new PSW image at
> the positions specified by the mask operand. **The UPDPSW.H instruction is
> restricted to modifying only the condition code fields in the PSW. The
> UPDPSW.W is a privileged instruction and can also modify the PSW control
> field.**

> If the immediate quick addressing mode is specified, the immediate data is
> zero extended to 32-bit length and used as the new PSW or mask operand.

Condition Codes — the whole block is one line:

> `Updated according to mask operand`

Exceptions:

> `Privileged Instruction (updpsw.w)`

One block, with the parenthetical scoping it. So **`UPDPSW.W` is privileged
and `UPDPSW.H` is not**, which is exactly what p. 3.299 says by putting
`UPDPSW.W` in the Privileged Instructions block with code `12` and leaving
`UPDPSW.H` on p. 3.298 under Miscellaneous with no `12`. Two books, same
answer, no surprise.

**Which bits each writes.** `UPDPSW.W` writes wherever the mask is set. For
`UPDPSW.H` the page's constraint is *"restricted to modifying only the
condition code fields"*, and §3 names those fields as "the integer and
floating point condition codes" — i.e. `CY OV S Z` at bits 3:0 and
`FIV FZD FOV FUD FPR` at bits 12:8. So `UPDPSW.H`'s effective write mask is
`mask ∧ 0x0000_10FF`.

**Three things the pages do not settle, and they matter for an
implementation:**

- **What `UPDPSW.H` does with mask bits outside `0x10FF`.** "Restricted to
  modifying" could mean the bits are silently ignored, or that setting them
  raises. The Exceptions block names only Privileged Instruction, and only for
  `.w`, so there is no exception on offer — which argues for silent masking,
  but the page does not say it.
- **What either form does to the RFU bits** (4:7, 13:15, 19:23). The Operation
  line writes them if the mask does. `UPDPSW.H`'s restriction covers 4:7 and
  13:15 by excluding them; nothing covers `UPDPSW.W` writing 19:23.
- **Whether `UPDPSW.W` may write `EL` (24:25).** §3 calls 24:25 part of the
  control/status information and says the status field "is modified by the
  execution of certain instructions such as CHLVL and RETIS" — which reads as
  a different mechanism from `UPDPSW.W`, but the Operation line does not
  exclude those bits. A `UPDPSW.W` that can raise its own execution level
  would make privilege meaningless, so this is worth deciding deliberately.

---

## Group 4 — privileged register access

### LDPR — Load Privileged Register

```
ldpr src.w.r, regID.w.w                 Opcode 12        Format I, II
```

Operation: `PrivilegedRegister( regID ) ← src`

> The source operand is loaded into the specified privileged register.

Condition Codes: all four Unchanged.

Exceptions: **Privileged Instruction** (#17) and **Illegal Data Field** (#20).
Plate: `2, 12`. Privileged: **yes**.

### STPR — Store Privileged Register

```
stpr regID.w.r, dst.w.w                 Opcode 02        Format I, II
```

Operation: `dst ← PrivilegedRegister( regID )`

> The contents of the specified privileged register are copied to the
> destination operand.

Condition Codes: all four Unchanged.

Exceptions: **Privileged Instruction** (#17) and **Illegal Data Field** (#20).
Plate: `1, 2, 12`. Privileged: **yes**.

### The per-id tables, and the two ids that differ

Both pages print an ID/Register/Name table. They are **not the same table**:

| ID | Name | Register | `LDPR` (write) | `STPR` (read) |
|---|---|---|---|---|
| 0 | `ISP` | Interrupt Stack Pointer | yes | yes |
| 1 | `L0SP` | Level 0 Stack Pointer | yes | yes |
| 2 | `L1SP` | Level 1 Stack Pointer | yes | yes |
| 3 | `L2SP` | Level 2 Stack Pointer | yes | yes |
| 4 | `L3SP` | Level 3 Stack Pointer | yes | yes |
| 5 | `SBR` | System Base Register | yes | yes |
| **6** | `TR` | Task Register | **absent** | yes |
| 7 | `SYCW` | System Control Word | yes | yes |
| 8 | `TKCW` | Task Control Word | yes | yes |
| **9** | `PIR` | Processor ID Register | **absent** | yes |
| 15 | `PSW2` | Emulation Mode Program Status Word | yes | yes |
| 16 | `ATBR0` | Area Table Base Register 0 | yes | yes |
| 17 | `ATLR0` | Area Table Length Register 0 | yes | yes |
| 18 | `ATBR1` | Area Table Base Register 1 | yes | yes |
| 19 | `ATLR1` | Area Table Length Register 1 | yes | yes |
| 20 | `ATBR2` | Area Table Base Register 2 | yes | yes |
| 21 | `ATLR2` | Area Table Length Register 2 | yes | yes |
| 22 | `ATBR3` | Area Table Base Register 3 | yes | yes |
| 23 | `ATLR3` | Area Table Length Register 3 | yes | yes |
| 24 | `TRMOD` | Trap Mode Register | yes | yes |
| 25 | `ADTR0` | Address Trap Register 0 | yes | yes |
| 26 | `ADTR1` | Address Trap Register 1 | yes | yes |
| 27 | `ADTRM0` | Address Trap Mask Register 0 | yes | yes |
| 28 | `ADTRM1` | Address Trap Mask Register 1 | yes | yes |

**Ids 6 (`TR`) and 9 (`PIR`) are readable and not writable** — they are in
`STPR`'s table and absent from `LDPR`'s. Both names say why: a Processor ID
Register is a constant, and the Task Register is loaded by `LDTASK` rather
than by hand. Ids 10-14 and 29-31 appear in neither table.

### What happens on a bad id, in the pages' own words

The two pages say **different** things, and this is the wording the lead
asked for.

**`STPR`** is precise:

> An Illegal Data Field exception will occur if the register ID field is not
> in the range of \[0\] to 31. Instruction execution results will also be
> unpredicatable if an undefined register ID is specified.

Two distinct cases: **id ≥ 32 raises #20**; an id inside 0..31 that names no
register is **unpredictable, with no exception**.

**`LDPR`** gives only the second half:

> Instruction execution results are unpredicatable if an invalid register ID
> is specified.

Its Exceptions block still lists Illegal Data Field, so the range check is
presumably the same, but the `LDPR` page does not state the boundary.

**Reading it as an implementer:** the checkable rule is `regID > 31 → Illegal
Data Field (#20, vector +80)`, on both instructions. Everything else in
0..31 — the gaps at 10-14 and 29-31, and 6/9 on `LDPR` — is explicitly
*unpredictable*, which means the pages permit any behaviour and do **not**
license an exception. `v60_regfile`'s per-id permission table therefore
implements a policy the pages allow rather than one they require, and a
sequencer that raises on a gap id is going beyond the page. That is fine as a
choice; it should be recorded as one.

### LDPR's side effects, which nothing else in tranche one has

> • Loading to area table base and length registers clears TLB entries with
>   corresponding section numbers.
> • The TLB is cleared if the virtual mode is changed to physical mode in the
>   STCW register.

Ids 16-23 therefore have an MMU side effect, and id 7 (`SYCW` — the page calls
it `STCW` in that sentence, which is the only place either spelling appears
with the other's meaning) can invalidate the whole TLB. Neither matters until
there is a TLB, but a tranche-one `LDPR` that silently drops these is
incomplete rather than correct.

---

## Group 5 — the I/O pair

### IN — Input

```
in.b  port.b.r, dst.b.w        Input Byte
in.h  port.h.r, dst.h.w        Input Halfword
in.w  port.w.r, dst.w.w        Input Word
                                        Format I, II
```

Operation: `dst ← port`

> The contents of the specified input port are copied to the destination
> operand.

### OUT — Output

```
out.b src.b.r, port.b.w        Output Byte
out.h src.h.r, port.h.w        Output Halfword
out.w src.w.r, port.w.w        Output Word
                                        Format I, II
```

Operation: `port ← src`

> The source operand is copied to output port.

Both: Condition Codes all four Unchanged. Exceptions: **Privileged
Instruction** (#17). Plate: `1, 12`. Privileged: **yes**, and §4 says it in
the strongest possible terms (below).

### The opcode disagreement is resolved, in the databook's favour

`insn_table.py`'s `DISAGREEMENTS` records that "databook p.3.299 prints
`00100.siz.0` (20 22 24); the Programmer's Reference §7 page for IN prints
'Opcode 21 23 25'". Reading the **`OUT`** page settles it:

| | plate (p. 3.299, 600 dpi) | Reference Opcode line |
|---|---|---|
| `IN` | `0 0 1 0 0 siz 0` → `20 22 24` | `21 23 25` |
| `OUT` | `0 0 1 0 0 siz 1` → `21 23 25` | `21 23 25` |

The Reference prints **the same three bytes on both pages**, which cannot be
right — they would collide. `OUT`'s value matches the plate exactly, so the
corrupted column is `IN`'s: its page carries `OUT`'s opcodes. **The databook
is right and the Reference's `IN` page is wrong**; `IN` is `20/22/24`, which
is what `insn_table.py` already has. The entry can be downgraded from an open
disagreement to a resolved one.

(This is not an OCR artefact of the sort the `5O08`-for-`5C-08` cases were —
the digits are individually plausible; it is the whole column repeated.)

### What address an I/O access uses

The syntax lines make `port` an ordinary addressed operand, and its Addressing
Modes column marks `Rn` as `X` (Illegal) on both instructions while permitting
every memory mode. So **the I/O address is the port operand's effective
address**, computed by the normal addressing machinery; what makes it an I/O
access is that the bus cycle is directed at the I/O address space rather than
memory — `MRQ*` high, `Single Mode I/O Access`, `MRQ*,ST2-ST0 = 1011`
(p. 3.233). `Rn` is illegal precisely because a register has no address to
send.

§4 (Reference, "I/O Address Space" / "I/O Space Access") gives the range, and
this is the sentence to implement against:

> The I/O address space is used for the placement and control of peripheral
> devices without requiring the reservation of a portion of the memory address
> space. Like the memory address space, the I/O address space is **16MB in
> size** with addresses ranging from 0x000000 to 0x\[FF\]FFFF in byte units.
> The valid I/O address space access ranges are completely determined by each
> individual system.

> **I/O space accesses are always generated by the execution of the privileged
> IN and OUT instructions.** An I/O port address is specified as a **32-bit
> operand** but because of the external address bus size restriction, **bits
> 24:31 of a port address must be zero. The operation using an I/O port address
> outside the range 0x00000000 to 0x00FFFFFF is unpredictable.**

So: a full 32-bit effective address is computed, the top byte must be zero, and
anything else is unpredictable rather than an exception. The address bus is 24
bits (p. 3.233's pin description) and that is the whole reason.

**Legal widths** are the three the `siz` field encodes — byte, halfword, word —
with `siz = 11` reserved (p. 3.295). There is no doubleword `IN`/`OUT`.

**One thing to carry over from the bus plates**: p. 3.291's three-TI recovery
rule is scoped to I/O — "three TI states are inserted between any consecutive
pair of I/O bus cycles" — and `rtl/cpu/v60x/v60_bus_pkg.sv` already implements
that as `bst_needs_io_recovery()`. Driving `v60_dxu`'s unused `io` input is
what makes that path reachable; nothing else in the instruction set can.

**What the pages do not settle:** whether a misaligned I/O halfword or word is
split into two I/O bus cycles the way a misaligned memory access is (p. 3.235's
`FAS*` description covers "any multiple bus cycle data transfer" without
excluding I/O), and whether the recovery gap applies between the two halves of
one split I/O access or only between separate accesses.

---

## Group 6 — the simple data-movement three

### MOVEA — Move Effective Address

```
movea.b src.b.n, dst.w.w       Move Byte Effective Address        40
movea.h src.h.n, dst.w.w       Move Halfword Effective Address    42
movea.w src.w.n, dst.w.w       Move Word Effective Address        44
                                        Format I, II
```

Operation: `dst ← effective_address( src )`

> The effective address of the source operand is transferred to the
> destination operand. **The source operand is not referenced and remains
> unchanged.** Separate instructions are provided for byte, halfword and word
> operands to permit correct computation of effective addresses using the
> autoincrement, autodecrement and scaled index addressing modes.

Condition Codes: all four Unchanged. Exceptions: **None**. Plate: `1`.
Privileged: **no**.

**The access type is `.n`** — not `r`, not `w`. It is the only one in this
tranche and it means what the Description says: no bus cycle is issued for
`src`. The destination is always `.w` (a word) regardless of the `siz` field,
because an address is 32 bits.

**`siz` still matters even though nothing is read**, and the second Description
sentence is why: `[Rn+]` steps by the operand size and `(Rx)` scales by it, so
`movea.w [R1+], R2` leaves `R1` four higher while `movea.b [R1+], R2` leaves it
one higher. A `MOVEA` that ignores `siz` because it issues no access is wrong
in exactly the cases the sentence names.

### RVBIT — Reverse Bit Order

```
rvbit src.b.r, dst.b.w                  Opcode 08        Format I, II
```

Operation: `dst ← bit_reversed( src )`

> The individual bits of the byte data addressed by the source operand are
> reversed

The page's diagram is `B7 B6 B5 B4 B3 B2 B1 B0` above and `B0 B1 B2 B3 B4 B5
B6 B7` below, so `dst[i] = src[7-i]`.

> The source operand is unaffected by this instruction.

> If the immediate quick addressing mode is specified for the source operand,
> the immediate data is zero extended to byte length before the bit reversal
> takes place.

Condition Codes: all four Unchanged. Exceptions: **None**. Plate: `1`.
Privileged: **no**.

**Byte operands.** `RVBIT` is `.b` in and `.b` out — it reverses eight bits,
not thirty-two. The zero-extension sentence has a sharp consequence: a quick
immediate is 0..15, so `rvbit #1, dst` reverses `0000_0001` and stores
`1000_0000`.

### RVBYT — Reverse Byte Order

```
rvbyt src.w.r, dst.w.w                  Opcode 2C        Format I, II
```

Operation: `dst ← byte_reversed( src )`

The diagram is `Byte3 Byte2 Byte1 Byte0` above and `Byte0 Byte1 Byte2 Byte3`
below — a full 32-bit endian swap.

> The byte order of 16-bit data can be reversed by the ROT instruction.

> If the immediate quick addressing mode is specified for the source operand,
> the immediate data is zero extended to word length before the byte reversal
> takes place.

> This instruction is provided to simplify data transfers between machines
> adopting different integer notations.

Condition Codes: all four Unchanged. Exceptions: **None**. Plate: `1`.
Privileged: **no**.

The `ROT` remark is the page telling you there is deliberately no halfword
form: `rot.h #8, dst` is the 16-bit swap (`docs/v60/SHIFTS.md`).

**Neither `RVBIT` nor `RVBYT` touches a flag.** Both plates print blank flag
rows and both Condition Codes blocks are four `Unchanged` lines — so a
byte-swap does not set `Z` even when the result is zero.

### SETF — Set Flag

```
setf cond.b.r, dst.b.w                  Opcode 47        Format I, II
```

Operation:

```
if ( condition ) then
    dst ← 01H
else
    dst ← 00H
```

> If the specified condition is satisfied by the interger PSW condition codes,
> the value 01H (true) is stored in the destination. Otherwise, the value 00H
> (false) is stored in the destintion.

> The condition code field is found in the **lower four bits** of the condition
> operand. The upper four bits are ignored and have no effect on this
> instruction.

Condition Codes: all four Unchanged. Exceptions: **None**. Plate: `1`.
Privileged: **no**.

**What `SETF` actually sets is the *destination byte*, not a flag.** The name
is misleading: it materialises a condition as a boolean byte and leaves
`CY OV S Z` alone. Both operands are bytes; the stored values are exactly
`0x01` and `0x00`, not "non-zero" and "zero". The condition table the page
reprints is p. 3.295's, all sixteen codes including `1010 T Always` and
`1011 F Never`, so `setf #0x0A, dst` stores 1 unconditionally and
`setf #0x0B, dst` stores 0.

---

## Group 7 — INC and DEC

```
inc.b dst.b.rw    Increment Byte        D8/9      Format III
inc.h dst.h.rw    Increment Halfword    DA/B
inc.w dst.w.rw    Increment Word        DC/D
dec.b dst.b.rw    Decrement Byte        D0/1      Format III
dec.h dst.h.rw    Decrement Halfword    D2/3
dec.w dst.w.rw    Decrement Word        D4/5
```

Operation: `dst ← dst + 1` / `dst ← dst - 1`

> The contents of the destination operand are incremented \[decremented\].

> The INC instruction is a shorter encoding for the more general instruction
> `add #1, dst`

> The DEC instruction is a shorter encoding for the more general instruction
> `sub #1, dst`

Those two sentences are the specification: **the flags are `ADD`'s and
`SUB`'s exactly**, and the Condition Codes blocks confirm it term for term.

`INC`:

```
CY  Set if a carry is generated, otherwise cleared
OV  Set if integer overflow occurs, otherwise cleared
S   Set if the result is negative, otherwise cleared
Z   Set if the result is zero, otherwise cleared
```

`DEC` is identical except:

```
CY  Set if a borrow is generated, otherwise cleared
```

So `inc.b 0xFF` gives `0x00` with `CY=1 OV=0 S=0 Z=1`, and `inc.b 0x7F` gives
`0x80` with `CY=0 OV=1 S=1 Z=0`. `dec.b 0x00` gives `0xFF` with `CY=1`
(borrow) `OV=0 S=1 Z=0`.

Exceptions: **None** on both (`INC`'s block is headed "Instruction
Exceptions"; `DEC`'s "Exceptions"; both say `None`). Plate: `1` on both, from
the `X Illegal Addressing Mode` cells against Immediate.Quick and Immediate in
each page's table. Privileged: **no**.

**One paragraph on both pages is boilerplate and should be ignored**: "If the
immediate quick addressing mode is specified for the source operand, the
immediate data is zero extended to the source operand length before performing
the operation." `INC` and `DEC` are Format III with **one** operand and no
source; the sentence is copied from `ADD`/`SUB` and describes nothing here. It
is worth naming because it is the kind of stray sentence an implementer can
spend an hour trying to honour.

---

## Group 8 — the four bit instructions

One shape, four instructions, and the flag rule the lead expected is confirmed
verbatim on all four pages.

```
test1 offset.w.r, base.w.r      Bit Test                    87    Format I, II
set1  offset.w.r, base.w.rw     Bit Test and Set            97    Format I, II
clr1  offset.w.r, base.w.rw     Bit Test and Clear          A7    Format I, II
not1  offset.w.r, base.w.rw     Bit Test and Complement     B7    Format I, II
```

Operations — the two flag lines are identical on all four, and only the third
line differs:

```
TEST1:  CY ← bit( base, offset )
        Z  ← ~bit( base, offset )

SET1:   CY ← bit( base, offset )
        Z  ← ~bit( base, offset )
        bit( base, offset ) ← 1

CLR1:   CY ← bit( base, offset )
        Z  ← ~bit( base, offset )
        bit( base, offset ) ← 0

NOT1:   CY ← bit( base, offset )
        Z  ← ~bit( base, offset )
        bit( base, offset ) ← ~bit( base, offset )
```

Condition Codes — the same four lines on all four pages:

```
CY  Set if the designated bit is 1, otherwise cleared
OV  Unchanged
S   Unchanged
Z   Set if the designated bit is 0, otherwise cleared
```

**Confirmed: `CY` takes the tested bit's prior value and `Z` is its
complement.** Every page states it a second time in prose — "The CY and Z flags
reflect **the state of the bit prior to the execution of the instruction**" —
so `set1` on a bit that was already 1 leaves `CY=1 Z=0`, and `set1` on a clear
bit leaves `CY=0 Z=1` *after having set it*. `CY` and `Z` are always
complements here; there is no input for which they agree.

Exceptions: **Illegal Data Field** (#20) on all four. Plate: `1, 2` on all
four. Privileged: **no**.

Three rules shared by all four, quoted because each one is a decision point:

**Where the bit is.**

> The location of the designated bit is determined by the base operand. If the
> register addressing mode is used for the base operand, the designated bit is
> located within a general purpose register at the specified bit offset. For
> any other addressing mode, the designated bit is at the specified bit offset
> from the base address.

So `base` is dual-natured: `Rn` means "inside that register", anything else
means "at that bit offset from that address". The two need different datapaths.

**The offset range, which is the exception.**

> An Illegal Data Field exception occurs if the bit offset is outside the range
> 0 to 31.

That is the *only* thing any of these four can raise, and it is a range check
on a word-wide operand's value, not on an addressing mode. Note the
consequence: even with a memory base, the reachable bits are `base+0` through
`base+31` — one word — despite the "sum of the byte base address and bit
offset" phrasing suggesting an unbounded bit array. `EXTBF`/`INSBF` are what
reach further.

**Autoincrement steps by four.**

> If the autoincrement or autodecrement addressing mode is specified for the
> base operand, the base operand is treated as **word data** and is incremented
> or decremented by four.

`base` is `.w`, so `[Rn+]` moves `Rn` by 4 — not by 1, and not by the bit
offset.

**And the quick immediate is zero extended.**

> When the immediate quick addressing mode is specified, the immediate data is
> zero extended to word length and used as the bit offset.

A quick immediate is 4 bits, so a quick `offset` covers bits 0..15 only and can
never be out of range. Reaching bits 16..31 needs a full immediate or a
register.

---

## Summary table

| | opcode | fmt | operands | flags moved | Exceptions (Reference) | plate | priv |
|---|---|---|---|---|---|---|---|
| `NOP` | `CD` | V | — | none | None | — | no |
| `HALT` | `00` | V | — | none | Privileged Instruction | `12` | **yes** |
| `BRK` | `C8` | V | — | none | Breakpoint Trap | — | no |
| `BRKV` | `C9` | V | — | none | Integer Overflow | — | no |
| `TRAP` | `F8/9` | III | 1 (`.b.r`) | none | Software Trap | — | no |
| `TRAPFL` | `CB` | V | — | none | FP ZeroDiv, InvalidOp, Ovf, Unf, Prec | `1,3,6,7,9` ✗ | no |
| `GETPSW` | `F6/7` | III | 1 (`.w.w`) | none | None | `1` | no |
| `UPDPSW.H` | `4A` | I,II | 2 (`.w.r`,`.w.r`) | per mask | *(none for `.h`)* | — | no |
| `UPDPSW.W` | `13` | I,II | 2 (`.w.r`,`.w.r`) | per mask | Privileged Instruction | `12` | **yes** |
| `LDPR` | `12` | I,II | 2 (`.w.r`,`.w.w`) | none | Privileged Instruction, Illegal Data Field | `2,12` | **yes** |
| `STPR` | `02` | I,II | 2 (`.w.r`,`.w.w`) | none | Privileged Instruction, Illegal Data Field | `1,2,12` | **yes** |
| `MOVEA` | `40/42/44` | I,II | 2 (`.siz.n`,`.w.w`) | none | None | `1` | no |
| `SETF` | `47` | I,II | 2 (`.b.r`,`.b.w`) | none | None | `1` | no |
| `INC` | `D8/9 DA/B DC/D` | III | 1 (`.siz.rw`) | CY OV S Z | None | `1` | no |
| `DEC` | `D0/1 D2/3 D4/5` | III | 1 (`.siz.rw`) | CY OV S Z | None | `1` | no |
| `RVBIT` | `08` | I,II | 2 (`.b.r`,`.b.w`) | none | None | `1` | no |
| `RVBYT` | `2C` | I,II | 2 (`.w.r`,`.w.w`) | none | None | `1` | no |
| `TEST1` | `87` | I,II | 2 (`.w.r`,`.w.r`) | CY Z | Illegal Data Field | `1,2` | no |
| `SET1` | `97` | I,II | 2 (`.w.r`,`.w.rw`) | CY Z | Illegal Data Field | `1,2` | no |
| `CLR1` | `A7` | I,II | 2 (`.w.r`,`.w.rw`) | CY Z | Illegal Data Field | `1,2` | no |
| `NOT1` | `B7` | I,II | 2 (`.w.r`,`.w.rw`) | CY Z | Illegal Data Field | `1,2` | no |
| `IN` | `20/22/24` | I,II | 2 (`.siz.r`,`.siz.w`) | none | Privileged Instruction | `1,12` | **yes** |
| `OUT` | `21/23/25` | I,II | 2 (`.siz.r`,`.siz.w`) | none | Privileged Instruction | `1,12` | **yes** |

Six are privileged — `HALT`, `UPDPSW.W`, `LDPR`, `STPR`, `IN`, `OUT` — which
is exactly p. 3.299's Privileged Instructions block for these mnemonics, and
each one's own Reference page says so independently. **`UPDPSW.H` is not
privileged and that is deliberate, stated on the shared UPDPSW page ("Privileged
Instruction (updpsw.w)") and in §3.** No surprises against the plate on
privilege.

---

## Where the Reference contradicts the plate

1. **`IN`'s opcode.** Plate `20/22/24`, Reference `21 23 25` — which is
   `OUT`'s column, printed twice. **Plate wins**; the disagreement in
   `insn_table.py` is resolvable.
2. **`TRAPFL`'s exceptions.** Plate `1, 3, 6, 7, 9`; Reference gives 11, 10,
   6, 7, 8. The plate's `1` and `3` are addressing-mode exceptions on a Format
   V instruction with no operands, and its `9` is a source-operand condition.
   **Reference wins.**
3. **`TRAP`'s opcode.** Plate `1110100-` (= `JSR`'s encoding on the same
   page), Reference `F8/9`. Already recorded in `insn_table.py` and
   `INSTRUCTION-SUMMARY-LEGEND.md`; **Reference wins**, and `1111100-` is
   claimed by nothing else.
4. **The exception-column vocabulary.** Eight of the twenty-three name
   *Illegal Data Field* (#20), which p. 3.299's legend cannot express. The
   plate uses code `2` ("Illegal Data Type") for the bit group, `LDPR` and
   `STPR` — consistent with `2 = Illegal Data Field` — but uses `3` ("Reserved
   Addressing Mode") for the character group, which is not. The identification
   is an inference, not a page fact, and it is stated as one above.

Everything else matches: all twenty-three encodings agree between the
Reference's Opcode lines, the plates and `insn_table.py`, and every privilege
assignment agrees between p. 3.299 and the Reference's own Exceptions blocks.

## What the pages do not settle

Twenty of the twenty-three are fully specified by their pages. Three are not,
and one of the three has a further wrinkle:

- **`UPDPSW.H` / `UPDPSW.W`** — three gaps, all listed in Group 3: what
  `UPDPSW.H` does with mask bits outside the condition-code fields (silent
  masking or a fault — no exception is on offer, which argues for masking but
  is not a statement); what either form does to the RFU bits at 4:7, 13:15 and
  19:23; and whether `UPDPSW.W` may write `EL` at 24:25, which §3 attributes to
  `CHLVL`/`RETIS` without excluding it from the Operation line's mask.

- **`LDPR` / `STPR`** — the pages give a *checkable* rule only for `regID > 31`
  (Illegal Data Field, `STPR`'s page; `LDPR`'s Exceptions block implies the same
  but its prose does not state the boundary). Every id inside 0..31 that names
  no register — 10-14, 29-31, and 6/9 on `LDPR` — is declared **unpredictable**
  with no exception. So the per-id permission table `v60_regfile` implements is
  a policy the pages *permit*, not one they *require*, and raising on a gap id
  goes beyond the page. That is a decision to record rather than a defect.

- **`IN` / `OUT`** — the address rule is complete (32-bit effective address,
  bits 24:31 must be zero, outside `0x00000000`–`0x00FFFFFF` is unpredictable
  rather than an exception), but two bus-level questions are not: whether a
  misaligned halfword or word I/O access splits into two I/O bus cycles the way
  a memory access does, and whether p. 3.291's three-TI I/O recovery gap
  applies between the halves of one split access or only between separate
  accesses.

- **`TRAP` with a quick immediate** — permitted by its Addressing Modes table,
  but a 4-bit quick immediate supplies only the vector nibble, leaving the
  condition nibble `0000` = "OV = 1". Whether that is intended or whether the
  quick immediate is placed differently here, the page does not say.

And, as everywhere in this tree, **timing**: the Clocks column is blank on
every one of the twenty-three rows (`docs/v60/INSTRUCTION-TIMING.md`).
