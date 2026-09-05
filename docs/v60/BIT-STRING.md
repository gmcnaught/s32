# The bit string group: MOVBS, NOTBS, ANDBS, ANDNBS, ORBS, ORNBS, XORBS, XORNBS, SCH0BS, SCH1BS

Ten instructions, twenty opcodes, one escape byte. Two things make this group
unlike everything else this tree has documented: it is the **first group whose
instructions are interruptible mid-execution**, and its operands are named by a
bit address with a length that can exceed anything an instruction word could
carry. Both are worked out below.

Sources: databook pp. 3.297-3.298 for the summary rows, p. 3.295 for the `d`
field, p. 3.293 for Format VII; Programmer's Reference §7 for the per-
instruction pages, §6 for the format and the extension byte, §3 for the data
type, the register set and the PSW, §8 for the exception PC rule. Exception
numbers are decoded with `docs/v60/INSTRUCTION-SUMMARY-LEGEND.md`.

## The twenty opcodes, and which book settles each

All ten are primary opcode **`0x5B`** (`01011011`), **Format VIIb**, Exceptions
column **`1`**. The `d` bit is the low bit of the sub-op byte.

| Mnemonic | subop | up (`d`=0) | down (`d`=1) | settled by |
|---|---|---|---|---|
| `SCH0BS` | `0000000d` | `5B-00` | `5B-01` | **both** |
| `SCH1BS` | `0000001d` | `5B-02` | `5B-03` | Reference only — p. 3.298 is wrong |
| `MOVBS` | `0000100d` | `5B-08` | `5B-09` | **both** |
| `NOTBS` | `0000101d` | `5B-0A` | `5B-0B` | **both** |
| `ANDBS` | `0001000d` | `5B-10` | `5B-11` | **both** |
| `ANDNBS` | `0001001d` | `5B-12` | `5B-13` | **both** |
| `ORBS` | `0001010d` | `5B-14` | `5B-15` | **both** |
| `ORNBS` | `0001011d` | `5B-16` | `5B-17` | Reference only — p. 3.298 is wrong |
| `XORBS` | `0001100d` | `5B-18` | `5B-19` | **both** |
| `XORNBS` | `0001101d` | `5B-1A` | `5B-1B` | Reference only — p. 3.298 is wrong |

### What p. 3.298 actually prints, read at 600 dpi

The five rows that continue onto p. 3.298 were re-rendered and cropped. Three
of the five are corrupt and **two are correct**, which is a narrower failure
than "the page is unreadable":

| row | p. 3.298 prints | should be | verdict |
|---|---|---|---|
| `ORNBS` | `0001001d` | `0001011d` | **wrong** — this is `ANDNBS`'s subop |
| `XORBS` | `0001100d` | `0001100d` | correct |
| `XORNBS` | `0001001d` | `0001101d` | **wrong** — also `ANDNBS`'s subop |
| `SCH0BS` | `0000000d` | `0000000d` | correct |
| `SCH1BS` | `0000101d` | `0000001d` | **wrong** — this is `NOTBS`'s subop |

So the plate prints `0001001d` **three times** — for `ANDNBS` on p. 3.297 and
for both `ORNBS` and `XORNBS` on p. 3.298. Three instructions cannot share one
encoding, and `ANDNBS`'s row is the one corroborated by the Reference
(`5B-12/13`), so the two on p. 3.298 are the failures. `SCH1BS` collides with
`NOTBS` the same way and loses for the same reason.

`XORBS` and `SCH0BS` are printed correctly and agree with the Reference's
`5B-18/19` and `5B-00/01`. They are double-sourced; only three rows rest on the
Reference alone.

### Why the Reference's five hold, arithmetically

Programmer's Reference §6 gives the rule that turns a printed bit pattern into
the hex the Reference uses, and it is not the obvious one:

> "All Format VII instructions use a 12-bit instruction field. The hexidecimal
> representation used for the opcode field of Format VII instructions is
> op*subop where op is the eight bit wide opcode field and subop is the five
> bit wide opcode extension field. A typical example of this format is the AND
> bit string (upward) instruction.
>
> Instruction   Opcode
> andbsu        5B-10"

