# The doubleword operand

What a 64-bit operand is in a register, what it is in memory, and what the six
instructions that take one actually do with it.

Sources: Programmer's Reference §2 (Data Types, pp. 2-3 and 2-5), §3
(Addressing Modes, the `Rn` page; and the alignment rule), the §7 pages for
`MOV.D`, `MULX`, `MULUX`, `DIVX`, `DIVUX` and the `CVT` pair, and the databook
plates at pp. 3.296 and 3.297 for the flags columns.

**One correction to the premise before anything else.** `CVT.LW` and `CVT.WL`
are **not** doubleword *integer* conversions. The Reference's `CVT` pages
print them as `cvt.wl src.w.r, dst.l.w  Convert Word to Long Real` and
`cvt.lw src.l.r, dst.w.w  Convert Long Real to Word`, and p. 3.297 lists both
in the **Floating Point Instructions** block. They are float↔integer
conversions whose long-real side happens to be 64 bits wide. There is no
integer↔integer doubleword conversion in the V60 instruction set at all. They
still belong to this tranche — a long real needs the same register pair and
the same eight-byte memory access — but they are `docs/v60/FLOATING-POINT.md`
semantically, and §7 of this document says what that means.

---

## 1. The rule

The Reference states it **twice**, on two different pages, in two different
sections, and the two agree.

**§2, Data Types, p. 2-3**, under the access-type diagrams (the doubleword
diagram is labelled `Rn + 1` over `Rn`):

> In the case of the doubleword access type, the operand occupies a pair of
> general purpose registers. **The lower numbered register contains the least
> significant word while the higher numbered register contains the most
> significant word.** However, since R31 cannot be used as the least
> significant register of a doubleword register pair, the results of using R31
> as the source or destination operand of a doubleword access type is
> unpredictable.

**§3, Addressing Modes, the `Rn` (register direct) page:**

> The operand is found in the specified register (or pair of consecutive
> registers). ... For byte or halfword data, the low order portion of the
> register is used (bits 7:0 or 15:0). **For doubleword (64-bit) data, the
> operand resides in the registers Rn and Rn+1, with the least significant word
> located in register Rn.** The use of R31 for doubleword data is
> unpredictable.

So `docs/v60/NEXT-STEPS.md`'s shorthand — "a register PAIR, low register
first" — is correct, and the pages add three things it does not carry:

### There is no evenness constraint

Neither sentence says the pair must start on an even register. §3 says "Rn and
Rn+1" for the specified `Rn`, with no restriction on `n`; §2 says "the lower
numbered register" and "the higher numbered register". **Any `n` from 0 to 30
is a legal pair**, including odd ones — `R7`/`R8` is as valid as `R6`/`R7`.
The only excluded value is 31.

