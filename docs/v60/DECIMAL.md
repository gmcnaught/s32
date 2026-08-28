# The decimal group: ADDDC, SUBDC, SUBRDC, CVTD.PZ, CVTD.ZP

Five instructions, five opcodes, and one thing that is not what its format
letter suggests: these are **Format VIIc, but their extension byte is a mask
pattern, not a length**. They are not variable-length string instructions.
Each one processes a single byte (or halfword) and is chained across a decimal
number by the CY flag, which is why `ADDDC` is "Add Decimal **with Carry**"
and why its `Z` flag has a definition unlike any other in this instruction set.

Sources: databook p. 3.297 for the summary rows, p. 3.293 for Format VIIc,
p. 3.261 for the data-type constants, **p. 3.270** for the vector and
**p. 3.272** for the exception code — both of which are in the databook extract
and were read on the plate; Programmer's Reference §7 for the per-instruction
pages, §6 for the extension field, §3 for the data type, §8 for the exception.
Exception numbers are decoded with `docs/v60/INSTRUCTION-SUMMARY-LEGEND.md`.

## The five rows, read off p. 3.297

Re-rendered at 600 dpi and cropped. All five are primary opcode **`0x59`**
(`01011001`), **Format VIIc**, Exceptions **`1, 5`**:

| Mnemonic | opcode | subop | Format | CY OV S Z | Exceptions |
|---|---|---|---|---|---|
| `ADDDC` | `01011001` | `00000000` | VIIc | `• – – •` | 1, 5 |
| `SUBDC` | `01011001` | `00000001` | VIIc | `• – – •` | 1, 5 |
| `SUBRDC` | `01011001` | `00000010` | VIIc | `• – – •` | 1, 5 |
| `CVTD.PZ` | `01011001` | `00010000` | VIIc | `– – – •` | 1, 5 |
| `CVTD.ZP` | `01011001` | `00011000` | VIIc | `– – – •` | 1, 5 |

The Programmer's Reference's Opcode blocks give `59-00`, `59-01`, `59-02`,
`59-10`, `59-18` — every row double-sourced, and none of the transcription
trouble that afflicts the bit-string group two blocks below on the same page.