The sub-op is **five bits**, and the summary prints it in an eight-bit column
with three leading zeros. Every bit-string row on both plates begins `000`,
which is that padding, and the low five bits are the number the Reference
prints. Checking the three contested rows against their Reference hex:

- `ORNBS` `5B-16` → `0x16` = `10110` → padded `0 0 0 1 0 1 1 0`, i.e.
  `0001011d`.
- `XORNBS` `5B-1A` → `0x1A` = `11010` → padded `0 0 0 1 1 0 1 0`, i.e.
  `0001101d`.
- `SCH1BS` `5B-02` → `0x02` = `00010` → padded `0 0 0 0 0 0 1 0`, i.e.
  `0000001d`.

**All three hold**, and they are exactly what `tools/v60x/insn_table.py`
already carries. The same check passes for all seven rows the plate gets right,
so the arithmetic is not being fitted to the answer. A third source agrees on
two of the three: `docs/v60/v60_operand_access.csv`, whose `opcodes` column is
drawn independently from the Reference, carries `ORNBS 5B-16 5B-17` and
`SCH1BS 5B-02 5B-03` (and `XORNBS`'s `5B-1A 5B-1B`, merged into a damaged
`XORBSU` row).

Note also that the five-bit sub-op means the group occupies `5B-00` through
`5B-1B` with no gaps in its own numbering: `00/02` searches, `08/0A` move and
negate, `10/12/14/16/18/1A` the six dyadic logicals. The three corrupt rows are
the only cells that break the pattern, which is itself a check.

### The `d` bit is p. 3.295's String Direction field

p. 3.295 prints:

```
String Direction
d   Direction
0   increment
1   decrement
```

The Reference's mnemonics confirm the mapping directly: `5B-08` is `movbsu`
"Move Bit String (**Upward**)" and `5B-09` is `movbsd` "(**Downward**)", so
`d`=0 is upward and `d`=1 is downward. §3 defines those words in terms of
addresses, which is why "increment" and "upward" are the same thing:

> "Like the character strings, the µPD70616 instruction set permits specifying
> the direction of bit string processing. The direction within a bit string in
> which addresses become larger is called the upward direction while the
> direction in which addresses become smaller is the downward direction."

The same `d` field appears on `MOVC`/`MOVCF`/`SCHC`/`SKPC` (p. 3.298), so it is
one field shared across the string groups, not a bit-string invention.

## Per-instruction

Every one of the ten prints the same `Instruction Format: Format VIIb`, the
same `Exceptions: None`, and (except the two searches) the same all-Unchanged
condition codes. What differs is the syntax line's access types and the
Operation.

### MOVBS — MOve Bit String

```
movbsu   bsrc.b.r, blen.b.r, bdst.b.w   Move Bit String (Upward)     5B-08
movbsd   bsrc.b.r, blen.b.r, bdst.b.w   Move Bit String (Downward)   5B-09
```

**Operation:** `bdst ← bsrc`

> "The source bit string is copied to the destination bit string. Specifying
> the direction of the operation allows the correct result to be computed when
> the two bit strings overlap."

Note `bdst.b.**w**` — write only. `MOVBS` and `NOTBS` are the only two whose
destination is not read.

### NOTBS — Negate Bit String

```
notbsu   bsrc.b.r, blen.b.r, bdst.b.w   Negate Bit String (Upward)   5B-0A
notbsd   bsrc.b.r, blen.b.r, bdst.b.w   Negate Bit String (Downward) 5B-0B
```

**Operation:** `bdst <- -bsrc` — printed with the OCR's hyphen for the
complement bar; the Description settles which operation it is:

> "The complement of the source bit string is stored in the destination bit
> string. Specifying the direction of the operation allows the correct result
> to be computed when bit strings overlap."

"Negate" in the mnemonic name means **logical complement**, not arithmetic
negation. A bit string is "treated as a logical data type" (§3) and has no
sign.

### The six dyadic logicals

All six take `bsrc.b.r, blen.b.r, bdst.b.**rw**` — the destination is
read-modify-write, which is what makes them non-idempotent and matters for
resumption below.