This is worth stating flatly because it is the opposite of the convention on
most machines with register pairs, and an implementation that masks the
low bit of the register number to "align" the pair would be wrong on every odd
`n`. `v60_regfile`'s `assign ra_pair = {gpr[ra_sel + 5'd1], gpr[ra_sel]}` is
right as written.

### R31 is *unpredictable*, not an exception

Both sentences use the word "unpredictable", and neither page's Exceptions
block names anything for it. This is the same construction the pages use for
`LDPR`/`STPR`'s undefined register ids (`docs/v60/TRANCHE-ONE.md`): the
architecture declines to define the behaviour and declines to require a fault.
So an implementation may do anything at all with `R31` as a doubleword
operand — wrap to `{R0, R31}`, read garbage, raise — and none of those is
non-conformant. What it may **not** do is claim the page requires a
particular one.

### The two words are ordered by register number, not by anything else

`Rn` is the **least** significant word. The diagram on p. 2-3 draws `Rn + 1`
to the left of `Rn` with the bit numbers 63 … 32 above `Rn + 1` and 31 … 0
above `Rn`, which is the same statement in a picture.

---

## 2. A doubleword in memory

**§2, Data Types**, the doubleword entry:

> A doubleword consists of 64 contiguous bits starting on **any byte
> boundary**. The individual bits within a byte are labeled \[0\] to 63 with
> bit \[0\] designated as the LSB (least significant bit) and bit 63 as the
> MSB (most significant bit). A doubleword occupies eight contiguous bytes and
> is **identified by the address of the low order byte**.

**§3, Data in Memory:**

> When the address of data is a multiple of the size of the data type in bytes,
> the data is said to be aligned. Byte data is always aligned and halfword,
> word, doubleword and quadword data are aligned when they have addresses that
> are a multiples of 2, 4, 8 and 16 respectively. ... **In some special cases,
> instructions and data must be aligned. However, generally there are no
> alignment requirements and only the performance is affected by not aligning
> data on its boundary.**

### What this settles for `v60_dxu`

**Byte order: the low word is at the operand's address.** "Identified by the
address of the low order byte" is unambiguous, and combined with the register
rule ("the lower numbered register contains the least significant word") the
machine is consistently little-endian about doublewords: address `A` holds
bits 7:0, `A+4` starts bits 39:32, `A+7` holds bits 63:56. A doubleword moved
from `Rn`/`Rn+1` to `[A]` puts `Rn` at `A` and `Rn+1` at `A+4`.

**The split walking upward is now supported, not merely chosen.**
`docs/v60/DATA-ACCESS-SPLIT.md` records "which cycle goes first" as a decision
with no page behind it. For a *doubleword* there is now a page behind the
grouping, if not the ordering: the operand is named by its low byte, so the
first word at the operand address is the low word, and reading upward means
reading low-then-high. That does not settle the order of the two bus cycles
*within* a word (an unaligned word still splits, and nothing says which half
goes first), so the decision remains a decision at that finer grain — but the
word-level ordering is no longer arbitrary.

**Alignment: unaligned doublewords are legal.** "Starting on any byte
boundary" and "generally there are no alignment requirements" together mean a
doubleword at an odd address must work. That is what
`DATA-ACCESS-SPLIT.md`'s cost table already assumes (4 cycles aligned, 5 at an
odd address).

**The `DL_WORD` choice is not contradicted, and cannot be confirmed.**
p. 3.235's `DL1-DL0` table has exactly four codes — Byte, Halfword, Word,
Reserved — and no doubleword code, which `DATA-ACCESS-SPLIT.md` already
records. Nothing in §2 or §3 or on either bus plate says what a V60 drives on
those pins during an eight-byte access. Driving `Word` and re-asserting `FAS*`
on the fifth byte keeps both pins self-consistent and is the only choice that
does; the alternative, `Reserved`, is a code the plate marks reserved. **The
pages neither support nor contradict it** — they are silent, and the decision
stands as a decision.

---

## 3. The one doubleword-specific exception the pages state

It is **not** about the register pair, and it is **not** Illegal Data Field.

**§3, the Immediate addressing mode page:**

> With the immediate addressing mode, the operand is contained in the
> instruction. ... **The immediate addressing mode cannot be used with
> doubleword data.**

and, in that page's Notes:

> The use of the immediate mode as the destination operand addressing mode will
> result in a Illegal Addressing Mode exception.
>
> **The attempted use of the immediate addressing mode as a doubleword source
> operand will result in a Reserved Addressing Mode exception.**

`MOV.D`'s own §7 page says it again for both immediate forms:

> On the µPD70616 microprocessor, a **Reserved Addressing Mode** exception will
> occur if the immediate or immediate quick addressing mode is specified for a
> doubleword source operand.

So: **immediate or immediate-quick as a doubleword source → Reserved
Addressing Mode, vector #18**, which is the databook summary's code `3`. Not
#19 (Illegal Addressing Mode, code 1), and not #20 (Illegal Data Field, code
2) — the pages pick the middle one of the three deliberately, and say so
twice.

Note the asymmetry the Notes draw: immediate as a *destination* is Illegal
Addressing Mode; immediate as a *doubleword source* is Reserved Addressing
Mode. Two different vectors for two different misuses of the same mode.

---

## 4. MOV.D

```
mov.d src.d.r, dst.d.w                  Opcode 3F        Format I, II
```

Operation: `dst ← src`

> The data designated by the source operand is copied to the destination
> operand.

Flags: the plate's `MOV.D` row is blank and the Reference's Condition Codes
block is four `Unchanged` lines. Exceptions: `1, 3` on the plate — Illegal
Addressing Mode and **Reserved Addressing Mode**, the latter being exactly the
immediate-source rule above. That is a case where the plate's exception column
is *more* informative than usual: code 3 on a data-transfer instruction is the
doubleword immediate rule showing through.

Four combinations, and all four are reachable:

| src | dst | what moves |
|---|---|---|
| `Rn`/`Rn+1` | `Rm`/`Rm+1` | `Rm ← Rn`, `Rm+1 ← Rn+1` |
| `Rn`/`Rn+1` | `[A]` | `[A] ← Rn`, `[A+4] ← Rn+1` |
| `[A]` | `Rm`/`Rm+1` | `Rm ← [A]`, `Rm+1 ← [A+4]` |
| `[A]` | `[B]` | `[B] ← [A]`, `[B+4] ← [A+4]` |

---

## 5. MULX and MULUX

```
mulx  src.w.r, dst.d.rw    Multiply Extended Word            86    Format I, II
mulux src.w.r, dst.d.rw    Multiply Extended Unsigned Word   96    Format I, II
```

Operation: `dst ← dst * src` / `dst ← dst * src (unsigned)`

### The `rw` is real, but only the low word is an input

This is the question the lead asked, and the Descriptions answer it in their
first clause:

**`MULX`:**

> **The word designated by the destination operand** is multiplied by the word
> contents of the source operand. The resulting doubleword product is stored in
> destination operand.

**`MULUX`:**

> **The unsigned word contents of the destination operand** is multiply by the
> unsigned word contents of the source operand. The resulting doubleword
> product is stored in the destination.

So the destination is declared `.d` (doubleword) because that is the width of
the **result**, but only **32 bits of it are read**. The `rw` is not nominal —
the destination genuinely is an input — but the upper word's prior value is
never used. Concretely:

- **Register pair:** read `Rn`, ignore `Rn+1`, multiply by `src`, write
  `Rn ← product[31:0]` and `Rn+1 ← product[63:32]`.
- **Memory:** read the four bytes at `A`, ignore the four at `A+4`, write all
  eight.

An implementation may therefore read only four bytes for the multiplicand.
Whether it is *permitted* to skip the upper-word read is a question about
observable bus cycles rather than about results; nothing on either page says
the upper word must be fetched, and nothing says it must not.

`v60_muldiv` already computes the full 64-bit product and discards the top
half. **Keeping it is the whole change** — the arithmetic is done.

### Flags — and this is a plate divergence

The Reference:

```
MULX                                    MULUX
CY  Unchanged                           CY  Unchanged
OV  Cleared                             OV  Cleared
S   Set if the result is negative,      S   Set if the MSB of the result is
    otherwise cleared                       set, otherwise cleared