The sub-op is five bits wide (§6: "op is the eight bit wide opcode field and
subop is the five bit wide opcode extension field"), so the printed `000`
prefix is padding and `0x10`/`0x18` are `10000`/`11000`. The group's numbering
is `00/01/02` for the three arithmetic and `10/18` for the two conversions —
bit 4 of the sub-op separates them and bit 3 gives the direction.

Note the plate's flag notation is not self-consistent across the page: this
block prints `–` for "unchanged" where the bit-field block prints an empty
cell, and elsewhere on p. 3.296 a literal `0` means "cleared". The Reference's
Condition Codes blocks resolve all three, and they agree with this row: on the
three arithmetic instructions **CY and Z move, OV and S do not**; on the two
conversions **only Z moves**.

## What Format VIIc's extension byte means here

p. 3.293 draws Format VIIc as `ext'  mod'  mod  [1 m m' | subop | op]`, i.e.
two addressing-mode fields and one extension byte, in stream order `op`,
`subop`, `mod`, `mod'`, `ext'` — the same shape `INSBF` uses
(`docs/v60/BIT-FIELD.md`). Every one of these five has **three** operands, and
the third is the extension byte. §6 says so twice. Once in its Format VII
prose:

> "Format VII instructions contain an 8-bit extension field which is used to
> determine the length of a variable length character or bit string operand.
> … This field is also used to store the mask pattern for the ADDDC, SUBDC,
> SUBRDC, and CVTD instructions."

and once in the field legend of its Format VIIc figure:

> "Operand extension field containing either a length operand or a mask
> pattern (decimal arithmetic instructions)."

§6's definition of the format is written for the length case and fits the
decimal case only loosely: "Format VIIc Used when the source operand is a fixed
length data type and the destination operand is a variable length data type
**or with decimal arithmetic instructions**." The trailing clause is the
decimal group being admitted as an exception to the rule.

Confirmation from the Reference's own Addressing Modes tables: each of the five
prints three columns — `src`, `dst`, `pat` — and the `pat` column is **empty**,
where `src` and `dst` carry the usual `O`/`X` grid. An operand with no
addressing modes is not addressed; it is the extension byte.

## The data types

Everything below is Programmer's Reference §3, "Decimal Data Type", quoted
whole because it is short and every sentence is load-bearing:

> "The decimal data type is used for the manipulation of both packed and
> unpacked decimal numeric strings. The decimal data type divides each byte
> into two 4-bit fields (nibbles). In the packed decimal representation, each
> 4-bit field is assumed to contain a valid BCD (binary code decimal) digit in
> the range [0..9]. In the unpacked (or zoned) decimal representation, only the
> lower 4-bit field is assumed to contain a digit and the higher 4-bit [field]
> is called the zone field.
>
> When a nibble is expected to contain a digit, only the valid BCD values
> [0..9] can be specified. Any other value will cause an illegal decimal format
> exception to occur. There is no restriction on the contents of the zone
> field."

So:

- **Packed decimal** — one byte, **two** digits, high nibble the more
  significant. Both nibbles must be `0`-`9`.
- **Zoned (= unpacked) decimal** — one byte, **one** digit in the low nibble,
  with the high nibble a *zone* whose contents are unrestricted. Two zoned
  bytes therefore carry the same information as one packed byte.

Neither is signed. §3 gives packed and zoned decimal no sign nibble, no sign
byte and no sign convention at all — unlike the integer types, whose
description a page earlier does define a sign bit for. **Sign is not part of
the V60's decimal data type**; a program that needs one carries it itself.
That also explains why `S` never moves on any of the five and why `OV` never
moves either: there is no sign to report and no representable range to
overflow beyond the byte, whose overflow is `CY`.

Databook p. 3.261's scaling table is consistent and explains its own two rows:
**Packed Decimal 1 / 1** and **Unpacked Decimal 2 / 2**. The unit in both cases
is *two digits* — one byte packed, two bytes zoned — which is exactly the
operand pair `CVTD` converts between, and exactly the step `[Rn+]` takes over
a decimal string of either kind.

## ADDDC, SUBDC, SUBRDC

```
adddc    src.b.r, dst.b.rw, pat.b.r   Add Decimal with Carry                59-00
subdc    src.b.r, dst.b.rw, pat.b.r   Subtract Decimal with Carry           59-01
subrdc   src.b.r, dst.b.rw, pat.b.r   Subtract Decimal Reversed with Carry  59-02
```

Both data operands are **bytes** — one packed-decimal byte, two digits. This
is a primitive, not a string operation.

**Operation:**

```
ADDDC    dst ← dst + src + CY  using mask pattern
SUBDC    dst ← dst - src - CY  using mask pattern
SUBRDC   dst ← src - dst - CY  using mask pattern
```

`SUBRDC` is the reversed one: source minus destination, result into the
destination. Its Description says it in words — "The CY flag and destination
operand are subtracted from the source operand with the result stored in the
destination operand" — so the reversal is of the operands, not of the result's
home.

**Descriptions**, `ADDDC`'s quoted whole; the other two differ only in the
operation and in "borrow" for "carry":

> "The CY flag and the decimal source operand are added to the decimal
> destination operand and the result is stored in the destination operand. The
> decimal addition operation occurs only for the unmasked portion of the
> operands, as determined by the mask pattern.
>
> The CY flag will be set if there is a carry out of the addition operation. If
> the result is non-zero or a carry is generated, the Z flag will be cleared,
> otherwise it remains unchanged.
>
> Following the addition operation, the result is checked to verify that a
> valid BCD representation exists in the unmasked portion of the result. If
> either value is not a valid BCD digit (0-9), a Decimal Format exception will
> occur and the destination will remain unchanged."

**Condition Codes**, all three (`SUBDC`'s and `SUBRDC`'s `CY` line reads
"borrow"):

```
CY  Set if a carry is generated, otherwise cleared          (ADDDC)
CY  Set if a borrow is generated, otherwise cleared         (SUBDC, SUBRDC)
OV  Unchanged
S   Unchanged
Z   Unchanged if the result is zero, otherwise cleared
```

### What CY actually means, and it is not the binary carry

`CY` here is the **decimal** carry or borrow out of the byte — out of the top
unmasked digit, i.e. a carry when the two-digit sum reaches 100 and a borrow
when the two-digit difference goes below zero. It is not bit 8 of a binary
addition of the two bytes: `0x59 + 0x59` as binary is `0xB2` with no carry out,
where as decimal it is 59 + 59 = 118, which is `0x18` with `CY` set.

`CY` is also an **input**, which no other flag in this instruction set is on
the read side of an arithmetic instruction: the Operation lines have `+ CY` and
`- CY` in them. That is the whole design. These five are the inner step of a
multi-byte decimal loop — clear `CY`, then `ADDDC` each byte from the least
significant upward, and the carry threads the digits together. It is why the
mnemonics all say "with Carry" and why there is no plain `ADDD`.

### Z is sticky, and it is the only sticky flag here

"**Unchanged** if the result is zero, otherwise cleared." `Z` is never *set* by
any of the five. To use it, a program presets `Z` (with `SETF`, or by any
instruction that leaves it set) before the loop; `Z` then survives to the end
only if every byte produced zero. It is an accumulated "the whole number was
zero" across a chain, not a per-byte result.

**The Condition Codes block and the Description do not agree.** The block says
`Z` is cleared when the result is non-zero. The Description says "If the result
is non-zero **or a carry is generated**, the Z flag will be cleared" — a second
clearing condition the one-liner omits. The Description is the more specific
statement and is the one that makes the chained use correct: a byte that
produces `00` with a carry out is not a zero result of the whole number. Both
sentences are on the same page of the same book, and nothing reconciles them;
this doc records the Description's reading and flags the conflict below.

## CVTD.PZ, CVTD.ZP

```
cvtd.pz  src.b.r, dst.h.w, pat.b.r   Convert Packed to Zoned Decimal   59-10
cvtd.zp  src.h.r, dst.b.w, pat.b.r   Convert Zoned to Packed Decimal   59-18
```

**The mnemonics do read left to right**, and the Reference says so in its
Instruction column rather than leaving it to be inferred: `CVTD.PZ` is "Convert
**Packed to Zoned** Decimal" and `CVTD.ZP` is "Convert **Zoned to Packed**
Decimal". The operand sizes are the independent check — `.PZ` takes a byte and
writes a halfword, `.ZP` takes a halfword and writes a byte, which is the only
way round two packed digits and two zoned digits can go.

### CVTD.PZ — packed to zoned

**Operation**, as printed (the OCR drops isolated zero digits throughout this
book; the two `tmp` zero-fills are restored and marked):

```
tmp[3:0]   ← src[7:4]
tmp[7:4]   ← 0                  [zero restored]
tmp[11:8]  ← src[3:0]
tmp[15:12] ← 0                  [zero restored]
dst[7:0]   ← tmp[7:0]  ∨ pat[7:0]
dst[15:8]  ← tmp[15:8] ∨ pat[7:0]
if src = 0 then Z ← Z else Z ← 0
```

> "The byte length source operand is unpacked by performing a bit-wise OR o[f]
> the digits with the pattern operand.
>
> [P]rior to the conversion, the source operand is checked to verify that a
> valid BCD representation exists in the unmasked portion of the data. If
> either value is not a legal BCD digit (0-9), a Decimal Format exception will
> occur and the destination will remain unchanged."

Two things this fixes that a summary would lose:

- **The digit order is crossed.** The **high** nibble of the packed source
  becomes the digit of the **low** half of the destination halfword, and the
  low nibble becomes the digit of the high half. Worked: `src = 0x59`,
  `pat = 0x30` → `tmp = 0x0905` → `dst = 0x3935`. In memory, little-endian,
  that is `0x35` at the lower address and `0x39` at the higher — `'5'` then
  `'9'`. So a zoned decimal string runs **most significant digit at the lowest
  address**, and `CVTD.PZ` is what puts it there.
- **`pat` supplies the zone**, by OR. `0x30` gives ASCII digits. The pattern is
  OR'd as a whole byte into both halves, so its low nibble lands on top of the
  digit — a pattern with `pat[3:0] ≠ 0` corrupts the digit it is meant to
  decorate. No page says the low nibble must be zero.

`Z` tests the **source**.

### CVTD.ZP — zoned to packed

**Operation**, as printed (the OCR renders `≠` as `*`; the Description
confirms it is a comparison):

```
if ( src[7:4] ≠ pat[7:4] ) or ( src[15:12] ≠ pat[7:4] ) then
    Decimal_Format_Exception
if ( src[3:0] > 9 ) or ( src[11:8] > 9 ) then
    Decimal_Format_Exception
dst[3:0] ← src[11:8]
dst[7:4] ← src[3:0]
if dst = 0 then Z ← Z else Z ← 0
```

> "The halfword source operand is converted from zoned decimal format to packed
> decimal format and stored in the destination operand.
>
> Prior to the conversion, the source operand is checked to verify that a valid
> BCD representation exists in the lower nibbles of the upper and lower bytes.
> The upper nibbles are then compared to the upper nibble of the mask pattern.
> If either condition exists, a Decimal Format exception will occur and the
> destination will remain unchanged."

It is the exact inverse of `CVTD.PZ`: `src = 0x3935`, `pat[7:4] = 3` →
`dst[3:0] = src[11:8] = 9`, `dst[7:4] = src[3:0] = 5`, `dst = 0x59`.

Two asymmetries with `CVTD.PZ`, both in the page and neither explained by it:

- `CVTD.PZ` **ORs `pat[7:0]`**, the whole byte. `CVTD.ZP` **compares
  `pat[7:4]`**, the upper nibble only. So a round trip that uses the same
  pattern byte works, but the two instructions read different widths of it.
- `Z` tests the **destination** here and the **source** on `CVTD.PZ`. For an
  exact conversion the two are the same test, so nothing observable turns on
  it — but they are printed differently and are transcribed that way.

`CVTD.ZP` is also the only one of the five that raises the decimal exception
for something that is **not** a bad digit: a zone nibble that does not match
`pat[7:4]` is a well-formed BCD digit position with an unexpected zone, and §3
says explicitly "There is no restriction on the contents of the zone field".
The restriction here comes from the instruction, not from the data type.

**Condition Codes**, both conversions: `CY`, `OV`, `S` unchanged, `Z` sticky as
above. That is the plate's `– – – •`.

## The Decimal Format exception

### What makes an operand illegally formatted

**Which nibble values:** anything outside `0`-`9`, i.e. `0xA`-`0xF`.

**In which position:** *digit* positions only. For a packed byte that is both
nibbles; for a zoned byte only the low nibble. §3: "When a nibble is expected
to contain a digit, only the valid BCD values [0..9] can be specified. …
There is no restriction on the contents of the zone field." §8 states the same
rule from the exception's side:

> "A decimal format exception occurs when the result of a decimal arithmetic
> operation or data type conversion is not a valid BCD representation."

**When each of the five checks, and what it checks:**

| | what is checked | when | on failure |
|---|---|---|---|
| `ADDDC` `SUBDC` `SUBRDC` | the **result**, in the unmasked portion | *following* the operation | destination unchanged |
| `CVTD.PZ` | the **source**, in the unmasked portion | *prior to* the conversion | destination unchanged |
| `CVTD.ZP` | source digit nibbles `> 9`, **and** source zone nibbles `≠ pat[7:4]` | *prior to* the conversion | destination unchanged |

**All five can raise it.** All five print an `Exceptions` block whose only entry
is `Decimal Format`, and all five carry `5` in the summary's Exceptions column.

Note that the three arithmetic instructions' *per-instruction* sentence checks
the **result** and not the operands. That is an *additional* check on the way
out, and it makes sense for hardware whose adder is nibble-wise and can produce
a non-digit from two digits.

**It does not replace §3**, which states the operand rule as a property of the
**data** — "Any other value will cause an illegal decimal format exception to
occur" — and therefore covers all five. `docs/v60/DECIMAL-AUDIT.md`'s D1 is the
correction: an earlier reading of this section treated the result check as the
only one and concluded it was unreachable, which was false in both halves. The
implementation now checks operands (total) and keeps the result check (the
page's own extra rule), which is what makes the unreachability claim true.

### The vector and the code, both off plates

The lead's figures are confirmed, and from the **databook**, not the
Programmer's Reference's OCR:

- **Vector 23.** Databook **p. 3.270** (PDF page 42) prints the System Base
  Table as a numbered figure. Read at 600 dpi, entries 16 through 23 are:
  `16 Reserved Opcode`, `17 Privileged Instruction`, `18 Reserved Addressing
  Mode`, `19 Illegal Addressing Mode`, `20 Illegal Data Field`, `21 Integer
  Arithmetic`, `22 Floating Point Arithmetic`, **`23 Decimal Arithmetic
  Exception`**. At four bytes an entry that is SBT offset **+92**. The
  Reference agrees from the other side: §8's Figure 8-5 heads its decimal block
  `#23  Decimal Exceptions / Decimal Format`.

  That plate settles two things left open elsewhere in this tree. It confirms
  `docs/v60/MULTIPLY-DIVIDE.md`'s Integer Arithmetic Exception at vector 21,
  and it confirms **Illegal Data Field at vector 20** — which
  `docs/v60/BIT-FIELD.md` could only take from §8's numbered list, because the
  OCR of the Reference's Figure 8-2 pairs its labels one row out from its
  offsets. The databook figure is numbered rather than offset and has no such
  drift.

- **Code `1780`.** Databook **p. 3.272** (PDF page 44) prints the Exception
  Codes table. Read at 600 dpi, the last row of the **Arithmetic Exceptions**
  block is `1780  decimal format exception`, directly under `1680 reserved
  floating point operand`. It is the only decimal code in the table. The
  databook has no separate "Decimal Exceptions" heading — the Reference's §8
  does — but the code numbering carries the split anyway: `15xx` integer
  (vector 21), `16xx` floating point (vector 22), `17xx` decimal (vector 23).

- **The frame.** §8's Figure 8-5 puts `#21`, `#22` and `#23` under one heading,
  `Arithmetic Exceptions`, with disposition `Abort / Continue` and one frame:

  ```
     +12   PC (Current PC)
     +8    Exception Code  |  8
     +4    PSW
      0    PC (Next PC)
  ```

  The same frame `docs/v60/MULTIPLY-DIVIDE.md` records for Zero Divide: the
  Current PC is a **parameter** above the code word, the return address on top
  is the **Next** PC, and the parameter count `8` = 4 × (1 parameter + 1), so a
  handler returns with `RETIS #8`. A decimal-format handler therefore returns
  *past* the instruction that trapped, onto an unchanged destination.

### Naming

The Reference calls it `Decimal Format` in every per-instruction block and
`Decimal Format` under `Decimal Exceptions` in §8; the databook's p. 3.299
legend calls code 5 **`Illegal Decimal Format`** and its p. 3.272 code table
calls it `decimal format exception`. Three spellings of one exception across
two books — the same drift `docs/v60/BIT-FIELD.md` recorded for `Illegal Data
Field` / `Illegal Data Type`. Nothing states they are the same thing; the code,
the vector and the instruction set that raises it all line up, so they are.

### Exception `1` is the immediates, not the register mode

The summary's other number decodes as Illegal Addressing Mode, and as in the
previous two groups it comes from the Addressing Modes table's `X` cells rather
than from the `Exceptions` block. Reading `ADDDC`'s table down all sixteen
modes: `src` is `O` for **every** mode including `Immediate.Quick` and
`Immediate`; `dst` is `O` for fourteen and `X` for the two immediates. So the
`1` here is just "you cannot write to an immediate".

That is a real contrast with the bit-field and bit-string groups, where the
`X` was on `Rn`: **register direct is perfectly legal for a decimal operand**.
These are ordinary byte operands addressed the ordinary way, which is another
sign that the group's kinship with the string formats is the extension byte
and nothing else.

## Interruptibility: no

**None of the five carries the interruptibility paragraph.** The sentence "To
minimize the interrupt latency time, the … instruction allows the service of
interrupts and faults following the completion of a bus cycle" appears on
exactly thirteen pages of the Programmer's Reference — the ten bit-string pages
(`docs/v60/BIT-STRING.md`) and the three character-comparison pages
(`CMPC`, `CMPCF`, `CMPCS`) — and on none of `ADDDC`, `SUBDC`, `SUBRDC`,
`CVTD.PZ`, `CVTD.ZP`. No decimal page names R28, R27 or any other resumption
register, and `PSW.IP` is not mentioned.

The reason is in the syntax lines rather than in any statement about
interrupts: **these instructions are not variable length**. `src.b`, `dst.b`,
`src.h`, `dst.h` — one byte or one halfword, fixed. The variable-length thing
in the group's format slot is not a length at all, it is the mask pattern.
There is no loop to interrupt. A decimal *string* on this machine is a software
loop of `ADDDC`s, and the interrupt lands between two of them like any other
instruction boundary.

So the structural finding from `docs/v60/BIT-STRING.md` — that this tree's
sequencer recognises exceptions only between instructions and would need a
mid-instruction entry path — **does not extend to this group**. Nothing here
costs the data-unit mux anything.

## What the pages do not settle

- **The mask pattern's encoding.** This is the largest gap. `ADDDC`, `SUBDC`
  and `SUBRDC` say the operation "occurs only for the unmasked portion of the
  operands, as determined by the mask pattern" and never define what a mask
  pattern looks like, which bit or nibble masks what, or what "unmasked
  portion" means at nibble granularity. The two `CVTD` instructions give
  bit-level Operation blocks for *their* use of the byte — OR'd in on `.PZ`,
  compared against `pat[7:4]` on `.ZP` — but that is a zone value, a different
  use of the same field. Same byte, two meanings, and only one of them printed.
- **What a masked decimal add computes.** If the high nibble is masked, is the
  result a single-digit add modulo 10 with `CY` out of the units digit, and is
  the masked nibble of the destination preserved? Nothing says.
- **Why the mask exists.** *Marked as a reading, not from a page:* a zoned byte
  has a digit in the low nibble and an unrestricted zone in the high one, and
  the arithmetic instructions' BCD check is explicitly restricted to "the
  unmasked portion". Masking the high nibble would let `ADDDC` operate directly
  on zoned bytes without the zone tripping the format exception. That fits
  every sentence involved and is the only use for a nibble mask that the data
  types suggest, but the Reference never connects the two.
- **`Z`'s two definitions.** The Condition Codes block ("Unchanged if the
  result is zero, otherwise cleared") and the Description ("If the result is
  non-zero **or a carry is generated**, the Z flag will be cleared") disagree
  on whether a carry out of a zero result clears `Z`. Same page, same book.
- **Whether `pat`'s bit 7 has the register-indirect meaning.** §6 defines
  bit 7 of the extension byte as the `r` bit — "Direct mode, length field
  contains the operand length" versus "Indirect mode, length field contains the
  number of a general purpose register". That definition is written entirely in
  terms of the **length**. Whether a *pattern* byte is subject to the same
  redirection — so that `pat` with bit 7 set means "the pattern is in Rn" — is
  never stated, and the decimal pages never mention it. A pattern of `0x80` or
  above is therefore undefined by the documents.
- **Whether `pat[3:0]` must be zero on `CVTD.PZ`.** It is OR'd straight onto
  the digit nibble, so a non-zero low nibble corrupts the digit. No page
  forbids it, and no page says what the result is.
- **Whether the arithmetic three trap on invalid input.** The pages check the
  *result*, not the operands. What happens for an input nibble of `0xA`-`0xF`
  that happens to yield a valid-BCD result is not addressed.
- **Sign.** §3 gives the decimal data type no sign representation. Whether the
  V60 has a convention for signed decimal that lives outside the data type
  description — a leading sign byte, a sign nibble by convention — is not in
  the material held.
- **Timing.** p. 3.297's Clocks column is blank for all five, as it is for
  every row in the summary (`docs/v60/INSTRUCTION-TIMING.md`).

## Cross-check: `tools/v60x/insn_table.py`

**No discrepancies.** The five encoding rows match the p. 3.297 plate exactly:

```python
('ADDDC',    '01011001',      '00000000', 'VIIc', '3.297'),
('SUBDC',    '01011001',      '00000001', 'VIIc', '3.297'),
('SUBRDC',   '01011001',      '00000010', 'VIIc', '3.297'),
('CVTD.PZ',  '01011001',      '00010000', 'VIIc', '3.297'),
('CVTD.ZP',  '01011001',      '00011000', 'VIIc', '3.297'),
```

Opcode byte, sub-op byte, format letter and page citation all confirmed, and
all five are corroborated by the Reference's `59-00/01/02/10/18`. These rows
print literal sub-ops rather than patterns, so unlike `EXTBF` and `INSBF` there
is no field expansion and no chance of the table claiming an opcode the
Reference does not document.

The operand widths are right too, and for a better reason than the comment
gives:

```python
'ADDDC': (1, 1), 'SUBDC': (1, 1), 'SUBRDC': (1, 1),
'CVTD.PZ': (1, 2), 'CVTD.ZP': (2, 1),
```

under "Decimal: packed decimal is 1 and unpacked is 2 (p.3.261), and the CVTD
pair converts between them in the direction its mnemonic gives". Databook
p. 3.261's plate does print Packed Decimal **1** and Unpacked Decimal **2**,
and the Reference's syntax lines independently give `src.b`/`dst.b` for the
three arithmetic, `src.b`/`dst.h` for `CVTD.PZ` and `src.h`/`dst.b` for
`CVTD.ZP` — two sources, same answer, and the mnemonic direction the comment
relies on is confirmed by the Reference's Instruction column rather than
assumed. This is the group where the `(a, b)` pairs came out right; the
bit-string group's did not (`docs/v60/BIT-STRING.md`).

As with `EXTBF`/`INSBF`, the pair covers the two `mod` operands and the third
operand — `pat` — has no slot, being the extension byte. Consistent with the
file's own convention.

## Cross-check: `rtl/cpu/v60/s32_v60.sv`

All five are implemented — the `8'h59` dispatch accepts sub-ops `5'h00`,
`5'h01`, `5'h02`, `5'h10`, `5'h18` and traps the rest to the `8'd8`
reserved-opcode catch-all, which is the whole documented group. The states are
`S_DEC_OP1` → `S_DEC_OP2` → (`S_DEC_RD`) → `S_DEC_EX` → (`S_DEC_WR`).

### What it gets right

- **Format VIIc byte order.** `S_DEC_OP2` reads the extension byte at
  `fb[5'd2 + len1 + len2]` — after both addressing-mode fields — and sets
  `total_len <= 5'd3 + len1 + len2`. That is `op`, `subop`, `mod`, `mod'`,
  `ext'`, matching p. 3.293's figure and `INSBF`'s layout.
- **Operand widths.** `ea_dim` is halfword for `CVTD.ZP`'s source (`5'h18` at
  decode) and for `CVTD.PZ`'s destination (`5'h10` in `S_DEC_OP1`), byte
  otherwise; `S_DEC_WR` writes `dbus_size` halfword only for `5'h10`. Matches
  `src.h.r` and `dst.h.w`.
- **`SUBRDC`'s reversal.** `sum = srcv - dstv - cy` where `srcv` comes from
  `op1` (the source) and `dstv` from the destination byte — the page's
  `dst ← src - dst - CY`.
- **Decimal, not binary, carry.** `srcv` and `dstv` are converted to `0`-`99`
  before the operation; `ADDDC` sets `cyo = (sum >= 100)` and reduces by 100,
  the subtracts set `cyo = (sum < 0)` and add 100. `CY` is fed in as `+ cy` /
  `- cy`. That is the page's chained decimal carry.
- **`Z` is only ever cleared** — `if (sum != 0 || cyo) f_z <= 1'b0;` — and it
  includes the carry term. So the RTL implements the **Description's** reading
  of `Z`, not the Condition Codes block's, which is the reading this doc records
  as correct. The conversions do `if (op1[7:0] != 0)` for `CVTD.PZ` and
  `if (resb != 0)` for `CVTD.ZP`, reproducing the page's source-versus-
  destination asymmetry exactly.
- **Both conversions' nibble crossings.** `CVTD.PZ` builds
  `resh = {(op1[3:0] | dec_pat), (op1[7:4] | dec_pat)}`, so `resh[15:8]` gets
  the source's low nibble and `resh[7:0]` its high nibble — the page's
  `dst[7:0] ← src[7:4] ∨ pat`, `dst[15:8] ← src[3:0] ∨ pat`. `CVTD.ZP` builds
  `resb = {op1[3:0], op1[11:8]}` — the page's `dst[7:4] ← src[3:0]`,
  `dst[3:0] ← src[11:8]`. Both correct, including the byte order that makes a
  zoned string most-significant-digit-first.
- **`CY`, `OV` and `S` are untouched by the conversion arms**, matching
  `– – – •`.
- **It is not interruptible, and does not need to be.** No `S_DEC_*` state
  tests `nmi_seen` or `irq_n`, which is correct here: no page asks for it, and
  the operands are one byte or one halfword. Unlike the bit-string group this
  is not a divergence.

### Divergences

1. **The mask pattern is decoded and then not used by the three arithmetic
   instructions.** `dec_pat` is loaded in `S_DEC_OP2` and never read in the
   `5'h00/01/02` arm of `S_DEC_EX`. The operation is unconditionally over the
   whole byte: `srcv = op1[7:4]*10 + op1[3:0]`, carry out at 100. The pages
   say the operation "occurs only for the unmasked portion of the operands, as
   determined by the mask pattern", so any non-trivial pattern gives the wrong
   result and the wrong carry. This is not straightforwardly fixable from the
   documents — see the first unsettled item above; the pattern's encoding is
   not printed anywhere, so the RTL is not *contradicting* a page here so much
   as declining to implement a sentence whose meaning the page withholds.

2. **`CVTD.ZP` never performs the zone check.** The page's Operation opens with
   `if (src[7:4] ≠ pat[7:4]) or (src[15:12] ≠ pat[7:4]) then
   Decimal_Format_Exception`, and the Description repeats it — "The upper
   nibbles are then compared to the upper nibble of the mask pattern". The
   `default` arm of `S_DEC_EX` computes `resb = {op1[3:0], op1[11:8]}` and
   compares nothing. `dec_pat` is dead on this path. Of the five, `CVTD.PZ` is
   the only one that uses the pattern at all.

3. **No Decimal Format exception is raised anywhere.** There is no BCD
   validity check in any of the five paths — not on the arithmetic result, not
   on `CVTD.PZ`'s source, not on `CVTD.ZP`'s digits. Invalid input is silently
   reinterpreted rather than trapped: `srcv = op1[7:4]*10 + op1[3:0]` on a
   nibble of `0xA` yields the *value* 10, so `0x0A` is treated as decimal 10
   and `0x1A` as 20. Nothing in the file references vector 23 or code `0x1780`.

4. **The pattern byte is given the length byte's register-indirect coding.**
   `S_DEC_OP2` does `dec_pat <= xb[7] ? rf_rdata_a[7:0] : xb`, under a comment
   saying "same reg-or-literal coding as lengths". §6 defines that `r` bit
   purely in terms of the length operand and no decimal page extends it to a
   pattern. The behaviour may well be right — it is one field and one bit — but
   it is not on a page, and it is the RTL choosing a reading of an
   undocumented case rather than following one.

5. **`bin2bcd` synthesises a divider.** `bin2bcd` does `q = v / 7'd10` on a
   7-bit value. That is a constant divide over a 0-99 domain and a fitter will
   reduce it, but it is worth knowing it is there — the rest of this core
   iterates rather than dividing (`docs/v60/MULTIPLY-DIVIDE.md`). Not a
   correctness divergence.

6. **`sum[6:0]` truncation is safe only because the reduction precedes it.**
   `resb = bin2bcd(sum[6:0])` is taken after the ±100 correction has brought
   `sum` into `0..99`, so the seven bits suffice. Recorded because the
   assignment reads as a truncation and is not one.
