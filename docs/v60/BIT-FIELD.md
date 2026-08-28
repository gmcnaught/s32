# The bit field group: EXTBF, INSBF, CMPBF

Three instructions, eight documented opcodes, one addressing mechanism that
nothing else in this tree uses. The encodings are read off the databook plate
at p. 3.296-3.299 (the instruction-set summary; the bit-field rows are on
p. 3.297); the syntax, operation, flags and exceptions are the Programmer's
Reference §7 pages for each instruction; the addressing is databook p. 3.261
and Programmer's Reference §3 and §6.

## The three rows, read off p. 3.297

The "Bit Field Instructions" block prints three rows. Both opcode bytes, the
format letter and the flags column, verbatim from the plate:

| Mnemonic | opcode | subop | Format | CY OV S Z | Exceptions |
|---|---|---|---|---|---|
| `EXTBF` | `01011101` | `000010 ext` | VIIb | *(blank)* | 1, 2 |
| `INSBF` | `01011101` | `000110 ext` | VIIc | *(blank)* | 1, 2 |
| `CMPBF` | `01011101` | `000000 ext` | VIIb | `• • • •` | 1, 2 |

So all three are escape opcode **`0x5D`** plus a sub-op byte whose low two bits
are the `ext` field. Expanded:

| | ext=00 | ext=01 | ext=10 | ext=11 |
|---|---|---|---|---|
| `CMPBF` | `5D-00` | `5D-01` | `5D-02` | reserved |
| `EXTBF` | `5D-08` | `5D-09` | `5D-0A` | reserved |
| `INSBF` | `5D-18` | `5D-19` | **not printed** | reserved |

The Programmer's Reference's Opcode blocks give exactly these bytes from the
other side — `5D-00/01/02`, `5D-08/09/0A`, `5D-18/19` — which is a second
source for every cell above and the reason `ext=10` is left blank for `INSBF`:
the Reference prints only two `INSBF` variants, `insbfr` and `insbfl`.

