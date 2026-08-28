# The floating point group

Twelve instructions on two escape opcodes. The encodings are read off the
databook's instruction summary plate at p. 3.297; the semantics are the
Programmer's Reference §7 pages, one per mnemonic, whose Opcode lines agree
with the plate everywhere the OCR is legible enough to compare. The two real
formats are the Reference §2 (p. 2-6), and the rounding modes and trap masks
are its Task Control Word page (p. 3-9).

`CVT.LW` and `CVT.WL` appear in the tables below because they share the plate
rows and the Reference pages with the instructions in this group, but they are
doubleword *integer* conversions and are not covered here.

## The two data types

From the Reference §2, p. 2-6, which is the only place either book states the
bit layouts:

> The short real data type is a 32-bit binary floating point representation
> conforming to the IEEE single precision format. The short real format
> consists of a mantissa sign bit, an 8-bit biased exponent and a 23-bit
> mantissa

> The long real data type Is a 64-bit binary floating point representation
> conforming to the IEEE double precision format. The long real format
> consists of a mantissa sign bit, an 1 1-bit biased exponent and a 52-bit
> mantissa

("1 1-bit" is the OCR splitting `11`; the diagram's field boundaries print as
"52 51", and 1 + 11 + 52 = 64.) §1 says the same from the other end: "The
U.PD70616 floating point data types and operations conform to the IEEE 754
standard. Floating point data can be represented in either the short real
(32-bit) or long real (64-bit) formats."

## The encoding

p. 3.297's Floating Point Instructions block, read off the plate at 600 dpi.
Every row is Instruction Format **II**. The first opcode column is the primary
byte, the second is the sub-op.

| | primary (plate) | `.s` | `.l` | sub-op (plate) | Reference Opcode line |
|---|---|---|---|---|---|
| `MOVF` | `0 1 0 1 1 1 s 0` | `5C` | `5E` | `0 0 0 0 1 0 0 0` | `5O08` / `5E-08` |
| `ADDF` | `0 1 0 1 1 1 s 0` | `5C` | `5E` | `0 0 0 1 1 0 0 0` | `5C-18` / `5E-18` |
| `SUBF` | `0 1 0 1 1 1 s 0` | `5C` | `5E` | `0 0 0 1 1 0 0 1` | `5C-19` / `5E«19` |
| `MULF` | `0 1 0 1 1 1 s 0` | `5C` | `5E` | `0 0 0 1 1 0 1 0` | `501A` / `5E-1A` |
| `DIVF` | `0 1 0 1 1 1 s 0` | `5C` | `5E` | `0 0 0 1 1 0 1 1` | `501B` / `5E-1B` |
| `CMPF` | `0 1 0 1 1 1 s 0` | `5C` | `5E` | `0 0 0 0 0 0 0 0` | `5C-00` / `5E-00` |
| `NEGF` | `0 1 0 1 1 1 s 0` | `5C` | `5E` | `0 0 0 0 1 0 0 1` | `5O09` / `5E-09` |
| `ABSF` | `0 1 0 1 1 1 s 0` | `5C` | `5E` | `0 0 0 0 1 0 1 0` | `5C-0A` / `5E-0A` |
| `SCLF` | `0 1 0 1 1 1 s 0` | `5C` | `5E` | `0 0 0 1 0 0 0 0` | `5O10` / `5E-10` |
| `CVTF` | `0 1 0 1 1 1 1 1` | `5F` | — | `0 0 0 0 1 0 0 0` | `5F-08` (as `cvt.ls`) |
| `CVT.WS` | `0 1 0 1 1 1 1 1` | `5F` | — | `0 0 0 0 0 0 0 0` | `5F-00` |
| `CVT.SW` | `0 1 0 1 1 1 1 1` | `5F` | — | `0 0 0 0 0 0 0 1` | `5F-01` |
| *(CVT.WL)* | `0 1 0 1 1 1 1 1` | `5F` | — | `0 0 0 1 0 0 0 1` | `5F-11` |
| *(CVT.LW)* | `0 1 0 1 1 1 1 1` | `5F` | — | `0 0 0 0 1 0 0 1` | `5F-09` |

**Read the plate for these, not the OCR.** The Reference's OCR mangles five of
the twelve primary bytes into `5O08`, `501A`, `501B`, `5O09`, `5O10` — `C`
read as `O` or as `01` — and `5E«19` for `5E-19`. The plate's bit columns are
unambiguous at 600 dpi and settle all six. The databook's own OCR
(`uPD70616_databook_1986_OCR.txt` lines 3074-3079) is no better: it renders
the size bit as `•`, drops the `CVT.SW` row entirely and calls `CVT.LW`
"CVT1W".

**The `s` bit is bit 1, and it is a *data type* selector, not a size field.**
p. 3.295's "Floating Point Data Type Selection" table:

| `s` | Data Type |
|---|---|
| `0` | short real |
| `1` | long real |

So `5C` is the short-real group and `5E` the long-real group, which is exactly
what the Reference's per-instruction Opcode lines say (`addf.s` → `5C-18`,
`addf.l` → `5E-18`). The `5F` conversions name their two types in the
mnemonic and so do not carry the bit.

### The printed sub-op byte is not the second byte in memory

p. 3.293's Format II diagram gives the second halfword as

```
 15  14  13  12          8  7            0
+---+---+---+-------------+--------------+
| 1 | m | m'|    subop    |      op      |
+---+---+---+-------------+--------------+
```

— `subop` is **five bits**, bits 12:8, and bits 15:13 carry the format
selector `1` and the two address-mode field bits `m` and `m'`. The summary
table prints the sub-op in an eight-column field, so what p. 3.297 shows as
`0 0 0 1 1 0 0 0` for `ADDF` is the 5-bit subop `11000` zero-extended, not a
literal byte. Every sub-op in this group fits in five bits with the top three
columns zero, so the plate is consistent — but an eight-bit compare against
the fetched byte matches nothing, because that byte's bit 7 is always 1.
`s32_v60.sv` agrees: it dispatches on `fb[1][4:0]` and takes `ea_modm <=
fb[1][6]`, i.e. `m` at bit 14 of the halfword.

### `CVTF` is one direction only, and the other one is missing from the plate