| | up | down | Operation | Description's operation |
|---|---|---|---|---|
| `ANDBS` | `5B-10` | `5B-11` | `bdst ← bsrc ∧ bdst` | "the bit-wise AND of the source and destination bit strings" |
| `ANDNBS` | `5B-12` | `5B-13` | `bdst ← ¬bsrc ∧ bdst` | "the bit-wise AND of the complemented source bit string and the destination bit string" |
| `ORBS` | `5B-14` | `5B-15` | `bdst ← bsrc ∨ bdst` | "the bit-wise OR of the source and destination bit strings" |
| `ORNBS` | `5B-16` | `5B-17` | `bdst ← ¬bsrc ∨ bdst` | "the bit-wise OR of the complemented source bit string and the destination bit string" |
| `XORBS` | `5B-18` | `5B-19` | `bdst ← bsrc ⊕ bdst` | "the bit-wise XOR of the source and destination bit strings" |
| `XORNBS` | `5B-1A` | `5B-1B` | `bdst ← ¬bsrc ⊕ bdst` | "the bit-wise XOR of the complemented source bit string and the destination bit string" |

Each Description closes with the same overlap sentence: "Specifying the
direction of the operation allows the correct result to be computed, even when
the source and destination bit strings overlap."

The `N` in `ANDNBS`/`ORNBS`/`XORNBS` complements the **source only** — the
Instruction column names them "AND/OR/XOR **Complemented** Bit String", and the
Description says "the complemented source bit string and the destination bit
string". None of them is a NAND, NOR or XNOR.

### SCH0BS, SCH1BS — Search Bit String

```
sch0bsu  bsrc.b.r, blen.b.r, dst.w.w   Search Bit String for 0 (Upward)    5B-00
sch0bsd  bsrc.b.r, blen.b.r, dst.w.w   Search Bit String for 0 (Downward)  5B-01
sch1bsu  bsrc.b.r, blen.b.r, dst.w.w   Search Bit String for 1 (Upward)    5B-02
sch1bsd  bsrc.b.r, blen.b.r, dst.w.w   Search Bit String for 1 (Downward)  5B-03
```

The destination is `dst.**w**.w` — a plain word, not a bit string. These are
the only two in the group with a fixed-length destination, which is what makes
Format VIIb's own definition fit them exactly (§6: "Format VIIb Used when the
source operand is a variable length data type and the destination operand is a
fixed length data type").

**Operation:** `dst ← bit_offset( first 0 bit )` / `dst ← bit_offset( first 1
bit )`

> "The source bit string is scanned until a zero bit is found or the bit string
> is exhausted. If found, the bit offset of the detected bit is stored in the
> destination operand and the Z flag is cleared. Otherwise, the Z flag is set
> and the bit offset of the next logical bit string after the searched bit
> string is stored in the destination operand."

(`SCH1BS`'s page is the same sentence with "a one bit".) Two things it fixes
that a summary would lose: the **not-found** case still writes the destination,
with the offset one past the end of the string; and the sense of `Z` is
inverted from the intuitive one — `Z` set means **not found**.

**Condition Codes** — the only two in the group that move a flag:

```
CY  Unchanged
OV  Unchanged
S   Unchanged
Z   Set if a zero bit is not found, otherwise cleared      (SCH0BS)
Z   Set if a one bit is not found, otherwise cleared       (SCH1BS)
```

**This contradicts the databook.** pp. 3.297-3.298 print the Flags column
**blank for all ten rows**, `SCH0BS` and `SCH1BS` included, where the Reference
gives them a live `Z`. The plate was cropped and re-read at 600 dpi to be sure;
the cells are empty. The Reference's block is explicit and prints the `*` in the
`Z` column of its own flag diagram, so the summary's row is the defect. Recorded
here rather than resolved by preference: a summary column that omits a flag is a
different kind of error from one that prints the wrong flag, and the whole point
of `Z` here is that it is the search's only report of failure.

### Condition codes, the other eight

```
CY  Unchanged
OV  Unchanged
S   Unchanged
Z   Unchanged
```

which matches pp. 3.297-3.298's blank Flags cells for those eight rows.

### Exceptions

Every one of the ten prints:

```
Exceptions
None
```

The databook's summary column prints **`1`** for all ten, which
`docs/v60/INSTRUCTION-SUMMARY-LEGEND.md` decodes as **Illegal Addressing
Mode**. The two are not in conflict — the same split appeared in
`docs/v60/BIT-FIELD.md`. The Reference's `Exceptions` block lists only
exceptions the *instruction semantics* raise, and each page carries the
addressing-mode condition separately, in its Addressing Modes table's `X`
cells. Reading `SCH1BS`'s `bsrc` column down all twenty-one rows gives
`X` for `Rn`, `O` for the next eighteen, and `X X` for `Immediate.Quick` and
`Immediate`. That is precisely p. 3.294's population:

> "Eighteen of the byte addressing modes (the exceptions are register and the
> two immediate addressing modes) discussed in the preceding section require
> two 32-bit values (often one of the values is implicitly 0) to be added in
> order to obtain the address of the operand. The µPD70616 re-interprets these
> addressing modes as suggested by the above diagram for instructions which
> operate on bit fields and bit strings."