The exception numbers are the legend at the foot of p. 3.299: **1 = Illegal
Addressing Mode, 2 = Illegal Data Type.** (The scan clips the leading `Il` of
entries 1, 2 and 5, so the plate reads "legal Addressing Mode"; entries 3, 4
and 6-12 are undamaged and fix the list's shape.)

## The `ext` field, and the name collision that matters

`ext` on p. 3.295 is a **two-bit field in the sub-op byte**:

```
Bit Field Extension
ext   Data Type
00    signed
01    unsigned
10    right justified
11    reserved
```

`ext` on p. 3.293 is a **byte in the operand stream** — a different field with
the same name, and Format VII's whole reason for existing:

> "The extension field is used to specify the length of a variable length data
> type and is encoded as follows:
> bit 7 (ext) = 0 → bits 6:0 (ext) are the operand length
> bit 7 (ext) = 1 → bits 6:0 (ext) contain a pointer (register ID) to the
> general purpose register containing the operand length"

Two fields, one name, one page apart. The sub-op `ext` picks *which variant* of
the instruction runs; the stream `ext` byte carries `blen`. Anything reading
p. 3.295 and p. 3.293 together has to keep them apart.

## Format VIIb and VIIc

p. 3.293's Instruction Formats figure draws the three Format VII variants with
the 16-bit `op`/`subop` word at the right and the operand fields extending
leftward, i.e. in increasing instruction-stream order:

```
Format VIIa   ext'  mod'  ext   mod   [1 m m' | subop | op]
Format VIIb         mod'  ext   mod   [1 m m' | subop | op]
Format VIIc   ext'  mod'        mod   [1 m m' | subop | op]
```

So the stream order is:

- **VIIb** (`EXTBF`, `CMPBF`): `op`, `subop`, `mod` (operand 1), `ext` (operand
  2 — the length byte), `mod'` (operand 3).
- **VIIc** (`INSBF`): `op`, `subop`, `mod` (operand 1), `mod'` (operand 2),
  `ext'` (operand 3 — the length byte).

Which is exactly the position `blen` holds in each syntax line below: second
for `EXTBF`/`CMPBF`, third for `INSBF`. That correspondence is the check —
the figure and the syntax lines are in different books and agree.

The figure's legend, quoted so the field names are not paraphrased:

```
op, subop : opcode fields          reg : register field
disp      : signed displacement    mod, m : address mode field
d         : direction field        ext : operand extension field
'         : second operand identifer
```

## EXTBF — Extract Bit Field

```
extbfs   bsrc.w.r, blen.b.r, dst.w.w    Extract Sign Extended Bit Field   5D-08
extbfz   bsrc.w.r, blen.b.r, dst.w.w    Extract Zero Extended Bit Field   5D-09
extbfl   bsrc.w.r, blen.b.r, dst.w.w    Extract Left Justified Bit Field  5D-0A
```

Three operands: a **bit address** read, a **byte** length read, a **word**
destination written. `docs/v60/v60_operand_access.csv` carries the same three
as `bsrc.w(4B).r ; blen.b(1B).r ; dst.w(4B).w`.

**Operation:** `dst ← bitfield`

**Description**, quoted whole:

> "The designated bit field is extracted using the specified mode and stored in
> the destination operand.
>
> If the bit field length is zero, zero will be stored in the destination
> operand.
>
> The sum of the bit offset and the bit field length must not exceed
> thirty-two, otherwise an Illegal Data Field exception will occur."

**Condition Codes:** the block prints `-  -  -  -` and four lines:

```
CY  Unchanged
OV  Unchanged
S   Unchanged
Z   Unchanged
```

which is why p. 3.297's flags column for this row is blank.

**Exceptions:** `Illegal Data Field`. The addressing-mode table above it also
marks `Rn` as `X` — Illegal Addressing Mode — for `bsrc`, which is p. 3.297's
exception code 1.

## INSBF — Insert Bit Field

```
insbfr   src.w.r, bdst.w.rw, blen.b.r   Insert Right Justified Bit Field  5D-18
insbfl   src.w.r, bdst.w.rw, blen.b.r   Insert Left Justified Bit Field   5D-19
```

Note the operand order and the access types: the word source is **first**, the
bit-addressed destination is **read-modify-write**, the length is **last**.
That last position is what makes this VIIc rather than VIIb.

**Operation:** `bitfield ← src`

**Description**, quoted whole:

> "The source operand is converted to a bit field of specified length and
> stored in the destination operand.
>
> No transfer will occur if the bit field length is zero.
>
> The sum of the bit offset and the bit field length must not exceed
> thirty-two, otherwise an Illegal Data Field exception will occur.
>
> If the immediate quick addressing mode is specified for the source operand,
> the immediate data is zero extended to the word length before performing the
> insertion operation."

Two sentences here are load-bearing and are *not* the same as `EXTBF`'s:
zero length is a **no-op on the destination** (`EXTBF` at zero length *writes
zero*), and the immediate-quick source is **zero** extended, never sign
extended, whatever the variant.

**Condition Codes:** `-  -  -  -`, all four "Unchanged", as `EXTBF`.

**Exceptions:** `Illegal Data Field`, plus `Rn` marked `X` for `bdst`.

## CMPBF — Compare Bit Field

```
cmpbfs   bsrc.w.r, blen.b.r, src.w.r    Compare Sign Extended Bit Field   5D-00
cmpbfz   bsrc.w.r, blen.b.r, src.w.r    Compare Zero Extended Bit Field   5D-01
cmpbfl   bsrc.w.r, blen.b.r, src.w.r    Compare Left Justified Bit Field  5D-02
```

Three reads, no write — the result is the flags.

**Operation:** `flags ← src - bitfield`

The direction is fixed twice over: the Operation block prints the source first
and the field second, and the Description says the same thing in words.

**Description**, quoted whole:

> "The designated bit field is extracted using the specified mode and compared
> to the source operand. The comparison is made by subtracting the bit field
> data from the word length source operand and storing the result in the
> condition codes.
>
> If the bit field length is zero, zero will be subtracted from the source
> operand.
>
> The sum of the bit offset and the bit field length must not exceed
> thirty-two, otherwise an Illegal Data Field exception will occur.
>
> If the immediate quick addressing mode is specified for the source operand,
> the immediate data is zero extended to the word length before performing the
> comparison operation."

**Condition Codes:** all four move — `• • • •` on p. 3.297 — and the block is
the ordinary subtract block:

```
CY  Set if a borrow is generated, otherwise cleared
OV  Set if integer overflow occurs, otherwise cleared
S   Set if the result is negative, otherwise cleared
Z   Set if the result is zero, otherwise cleared
```

"Set if a **borrow** is generated" and not "carry": this is `CMP`'s convention,
not `ADD`'s.

**Exceptions:** `Illegal Data Field`, plus `Rn` marked `X` for `bsrc`.

## The addressing: what a bit address is

This is the part the pages settle completely, and it is on databook p. 3.261
under the heading "Bit Addressing":

> "In the µPD70616, bit addresses are required to support the bit field and bit
> string data types which unlike the other data types can be aligned on an
> arbitrary bit boundary. To address any bit within the 4GB virtual address
> space, a 35-bit address is required. The µPD70616 generates this 35-bit
> address using a 32-bit base address and a 32-bit bit offset.
>
> To compute a bit address, the 32-bit base address is zero extended on the
> right to 35 bit length. Next the 32-bit bit offset is sign extended to 35-bit
> length and the sum of these two identify the starting address of the bit
> field or bit string."

The figure below that sentence draws it: a 31..0 `Base Address` box with three
extra `0` cells hanging off its right end; a 31..0 `Sign Extended Bit Offset`
box with "Sign Extension" arrowed at its top end; both into a `+`; out into a
34..0 `Bit Address`.

So, answering the three questions directly:

- **Is the offset signed?** Yes. "the 32-bit bit offset is sign extended to
  35-bit length". A negative offset addresses bits *below* the base byte.
- **How wide is the offset?** 32 bits, sign extended to 35. Where the offset
  comes from depends on the addressing mode (below), and a displacement-derived
  offset may be 8, 16 or 32 bits — signed, per p. 3.293's legend "disp :
  signed displacement" — before that widening.
- **How is the offset scaled?** It is not. The *base* is scaled: "zero extended
  on the right to 35 bit length" is a shift left by three, converting a byte
  address to a bit address. The offset is added at bit granularity, unscaled.
- **Maximum field width?** 32 bits. Programmer's Reference §3: "An instance of
  the bit field data type can take any length between [0] and 32 bits, starting
  at any bit position in memory and subject only to the constraint that the bit
  field not span a length of greater than four bytes." §8 says the same from
  the exception side: "the bit field data type can range in length from [0] to
  32 bits. Should a length greater than 32 bits be specified, an illegal data
  field exception will occur."

The Programmer's Reference §3 adds the sentence that turns the 35-bit address
back into something a bus can use:

> "Once formed, the upper 32-bits of the bit address is used to identify the
> byte address of the operand with the lower three bits identifying the bit
> offset within the byte."

That is an **arithmetic** split of the 35-bit sum — a floor, not a truncation —
because it is a field selection out of a two's-complement number, not a
division. It matters, and it is where the RTL parts company; see below.

`docs/v60/DATA-ACCESS-SPLIT.md` already records the same reading of the same
page from the addressing side, and `docs/v60/ADDRESSING-MODES.md` records the
p. 3.294 sentence that closes the loop: "Bit addressing modes use the same
encodings as the equivalent byte addressing modes, only the assembler format
differs."

### How each addressing mode supplies base and offset

Programmer's Reference §6, quoted:

> "The bit displacement modes are re-interpretations of the byte displacement
> addressing modes. The displacement field is interpreted as the bit offset
> from the base address. In the case of instructions with no displacement
> field, an offset of [zero] is substituted. The other exception is the double
> displacement addressing mode which uses one displacement field to locate a
> memory based pointer and the second displacement field as the bit offset.
>
> The bit index modes are re-interpretations of the scaled index addressing
> modes. When used where a bit address is required, the index register Rx is
> interpreted as a bit displacement and any base register and displacement
> fields form the byte base address. Notice that this addressing mode is not
> inconsistent with its other uses, since the index register is scaled to the
> size of the data, which in this case is a single bit."

And the autoincrement step, §6:

> "The contents of register Rn and a bit offset of [zero] are used to compute
> the bit address of the operand. The contents of Rn are then incremented by 1
> for the bit string data type or by 4 for the bit field data type."

### What p. 3.261's scaling table actually prints

The table at the top of p. 3.261, read off the plate, in full — because the
existing tree's note about it is not quite what the page says:

| Data Type | Increment/Decrement | Scaled Index |
|---|---:|---:|
| Byte | 1 | 1 |
| Halfword | 2 | 2 |
| Word | 4 | **3** |
| Doubleword | 8 | 8 |
| Packed Decimal | 1 | 1 |
| Unpacked Decimal | 2 | 2 |
| Byte Character | 1 | 1 |
| Halfword Character | 2 | 2 |
| **Bit** | **4** | **4** |
| **Bit Field** | **4** | **—** |
| **Bit String** | **1** | **—** |

with the footnote `– Not Available`.

Three things follow that a summary of this table loses:

1. **Bit Field and Bit String are different rows with different constants.**
   Bit Field increments by 4; Bit String increments by **1**. They are not
   "both 4".
2. **Bit Field has no scaled index constant at all** — the cell is the
   Not-Available dash. So does Bit String. Only the **Bit** data type (the
   `TEST1`/`SET1`/`CLR1`/`NOT1` group) has 4/4.
3. The Word/Scaled-Index cell prints **3**, which is a defect in the plate
   already recorded in `docs/v60/DATA-ACCESS-SPLIT.md`; it is adjacent to these
   rows and reading them at 600 dpi does not rehabilitate it.

Point 2 sits awkwardly against §6's "bit index modes" paragraph above, which
does describe an index register used with a bit address. **Decision, marked
here because it is not on a page:** the two are reconcilable if the dash means
"no scaling *constant* applies" rather than "the mode is unavailable" — the §6
sentence says Rx is taken as a bit displacement, i.e. scaled by one bit, which
is not a byte count and so has no entry in a table of byte counts. Nothing
prints that reconciliation, and it is recorded as a reading, not a fact.

### The "must not exceed thirty-two" constraint

All three Description blocks say "The sum of the bit offset and the bit field
length must not exceed thirty-two". Taken with §3's "not span a length of
greater than four bytes", the constraint is what makes a bit field always
reachable in one 32-bit access.

**What the pages do not settle:** *which* offset the sum is over. The offset in
the addressing model is a signed 32-bit quantity that can be far larger than
32, so "offset + length ≤ 32" cannot mean the raw offset without making almost
every bit field illegal. The consistent reading is that the offset is first
normalised — the 35-bit sum split into a byte address and a 0..7 bit-within-
byte, per §3's "the lower three bits identifying the bit offset within the
byte" — and the constraint applies to that **residual 0..7 offset**, giving
"residual + length ≤ 32" and hence a maximum length of 32 only at residual 0.
No page states that the constraint is over the residual. It is the only reading
under which both the sentence and the addressing model hold, but it is a
reading.

## Cross-check: `tools/v60x/insn_table.py`

The three encoding rows agree with the plate exactly:

```python
('EXTBF',    '01011101',      '000010{ext}', 'VIIb', '3.297'),
('INSBF',    '01011101',      '000110{ext}', 'VIIc', '3.297'),
('CMPBF',    '01011101',      '000000{ext}', 'VIIb', '3.297'),
```

Opcode byte, sub-op pattern, format letter and page citation all match
p. 3.297. The file's header note that `ext` is "2 bits, bit field extension:
00 signed, 01 unsigned, 10 right justified, 11 RESERVED" is p. 3.295 verbatim.

Three discrepancies, none in the encodings:

1. **`INSBF` is expanded to three opcodes; only two are documented.**
   `FIELD_VALUES['ext'] = [0, 1, 2]` excludes only the reserved code, so the
   row generates `5D-18`, `5D-19` **and `5D-1A`**. The Programmer's Reference
   prints two `INSBF` variants (`insbfr` `5D-18`, `insbfl` `5D-19`) and no
   third; p. 3.297's row cannot distinguish this because it prints the family,
   not the members. `5D-1A` is a hole the table currently claims.

2. **The `DATA_TYPE` comment mis-states the p. 3.261 constants for two data
   types.** It reads "bit 4, bit field 4, bit string 4"; the plate prints Bit
   Field 4 and Bit **String 1**. The same comment says the table lists "the
   unit size for all eleven data types", which is right for the databook plate
   (eleven rows) but not for the Programmer's Reference's version of the same
   table, which adds Short Real and Long Real for thirteen. The inline comment
   beside the bit-field entries — "Bit field and bit string are both 4
   (p.3.261); their LENGTH is the extension field's, not this" — carries the
   same error in its first clause and is exactly right in its second.
   (`docs/v60/ADDRESSING-MODES.md` line 164 repeats "bit string 4" from the
   same source; `docs/v60/DATA-ACCESS-SPLIT.md` has the table right.)

3. **The `(4, 4)` widths describe two operands; these instructions have
   three.** For `EXTBF` the pair is `bsrc.w` and `dst.w`, for `CMPBF`
   `bsrc.w` and `src.w`, for `INSBF` `src.w` and `bdst.w` — all four bytes, so
   `(4, 4)` is correct for the two `mod` operands in each case. The third
   operand, `blen`, is a **byte** (`blen.b.r` in all five syntax lines) and is
   carried by the Format VII `ext` field rather than by a `mod` field, so it
   has no slot in the pair. That is consistent with the file's own comment and
   is noted only because "(4, 4)" for a three-operand instruction does not
   look self-explanatory next to `CVTD.PZ`'s `(1, 2)`.

## Cross-check: `rtl/cpu/v60/s32_v60.sv`

The MAME-derived core implements `EXTBF` and `INSBF` in `S_BAM_MODE` →
`S_BAM_VAL` → `S_BF_EXT1`/`S_BF_EXTW` and `S_BF_INS1`/`S_BF_INS2`/
`S_BF_INSRD`/`S_BF_INSWR`. What it gets right, and five divergences.

Right, and worth saying because it is the non-obvious half: the length byte is
decoded exactly as p. 3.293 specifies — `bit_len <= lb[7] ? rf_rdata_a :
{24'b0, lb}`, i.e. bit 7 selects register-supplied length over immediate
length. The operand stream offsets also confirm the Format VII byte order
independently of the figure: `EXTBF` takes its `mod` at offset 2, its `ext`
byte at `fb[2 + len1]` and its `mod'` at `3 + len1` (VIIb), while `INSBF` takes
`mod` at 2, `mod'` at `2 + len1` and its `ext'` byte at `fb[2 + len1 + len2]`
(VIIc).

1. **`CMPBF` is not implemented.** The `8'h5d` dispatch handles sub-op `5'h08`,
   `5'h09`, `5'h0a`, `5'h18`, `5'h19`; sub-ops `00`/`01`/`02` fall to the
   `default` arm and raise `exc_vector <= 8'd8`, the core's catch-all for
   reserved opcodes. p. 3.297 prints `CMPBF` as a documented row of the same
   escape group, and it is the only one of the three whose flags column has
   dots.

2. **`bitdiv8` truncates toward zero where the page floors.** The function is
   commented "C-style truncating divide-by-8 of a signed bit offset (MAME
   bamoffset/8)" and computes `off[31] ? -((-off) >> 3) : (off >> 3)`. The
   residual is then taken as `bam_off[2:0]`, the low three bits of the *two's
   complement* offset. For a negative offset that is not a multiple of eight
   the two disagree: at `off = -1`, `bitdiv8` gives byte `base + 0` and residual
   `7`, where p. 3.261's 35-bit sum gives `base*8 - 1`, i.e. byte `base - 1`,
   bit 7 — a whole byte apart. The page's construction is a single 35-bit
   addition followed by a field split, which is a floor; only a non-negative
   offset makes the two the same. This is MAME's arithmetic, and MAME is not an
   authority against a printed page.