Z   Set if the result is zero,          Z   Set if the result is zero,
    otherwise cleared                       otherwise cleared
```

"The result" is the **doubleword** product, so `S` is bit 63 and `Z` tests all
64 bits.

**`OV` is `Cleared`, unconditionally, on both** — and that is coherent: a
32×32 product always fits in 64 bits, so an X-form multiply *cannot* overflow.
It is exactly the property that distinguishes them from `MUL`/`MULU`, whose
`OV` reports a product that will not fit the destination
(`docs/v60/MULTIPLY-DIVIDE.md`).

**The plate disagrees.** p. 3.296's `MULX` and `MULUX` rows both print
`— • • •`, verified at 600 dpi against the `MUL`/`MULU` rows directly above
them, which carry the same glyphs. So the plate says `OV` is *updated* where
the Reference says it is *cleared*.

**Decision: take the Reference.** The plate's X-form rows look copied from the
non-X rows above them — same four glyphs, same exception code `1` — and the
Reference's reading is the only one with a mechanism behind it, because there
is no input to a 32×32→64 multiply that overflows. This is a decision, not a
page fact.

Exceptions: the plate prints `1` (Illegal Addressing Mode) on both rows, from
the `X` cells in each page's Addressing Modes table. Neither §7 page prints an
Exceptions block naming anything else.

---

## 6. DIVX and DIVUX

```
divx  src.w.r, dst.d.rw    Divide Extended            A6    Format I, II
divux src.w.r, dst.d.rw    Divide Extended Unsigned   B6    Format I, II
```

Operation: `dst ← dst ÷ src` / `dst ← dst ÷ src (unsigned)`

### The two-halves destination, quoted

**`DIVX`:**

> **The doubleword contents of the destination operand is divided by the word
> contents of the source operand** according to the rules of signed division.
> **The resulting 32-bit quotient is stored in the lower word of the
> destination and the 32-bit remainder is stored in the upper word of the
> destination.**

**`DIVUX`** prints the same sentences with "unsigned division".

The `DIVX` page draws it, and the diagram's own labels are the answer to "what
do the register case and the memory case each look like":

```
   63                                    0
   +-------------------------------------+
   |              Dividend               |   dst   (before)
   +-------------------------------------+
                     ÷
                 31        0
                 +----------+
                 | Divisor  |             src
                 +----------+
                     =
   63          32  31         0
   +-------------+ +----------+
   |  Remainder  | | Quotient |           dst   (after)
   +-------------+ +----------+
   • Upper Word/Register •  • Lower Word/Register •