So the summary's `1` is exactly those three `X` cells and nothing else. Unlike
the bit-field group, **no `2` (Illegal Data Type) appears** on any bit-string
row — there is no "must not exceed thirty-two" constraint here to violate.

## The addressing, and how it differs from the bit field group

The bit **address** mechanism is identical to the one
`docs/v60/BIT-FIELD.md` records from databook p. 3.261: a 32-bit byte base
zero-extended right to 35 bits, plus a **sign-extended** 32-bit bit offset,
summed to a 35-bit bit address whose upper 32 bits are the byte address and
whose lower three are the bit within the byte. Same table, same figure, same
re-interpretation of the eighteen modes (p. 3.294: "Bit addressing modes use
the same encodings as the equivalent byte addressing modes, only the assembler
format differs").

Four things differ, and all four are consequences of one root difference —
a bit field is at most 32 bits and a bit string is up to 4 gigabits.

**1. The length is unbounded where a bit field's is 32.** §3:

> "A bit string is a variable length logical data structure containing [0] to
> 2^32 - 1 bits."

§2 says the same as "ranging from [0] to 4 gigabits in length". Against the bit
field's "any length between [0] and 32 bits". There is consequently **no**
"sum of the bit offset and the bit field length must not exceed thirty-two"
sentence on any bit-string page, and no Illegal Data Field exception.

**2. The length therefore usually has to come from a register.** §6 on the
Format VII extension byte:

> "Format VII instructions contain an 8-bit extension field which is used to
> determine the length of a variable length character or bit string operand.
> The most significant bit of the extension field is used to determine whether
> the direct mode (the operand length is in the lower seven bits of the
> extension field) or the indirect mode (the operand length is contained in the
> general purpose register identified by the lower seven bits of the extension
> field) is specified."
>
> "bit 7 r  The r (register) bit determines whether the length field contains
> the operand length (direct mode) or contains a pointer to a general purpose
> register containing the operand length. This field is decoded as follows:
> r = [0] Direct mode, length field contains the operand length.
> r = 1 Indirect mode, length field contains the number of a general purpose
> register (0-31) that contains the operand length."
>
> "bits 6:0 length  The length operand (0-127) or the register ID (0-31)
> resides in this field, as determined by the r field."

So a direct-mode `blen` tops out at **127 bits**. Anything longer — which is
most of what a bit string is for — must use the indirect mode. For a bit field,
where the maximum is 32, direct mode always suffices; for a bit string it
almost never does.

**3. The unit size is 1, not 4 — and it is visible in the syntax line.**
Databook p. 3.261 gives Bit Field an increment/decrement constant of 4 and Bit
String **1** (both with `—`, Not Available, in the Scaled Index column). §6
says the same thing operationally:

> "The contents of register Rn and a bit offset of [zero] are used to compute
> the bit address of the operand. The contents of Rn are then incremented by 1
> for the bit string data type or by 4 for the bit field data type."

And the syntax lines carry it as the operand's type suffix: bit field is
`bsrc.**w**.r`, bit string is `bsrc.**b**.r`. So `[Rn+]` on a bit-string
operand steps the base register by **one byte**, where the same mode on a
bit-field operand steps it by four. Three sources, one fact.

**4. Direction is a field; a bit field has none.** The `d` bit exists because a
bit string can overlap itself and a 32-bit bit field cannot meaningfully. The
Descriptions say so in as many words on all eight of the copy/logical pages.

What is *the same*: the offset is signed 32 bits, the base is a byte address,
the `Rn`/`Immediate`/`Immediate.Quick` modes are illegal for a bit-address
operand, and the `d` and `ext` sub-op fields sit in the same two-bit and
one-bit slots of the same sub-op byte.

## Interruptibility

Every one of the ten prints this paragraph, with only the mnemonic changing.
Quoted in full from `MOVBS`:

> "To minimize the interrupt latency time, the MOVBS instruction allows the
> service of interrupts and faults following the completion of a bus cycle.
> After servicing the interrupt or correction of the fault condition,
> instruction execution continues from the point of interruption."

(`NOTBS`'s copy of it reads "the ANDBS instruction" — a typesetting slip in the
Reference; its neighbouring paragraph on the same page correctly names
`NOTBS`.)

The eight copy/logical pages then print, again with only the mnemonic changing:

> "During the execution of the MOVBS instruction, registers R28 and R27 contain
> pointers to the bytes within the source and destination bit strings to be
> processed next. Following the execution of the instruction, R28 contains the
> address of the byte containing the final bit of the source bit string while
> R27 contains the address of the byte containing the final bit of the
> destination bit string."

and the two searches, which have only one string, print:

> "Register R28 is used as a work register during the execution of this
> instruction, pointing to the current position within the bit string. After
> the completion of this instruction, R28 will point to the byte containing the
> detected bit or the byte containing the final bit in the bit string."

Three further pages complete the mechanism. §3, on the general purpose
registers:

> "In addition to the AP, FP, and SP registers, other general purpose registers
> are required by string instructions to allow the instruction to [be] resumed
> following an interrupt or exception. In this case, registers are reserved for
> use starting from R28 and allocated in a downward direction."

§3, on the PSW, bit 26:

> "bit 26 IP  The IP (instruction pending) flag indicates whether or not an
> instruction has been interrupted and should be resumed.
> IP = [0] no[,] instruction pending
> IP = 1 instruction pending"

§3, on the PC:

> "The program counter (PC) is a register which contains the memory address of
> the first byte of the instruction currently being executed."

§8, on which PC is stacked:

> "An exception during the execution of an instruction stacks the PC of the
> instruction causing the exception (Current PC)."

### What that requires of a sequencer

Put together, the architecture is *resume-in-place*, not restart:

1. **Recognition happens inside the string loop, at bus-cycle granularity.**
   "following the completion of a bus cycle" is the grain — not the instruction
   boundary, and not an arbitrary cycle either. A sequencer that samples
   interrupts only in its decode state does not implement this.

2. **The stacked PC is the address of the string instruction itself.** §8's
   Current PC rule plus §3's definition of the PC. A suspended `MOVBS` at
   `0x1000` stacks `0x1000`, not the address after it, so the return from the
   handler re-fetches and re-decodes the *same* instruction from its first
   byte. Nothing is stacked that describes how far it got.

3. **`PSW.IP` is what distinguishes the resume from a fresh start.** It is
   saved with the PSW on suspension and restored on return, and the re-decoded
   instruction must consult it. The consequence is that the interrupt-handler
   entry must set it and `RETIU`/`RETIS` must restore it, and that a handler
   which corrupts the saved PSW's bit 26 breaks the string.

4. **R28 and R27 are the resumption state, and they must be architecturally
   committed before the interrupt is taken.** Not shadow copies: the pages say
   the registers "contain pointers to the bytes ... to be processed next"
   *during* execution, which only means anything if a handler can see them and
   a resumed instruction can read them back. Note the two different
   requirements in one paragraph — during execution R28/R27 name the **next**
   byte, after completion they name the byte holding the **final** bit. An
   implementation that writes the current byte each iteration satisfies the
   second and not the first.

5. **A partially-updated destination is expected and is never undone.** No page
   says the destination is restored, and it cannot be: `bdst.b.rw` on the six
   dyadic logicals means the instruction has already consumed and overwritten
   the destination bits it has processed. Restarting `XORBS` from the top would
   XOR them a second time. That non-idempotence is the whole reason resumption
   is from R28/R27 rather than from a plain re-execute, and it is the reason
   `MOVBS`'s and the logicals' pages bother to name the registers at all.

6. **The natural — and probably only — safe suspension point is a byte
   boundary with the destination byte already written.** This follows rather
   than being printed, and is marked as a reading: a bit-string engine holds a
   partially assembled destination byte that is not yet in memory and has no
   architectural home (R28/R27 are byte *addresses*, not data). If an interrupt
   were taken with that byte live, resumption from R28/R27 alone could not
   reconstruct it. "Following the completion of a bus cycle" is exactly the
   point at which no such byte is live, so NEC's sentence and the resumption
   state are consistent with each other only at byte granularity. The searches
   are the easy case — they never write until the end and hold no such byte.

7. **The structural cost for this tree.** `v60_seq` recognises exceptions and
   interrupts only *between* instructions, which is what lets the data unit be
   a mux rather than an arbiter: at most one instruction owns the datapath and
   it owns it until it retires. Implementing this group to the letter breaks
   that invariant in a specific way — the exception-push sequence must be able
   to preempt a string loop that is itself in the middle of bus traffic, and
   the loop's private state (byte pointers, bit-within-byte positions, the
   assembled destination byte, the residual count) must either be reconstructed
   from R28/R27 and the operands or not exist across the boundary. Point 6 says
   a byte-boundary suspension makes the destination byte a non-problem; the
   pointers come back from R28/R27; **the residual count is the one piece with
   no home** (below). The mux does not have to become an arbiter, but the
   sequencer does have to acquire a second, mid-instruction exception entry
   path, and the string states have to be re-entrant with respect to it.