3. **A length of 32 produces zero instead of the whole word.** Both flows build
   `mask = (32'h1 << bit_len[4:0]) - 32'h1`. `bit_len[4:0]` truncates the
   length to five bits, so length 32 becomes 0 and the mask becomes 0 —
   indistinguishable from the length-0 case. §3 and §8 both give the range as 0
   **to 32** inclusive, and `EXTBF`'s and `CMPBF`'s "if the bit field length is
   zero" sentences make length 0 a distinct documented case, so the two cannot
   be allowed to alias.

4. **No Illegal Data Field exception is raised, ever.** All three Description
   blocks make "the sum of the bit offset and the bit field length must not
   exceed thirty-two" an exception condition, and §8 makes an over-32 length
   one; the RTL silently reduces the length modulo 32 and shifts. With the
   residual offset in 0..7 and a length up to 31, `S_BF_EXTW` can be asked for
   a field running past bit 31 of the single dword it fetched and will produce
   a truncated answer rather than trapping.

5. **The `ext=10` variant is implemented as a left justification, and the
   databook calls that code "right justified".** `S_BF_EXTW`'s default arm is
   `res = v << (32 - bit_len[4:0])`, which moves the extracted field to the
   *top* of the word — left justification — and `S_BF_INSWR`'s `subop[0]`
   pre-shift does the mirror for `insbfl`. That agrees with the Programmer's
   Reference, whose mnemonics for `5D-0A`/`5D-02` are `extbfl`/`cmpbfl`,
   "Extract/Compare **Left** Justified Bit Field". It disagrees with the
   databook's own p. 3.295 table, which labels `ext = 10` "right justified".
   The RTL is on the side of the Reference; the conflict is between the two
   books, not introduced by the RTL, and is recorded below rather than resolved.