```

**The page's caption is literally "Upper Word/Register" and "Lower
Word/Register"** — one picture covering both operand kinds, because the two
cases are the same layout expressed in the two media:

- **Register pair:** dividend is `{Rn+1, Rn}` (high, low). After: **`Rn ←
  quotient`, `Rn+1 ← remainder`.**
- **Memory at `A`:** dividend is `{[A+4], [A]}`. After: **`[A] ← quotient`,
  `[A+4] ← remainder`.**

So `DIVX` reads the whole doubleword and writes the whole doubleword, but the
two halves of the write carry **different quantities**. That is what makes it
unlike anything else in this tree: it is not a 64-bit result, it is two
independent 32-bit results that happen to share one operand. An implementation
cannot route it through a single "write the result" path; it needs a
two-value writeback, and for the memory case two write cycles with different
data rather than one 64-bit store split in half.

### The destination survives both failures

> **`DIVX`:** Overflow occurs when the negative maximum integer is divided by
> −1. **The destination operand does not change when an overflow or a Zero
> Divide exception occurs.**
>
> **`DIVUX`:** The destination operand does not change when an overflow or a
> Zero Divide exception occurs.

One sentence, two different things, exactly as `DIV`'s does
(`docs/v60/MULTIPLY-DIVIDE.md`): overflow is a **flag** and zero divide is an
**exception**, and neither writes the destination. So the writeback must be
gated on both conditions being clear — which for `DIVX` means the overflow
test has to happen *before* the two halves are stored, not after.

### Flags

```
CY  Unchanged
OV  Set if integer overflow occurs, otherwise cleared
S   Set if the result is negative, otherwise cleared
Z   Set if the result is zero, otherwise cleared
```

Identical on both pages except `DIVUX` says "unsigned division"; `DIVUX`'s
`S`/`Z` sentences are the signed wording even though its operands are
unsigned, the same construction `REMU` uses ("the condition code flags are set
as if the remainder is a signed value").

**`OV` moves on both, and the plate agrees** — p. 3.296 prints `— • • •` for
both `DIVX` and `DIVUX`, verified at 600 dpi. That is a real and deliberate
asymmetry against `DIVU`, whose row two lines above prints a literal `0` in
the same column (`docs/v60/INSTRUCTION-SUMMARY-LEGEND.md` already records
that). The mechanism is obvious once stated: **a 64÷32 divide overflows its
32-bit quotient routinely** — `0xFFFFFFFF_FFFFFFFF ÷ 1` needs 64 quotient bits
— whereas a 32÷32 unsigned divide never can. The X-forms are the only divides
in the set that can overflow on ordinary inputs.

**`DIVX`'s overflow condition is under-specified.** The page names exactly one
case — "the negative maximum integer divided by −1" — which is the *word*
`DIV` rule copied across. It does not mention the quotient-does-not-fit case,
which for a doubleword dividend is far commoner. The flag sentence says "Set
if integer overflow occurs", so the general condition is clearly intended;
the Description just fails to enumerate it. See §8.

### Exceptions

**Zero Divide**, and that is the entire block on both pages. Plate: `1, 4` —
Illegal Addressing Mode (from the `X` cells) and **Integer Zero Divide** (#4),
which is Table 8-1's code `1500` at vector 21, the same one `DIV`/`DIVU`/
`REM`/`REMU` raise.

---

## 7. CVT.WL and CVT.LW

Confirmed from the pages rather than the mnemonics, which is the discipline
that the `CVT.SL`/`CVT.LS` pair forced.

The Reference prints these on **two different pages**, each pairing a
short-real form with a long-real form:

| Reference page | syntax | Instruction column | Opcode |
|---|---|---|---|
| "Convert Word to …" | `cvt.ws src.w.r, dst.s.w` | Convert Word to Short Real | `5F-00` |
| | `cvt.wl src.w.r, dst.l.w` | **Convert Word to Long Real** | `5F-11` |
| "Convert … to Word" | `cvt.sw src.s.r, dst.w.w` | Convert Short Real to Word | `5F-01` |
| | `cvt.lw src.l.r, dst.w.w` | **Convert Long Real to Word** | `5F-09` |

Both match p. 3.297's plate (`CVT.WL` sub-op `00010001`, `CVT.LW` sub-op
`00001001`) and `insn_table.py`'s `(4, 8)` and `(8, 4)`.

So the directions are what the mnemonics suggest — `WL` is word→long,
`LW` is long→word — **but "long" means long real, an IEEE double, not a long
integer.** `docs/v60/FLOATING-POINT.md` covers the pair's semantics; the
doubleword-relevant part is that the long-real operand is 64 bits and
therefore needs exactly the register pair and the eight-byte memory access
this document describes.

Caveat carried over: the OCR of the `cvt.ws`/`cvt.wl` syntax lines prints
`dst.l.w` for **both**, which cannot be right for a page whose Instruction
column distinguishes Short Real from Long Real. `cvt.wl`'s `dst.l.w` is the
one that is right; `cvt.ws`'s is the corrupted line. The Reference PDF is not
held, so this is corrected from the same page's other columns.

### Converting down: `CVT.LW`

Condition Codes (the `cvt.sw`/`cvt.lw` page):

```
CY  Unchanged
OV  Set if integer overflow occurs, otherwise cleared
S   Set if the result is negative, otherwise cleared
Z   Set if the result is zero, otherwise cleared
```
```
FIV  Set if an invalid operation is attempted, otherwise unchanged
FZD  Unchanged
FOV  Unchanged
FUD  Unchanged
FPR  Set if a precision error occurs, otherwise unchanged
```

Exceptions: Reserved Floating Point Operand, Invalid Floating Point Operation,
Floating Point Precision.

So overflow converting down is reported in **`OV`**, and — this is the gap —
**no page says what value is stored.** `DIV`'s page states the
destination-unchanged rule explicitly for its overflow; `CVT.LW`'s does not,
and neither does `CVT.SW`'s. Saturation, truncation and leaving the
destination alone are all consistent with the page.

`CVT.LW` is also the only instruction in this document whose `CY` is
*unchanged* rather than participating — it is the integer flag set, because
the destination is an integer.

---

## 8. Cross-check: `rtl/cpu/v60/s32_v60.sv`

Read only. `MOV.D` decode at 4416-4432 and states `S_MOVD_RL`/`RH`/`WL`/`WH`
at 2704-2727; `MULX`/`MULUX` at 4655-4675; `DIVX`/`DIVUX` at 4676-4711 with
`S_DIVXM_RH` at 2672-2699 and `S_DIVX` at 2487-2508.

### Where it agrees with the pages

- **Register pair order.** `movd_lo <= r[op1[4:0]]; movd_hi <= r[op1[4:0] +
  5'd1];` — `Rn` low, `Rn+1` high. Matches §2 and §3, and matches
  `v60_regfile`'s `ra_pair = {gpr[ra_sel + 5'd1], gpr[ra_sel]}`.
- **No evenness enforcement anywhere.** The core uses `op[4:0] + 5'd1`
  directly, so every `n` is a legal pair — which is what the pages say.