## What the pages do not settle

- **Where the residual length lives across an interrupt.** R28 and R27 are
  named; nothing else is. If `blen` was given in direct mode the count is an
  immediate byte inside the instruction, which cannot be decremented; if in
  indirect mode it is a general purpose register, which could be — but no page
  says it is written. §3's "registers are reserved for use starting from R28
  and allocated in a downward direction" implies R26 and below are available to
  other string instructions (the character group uses R26 as a fill character),
  and leaves open whether a bit string uses a third register for the count. The
  alternative — recomputing the residual from R28/R27 against the original
  operands — works only for the upward direction and only if the starting bit
  offsets are recoverable, which they are, since the instruction is re-decoded
  from its first byte. Neither reading is printed.
- **Whether `PSW.IP` is set by the hardware or is advisory.** §3 says what the
  flag *indicates*; no page in the material held says who writes it, whether it
  is cleared on completion, or what a resumed instruction does if it is set
  when the opcode is not a string instruction.
- **What `SCH0BS`/`SCH1BS` return for a downward search.** The Operation is
  `dst ← bit_offset( first 0 bit )` and the not-found case is "the bit offset
  of the next logical bit string after the searched bit string". For `d`=1 the
  scan runs toward lower addresses, and no page says whether the reported
  offset is measured from the string's start (the `bsrc` bit address) or from
  the scan's start, nor which end "the next logical bit string after" is at.