The Reference prints both real↔real conversions on one page (§7, "CVT
Convert"):

```
cvt.sl   src.s.r, dst.l.w    Convert Short Real to Long Real   5F-10
cvt.ls   src.l.r, dst.s.w    Convert Long Real to Short Real   5F-08
```

The databook mnemonic `CVTF` sits on `5F-08`, so **`CVTF` is long real →
short real**, `src.l.r, dst.s.w`. The plate has no row for `5F-10` at all —
`5F` sub-op `10` is simply absent from p. 3.297, though `5C`/`5E` sub-op `10`
is `SCLF`. So the summary table under-reports the instruction set by one
encoding, and the Reference is the source for it.

## Syntax, operation and flags

Operand notation is the Reference's: `name.size.access`, `s` = short real, `l`
= long real, `w` = word, `h` = halfword; `r` read, `w` write, `rw` read-modify-
write.

### MOVF — Move Floating

```
movf.s  src.s.r, dst.s.w        Move Short Real
movf.l  src.l.r, dst.l.w        Move Long Real
```

Operation: `dst ← src`

> The source operand is copied to the destination operand and the flags
> updated to reflect the state of the destination.

Condition Codes — note every sentence says *destination*, not *result*:

```
CY  Set if the destination is negative and non-zero, otherwise cleared
OV  Cleared
S   Set if the destination mantissa sign bit is set, otherwise cleared
Z   Set if the destination is zero, otherwise cleared
```
```
FIV  Set if the destination is a NaN or infinite, otherwise unchanged
FZD  Unchanged
FOV  Unchanged
FUD  Set if the destination is denormal, otherwise unchanged
FPR  Unchanged
```

Exceptions: Reserved Floating Point Operand, Floating Point Underflow.
Plate flags `• 0 • •`, exceptions `1, 3, 7, 9` — agrees.

`MOVF` is the only instruction in the group whose `FIV` sentence names NaN and
infinity directly rather than saying "an invalid operation is attempted".

### ADDF — Add Floating

```
addf.s  src.s.r, dst.s.rw       Add Short Real
addf.l  src.l.r, dst.l.rw       Add Long Real
```

Operation: `dst ← src + dst`

> The sum of the source and destination operands is stored in the destination
> operand. Both the integer condition codes and the floating point condition
> codes are updated to reflect the result of the operation.

> If the absolute values of the source and destination operands are equal but
> differ in sign, the sign of the zero result will be determined by the
> programmed rounding mode.

> If a source or destination operand is a NaN or an infinity, a Reserved
> Floating Point Operand exception will occur and the flags and destination
> will remain unchanged.

That last sentence is the group's central rule and it is stated on `ADDF`,
`ABSF` and `CMPF`'s pages: **an infinity is a trapping operand, not a value to
compute with.** No page in this group describes arithmetic *on* infinities.

```
CY  Set if the result is negative and non-zero, otherwise cleared
OV  Cleared
S   Set if the mantissa sign bit of the result is set, otherwise cleared
Z   Set if the result is zero, otherwise cleared
```
```
FIV  Set if an invalid operation is attempted, otherwise unchanged
FZD  Unchanged
FOV  Set if the result is infinite, otherwise unchanged
FUD  Set if the destination result is denormal, otherwise unchanged
FPR  Set if a precision error occurs, otherwise unchanged
```

Exceptions: Reserved Floating Point Operand, Floating Point Overflow, Floating
Point Underflow, Floating Point Precision. Plate `• 0 • •` / `1, 3, 6, 7, 8, 9`
— agrees.

**`CY` is redundant with `S` except at zero.** `CY` is "negative and non-zero",
`S` is the mantissa sign bit; they differ only on negative zero, where `S` is
1 and `CY` is 0. That pair of sentences is printed verbatim on `ADDF`, `SUBF`,
`MULF`, `DIVF`, `NEGF`, `SCLF`, `CVTF` and `CVT.WS`.

### SUBF — Subtract Floating

```
subf.s  src.s.r, dst.s.rw      Subtract Short Real
subf.l  src.l.r, dst.l.rw      Subtract Long Real
```

Operation, **as the OCR renders it**: `dst ← src - dst`. See "What the pages do
not settle" below — this is the one operand order in the group that the sources
disagree about, and the Reference PDF that would settle it is not held.

> The difference of the source operand and destination operand is stored in
> the destination operand. Both the integer and floating point condition codes
> are updated to reflect the result of the operation.

> If the source and destination operands are equal, the sign of the zero result
> will be determined by the programmed rounding mode.

Condition codes and floating point flags: identical text to `ADDF`, except
`FUD` reads "Set if the result is denormal" rather than "the destination
result". Exceptions: Reserved Floating Point Operand, Floating Point Overflow,
Floating Point Underflow, Floating Point Precision. Plate `• 0 • •` /
`1, 3, 6, 7, 8, 9` — agrees.

### MULF — Multiply Floating

```
mulf.s  src.s.r, dst.s.rw      Multiply Short Real
mulf.l  src.l.r, dst.l.rw      Multiply Long Real
```

Operation: `dst ← src * dst`

> The product of the source operand and destination operand is stored in the
> destination operand. Both the integer and floating point condition codes are
> updated to reflect the result of the operation.

> If either of the operands is zero and the other operand is either zero or
> normal, the result is zero with the sign determined by the exclusive OR of
> the source and destination signs.

Condition codes as `ADDF`. Floating point flags: `FIV` set on invalid, `FZD`
unchanged, `FOV` "Set if the result is infinite", `FUD` "Set if the result is
denormal", `FPR` set on precision error. Exceptions: Reserved Floating Point
Operand, Floating Point Overflow, Floating Point Underflow, Floating Point
Precision. Plate `• 0 • •` / `1, 3, 6, 7, 8, 9` — agrees.

### DIVF — Divide Floating

```
divf.s  src.s.r, dst.s.rw      Divide Short Real
divf.l  src.l.r, dst.l.rw      Divide Long Real
```

Operation: `dst ← dst ÷ src` (the OCR prints the divide sign as `+`:
"dst \[←\] dst + src").

> The quotient of the source operand and destination operand is stored in the
> destination operand. Both the integer and floating point condition codes are
> updated to reflect the result of the operation.

> If the destination operand is zero and the source operand a non-zero
> normalized number, the result is zero with the sign determined by the
> exclusive OR of the source and destination signs.

That sentence is what fixes the direction: the *destination* is the dividend,
so `dst ÷ src`, the same way round as the integer `DIV`
(`docs/v60/MULTIPLY-DIVIDE.md`).

Condition codes as `ADDF`. Floating point flags — this is the only instruction
in the group where all five move:

```
FIV  Set if an invalid operation occurs, otherwise unchanged
FZD  Set if division by zero occurs, otherwise unchanged
FOV  Set if the result is infinite, otherwise unchanged
FUD  Set if the destination result is denormal, otherwise unchanged
FPR  Set if a precision error occurs, otherwise unchanged
```

Exceptions: Reserved Floating Point Operand, Invalid Floating Point Operation,
Floating Point Divide by Zero, Floating Point Overflow, Floating Point
Underflow, Floating Point Precision. Plate `• 0 • •` /
`1, 3, 6, 7, 8, 9, 10, 11` — agrees exactly, and it is the only FP row on the
plate carrying codes 10 and 11.

### CMPF — Compare Floating

```
cmpf.s  src1.s.r, src2.s.r     Compare Short Real
cmpf.l  src1.l.r, src2.l.r     Compare Long Real
```

(The OCR prints `srd` for `src1` throughout the page.)

Operation: `Flags ← src2 - src1`

> The difference of the two source operands is computed and the Integer and
> floating point condition codes are updated to reflect the result of the
> operation.

> If either source operand is a NaN or an infinity, a Reserved Floating Point
> Operand exception will occur and the flags will remain unmodified.

`CMPF` is the **only** instruction in the group with no destination — nothing
is written — and the only one whose `OV` moves:

```
CY  Set if the result is negative, otherwise cleared
OV  Set if unordered, otherwise cleared
S   Set to the MSB of the result
Z   Set if the result is zero, otherwise cleared
```
```
FIV  Set if an invalid operation is attempted, otherwise unchanged
FZD  Unchanged
FOV  Unchanged
FUD  Unchanged
FPR  Unchanged
```

Note `CY` here is "negative", not "negative and non-zero" as everywhere else,
and there is no immediate-quick or immediate restriction difference between
the two operands — both are marked Δ (reserved addressing mode).

Exceptions: Reserved Floating Point Operand, Invalid Floating Point Operation.
Plate flags `• • • •` — agrees, and the `OV` cell is a dot, verified at
maximum zoom against the `0` cells directly above and below it. Plate
exceptions `1, 3, 6, 7, 8, 9` — **does not agree**; see the exception table
below.

### NEGF — Negate Floating

```
negf.s  src.s.r, dst.s.w       Negate Short Real
negf.l  src.l.r, dst.l.w       Negate Long Real
```

Operation: `dst ← -src`

> The negation of the source operand is stored in the destination operand.
> Both the integer and floating point condition codes are updated to reflect
> the result of the operation.

Condition codes as `ADDF`. Floating point flags: `FIV` set on invalid, `FZD`
unchanged, `FOV` unchanged, `FUD` "Set if the result is denormal", `FPR`
unchanged. Exceptions: Reserved Floating Point Operand, Floating Point
Underflow. Plate `• 0 • •` / `1, 3, 7, 9` — agrees.

`NEGF` and `ABSF` are the two arithmetic instructions with a `.w` (write-only)
destination rather than `.rw`: they read `src` and write `dst`, and the
destination's prior contents are not an input.

### ABSF — Absolute Value

```
absf.s  src.s.r, dst.s.w       Absolute Value Short Real
absf.l  src.l.r, dst.l.w       Absolute Value Long Real
```

Operation: `dst ← |src|`

> The absolute value of the source operand is stored in the destination
> operand. Both the integer condition codes and the floating point condition
> codes are updated to reflect the result of the operation.

> If the source operand is a NaN or an infinity, a Reserved Floating Point
> Operand exception will occur and the flags and destination will remain
> unchanged.

`ABSF` has the group's one distinctive flag block — three of the four integer
flags are unconditionally cleared, because the result cannot be negative:

```
CY  Cleared
OV  Cleared
S   Cleared
Z   Set if the result is zero, otherwise cleared
```
```
FIV  Set if an invalid operation is attempted, otherwise unchanged
FZD  Unchanged
FOV  Unchanged
FUD  Set if the result is denormal
FPR  Unchanged
```

Exceptions: Reserved Floating Point Operand, Floating Point Underflow. Plate
`0 0 0 •` / `1, 3, 7, 9` — agrees, and `ABSF` is the only row in the whole
Floating Point block with a `0` in the `CY` and `S` columns.

### SCLF — Scale Floating

```
sclf.s  count.h.r, dst.s.rw    Scale Short Real
sclf.l  count.h.r, dst.l.rw    Scale Long Real
```

Operation: `dst ← dst * 2^count`

> The destination operand is scaled by the integer count and stored in the
> destination operand. Both the integer condition codes and the floating point
> condition codes are updated to reflect the result of the operation.

**The count is a halfword, and the destination is a real** — one instruction
with two operands at different widths, the same shape the shift group has
(`docs/v60/SHIFTS.md`). The `.h` is on the count in both the `.s` and the `.l`
syntax lines, so the count's width does not follow the `s` bit.

**`SCLF` is also the one instruction in the group that accepts Immediate Quick
for its first operand.** Its Addressing Modes table marks Immediate.Quick and
Immediate as `O` for `count`, where every other page in the group marks the
first operand `Δ` (Reserved Addressing Mode). The page does not say whether
the quick immediate is sign- or zero-extended to the halfword count — see
below.

Condition codes as `ADDF`. Floating point flags: `FIV` set on invalid, `FZD`
unchanged, `FOV` "Set if the result is infinite", `FUD` "Set if the result is
denormal", `FPR` set on precision error. Exceptions: Reserved Floating Point
Operand, Floating Point Overflow, Floating Point Underflow, Floating Point
Precision. Plate `• 0 • •` / `1, 3, 6, 7, 8, 9` — agrees.

### CVTF — Convert Long Real to Short Real

```
cvt.ls  src.l.r, dst.s.w       Convert Long Real to Short Real     5F-08
```

The plate's mnemonic is `CVTF`; the Reference's is `cvt.ls`, on a page it
shares with `cvt.sl` (`src.s.r, dst.l.w`, `5F-10`), which the plate does not
list. Both are Format II.

Operation: `dst ← src`

> The source operand is converted to the destination operand format. The
> integer and floating point condition codes are updated to reflect the result
> of the operation.

```
CY  Set if the result is negative and non-zero, otherwise cleared
OV  Cleared
S   Set if the mantissa sign bit of the result is set, otherwise cleared
Z   Set if the destination is zero, otherwise cleared
```
```
FIV  Set if an invalid operation is attempted, otherwise unchanged
FZD  Unchanged
FOV  Set if the result is infinite, otherwise unchanged
FUD  Set if the destination result is denormal, otherwise unchanged
FPR  Set if a precision error occurs, otherwise unchanged
```

Exceptions: Reserved Floating Point Operand, Floating Point Overflow, Floating
Point Underflow, Floating Point Precision. Plate `• 0 • •` /
`1, 3, 6, 7, 8, 9` — agrees.

This page's `Z` sentence says "destination" where the arithmetic pages say
"result"; on a conversion they are the same object.

### CVT.WS — Convert Word to Short Real

```
cvt.ws  src.w.r, dst.s.w       Convert Word to Short Real          5F-00
```

The OCR of this syntax line reads `src.w.r, dst.l.w` for **both** `cvt.ws` and
`cvt.wl` — the two lines are identical in the text layer, which cannot be
right for a page whose Instruction column distinguishes "Convert Word to Short
Real" from "Convert Word to Long Real". The Instruction column and the
mnemonic settle it: `cvt.ws`'s destination is `.s`. The Reference PDF is not
held, and the databook prints no syntax lines, so this is corrected from the
same page's other columns rather than re-read.

Operation: `dst ← src`

> The word source operand is converted to the destination operand format. The
> integer and floating point condition codes are updated to reflect the result
> of the operation.

```
CY  Set if the result is negative and non-zero, otherwise cleared
OV  Cleared
S   Set if the mantissa sign bit of the result is set, otherwise cleared
Z   Set if the result is zero, otherwise cleared
```
```
FIV  Unchanged
FZD  Unchanged
FOV  Unchanged
FUD  Unchanged
FPR  Set if a precision error occurs, otherwise unchanged
```

Exceptions: **Floating Point Precision** — that is the whole block. This is
the only instruction in the group that cannot raise Reserved Floating Point
Operand, which follows: its source is an integer and every 32-bit integer is a
representable operand. Only the *result* can be inexact, because a 24-bit
significand cannot hold every 32-bit integer.

Plate flags `• 0 • •` — agrees. Plate exceptions `1, 3, 6, 7, 8, 9` — **does
not agree**; see below.

### CVT.SW — Convert Short Real to Word

```
cvt.sw  src.s.r, dst.w.w       Convert Short Real to Word          5F-01
```

Operation: `dst ← src`

> The source operand is converted to the word data type. The integer and
> floating point condition codes are updated to reflect the result of the
> operation.

This is the only instruction in the group whose destination is an integer, and
its flag block is correspondingly the integer one — `CY` does not move at all
and `OV` reports an integer overflow rather than being cleared:

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

Plate flags `— • • •` — agrees, and `CVT.SW`/`CVT.LW` are the only two rows in
the Floating Point block with a dash in the `CY` column. Plate exceptions
`1, 3, 6, 7, 8, 9` — **does not agree**; see below.

## Reading the plate's two right-hand columns

**The exception numbers** are legended at the foot of p. 3.299:

```
 1. Illegal Addressing Mode          7. Floating Point Underflow
 2. Illegal Data Type                8. Floating Point Precision
 3. Reserved Addressing Mode         9. Reserved Floating Point Operand
 4. Integer Zero Divide             10. Invalid Floating Point Operation
 5. Illegal Decimal Format          11. Floating Point Zero Divide
 6. Floating Point Overflow         12. Privileged Instruction
```

Codes 1 and 3 appear on every row in the block and correspond to the
Reference's Addressing Modes table rather than its Exceptions block: `X`
"Illegal Addressing Mode" and `Δ` "Reserved Addressing Mode" are printed as
cell markers there, not as exception names. So the two books agree wherever
the plate's list is `{1, 3} ∪` the Reference's Exceptions block.

That holds for eight of the eleven rows in this group. It does not hold for
three:

| | Reference Exceptions block | plate | plate has extra | plate omits |
|---|---|---|---|---|
| `CMPF` | Rsvd FP Operand, Invalid FP Operation | `1,3,6,7,8,9` | 6 Overflow, 7 Underflow, 8 Precision | 10 Invalid FP Operation |
| `CVT.WS` | FP Precision | `1,3,6,7,8,9` | 6 Overflow, 7 Underflow, 9 Rsvd FP Operand | — |
| `CVT.SW` | Rsvd FP Operand, Invalid FP Operation, FP Precision | `1,3,6,7,8,9` | 6 Overflow, 7 Underflow | 10 Invalid FP Operation |

The plate prints the identical string `1, 3, 6, 7, 8, 9` on nine of the
fourteen Floating Point rows, including rows where the Reference's block is
much shorter. **Decision: take the Reference's per-instruction Exceptions
blocks as authoritative and the plate's column as a coarse summary.** The
Reference's lists are instruction-specific and internally consistent — a
compare that writes nothing cannot overflow a destination, an integer source
cannot be a reserved floating point operand — while the plate's repeats a
boilerplate. This is a judgement about which of two printed pages to believe,
not something either page states.

**The flag symbols `•`, `0`, `—` and blank are never legended.** Neither
p. 3.296 (the table's first page) nor p. 3.299 (its last, which legends the
exception numbers and the Notes) prints a key for them, and the OCR of both
books offers nothing further. Their meaning is recoverable from the
Reference's Condition Codes blocks, which agree with the columns on every row
checked here: `•` = updated per the instruction's sentence, `0` = cleared
unconditionally, `—` = unchanged, blank = not affected. `ABSF`'s `0 0 0 •`
against its "CY Cleared / OV Cleared / S Cleared" and `CVT.SW`'s `— • • •`
against its "CY Unchanged" are the two rows that pin the mapping down.

## Rounding modes and the trap masks

`ADDF` and `SUBF` both defer a sign question to "the programmed rounding
mode". The Reference's Task Control Word page (p. 3-9) is where it is
programmed:

```
bits 0:1  RD   RD = 00  round toward nearest
               RD = 01  round toward -infinity
               RD = 10  round toward +infinity
               RD = 11  round toward zero
bit 2     RDI  RDI = 0  use RD field rounding mode
               RDI = 1  round toward zero
bit 3     RFU  Reserved for future use
bit 4     FPT  floating point precision trap enable
bit 5     FUT  floating point underflow trap enable
```

(The OCR renders the four `RD` values as "00 / 01 / 1 / 1 1" and the enable
values as "= " / "= 1"; the four-way field and the two-way flags are
unambiguous from the count of listed alternatives.) `RDI` governs **floating
point to integer conversions** specifically, which in this group is `CVT.SW`
alone.

The five floating point condition codes live in the PSW and the matching trap
enables in the TKCW, which `TRAPFL` (`CB`, Format V, p. 3.297) reads:

> if ( TKCW\[8:4\] ∧ PSW\[12:8\] ) ≠ 0 then Floating Point Operation Exception

> The bit-wise AND of floating point trap mask field in the TKCW register and
> the floating point condition codes in the PSW is computed and if the result
> is non-zero, a floating point operation trap will occur.

So `FIV FZD FOV FUD FPR` are PSW bits 12:8 and their enables TKCW bits 8:4,
and the flags are **sticky** — every sentence in this group reads "otherwise
unchanged", never "otherwise cleared". Nothing in this group clears them; they
accumulate until software does.

## What the pages do not settle

Everything in this section is genuinely absent from the pages held, not merely
hard to read. None of it is decided here.

1. **`SUBF`'s operand order.** The OCR of the Operation block reads `dst ←
   src - dst`. Three things argue the other way: the integer `SUB` page in the
   same book prints `dst ← dst - src`; `DIVF`, the other
   non-commutative operation in the group, prints `dst ← dst ÷ src`; and
   `CMPF` prints `Flags ← src2 - src1`, which for a first-operand `src` and a
   second-operand `dst` is `dst - src`. Against that, the OCR is a faithful
   token sequence for `ADDF` (`src + dst`) and `MULF` (`src * dst`) on the
   same book, so it may be reproducing a genuinely source-first convention.
   **The Programmer's Reference PDF is not held and the databook prints no
   Operation blocks**, so there is no plate to check. This one must be decided,
   and it changes results.

2. **Rounding for the arithmetic instructions.** `ADDF`/`SUBF` name the
   programmed rounding mode only for the *sign of a zero result*. No page
   states that `RD` governs the significand rounding of `ADDF`/`SUBF`/`MULF`/
   `DIVF`/`SCLF`/`CVT.WS`, nor what "round toward nearest" does on an exact
   tie (nearest-even is IEEE 754's default, and §1 claims conformance, but
   neither page says so).

3. **Subnormals.** `FUD` is "Set if the result is denormal", and `ABSF`,
   `MOVF` and `NEGF` list Floating Point Underflow as an exception, so
   denormal results plainly exist and are producible. But no page says whether
   a denormal is produced by gradual underflow or flushed, whether a denormal
   *source* operand is accepted, or what happens when `FUT` is disabled and
   the result underflows.

4. **NaN behaviour.** The pages say only what happens on the way *in*: a NaN
   or infinity source raises Reserved Floating Point Operand and leaves flags
   and destination unchanged (`ADDF`, `ABSF`, `CMPF`). Nothing states whether
   a NaN can be produced, what its payload would be, whether signalling and
   quiet NaNs are distinguished, or what `Invalid Floating Point Operation`
   (exception code 10, listed for `DIVF`, `CMPF` and `CVT.SW`) means as
   distinct from `Reserved Floating Point Operand` (code 9). `MOVF` is the
   sharpest gap: its `FIV` sentence sets a flag on a NaN or infinite
   destination, its Exceptions block lists Reserved Floating Point Operand,
   and its Description does neither — so whether a `movf` of a NaN traps or
   merely flags is not stated.

5. **`CVT.SW`'s out-of-range result.** `OV` is "Set if integer overflow
   occurs", but no page says what is *stored* when a real exceeds the word
   range — a saturated value, a truncated one, or the destination left
   unchanged. The integer `DIV` page states the unchanged-destination rule
   explicitly for its overflow; `CVT.SW`'s does not.

6. **`SCLF`'s immediate-quick count.** `SCLF` uniquely permits Immediate Quick
   for `count`, which is a 4-bit field, and the count operand is a halfword.
   The page does not say whether the quick immediate is zero-extended (as
   `SHL`/`SHA` explicitly are, `docs/v60/SHIFTS.md`) or sign-extended. It also
   does not bound the count, or say what `SCLF` does when scaling drives the
   result out of range beyond setting `FOV`.

7. **`5F-10` (`cvt.sl`).** Present in the Reference, absent from the plate.
   Whether the plate's omission is a printing error or a genuine statement
   that `5F-10` is not implemented cannot be told from the pages.

8. **Timing.** As everywhere else in this tree, the plate's Clocks column is
   blank for every row (`docs/v60/INSTRUCTION-TIMING.md`).

## Cross-check: `tools/v60x/insn_table.py`

Read only; nothing changed. The twelve rows in this group are at lines
112-124, the operand widths at lines 330-335.

**Opcodes: all twelve agree with the plate exactly.** `010111{s}0` for the
nine `5C`/`5E` instructions and `01011111` for the three `5F` ones, and every
sub-op pattern matches the plate's printed bits. The `s` field is declared
1 bit with values `[0, 1]` and documented as "floating point: 0 short real,
1 long real", which is p. 3.295's table verbatim. No transcription error found.

Three things to report:

1. **`SCLF`'s count width is wrong.** Line 333 has `'SCLF': (4, 's')` — a
   4-byte count. The Reference's syntax lines are `sclf.s count.h.r,
   dst.s.rw` and `sclf.l count.h.r, dst.l.rw`: the count is a **halfword**, 2
   bytes, in both. This is the same class of error `docs/v60/SHIFTS.md`
   records for the shift group's operand pair, and it has a second independent
   witness: `s32_v60.sv`'s `fp_dim1()` returns dim 1 (16-bit) for `5C-10` and
   dim 2 (32-bit) for everything else, with the comment "SCLFS takes a 16-bit
   integer scale". Should be `(2, 's')`.

2. **`CVTF`'s direction is now settled.** Line 333-334 has `'CVTF': ('?',
   '?')` with the comment "converts between the two reals; which way is in the
   Reference, not in the opcode". It is: `5F-08` is `cvt.ls`, `src.l.r,
   dst.s.w` — long real in, short real out. That makes the widths `(8, 4)`.
   The comment is exactly right about where to look; the answer just had not
   been fetched.

3. **`5F-10` is missing from the table**, because it is missing from the
   plate. The table is faithful to its stated source (p. 3.297) and this is
   not a transcription error, but it leaves `5F` sub-op `10` decoding to
   nothing when the Reference gives it as `cvt.sl`, `src.s.r, dst.l.w`, Format
   II. Adding it would need a mnemonic the databook never prints.

One structural caveat, not a discrepancy in this group's rows: `check_table()`
at line 543 enforces that every sub-op pattern is exactly 8 bits, and the
patterns are written as 8-bit literals. Format II's `subop` field is 5 bits
(p. 3.293), with `1`/`m`/`m'` above it, so these literals are the plate's
zero-extended rendering rather than a byte any consumer can compare against
the fetched second byte. Every sub-op in this group has its top three bits
zero, so the expansion and collision check are unaffected — but a decoder
generated from this column must mask to `[4:0]`.

## Cross-check: `rtl/cpu/v60/s32_v60.sv`

Read only. The FP unit is at lines 5163-5600, decode at 1762-1796, states at
3355-3420. Its own header comment states its contract: "Behavioral contract is
MAME op2.hxx/op5.hxx, which use host `float` — round-to-nearest-even, with
gradual underflow (subnormals) and IEEE special values. No System 32 game is
known to execute these."

**Where it agrees with the pages.**

- Format II decode: dispatches on `fb[1][4:0]`, takes `m` from `fb[1][6]`.
  That is p. 3.293's layout, and it is independent confirmation that the
  plate's 8-column sub-op is a 5-bit field.
- `SCLF`'s count is 16 bits (`fp_dim1`), against the table's 4 — the Reference
  agrees with the core.
- `DIVF` computes `fp_div_start(fp_b, fp_a)` with `fp_b` = op2 = dst, so
  `dst ÷ src` — the Reference's direction.
- `CMPF` computes "f(op2)-f(op1)", i.e. `src2 - src1` — the Reference's
  Operation line exactly.
- `CVT.SW` leaves `CY` alone (`f_s`, `f_ov`, `f_z` are assigned; `f_cy` is
  not), matching "CY Unchanged" and the plate's `—`.
- `CVT.SW` takes its rounding mode from `tkcw[2:0]`, and the three-way split
  it decodes — 1 → floor, 2 → ceil, else truncate — lines up with p. 3-9's
  `RD` = 01 toward −∞, 10 toward +∞, 11 toward zero, and with `RDI` = 1 (any
  `tkcw[2]`) forcing toward zero.

**Divergences, each against the page that contradicts it.**

1. **Long real is not implemented at all.** `fp_valid()` accepts only
   `op == 8'h5c` and `op == 8'h5f`; `5E` falls through the `8'h5c, 8'h5f` case
   label entirely and lands on the reserved-opcode path (vector 8). Every
   `.l` form on p. 3.297 — `movf.l` through `sclf.l`, all nine — is
   unimplemented, and so are `CVTF` (`5F-08`), `CVT.WL` (`5F-11`) and
   `CVT.LW` (`5F-09`); `fp_valid` admits only `5F-00` and `5F-01`. The entire
   datapath is 32-bit (`fp_a`, `fp_b`, `fp_res` are `[31:0]`).

2. **`MOVF` sets no flags.** Line 5572: `5'h08: begin r = fp_a; fp_res <= r;
   fp_finish_write(); end   // MOVFS (no flags)`. The Reference's `MOVF` page
   prints a full four-line Condition Codes block and the plate's row is
   `• 0 • •`. `f_cy`/`f_ov`/`f_s`/`f_z` keep whatever the previous instruction
   left.

3. **`CMPF`'s `CY` and `OV` are hardwired to zero.** Lines 5566-5570 set
   `f_ov <= 1'b0; f_cy <= 1'b0` and put the ordering into `f_s <= fp_lt(fp_b,
   fp_a)`. The Reference says "CY Set if the result is negative, otherwise
   cleared" and "OV Set if unordered, otherwise cleared", and the plate's
   `CMPF` row is the only one in the block whose `OV` cell is a dot rather
   than a `0` — the plate specifically records that `OV` moves here. The core
   instead signals unordered by forcing `f_z` and `f_s` to 0 (its `un` term),
   which is MAME's materialised-subtraction behaviour, not the page's.

4. **No floating point condition codes are ever produced.** `FIV FZD FOV FUD
   FPR` are PSW bits 12:8 (`TRAPFL`, p. 3.297 / Reference §7). The core reads
   them once — line 1826, `(tkcw & 32'h0000_01f0) & ((psw & 32'h0000_1f00) >>
   4)` in `TRAPFL` — and writes them nowhere. Grepping the file for any write
   to that field returns only that read. So `TRAPFL` can never fire as a
   consequence of an FP result, and every "Set if … otherwise unchanged"
   sentence on all eleven pages is unimplemented.

5. **No floating point exception is ever raised.** None of Reserved Floating
   Point Operand, Invalid Floating Point Operation, Floating Point Zero
   Divide, Overflow, Underflow or Precision. Concretely: `ADDF`'s "If a source
   or destination operand is a NaN or an infinity, a Reserved Floating Point
   Operand exception will occur and the flags and destination will remain
   unchanged" is contradicted by `fp_add()`, which returns `32'h7fc00000` for
   a NaN input and propagates infinities as values; and `DIVF`'s Floating
   Point Divide by Zero (the plate's code 11, on the only row that carries it)
   is contradicted by `fp_div_start()`, which returns `{sign, 8'hff, 23'd0}` —
   a signed infinity — for a zero divisor. This is the same shape of
   divergence `docs/v60/MULTIPLY-DIVIDE.md` records for the integer zero
   divide: three NEC statements against an emulator's omission.

6. **Rounding ignores `RD`.** `fp_pack()` is unconditionally
   round-to-nearest-even for `ADDF`/`SUBF`/`MULF`/`DIVF`/`SCLF`/`CVT.WS`; it
   never reads `tkcw`. p. 3-9 gives four programmable directions and
   `ADDF`/`SUBF` explicitly defer the zero-sign question to "the programmed
   rounding mode".

7. **`CVT.SW`'s nearest mode rounds half away from zero.** `cvt_s_w`'s comment
   and code: mode 0 is "round-half-away-from-zero" (`roundup = fracbits[31]`).
   p. 3-9 calls `RD = 00` "round toward nearest" without a tie rule; §1 claims
   IEEE 754 conformance, whose nearest mode breaks ties to even. The core's
   choice follows the x86 host convert MAME was pinned to, which its comments
   say outright ("Pinned MAME converts (uint32_t)(int64_t)val on its x86
   host").

8. **`CVT.SW` out of range stores low bits, not a saturate.** `cvt_s_w` for
   `e >= 31` takes `big[31:0]` of the 64-bit truncation and for `e >= 63`
   stores 0, with the comment "MAME stores the LOW 32 BITS of the int64
   truncation, not a clamp". The page says only that `OV` is set; it does not
   say what is stored, so this is MAME filling a gap the Reference leaves —
   see item 5 of the previous section.

9. **`ABSF`'s `S` is not unconditionally cleared.** Line 5583 computes
   `neg = fp_a[31] & (…) & !fp_isnan(fp_a)` and then `f_s <= r[31]`, so a
   negative NaN source leaves `S` set. The Reference says "S Cleared" with no
   qualifier and the plate's `ABSF` row prints a literal `0` in the `S`
   column. (On the page's own terms the case cannot arise, because a NaN
   source is supposed to trap before anything is written — so this divergence
   is downstream of item 5.)

10. **`NEGF`/`ABSF` do not read their destination**, which is correct
    (`dst.s.w`, write-only) and worth recording as agreement rather than
    divergence — the core's `fp_op2_rmw()` deliberately excludes them, with
    the comment "they operate on op1 and must not read a possibly
    read-sensitive destination". The Reference's `.w` access type is the
    authority for that, and the core matches it.

---

# Addendum: `SUBF`'s operand order, run to ground

`What the pages do not settle` item 1 above records `SUBF`'s operand order as
open, and says it "must be decided". This section is the evidence, gathered
afterwards. **It does not close the question from a page — but it moves it a
long way, and it inverts one of the arguments the item leans on.**

The Programmer's Reference PDF is still not held. Everything quoted from it is
`docs/reference/NEC_V60pgmRef_djvu.txt`, its OCR text layer. Everything quoted
from the databook is read on the plate.

## 1. What the OCR actually prints, verbatim

Blank lines elided; nothing else changed. Line numbers are into the OCR file.

**`ADDF`** (16689):

```
Operation

dst



src + dst



Description

The sum of the source and destination operands is
stored in the destination operand.
```

**`SUBF`** (47615):

```
Operation

dst



src - dst



Description

The difference of the source operand and destination
operand is stored in the destination operand.
```

**`MULF`** (34522):

```
Operation
dst



Addressing Modes



src * dst



Description

The product of the source operand and destination
operand is stored in the destination operand.
```

**`DIVF`** (25516):

```
Operation

dst



dst + src



Description

The quotient of the source operand and destination
operand is stored in the destination operand.
```

**`CMPF`** (22543):

```
Operation

Flags



src2 - srd



Description

The difference of the two source operands is computed
and the Integer and floating point condition codes are
updated to reflect the result of the operation.
```

(`CMPF`'s syntax line is `srd.s.r, src2.s.r` — the OCR reads `src1` as `srd`
in both places, consistently. `DIVF`'s `+` is the OCR's rendering of `÷`; the
same substitution appears on the integer `DIV` page, where the Description
independently says "quotient".)

**On the formatting question the brief asks — is `SUBF`'s line laid out like
`DIVF`'s or like `ADDF`'s?** All four are laid out identically: the word
`Operation`, then `dst` alone on a line, then the expression on a line of its
own. `MULF` is the only one whose block is disturbed, and only by the
`Addressing Modes` heading floating up into it from the next column. **Layout
distinguishes nothing here.** What differs between the pages is not the
structure but the token order inside the expression, and the OCR reproduces
that faithfully — which is the point item 1 makes, and which turns out to cut
the other way.

## 2. The reframing: OCR fidelity is what convicts `SUBF`'s line

Item 1's counter-argument is that "the OCR is a faithful token sequence for
`ADDF` (`src + dst`) and `MULF` (`src * dst`) on the same book, so it may be
reproducing a genuinely source-first convention."

Two things are wrong with that as an argument for `src - dst`.

**First, `ADDF` and `MULF` are evidence of nothing.** Addition and
multiplication are commutative. NEC could print either order on those two pages
and be correct, so their order establishes no convention — it establishes only
that the OCR preserves order, which nobody disputes.

**Second, and decisively: the group's other non-commutative operations are
printed destination-first.** If a source-first convention existed, `DIVF` would
read `src ÷ dst`. It reads `dst ÷ src`. And `SCLF` (43844), the third
non-commutative floating point operation, reads:

```
Operation

dst

dst * 2count

Description

The destination operand is scaled by the integer count
and stored in the destination operand.
```

— `dst ← dst × 2^count`, destination first again.

So within the floating point group:

| | operation printed | order observable? |
|---|---|---|
| `ADDF` | `src + dst` | no — commutative |
| `MULF` | `src * dst` | no — commutative |
| `DIVF` | **`dst ÷ src`** | **yes — destination first** |
| `SCLF` | **`dst * 2^count`** | **yes — destination first** |
| `SUBF` | **`src - dst`** | **yes — source first** |

**`SUBF` is the sole outlier among the operations where order can be seen at
all**, and the fidelity of the OCR is precisely what makes that visible: the
same transcription that preserves `src - dst` on one page preserves
`dst ÷ src` on another. There is no single convention under which both lines
are right. One of the two is a typesetting error in NEC's book.

## 3. The Description prose cannot settle it, and demonstrating that is itself a result

The brief asks whether `SUBF`'s Description says in words what its formula
says in symbols, the way `SUBRDC`'s does. **It does not — and neither does
`DIVF`'s, which is why the prose is worthless here.**

Set them side by side:

- `SUBF`: "The **difference of the source operand and destination operand** is
  stored in the destination operand."
- `DIVF`: "The **quotient of the source operand and destination operand** is
  stored in the destination operand."

Word-for-word parallel — *the X of the source operand and destination operand*
— sitting over two formulas that are printed in **opposite** orders. The same
English phrase covers `src - dst` on one page and `dst ÷ src` on the next.
`ADDF` ("The sum of the source and destination operands") and `MULF` ("The
product of the source operand and destination operand") use the same template.

So the floating point group's Description sentences are **order-neutral
boilerplate**. They cannot decide `SUBF`, and their inability to is not a gap
in the transcription — it is a property of how the four pages were written.

Contrast the two places in the book where NEC *does* put the order in words:

- **Integer `SUB`** (46651): "The source operand is subtracted **from** the
  destination operand and the result stored in the destination operand."
- **`SUBDC`** (47272): "The CY flag and source operand are subtracted **from**
  the destination operand."
- **`SUBRDC`** (47961): "The CY flag and destination operand are subtracted
  **from** the source operand."
- **`REM`** (39699): "The integer remainder of **the destination operand
  (dividend) divided by the source operand (divisor)**."

The preposition "from", and `REM`'s parenthetical role names, carry the order.
The floating point group uses "the difference of A and B" and carries nothing.

## 4. The integer group is uniformly destination-first

Every integer operation whose order is observable, with its Operation block as
the OCR prints it:

| | operation | prose says the order? |
|---|---|---|
| `SUB` (46651) | `dst ← dst − src` | **yes** — "subtracted from the destination operand" |
| `SUBC` (46946) | `dst ← dst − src − CY` | no |
| `DIV` (25223) | `dst ← dst ÷ src` | no — same "quotient of" boilerplate |
| `REM` (39699) | `dst ← dst % src` | **yes** — "the destination operand (dividend) divided by the source operand (divisor)" |

Four for four, and the two that spell it out spell out destination-first. There
is no instruction anywhere in the book, outside `SUBF` and the explicitly
reversed `SUBRDC`, whose Operation block puts the source on the left of a
non-commutative operator.

## 5. A reversed form gets its own mnemonic — and the floating point group has none

`SUBRDC` is the whole argument in one row. NEC needed `dst ← src − dst` in the
decimal group, and rather than reverse `SUBDC` it added a **separate
instruction with a separate opcode and a separate mnemonic**: `59-02`,
"Subtract Decimal **Reversed** with Carry". The plain form and the reversed
form coexist, and the name says which is which.

The floating point group's instruction list, read off the databook **p. 3.297**
plate, is:

`MOVF` `ADDF` `SUBF` `MULF` `DIVF` `CMPF` `NEGF` `ABSF` `SCLF` `CVTF`
`CVT.WS` `CVT.WL` `CVT.SW` `CVT.LW` `TRAPFL`

**There is no `SUBRF` and no `DIVRF`.** So if `SUBF` really computed
`src − dst`, the V60 would have *no way at all* to compute `dst − src` in a
single floating point instruction — the operation an accumulate loop actually
needs, and the one every other subtract in the instruction set performs. A
machine that provides only the reversed subtract, provides the plain divide,
and provides no reversed divide, is not a coherent design.

## 6. The databook has nothing to add — confirmed on the plate

p. 3.297's column headers, cropped and read at 600 dpi:

```
Mnemonic | Opcode 7 6 5 4 3 2 1 0  7 6 5 4 3 2 1 0 | Instruction Format | Clocks | Flags CY OV S Z | Exceptions
```

**There is no Operation column**, on that page or anywhere in the summary. The
databook prints encodings, formats, flags and exception numbers and no
semantics for any instruction in the set, so it cannot bear on operand order
for this or anything else.

The third PDF held, `1987_Microcomputer_Products_Vol_2.pdf`, was extracted and
searched: its µPD70616 section is the **same datasheet**, at the same `3-229`
page numbering, and its only `ADDF`/`SUBF` hits are an unrelated ALU
function-code table for a different part. No second source exists in the
material held.

## 7. What I would decide, and how confident

**Decision: implement `SUBF` as `dst ← dst − src`.**

Confidence: **high**, and the reasoning is a weight-of-evidence argument rather
than a page quotation — so it is a **decision**, not a page fact, and should be
recorded as one at the point of decision in the RTL.

Separated as usual:

- **Page.** `SUBF`'s Operation block prints `src - dst`. This is the single
  piece of direct evidence, and it is against the decision.
- **Page.** `DIVF` prints `dst ÷ src` and `SCLF` prints `dst × 2^count` — the
  only other floating point operations whose order is observable, both
  destination-first, both on pages transcribed by the same OCR.
- **Page.** Integer `SUB`, `SUBC`, `DIV` and `REM` are all destination-first,
  and `SUB` and `REM` say so in prose.
- **Page.** The floating point Description sentences are order-neutral
  boilerplate, identical over `SUBF`'s and `DIVF`'s opposite formulas, so they
  support neither reading.
- **Page.** The decimal group needs a separate mnemonic (`SUBRDC`) for a
  reversed subtract; the floating point group has no reversed mnemonic.
- **Inferred.** If `SUBF` were `src − dst`, `dst − src` would be uncomputable
  in one floating point instruction while `dst ÷ src` remained available —
  which no instruction set does on purpose.
- **Inferred.** `SUBF`'s printed line is a typesetting error, most plausibly
  the commutative `ADDF` line above it being edited into a subtract without the
  operands being reordered. `ADDF` is `5C-18` and `SUBF` is `5C-19`; they are
  adjacent pages of the same template, and `src + dst` → `src - dst` is a
  one-character edit.
- **Unknown.** Nothing held can rule out the possibility that NEC intended a
  reversed floating point subtract. That possibility is what keeps this a
  decision. It would require the design defect in the previous bullet to be
  deliberate, and it would still leave `DIVF`'s line and `SUBF`'s line
  mutually inconsistent as a "convention".

**What would settle it.** A plate of Programmer's Reference page 7-97 (`SUBF`),
which the tree does not hold; or any V60 assembler, compiler back end or
worked example that performs a floating point subtract and shows which operand
is diminished. The µPD70632 (V70) documentation cited in
`docs/v60/INSTRUCTION-TIMING.md` would also serve if it prints Operation
blocks, since the V70 is instruction-set compatible — that is the cheapest
remaining avenue and it has not been tried here.

**If it is implemented as `dst − src`, the risk is bounded and detectable.**
`CMPF` prints `Flags ← src2 − src1`, which for a first operand `src1` and a
second operand `src2` is *second minus first* — the same direction as
`dst − src`. So `SUBF` and `CMPF` agree under the decision and disagree under
the printed line, and a program that subtracts and then compares the same pair
would expose the difference immediately. That is worth a test either way.