- **Memory layout.** Every path reads/writes the low word at the operand
  address and the high word at `+4`: `dbus_addr <= op1` then `dbus_addr <= op1
  + 32'd4`. Matches "identified by the address of the low order byte".
- **Low word first**, on both reads (`S_MOVD_RL` → `S_MOVD_RH`) and writes
  (`S_MOVD_WL` → `S_MOVD_WH`). That is `v60_dxu`'s "walks upward" decision,
  reached independently by a second implementation.
- **Two 32-bit accesses, not one eight-byte access** — `dbus_size <= 2'd2`
  twice. Same shape as `v60_dxu`'s "two logical word accesses", though this
  core has no `DL1-DL0` or `FAS*` pins at all so it is not evidence about
  those.
- **`MULX`/`MULUX` read only the destination's low word.** The product is
  `op1 * b` with `b` a 32-bit value sign- or zero-extended to 64. That is the
  Description's "the word designated by the destination operand", exactly.
- **`DIVX` writes quotient low, remainder high**, in both media:
  `queue_reg_write(xdiv_dst, xdiv_qresult)` and `queue_reg_write(xdiv_dst +
  5'd1, xdiv_rresult)` for the register case; `movd_lo <= xdiv_qresult;
  movd_hi <= xdiv_rresult;` into `S_MOVD_WL` for the memory case. Matches the
  page and its diagram.