- **The flags on `SCH0BS`/`SCH1BS`, as a matter of two books disagreeing.**
  The Reference gives `Z`; pp. 3.297-3.298 print the Flags cell blank. The
  Reference is the more specific document and its own flag diagram carries the
  `*`, so this doc records `Z` as live — but nothing reconciles the two.
- **Three subops rest on one book.** `ORNBS`, `XORNBS` and `SCH1BS` are
  corroborated by the Reference's Opcode lines, by the five-bit arithmetic of
  §6, and (for `ORNBS` and `SCH1BS`) by `v60_operand_access.csv`, but the
  databook plate contradicts all of that. Three agreeing derivations from one
  book are still one book.
- **Overlap semantics at the bit level.** The Descriptions say choosing the
  direction "allows the correct result to be computed ... when the source and
  destination bit strings overlap", which is a statement about what the
  programmer can achieve, not a definition of what happens when the wrong
  direction is chosen. No page defines the result of an overlapping copy in the
  wrong direction.
- **Timing.** Both plates' Clocks column is blank for all ten rows, as it is for
  every row in the summary (`docs/v60/INSTRUCTION-TIMING.md`).

## Cross-check: `tools/v60x/insn_table.py`

**The encodings are right, including all three rows the plate corrupts.** The
table carries `ORNBS 0001011{d}`, `XORNBS 0001101{d}` and `SCH1BS
0000001{d}` from the Reference with a comment saying so, and the §6 five-bit
arithmetic confirms each. Nothing in the encoding rows needs touching.