One more thing the RTL does that the pages support: `S_BAM_MODE`'s `m = 1`
branch has no case for `modtop == 3'd3`, so **register-direct is rejected for a
bit-address operand** and raises. The Programmer's Reference's Addressing Modes
table marks `Rn` as `X` in the `bsrc`/`bdst` column for all three instructions,
which is p. 3.297's exception code 1. The core raises `exc_vector 8'd8` for it
rather than the Illegal Addressing Mode vector, which is a vector-selection
divergence rather than a behavioural one, and it is the same catch-all used for
unimplemented sub-opcodes. Note the contrast with the single-bit group
(`TEST1`/`SET1`/`CLR1`/`NOT1`), whose pages explicitly *do* allow `Rn`: "If the
register addressing mode is used for the base operand, the designated bit is
located within a general purpose register at the specified bit offset." Bit and
bit field differ here.

## What the pages do not settle

- **`ext = 10`: "right justified" or "left justified".** Databook p. 3.295
  prints `10  right justified`. The Programmer's Reference names the three
  `EXTBF` variants `extbfs`/`extbfz`/`extbfl` and spells `5D-0A` out as
  "Extract Left Justified Bit Field", and does the same for `CMPBF`. Both books
  were checked; neither reconciles the two. Nothing on either page says what
  the field is justified *within*, which is what would decide it.
- **`INSBF`'s use of the same two bits.** `5D-18` is `insbfr` ("Insert **Right**
  Justified") and `5D-19` is `insbfl` ("Insert **Left** Justified"), so `ext`
  = 00 and 01 here mean right and left — not "signed" and "unsigned", which is
  what p. 3.295's table calls those codes. The p. 3.295 table is therefore not
  a single decode that applies uniformly across the group, and no page says
  which instructions it does apply to.
- **Whether `5D-1A` exists.** p. 3.297 prints `INSBF` as `000110 ext`, a
  four-member family; the Reference documents two members. Whether `ext = 10`
  on `INSBF` is reserved, aliases one of the two, or is a third variant the
  Reference omits is not printed anywhere.
- **Which offset "the sum ... must not exceed thirty-two" is over** — raw or
  post-normalisation residual. Discussed above; the residual reading is the
  only self-consistent one but is not stated.
- **What happens at a length of exactly 32 with a non-zero residual offset.**
  The constraint forbids it; what the hardware does when it is violated is
  described only as "an Illegal Data Field exception will occur", with no
  statement about the destination. Compare `DIV`, whose page does say ("The
  destination will remain unchanged if an integer overflow or Zero Divide
  exception occurs" — `docs/v60/MULTIPLY-DIVIDE.md`); the bit-field pages say
  nothing equivalent, so whether `INSBF` may have partially written before
  trapping is open.
- **The exception's identity across the two books.** The Reference's Exceptions
  blocks say `Illegal Data Field`; the databook's p. 3.299 legend calls code 2
  `Illegal Data Type`. They are in the same slot of the same instruction rows
  and are presumably one exception under two names, but no page says so.
- **Its vector number.** Programmer's Reference §8's numbered list gives `#20
  Illegal Data Field` (after `#19 Illegal Addressing Mode`), which puts it at
  vector-table offset 80 and is consistent with the anchor
  `docs/v60/MULTIPLY-DIVIDE.md` established from BRKV's page ("PC ← [ Exception
  Vector 21 ]" for the Integer Arithmetic Exception at offset 84). The OCR of
  Figure 8-2 pairs its labels with offsets one row out from that, so the figure
  was not used. The figure has not been read on a plate: the Programmer's
  Reference PDF is not held in `docs/reference/`, only its OCR text layer, and
  the databook extract (pp. 3.229-3.301) does not contain §8.
- **Timing.** p. 3.297's Clocks column is blank for all three rows, as it is
  for every row in the summary (`docs/v60/INSTRUCTION-TIMING.md`).