- **`DIVX` dividend assembly.** `num = {bus_rdata, op2val}` with `bus_rdata`
  from `[op2]+4` and `op2val` from `[op2]` — `{high, low}`. Correct.
- **The destination survives a zero divide.** `if (op1 == 0) st <= S_NEXT;`
  skips the whole operation, so nothing is written — which is the page's "The
  destination operand does not change when ... a Zero Divide exception
  occurs", achieved by not doing it rather than by gating a writeback.

### Divergences

1. **No Zero Divide exception on `DIVX`/`DIVUX`.** `if (op1 == 0) st <=
   S_NEXT;   // MAME: no zero-divide trap`. Both §7 pages print an Exceptions
   block whose only entry is **Zero Divide**, and p. 3.296 prints `1, 4` on
   both rows. This is the same divergence `docs/v60/MULTIPLY-DIVIDE.md`
   records for `DIV`/`DIVU`/`REM`/`REMU`, extended to the X-forms, and this
   tree's precedent is to follow the documents.

2. **`OV` is never written by `DIVX`/`DIVUX`.** `S_DIVX` sets `f_z` and `f_s`
   and the comment says "MAME opDIVX/opDIVUX set only S/Z and leave OV
   unchanged; do not clear it." The Reference says `OV Set if integer overflow
   occurs, otherwise cleared` and the plate prints `•`. **This one matters
   more than the usual flag divergence**, because of the mechanism:
   `xdiv_qresult` is `xdiv_shift_next[31:0]` — the quotient is built in the
   low 32 bits of a 64-bit shift register — so a quotient that needs more than
   32 bits is **silently truncated**, with no flag and nothing observable to
   distinguish it from a correct answer. A 64÷32 divide reaches that case on
   ordinary inputs, not on edge cases.

3. **`OV` is never written by `MULX`/`MULUX`** either — "MAME opMULX/opMULUX
   leave OV unchanged". The Reference says `OV Cleared`. Here the plate is on
   the core's side (`•`, i.e. updated) and neither matches "cleared", so all
   three sources differ; see §5 for why the Reference's reading is the one
   with a mechanism.

4. **`DIVX` overflow is not detected at all**, so the "destination operand
   does not change when an overflow ... occurs" half of that sentence is
   unimplemented. The zero-divide half is implemented (by skipping).

5. **No Reserved Addressing Mode check on an immediate doubleword source.**
   Nothing in the `8'h3f` (`MOV.D`) path tests for it. The rule is stated
   twice in the Reference (§3's Immediate page and `MOV.D`'s own page) and
   shows up on the plate as `MOV.D`'s exception code `3`.