One discrepancy, in the operand widths rather than the opcodes:

**All ten bit-string entries carry `(4, 4)`; the unit size of a bit string is
1.** `DATA_TYPE` has `'MOVBS': (4, 4)` through `'SCH1BS': (4, 4)`, under a
comment reading "Bit field and bit string are both 4 (p.3.261)". Databook
p. 3.261's plate prints Bit Field **4** and Bit String **1**; §6 says "The
contents of Rn are then incremented by 1 for the bit string data type or by 4
for the bit field data type"; and the Reference's syntax lines type every
bit-string operand `.b`, not `.w`. The file's own comment defines these values
as "the constant `[Rn+]` steps by and a scaled index is multiplied by", so this
is not a labelling nit — a bit-string operand in `[Rn+]` must step the base
register by one byte and this table says four. The correct pairs are:

- `MOVBS` `NOTBS` `ANDBS` `ANDNBS` `ORBS` `ORNBS` `XORBS` `XORNBS`: both
  operands are bit strings (`bsrc.b`, `bdst.b`) → `(1, 1)`.
- `SCH0BS` `SCH1BS`: `bsrc.b` and `dst.w` → `(1, 4)`.

This is the same root error `docs/v60/BIT-FIELD.md` reported in that comment's
first clause; there it was only a comment, here it has propagated into the data.
`rtl/cpu/v60/s32_v60.sv` independently disagrees with the table and agrees with
the pages: its autoincrement arm steps by `(cur_op == 8'h5b) ? 32'd1 : 32'd4`.

## Cross-check: `rtl/cpu/v60/s32_v60.sv`

### It is not interruptible, and cannot be without a structural change

The only interrupt sampling point in the core is at the top of `S_DECODE`,
under a comment that says so — "interrupts sampled at instruction boundary" —
where `nmi_seen` and `!irq_n && psw_ie` are tested before the primary opcode
dispatch. **No bit-string state tests either signal.** `S_BS_SCHRD`,
`S_BS_SCHB`, `S_BS_MOVS`, `S_BS_MOVD`, `S_BS_MOVB` and `S_BS_MOVF` loop to
completion and only then reach `S_NEXT`. A `MOVBS` of a long string therefore
holds off every maskable interrupt and NMI for its whole duration, which is the
exact latency the Reference's paragraph exists to bound.

There is also no `PSW.IP`. The PSW is assembled as `{psw_rest[31:4], f_cy,
f_ov, f_s, f_z}` and the exception path clears bits 16, 17, 18, 27 and 29 on
entry; bit 26 is never read or written anywhere in the file.

So the finding for the sequencer plan is unqualified: **implementing this group
to the page requires a mid-instruction exception entry path that does not exist
today**, plus a `PSW.IP` bit and a resume path in the `0x5B` decode. See
"What that requires of a sequencer" above for the five properties it has to
have; point 6 is the one that keeps the cost bounded.

### Seven of the ten instructions are not implemented at all

The `8'h5b` dispatch accepts exactly four sub-ops — `5'h00`, `5'h02`, `5'h08`,
`5'h09` — and everything else raises `exc_vector <= 8'd8`, the core's
reserved-opcode catch-all, with a `$display` saying "unimplemented 5B sub". So:

- **implemented:** `SCH0BSU` (`5B-00`), `SCH1BSU` (`5B-02`), `MOVBSU`
  (`5B-08`), `MOVBSD` (`5B-09`).
- **not implemented, traps:** `SCH0BSD` (`5B-01`), `SCH1BSD` (`5B-03`),
  `NOTBS` (`0A/0B`), `ANDBS` (`10/11`), `ANDNBS` (`12/13`), `ORBS` (`14/15`),
  `ORNBS` (`16/17`), `XORBS` (`18/19`), `XORNBS` (`1A/1B`).

That is seven of the ten mnemonics and sixteen of the twenty opcodes. The two
downward searches are the notable pair: `MOVBS` implements both directions
(`subop[0]` selects `str_src - 1`/`+ 1` and `bs_soff` `7`/`0` throughout), but
`S_BS_SCHB` advances unconditionally upward — so the downward searches could
not have been implemented by widening the dispatch alone, and trapping them is
the honest behaviour rather than an oversight.

The dispatch's routing is also narrower than it looks: `bam_flow <= fb[1][3] ?
2'd3 : 2'd2` distinguishes move from search by bit 3 of the sub-op, which is
correct only across `{00, 02, 08, 09}`. `ANDBS`'s `0x10` has bit 3 clear and
would route as a search if it were ever admitted.

### What it gets right

- **R28 and R27 are written.** `S_BS_SCHB` does `queue_reg_write(5'd28,
  str_src, ...)` once per bit, and `S_BS_MOVB` writes both R28 and R27. The
  final values are the byte containing the final bit, which is what the pages
  require "following the execution of the instruction". They are not the byte
  "to be processed next" mid-execution — the RTL commits the byte it is
  processing *now* — but that distinction is unobservable while the instruction
  is uninterruptible, and it becomes a real requirement the moment it is not.
- **The search results match the page.** `bit_val <= str_cnt` with `f_z <= 0`
  when the bit is found, and `bit_val <= bit_len` with `f_z <= 1` when the
  string is exhausted — the found offset and "the bit offset of the next
  logical bit string after the searched bit string", and `Z` set means not
  found, both as printed. The zero-length case short-circuits to `f_z <= 1`
  with a result of 0, which is the exhausted case with nothing scanned.
- **The extension byte is decoded per p. 3.293 / §6.** `lb[7] ? rf_rdata_a :
  {24'b0, lb}` in `S_BS_SCH1` and `S_BS_MOV1` — bit 7 selects the register-
  supplied length. Note it takes the whole byte in direct mode rather than
  masking to `lb[6:0]`, which is harmless only because bit 7 is known zero on
  that path.
- **`[Rn+]`/`[-Rn]` step by 1 for `0x5B`**, per §6, against the instruction
  table's 4.
- **Register-direct and both immediates are rejected** for a bit-address
  operand, matching the `X` cells and hence the summary's exception `1` —
  though as in the bit-field group it raises the `8'd8` catch-all rather than an
  Illegal Addressing Mode vector.

### Divergences beyond the two above

- **`bitdiv8` truncates toward zero where p. 3.261 floors.** Same function,
  same consequence, already recorded in `docs/v60/BIT-FIELD.md`: for a negative
  bit offset that is not a multiple of eight, `bam_base + bitdiv8(bam_off)`
  with the residual taken as `bam_off[2:0]` lands one byte away from the 35-bit
  sum the page constructs. `S_BS_SCH1` and `S_BS_MOV2` both use it.
- **`MOVBS` downward computes its start as `off + bit_len - 1`.** `S_BS_MOV2`
  does `o1 = subop[0] ? bs_off1 + bit_len - 1 : bs_off1`, i.e. a downward move
  starts at the *last* bit of the string and walks back. No page states this;
  it is the only reading consistent with §3's definition of downward and with
  the overlap sentence, but it is MAME's choice about where a downward string
  begins and NEC does not print it.
- **The length is used at full width in the searches and the move but the
  direct-mode maximum is 127.** Not a divergence in behaviour — `{24'b0, lb}`
  is at most 255 and `rf_rdata_a` is a full word — but §6 caps a direct-mode
  length at `0-127` (bits 6:0), and the RTL would accept a direct byte of
  `0x40..0x7F` correctly and a byte with bit 7 set as the indirect form, which
  is exactly right. Recorded only because "length 0-127" is easy to misread as
  a limit on the instruction rather than on the direct encoding.