6. **`R31` wraps rather than being flagged.** `op[4:0] + 5'd1` and
   `ra_pair`'s `ra_sel + 5'd1` both wrap 31→0, so a doubleword at `R31` reads
   `{R0, R31}`. The pages call that case *unpredictable*, so wrapping is
   **permitted** — this is recorded as a behaviour to know, not a defect. It
   is worth an assertion rather than a silent wrap, because it is the shape of
   bug that produces plausible wrong answers.

### One thing the core does that the pages do not require

`DIVX`'s remainder takes the **dividend's** sign (`xdiv_rneg <= num[63]`).
That is `REM`'s stated rule — "The sign of the remainder is the same as the
sign of the dividend" — but **`DIVX`'s page does not say it**, and a divider
could reasonably use the divisor's sign or always produce a non-negative
remainder. The core's choice is the consistent one for this instruction set;
it is an inference from `REM`'s page, not a statement on `DIVX`'s.

---

## 9. What the pages do not settle

1. **Is there an alignment or evenness constraint on the register pair, and
   what happens if it is violated?** **No, and nothing.** This is the direct
   answer to the question, and it is a negative result rather than a gap:
   - There is **no evenness constraint**. Both statements say `Rn`/`Rn+1` for
     any specified `Rn`, and neither restricts `n` to even values.
   - The only restriction is **R31**, and both pages call the result
     **"unpredictable"** — not an exception. Neither page's Exceptions block
     names anything for it, and §8's Instruction Exceptions list gives no
     candidate that fits.
   - **Illegal Data Field (#20) is *not* stated for it**, and should not be
     assumed. §8 defines #20 as "an error is detected in the size of an
     operand", and its example is a bit field wider than 32; every instruction
     in this tree that actually raises #20 does so on a *length or offset
     value* (`TEST1`'s bit offset, `STPR`'s register id, the character
     group's string lengths), not on a register number. Raising #20 on `R31`
     would be an implementation's own policy, permitted by "unpredictable" but
     required by nothing.
   - The one doubleword exception the pages **do** state is a different thing
     entirely: **immediate or immediate-quick as a doubleword source →
     Reserved Addressing Mode (#18)**, said twice (§3's Immediate page and
     `MOV.D`'s page). That is the check an implementation owes.

2. **`DIVX`'s overflow condition.** The Description names only "the negative
   maximum integer divided by −1", which is the 32÷32 rule. The flag sentence
   is general ("Set if integer overflow occurs"), and a 64÷32 divide's
   quotient overflows a 32-bit destination on ordinary inputs — but no page
   states the test. An implementation has to define it (the natural reading:
   the quotient's magnitude does not fit the destination word at the
   instruction's signedness, plus `DIVX`'s named `INT_MIN ÷ −1` case).

3. **What `CVT.LW` stores on integer overflow.** `OV` reports it; no page says
   whether the destination is saturated, truncated, or left unchanged. The
   same gap `CVT.SW` has (`docs/v60/FLOATING-POINT.md`).

4. **What `DL1-DL0` carries during an eight-byte access.** p. 3.235's table
   has four codes and none of them is doubleword. `v60_dxu`'s `DL_WORD` +
   re-asserted `FAS*` is unrefuted and unconfirmed.

5. **Whether `MULX`/`MULUX` must fetch the destination's upper word.** Only
   the low word is an input, so the upper read is architecturally pointless —
   but the operand is declared `.d.rw` and nothing says the read may be
   narrowed. This is observable on the bus and nowhere else.

6. **`DIVX`'s remainder sign.** Stated on `REM`'s page for `REM`; not stated
   on `DIVX`'s page for `DIVX`.

7. **The order of the two bus cycles within an unaligned word.** The
   doubleword's word-level order is now settled by "identified by the address
   of the low order byte"; the sub-word order is still
   `DATA-ACCESS-SPLIT.md`'s own decision.

8. **Timing**, as everywhere: p. 3.296's Clocks column is blank on all six
   rows (`docs/v60/INSTRUCTION-TIMING.md`).
