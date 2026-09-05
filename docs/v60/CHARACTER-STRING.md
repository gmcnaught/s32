# The character manipulation group

Eight instructions, sixteen encodings, on two escape opcodes. They are the
first thing in this tree that would make the processor issue a **string mode
bus cycle**, which is a bus state nothing here has ever driven, and the first
whose pages say the instruction can be **interrupted and resumed part way
through** — which this tree's sequencer has no mechanism for. Those two facts
are the reason this is a document rather than a table row, and they are at the
end.

Sources: the databook's instruction summary plate at p. 3.298 for the
encodings, its field tables at p. 3.295, the Programmer's Reference §7 pages
for the semantics and §2 (p. 2-7) for what a character string is, and the two
bus plates at p. 3.233 and p. 3.235. Exception numbers are decoded with
`docs/v60/INSTRUCTION-SUMMARY-LEGEND.md`.

## The encoding

p. 3.298's Character Manipulation Instructions block, read off the plate at
600 dpi. The primary byte is `0101 10c0`; the sub-op is the Format VII
`subop` field, printed zero-extended into an eight-column box (see below).

| | primary | sub-op | fmt | `.b` (c=0) | `.h` (c=1) | Reference Opcode line |
|---|---|---|---|---|---|---|
| `MOVC` | `0 1 0 1 1 0 c 0` | `0 0 0 0 1 0 0 d` | VIIa | `58-08` / `58-09` | `5A-08` / `5A-09` | all four printed |
| `MOVCF` | `0 1 0 1 1 0 c 0` | `0 0 0 0 1 0 1 d` | VIIa | `58-0A` / `58-0B` | `5A-0A` / `5A-0B` | `58*0 A`, `58- OB`, `5A»0A`, `5A»0B` |
| `MOVCS` | `0 1 0 1 1 0 0 0` (sic — see below) | `0 0 0 0 1 1 0 0` | VIIa | `58-0C` | `5A-0C` | `58«0C` / `5A-0C` |
| `CMPC` | `0 1 0 1 1 0 c 0` | `0 0 0 0 0 0 0 0` | VIIa | `58-00` | `5A-00` | `58*00` / `5A-00` |
| `CMPCF` | `0 1 0 1 1 0 c 0` | `0 0 0 0 0 0 0 1` | VIIa | `58-01` | `5A-01` | `58*0 1` / `5A-01` |
| `CMPCS` | `0 1 0 1 1 0 c 0` | `0 0 0 0 0 0 1 0` | VIIa | `58-02` | `5A-02` | `58«02` / `5A«02` |
| `SCHC` | `0 1 0 1 1 0 c 0` | `0 0 0 1 1 0 0 d` | VIIb | `58-18` / `58-19` | `5A-18` / `5A-19` | all four printed |
| `SKPC` | `0 1 0 1 1 0 c 0` | `0 0 0 1 1 0 1 d` | VIIb | `58-1A` / `58-1B` | `5A-1A` / `5A-1B` | `58-1 A`, `58«1B`, `5A-1A`, `5A-1B` |

**The `MOVCS` row is a databook misprint.** It is the only one of the eight
that prints a literal `0` in bit 1 where the other seven print `c`, and at
600 dpi that glyph is unmistakably a zero — it sits directly above `CMPC`'s
`c` in the same column and the two are plainly different characters. The
Reference's `MOVCS` page prints **two** syntax lines (`movcs.b` and
`movcs.h`) and **two** opcodes (`58«0C` and `5A-0C`), so the `c` bit is live
and the databook simply lost it. `tools/v60x/insn_table.py` already records
this in its `DISAGREEMENTS` table and takes the Reference; that is the right
call and this reading of the plate is a second, independent confirmation of
the databook side of it.

As with the floating point group, **the printed sub-op is not the second byte
in memory.** p. 3.293's Format VII diagrams put `subop` at bits 12:8 of the
base halfword with `1`, `m` and `m'` above it at 15:13, so the `subop` field
is five bits and the plate's eight columns are a zero-extension. All sixteen
sub-ops here fit in five bits. Both cores agree: `s32_v60.sv` dispatches on
`fb[1][4:0]` and takes `ea_modm` from `fb[1][6]` (= `m`) for the first operand
and `subop[5]` (= `m'`) for the second; `v60_op_pkg.sv` keys its format lookup
on `{op, 3'b000, subop}`.

## The three fields

**`c` — Character Data Type Selection** (p. 3.295):

| `c` | Character Data Type |
|---|---|
| `0` | byte |
| `1` | halfword |

So `58` is the byte-character group and `5A` the halfword-character group, and
that is exactly what the Reference's `.b`/`.h` syntax lines and opcode pairs
say. All eight instructions carry it (the `MOVCS` misprint above
notwithstanding).

**`d` — String Direction** (p. 3.295):

| `d` | Direction |
|---|---|
| `0` | increment |
| `1` | decrement |

**Only four of the eight carry it**: `MOVC`, `MOVCF`, `SCHC`, `SKPC`. The
Reference spells the two forms with a `u`/`d` suffix — `movcu`/`movcd`,
`schcu`/`schcd`, `skpcu`/`skpcd` — and names them "Upward"/"Downward" in the
Instruction column. `MOVCS`, `CMPC`, `CMPCF` and `CMPCS` have no direction bit
and no `u`/`d` form, so they process upward only.

§2 (p. 2-7) is what the direction actually means, and it is worth quoting
because it is easy to get backwards:

> Some instruction permit specifying the direction of string processing. The
> direction within a character string in which addresses become larger is
> called the upward direction while the direction in which addresses become
> smaller is the downward direction. **In all cases the ordering of characters
> within the string is in the upward (increasing addresses) direction. Only
> the direction of processing changes.**

So a downward `MOVC` moves the same bytes to the same places as an upward one;
it visits them in the opposite order. That matters for overlapping strings and
for nothing else.

**The `F` and `S` suffixes** distinguish three terminating rules, and the
Reference's title lines name them:

| | title | rule |
|---|---|---|
| `MOVC` / `CMPC` | "Move Character" / "Compare Character" | plain — the operation covers `min(slen, dlen)` characters |
| `MOVCF` / `CMPCF` | "with Filler" | the shorter string is extended with the **fill character in R26** |
| `MOVCS` / `CMPCS` | "with Stopper" | the operation stops early on the **stop character in R26** |

Both `F` and `S` therefore mean "R26 holds a character", and which one it is
depends on the suffix: a filler for `F`, a stopper for `S`. There is no
`SCHCF`/`SCHCS` — the search and skip instructions take their character as a
third operand instead.

## Format VIIa and VIIb, and where the lengths live

p. 3.293:

```
 ext' | mod' | ext | mod | 1 m m' | subop | op     Format VIIa
        mod' | ext | mod | 1 m m' | subop | op     Format VIIb
 ext' | mod' |       mod | 1 m m' | subop | op     Format VIIc
```

> The extension field is used to specify the length of a variable length data
> type and is encoded as follows:
> bit 7 (ext) = 0 → bits 6:0 (ext) are the operand length
> bit 7 (ext) = 1 → bits 6:0 (ext) contain a pointer (register ID) to the
> general purpose register containing the operand length

`MOVC`/`MOVCF`/`MOVCS`/`CMPC`/`CMPCF`/`CMPCS` are **VIIa** — two addressed
operands, each with its own length. `SCHC`/`SKPC` are **VIIb** — two addressed
operands (the string and the character) but only one length, the string's.

This is why the Reference's syntax lines have four operands where the format
has two mod fields:

```
movc.b   src.b.r, slen.b.r, dst.b.w, dlen.b.r
schc.b   src.b.r, slen.b.r, char.b.r
```

`slen` and `dlen` are the `ext`/`ext'` fields, not addressed operands. Their
columns in the Reference's Addressing Modes tables are marked `O` against `Rn`
and `-` ("Unavailable Addressing Mode") against everything else — which is
that encoding rule stated the other way: a length is either an immediate
7-bit literal or a register number, and nothing else. A literal length is
therefore at most **127** characters; a register length is a full 32 bits.

§2 (p. 2-7) adds the two facts a length calculation needs:

> Note that the number of characters and the length of a byte character string
> are the same while a halfword character has a byte length twice the number of
> characters in the string.

> the sum of the starting address and the length of a character string (in
> bytes) must be less than 2^32 − 1

And every one of the move and compare pages repeats it for the instruction:
"The source and destination length parameters indicate the number of
characters to be transferred rather than the number of bytes to be
transferred."

## The eight instructions

Notation is the Reference's: `name.size.access`. Plate flag cells are quoted
as `CY OV S Z`.

### MOVC — Move Character

```
movcu.b  src.b.r, slen.b.r, dst.b.w, dlen.b.r   Move Byte Character Upward       58-08
movcd.b  src.b.r, slen.b.r, dst.b.w, dlen.b.r   Move Byte Character Downward     58-09
movcu.h  src.h.r, slen.b.r, dst.h.w, dlen.b.r   Move Halfword Character Upward   5A-08
movcd.h  src.h.r, slen.b.r, dst.h.w, dlen.b.r   Move Halfword Character Downward 5A-09
```

Operation: `dst ← src`

> The source character string is copied to the destination character string.
> The source and destination length parameters indicate the number of
> characters to be transferred rather than the number of bytes to be
> transferred.

> Character string transfers are initiated from the head of the strings in the
> address increment mode and from the tail end of the strings in the address
> decrement mode.

> The number of characters copied is the minimum of the source and the
> destination string lengths.

> This instruction is interruptable and resumable with registers R28 and R27
> used to maintain the source and destination addresses respectively.
> Following the execution of the MOVC instruction, these registers contain the
> address of the next logical character to be transferred.

Condition Codes:

```
CY  Unchanged
OV  Unchanged
S   Unchanged
Z   Unchanged
```

Exceptions: Illegal Data Field. Plate flags blank, exceptions `1, 3` — agrees
(see "The two books' exception columns" below).

### MOVCF — Move Character with Filler

```
movcfu.b / movcfd.b / movcfu.h / movcfd.h       58-0A / 58-0B / 5A-0A / 5A-0B
src.b.r, slen.b.r, dst.b.w, dlen.b.r    (and the .h form with .h on src and dst)
```

Operation: `dst ← src`

> The source character string is copied to the destination character string.
> The shorter of the source and destination lengths determines the number of
> characters to be transferred with any additional positions in the
> destination string filled using the fill character in R26.

> Character string transfers are initiated from the head of the strings in the
> address increment mode and from the tail end of the strings in the address
> decrement mode.

> This instruction is interruptable and resumable with registers R28 and R27
> used to maintain the source and destination addresses respectively.

Condition Codes: all four Unchanged, as `MOVC`. Exceptions: Illegal Data
Field. Plate flags blank, exceptions `1, 3` — agrees.

The filler goes into the **destination** only, and only past the copied
prefix; the source is never written.

### MOVCS — Move Character with Stopper

```
movcs.b  src.b.r, slen.b.r, dst.b.w, dlen.b.r   Move Byte Character with Stopper      58-0C
movcs.h  src.h.r, slen.b.r, dst.h.w, dlen.b.r   Move Halfword Character with Stopper  5A-0C
```

Operation: `dst ← src`

> The source character string is copied to the destination string until the end
> of the source or destination string is reached or the stop character
> specified by R26 is detected in the source string.

> This instruction is interruptable and resumable with registers R28 and R27
> used to maintain the source and destination addresses respectively.

Condition Codes — **`MOVCS` is the only move that touches a flag**:

```
CY  Cleared if the stop character is found, otherwise set
OV  Unchanged
S   Unchanged
Z   Unchanged
```

Exceptions: Illegal Data Field.

Plate flags **blank** — **does not agree.** The plate gives `MOVCS` an empty
flags row, the same as `MOVC` and `MOVCF`, where the Reference's Condition
Codes block prints `*` in the CY column and a sentence for it. This is the
second thing the `MOVCS` row of p. 3.298 gets wrong, alongside the missing
`c`. **Decision: take the Reference.** Its block and its Description agree
with each other, `CMPCS`'s page carries the same CY rule in the same words,
and a stopper instruction with no way to report whether it stopped would be
useless. Note the stop character is sought **in the source string** only,
where `CMPCS` looks in either.

### CMPC — Compare Character

```
cmpc.b  src.b.r, slen.b.r, dst.b.r, dlen.b.r    Compare Byte Character String       58-00
cmpc.h  src.h.r, slen.b.r, dst.h.r, dlen.b.r    Compare Halfword Character String   5A-00
```

Operation: `flags ← dst - src`

Both operands are `.r` — nothing is written.

> The character string designated by the source operand is compared to the
> character string designated by the destination operand. The comparison
> continues until the end of either character string is reached or there is a
> disagreement between the string contents.

> The S flag reflects the lexical ordering of the character strings. If the
> compare instruction terminates with different characters, then the S flag
> reflects the unsigned comparison of the two strings. If the compare
> instruction terminates by reaching the \[end\] of either string, the S flag
> will indicate the shorter string. The Z flag will be set if and only if the
> character strings are of identical length and contents.

("reaching the of either string" in the text layer; the word is plainly
"end", and `CMPCS`'s page prints the same sentence with it.)

> During the comparison operation, registers R28 and R27 are used to maintain
> the source and destination addresses respectively. Following the execution
> of the CMPC instruction, these registers contain the addresses of the
> characters immediately following the the strings if the end of either string
> was reached. Otherwise, R28 and R27 will contain the addresses of the
> characters in disagreement.

Condition Codes:

```
CY  Unchanged
OV  Unchanged
S   Set if src > dst, otherwise cleared
Z   Set if src = dst, otherwise cleared
```

Exceptions: Illegal Data Field. Plate `— — • •` / `1, 3` — agrees.

The two `S` statements are the same one at different resolutions: "src > dst"
is the unsigned comparison at the first differing character, and, when no
character differs, the longer string is the greater. `Z` is total equality of
length *and* content.

### CMPCF — Compare Character with Filler

```
cmpcf.b / cmpcf.h    src.{b,h}.r, slen.b.r, dst.{b,h}.r, dlen.b.r    58-01 / 5A-01
```

Operation: `flags ← dst - src`

> The comparison operation continues until a disagreement between the string
> contents is detected or both strings are exhausted. If the source and
> destination character strings are not of equal length, the shorter string
> will be automatically extended using the fill character in R26 to the longer
> string length.

Condition Codes and Exceptions identical to `CMPC`. Plate `— — • •` / `1, 3`
— agrees.

The filler makes the comparison run over `max(slen, dlen)` characters rather
than `min`, and it is a *notional* extension — the page does not say the
shorter string is written, and both operands are `.r`.

### CMPCS — Compare Character with Stopper

```
cmpcs.b / cmpcs.h    src.{b,h}.r, slen.b.r, dst.{b,h}.r, dlen.b.r    58-02 / 5A-02
```

Operation: `flags ← dst - src`

> The comparison operation continues until a disagreement between the string
> contents is detected a string is exhausted or the stop character in R26 is
> detected in either string. Following the execution of this instruction, the
> S, Z, and CY flags are updated to reflect the relationship between the
> character strings.

> If the compare instruction terminates by reaching the end of either string
> without detecting the stop character, the S flag will indicate the shorter
> string. The Z flag will be set if and only if the character strings are of
> identical length and content. **The CY flag is cleared if the stop character
> is detected in either string, otherwise it is set.**

Condition Codes:

```
CY  Set if the compare operation terminates without detecting the stop
    character in either string, otherwise cleared
OV  Unchanged
S   Set if src > dst, otherwise cleared
Z   Set if src = dst, otherwise cleared
```

Exceptions: Illegal Data Field.

Plate `— — • •` — **does not agree**: the plate prints a dash in the CY
column. Verified at maximum zoom against `CMPC` and `CMPCF` immediately above,
whose CY cells are the same glyph — so this is not a faint dot. The Reference
states CY twice in two different blocks on the same page, and the wording
matches `MOVCS`'s. **Decision: take the Reference.** That makes the plate
wrong about CY on **both** stopper instructions, which is a consistent
omission rather than two independent ones.

### SCHC — Search Character

```
schcu.b  src.b.r, slen.b.r, char.b.r    Search Byte Character Upward         58-18
schcd.b  src.b.r, slen.b.r, char.b.r    Search Byte Character Downward       58-19
schcu.h  src.h.r, slen.b.r, char.h.r    Search Halfword Character Upward     5A-18
schcd.h  src.h.r, slen.b.r, char.h.r    Search Halfword Character Downward   5A-19
```

Operation:

```
R28 ← search character byte address
R27 ← search character offset
```

> The character string is searched for the designated character until either
> the character is found or all characters in the string have been examined.
> Character string searches are initiated from the head of the string in the
> address increment mode and from the tail in the address decrement mode.

> This instruction is interruptable and resumable with register R28 used to
> maintain the character address being scanned. Following the execution of the
> SCHC instruction, R28 contains the address of the first character meeting
> the search criteria or the next character after the source string if no
> matching character was found. Register R27 contains the number of characters
> (character offset) from the start position to the search end position.

Condition Codes:

```
CY  Unchanged
OV  Unchanged
S   Unchanged
Z   Set if the search character is found, otherwise cleared
```

Exceptions: Illegal Data Field. Plate `— — — •` / `1, 3` — agrees.

Note the two result registers hold different *kinds* of thing: R28 is a **byte
address** and R27 is a **character offset**, so for a halfword search they
differ by a factor of two plus the base.

### SKPC — Skip Character

```
skpcu.b / skpcd.b / skpcu.h / skpcd.h    src.{b,h}.r, slen.b.r, char.{b,h}.r
                                          58-1A / 58-1B / 5A-1A / 5A-1B
```

Operation:

```
R28 ← skipped character byte address
R27 ← skipped character offset
```

> The source character string is scanned until a position different from the
> designated character is reached or the string is exhausted. Character string
> scanning is initiated from the head of the string in the address increment
> mode and from the tail in the address decrement mode.

> This instruction is interruptable and resumable with register R28 used to
> maintain the character address being scanned. Following the execution of the
> SKPC instruction, R28 contains the address of the first character not
> meeeting the skip criteria or the next character after the source string if
> the skip criteria was continuously satisfied.

Condition Codes:

```
CY  Unchanged
OV  Unchanged
S   Unchanged
Z   Set if the skip character is found, otherwise cleared
```

Exceptions: Illegal Data Field. Plate `— — — •` / `1, 3` — agrees.

`SKPC` is `SCHC`'s complement: it advances while the character **matches** and
stops on the first that does not. The `Z` sentence is copied from `SCHC`'s
page verbatim ("Set if the skip character is found") and reads against the
Description, which stops when a character is *not* the skip character. The
page does not resolve which event `Z` reports; see "What the pages do not
settle".

## The two books' exception columns

The plate prints `1, 3` on all eight rows and nothing else. Decoded with
`INSTRUCTION-SUMMARY-LEGEND.md`: **1 = Illegal Addressing Mode**, **3 =
Reserved Addressing Mode**. The Reference's Exceptions block on all eight
pages names exactly one thing: **Illegal Data Field**, which the legend at
p. 3.299 does not list at all.

These are complementary rather than contradictory. The Reference puts the
addressing-mode exceptions in its Addressing Modes table instead of its
Exceptions block — the legend under each of these eight tables is `X Illegal
Addressing Mode` / `- Unavailable Addressing Mode` — so the plate's `1` is the
`X` cells said another way. The plate's `3` has no marker on these pages
(unlike the floating point group, which uses `Δ Reserved Addressing Mode`);
the natural reading is that a reserved *mode encoding* faults wherever it
appears, independently of the per-instruction table, but no page says that.
The plate's column simply has no code for Illegal Data Field.

The Reference's §8 does define it, and gives it a vector:

> **Illegal Data Field** — An illegal data field exception occurs when an
> error is detected in the size of an operand. For example, the bit field data
> type can range in length from \[0\] to 32 bits. Should a length greater than
> 32 bits be specified, an illegal data field exception will occur.

It is **#20** in the Instruction Exceptions list (`#16 Reserved Opcode`,
`#17 Privileged Instruction`, `#18 Reserved Addressing Mode`, `#19 Illegal
Addressing Mode`, `#20 Illegal Data Field`), at vector-table offset **+80**,
which is 4 × 20 — the same arithmetic `docs/v60/MULTIPLY-DIVIDE.md` used to
place the Integer Arithmetic Exception at 84. So the plate's `1` and `3` are
vectors 19 and 18, and the exception the Reference actually names for this
group is vector 20.

**What triggers it for a character string is not stated.** The §8 example is a
bit field wider than 32; the only size restriction §2 places on a character
string is that "the sum of the starting address and the length ... must be
less than 2^32 − 1". Whether that is what raises #20 here, or whether it is
something about the extension field's encoding, no page says.

## String mode bus cycles

This is the part that is directly actionable, because
`rtl/cpu/v60x/v60_bus_pkg.sv` can already name every code below and nothing in
the tree ever asks for one.

### What a string mode bus cycle is

p. 3.233, in the `ST2-ST0 [Bus Status]` pin description:

> Two separate bus access modes are supported by the µPD70616. **String mode
> bus accesses occur during bus cycles for variable length data types. All
> other bus cycles are single mode.**

and the footnote under its table:

> String Mode: variable length data type (character string and bit string) bus
> cycles
> Single Mode: all other data access cycles

and its own entry in the pin list:

> **String Mode Memory Access** ... (String Mode)
> The processor is performing a character or bit string data access in the
> memory address space.

The mode is carried in the bus status, `{MRQ*, ST2, ST1, ST0}`. Two of the
sixteen codes are string mode and the other fourteen are not:

| MRQ* ST2 ST1 ST0 | Bus Status | mode |
|---|---|---|
| `0 0 0 1` | String Mode Data Access | **String** |
| `1 0 0 1` | String Mode I/O Access | **String** |
| `0 0 1 1` | Single Mode Data Access | Single |
| `0 0 1 0` | Short Path Data Access | Single |
| `0 1 0 0` | System Base Table Access | Single |
| `0 1 0 1` | Translation Table Access | Single |
| `0 1 1 0` | Demand Mode Instruction Fetch | — |
| `0 1 1 1` | Instruction Prefetch | — |
| `1 0 1 1` | Single Mode I/O Access | Single |
| `1 1 0 0` | Machine Fault Acknowledge | — |
| `1 1 0 1` | Halt Acknowledge | — |
| `1 1 1 0` | Interrupt Acknowledge | Single |
| `0 0 0 0`, `1 0 0 0`, `1 0 1 0`, `1 1 1 1` | Reserved for Future Use | |

`MRQ*` is active low, so `0` is memory and `1` is I/O; the string-mode pair is
the same code in both spaces.

### When it is issued

Every data bus cycle an instruction in **this** group makes to a character
string operand, and every cycle the bit string group makes to a bit string
operand. That is the whole rule — "bus cycles for variable length data types"
— and it is a property of the *operand*, not of the instruction. Which means,
read strictly:

- `MOVC`'s reads of `src` and writes to `dst` are string mode.
- `SCHC`'s reads of `src` are string mode; but its `char` operand is a fixed
  length byte or halfword, so a memory fetch of `char` is a **single mode**
  cycle in the middle of the same instruction.
- `MOVCF`'s filler writes come from R26 into the destination *string*, so they
  are string mode; the R26 read is not a bus cycle at all.
- The instruction fetch and any operand-address computation (a `[disp[Rn]]`
  indirection, say) are ordinary cycles with their own statuses.

So an instruction is not "a string instruction" as far as the bus is
concerned — individual cycles are string mode or not, and one instruction
emits both kinds.

### What DL1-DL0 and FAS* say during one

p. 3.235, `DL1-DL0 [Data Length]`:

> DL1-DL0 are three-state outputs and are used together with FAS* and the bus
> status outputs to determine operand size for fixed length data or **the
> position and direction for variable length data types**. During instruction
> fetch accesses, DL1-DL0 are driven low.

The same two pins therefore carry two different tables, and which one applies
comes from the bus status:

| DL1 DL0 | single mode: Data Length | string mode: String Direction |
|---|---|---|
| `0 0` | Byte (1 byte) | — |
| `0 1` | Halfword (2 bytes) | — |
| `1 0` | Word (4 bytes) | Address Increment |
| `1 1` | Reserved | Address Decrement |

`FAS*` [First Data Access Status] splits each direction into its first cycle
and its continuation:

> FAS* is a three-state output indicating the type of data bus cycle. FAS* is
> asserted during the first bus cycle of any multiple bus cycle data transfer.
> FAS* is negated in any subsequent bus cycle.
>
> FAS* is undefined during an instruction fetch bus access.

The combined table at the foot of p. 3.235 (`FAS = 0 : First bus cycle`,
`FAS = 1 : Subsequent bus cycles`):

| Mode | meaning | DL1 | DL0 | FAS* | MRQ*,ST2-ST0 |
|---|---|---|---|---|---|
| Single | Byte | 0 | 0 | 0 | `0000 0010 0011 0100 0101 1000 1011 1110` |
| Single | Halfword | 0 | 1 | 0/1 | " |
| Single | Word | 1 | 0 | 0/1 | " |
| Single | Reserved | 1 | 1 | 0/1 | " |
| **String** | **Start Increment** | **1** | **0** | **0** | `0001`, `1001` |
| **String** | **Start Decrement** | **1** | **1** | **0** | `0001`, `1001` |
| **String** | **Address Increment** | **1** | **0** | **1** | `0001`, `1001` |
| **String** | **Address Decrement** | **1** | **1** | **1** | `0001`, `1001` |

(The plate's column header misprints the second column as `DL1` where it must
be `DL0`; the four single-mode rows `00 01 10 11` against Byte/Halfword/Word/
Reserved match the DL1/DL0 table above it exactly, which settles it.)

Four things fall out of that table:

1. **DL1 is always 1 in string mode.** The pins carry no size information at
   all during a string cycle, so an external system cannot tell a byte
   character string from a halfword one from DL — it has to use `UBE*` and
   `A0` (p. 3.236). The `c` bit never reaches these two pins.

2. **DL0 is the `d` bit.** `d = 0` (increment) → `DL0 = 0`; `d = 1`
   (decrement) → `DL0 = 1`. The sub-op's direction bit becomes a bus pin, one
   for one, for the four instructions that carry it. The four that do not
   (`MOVCS`, `CMPC`, `CMPCF`, `CMPCS`) can only issue Increment cycles.

3. **FAS\* marks the head of the string, not the head of an aligned
   transfer.** In single mode FAS* distinguishes the first physical 16-bit
   cycle of a misaligned word from its continuation, which is why the Byte row
   is `FAS = 0` only — a byte access is never split. In string mode it
   distinguishes the *first character of the string* from every later one, so
   a `MOVC` of 100 characters issues one Start Increment and 99 Address
   Increments per operand. That is a longer-lived meaning than the single-mode
   one, and it is the pin that tells a memory system a burst has begun.

4. **`Start Increment`/`Start Decrement` is exactly the "initiated from the
   head / from the tail end" sentence** printed on `MOVC`, `MOVCF`, `SCHC` and
   `SKPC`. The bus plate and the instruction pages are describing the same
   event from the two ends.

### Why emitting the right status is not cosmetic

`rtl/cpu/v60x/v60_seq.sv` already keys the bus-error exception code off the
bus status, and the string codes are distinct from the fixed-length ones:

```
0301 string data write     0311 string data read
0303 fixed length write    0313 fixed length read
0309 string I/O write      0319 string I/O read
030B fixed length I/O write  031B fixed length I/O
```

So a bus error on a `MOVC` element read must report `0311`, not `0313`. A core
that issues every cycle as Single Mode Data Access reports the wrong exception
code for every string fault, and there is no way to recover the right one
afterwards.

## Interruptibility — the structural finding

> **Correction, added after `docs/v60/DECIMAL.md` counted the corpus.** This
> section originally read the group as interruptible. Only three of the eight
> are. The sentence "to minimize the interrupt latency time, the ... instruction
> allows the service of interrupts and faults following the completion of a bus
> cycle" appears on **exactly thirteen** pages of the Programmer's Reference,
> and they are the ten bit string pages plus **`CMPC`, `CMPCF` and `CMPCS`** —
> the three character *comparisons*. `MOVC`, `MOVCF`, `MOVCS`, `SCHC` and
> `SKPC` do not carry it.
>
> Verified by counting the whole text: thirteen occurrences, owned by ANDBS,
> ANDNBS, CMPC, CMPCF, CMPCS, MOVBS, NOTBS, ORBS, ORNBS, SCH0BS, SCH1BS, XORBS,
> XORNBS.
>
> Why the moves and searches are omitted is **not explained on any page held
> here**, and it is odd: `MOVC` is as variable-length as `CMPC` and has the same
> reason to want a bounded interrupt latency. Two readings are open — NEC
> documented it only where it mattered most, or the moves genuinely run to
> completion — and nothing distinguishes them. Recorded rather than guessed.
>
> The consequence for this tree is a smaller one than this section first
> claimed: thirteen instructions need the mid-instruction exception entry path
> described in `docs/v60/BIT-STRING.md`, not eighteen.


**Yes, and in two different strengths, both stated on the pages.**

The three `MOV` instructions and the two scan instructions say:

> This instruction is interruptable and resumable with registers R28 and R27
> used to maintain the source and destination addresses respectively.
> Following the execution of the MOVC instruction, these registers contain the
> address of the next logical character to be transferred.

(`SCHC`/`SKPC`: "with register R28 used to maintain the character address
being scanned".)

The three `CMP` instructions say it more precisely, and this is the sentence
that matters most for the sequencer:

> To minimize the interrupt latency time, the CMPC instruction allows the
> service of **interrupts and faults following the completion of a bus cycle**.
> After servicing the interrupt or correction of the fault condition,
> **instruction execution continues from the point of interruption**.

Three consequences, stated as precisely as the pages allow:

1. **The recognition point is a bus-cycle boundary, not an instruction
   boundary.** An interrupt or a fault taken between two element accesses of a
   `CMPC` is architectural, not an implementation liberty.

2. **R28 and R27 are architectural state during execution, not just results.**
   The `CMPC` page says "During the comparison operation, registers R28 and
   R27 **are used to maintain** the source and destination addresses"; the
   bit-string group's `MOVBS` page says the same thing in the same words
   ("During the execution of the MOVBS instruction, registers R28 and R27
   contain pointers to the bytes within the source and destination bit strings
   to be processed next"). They are the resume state. A design that keeps the
   working pointers in hidden registers and only publishes R28/R27 at
   termination cannot resume, because after an interrupt those registers hold
   whatever the *previous* instruction left.

3. **This group is interruptible in exactly the way the bit string group is.**
   The lead's question was whether they match: they do, and `MOVBS` carries
   the identical "To minimize the interrupt latency time ..." paragraph. There
   is one wording difference — the character `MOV`s and the scans add
   "interruptable and resumable", which the `CMP`s do not — but the `CMP`s'
   own paragraph says "instruction execution continues from the point of
   interruption", which is resumability under another name.

**What the pages do not say** is how the resume actually works: whether the
saved PC points at the instruction (so it re-executes and re-reads R28/R27 as
its starting point) or past it, whether the length operands are also updated
as work is consumed, and what happens if a handler modifies R28/R27. Nothing
in either book that this tree holds addresses that, and it is the piece a
sequencer implementation needs. See below.

## Cross-check: `tools/v60x/insn_table.py`

Read only; nothing changed. The eight rows are at lines 173-180, the
`DISAGREEMENTS` note at 267-269, the data types at 367-369.

**Everything in this group agrees with the plate, and the one place it
deliberately does not is already documented.**

- All eight opcode patterns `010110{c}0` and all eight sub-op patterns match
  the plate bit for bit, including the `{d}` placement on `MOVC`, `MOVCF`,
  `SCHC` and `SKPC` and its absence on `MOVCS`, `CMPC`, `CMPCF` and `CMPCS`.
- Formats: VIIa for the six move/compare, VIIb for `SCHC`/`SKPC` — matches the
  plate's Instruction Format column exactly.
- `MOVCS` is given `'010110{c}0'` where the plate prints `01011000`, with the
  `DISAGREEMENTS` entry "the databook prints only the c=0 form (58); the
  Programmer's Reference gives 58-0C and 5A-0C, so the c bit is live. Taken
  from the Reference." That is correct and this reading confirms it.
- `DATA_TYPE` gives all eight `('c', 'c')`. The table's own contract is the
  data type's **unit size** for the two *format* operands, and for VIIa those
  are `src` and `dst` (both `c`-sized) and for VIIb `src` and `char` (also both
  `c`-sized: `schc.b ... char.b.r`, `schc.h ... char.h.r`). Correct on both
  counts. `slen`/`dlen` are extension fields and the file says so in the
  comment above the table.

**No discrepancy to report against this file for this group.**

One thing worth recording rather than fixing: the plate's `Exceptions` column
for all eight is `1, 3`, and the legend has no code for the exception the
Reference actually names (Illegal Data Field, vector 20). Anything generated
from the summary column alone will under-report these instructions' faults.

## Cross-check: `rtl/cpu/v60/s32_v60.sv`

Read only. Decode at 1655-1682, states `S_STR_OP1`/`S_STR_OP2`/`S_STR_RD`/
`S_STR_WR`/`S_STR_FILL` at 2985-3235, bus adapter `s32_v60_bus.sv`.

### It does not issue string mode bus cycles. At all.

`s32_v60_bus.sv` declares the whole status table and then drives two of it:

```
localparam [2:0] ST_STRING_DATA = 3'b001;   //   0    string mode data access
...
assign st = bcy ? (c_fetch ? ST_PREFETCH : ST_SINGLE_DATA) : ST_RESERVED_0;
```

`ST_STRING_DATA` is declared and **never referenced again**. Every data access
the core makes — including every element read and write of `MOVC`, `CMPC`,
`SCHC` and `SKPC` — goes out as `ST_SINGLE_DATA` (`011`). The file says so and
gives its reason:

> Data accesses are single mode: this adapter is only ever handed one operand
> at a time, and string-mode accesses are an architectural feature the core
> does not implement (the audit records string instructions as
> non-interruptible and non-resumable, driven from internal registers).

The core also has no `DL1-DL0` and no `FAS*` outputs at all — neither pin
appears in `s32_v60_bus.sv`. So the direction and start-of-string information
the databook puts on the bus has nowhere to go, and `Start Increment` versus
`Address Increment` is not a distinction this core can make.

By contrast the clean-room `rtl/cpu/v60x/v60_bus_pkg.sv` already carries all
sixteen bus statuses from p. 3.233, `bst_is_string()`, both DL tables as
`dl_single_e` and `dl_string_e` with the FAS* note, and `v60_seq.sv` maps
`BST_MEM_STRING`/`BST_IO_STRING` to their own bus-error codes. **The
vocabulary is complete and nothing speaks it.**

### It samples interrupts only between instructions

`S_DECODE`, line 1394, comment and all:

```
// interrupts sampled at instruction boundary
if (nmi_seen) begin ... end
else if (!irq_n && psw_ie) begin ... end
```

There is no interrupt or fault test anywhere in `S_STR_RD`, `S_STR_WR` or
`S_STR_FILL`. A 64 KB `MOVC` is atomic in this core. That is the divergence
from the "following the completion of a bus cycle" sentence quoted above, and
it is a latency property as well as a correctness one.

### R28/R27 are results, not working state

The loop runs on internal `str_src`, `str_dst`, `str_cnt`, `str_len1`,
`str_len2`, and R28/R27 are written by `queue_reg_write(5'd28, ...)` /
`queue_reg_write(5'd27, ...)` **only at the termination branches** — the
`str_cnt == 0` exhaustion path, the first-difference path, the stop-character
path. So even if an interrupt were taken mid-loop, there would be no
architectural state to resume from: the Reference's "these registers contain
the address of the next logical character to be transferred" is not
maintained during execution. The two divergences are the same divergence.

### CMPC's R28/R27 hold indices, not addresses

The core writes `str_len1 + (cmin << shf)` into R28 and `str_len2 + (cmin <<
shf)` into R27, with the comment "MAME opCMPSTR tail". The Reference says
those registers "contain the addresses of the characters immediately following
the the strings" or "the addresses of the characters in disagreement" — that
is `src + i*step` and `dst + i*step`, not `slen + i*step`. The core's value is
a length plus a scaled index and does not involve the operand addresses at
all. `SCHC`/`SKPC` are the other way round and match the page: they write
`str_src` (a real address) into R28 and an index into R27, which is what
"R28 ← search character byte address / R27 ← search character offset" asks
for.

### SCHC/SKPC's Z is inverted

The core says so itself, at `S_STR_RD`:

> V60 SEARCH uses the opposite Z sense from the published manual: Z=1 only when
> the whole range is exhausted.

The published manual is the `SCHC` page quoted above: "Z Set if the search
character is found, otherwise cleared". MAME sets `Z` on *not* found. This is
a flat contradiction between an emulator and the page, recorded in the core
rather than resolved, and `docs/v60/MULTIPLY-DIVIDE.md`'s precedent is that
this tree follows the documents.

### CMPCS clears CY only when the elements are also equal

```
else if (subop[4:0] == 5'h02 && (a == fb26 || b == fb26)) begin
    f_cy <= 1'b0; ...
```

That branch is reached only after `if (a != b)` has fallen through, so a
`CMPCS` whose two characters *differ* and one of which *is* the stop character
terminates on the difference with `CY` left set. The Reference says "The CY
flag is cleared if the stop character is detected in either string, otherwise
it is set", with no equality condition. The core does initialise `f_cy <= 1'b1`
at `S_STR_OP2` for sub-op `02`, which is the "otherwise it is set" half done
correctly.

### MOVCS looks for the stopper in the copied element

```
if (subop[4:0] == 5'h0c && elem == fb26) movc_finish(cmin - str_cnt);
```

`elem` is `alu_r`, the value just read from the source and written to the
destination, so this is the source character — matching the page's "the stop
character specified by R26 is detected **in the source string**". It also
means the stop character is copied *before* the instruction ends; the page
does not say whether it should be, so this is agreement on the tested part and
silence on the rest.

### Where it agrees

- `MOVCS` exists in both `c` forms: the decode is `8'h58, 8'h5a` with sub-op
  `5'h0c` accepted in both, which is the Reference's reading against the
  databook plate. The clean-room `v60_op_pkg.sv` lists all sixteen encodings
  including `5A0C`.
- The `c` bit selects the element size everywhere it should: `dbus_size <=
  cur_op[1] ? 2'd1 : 2'd0` for every element access, and `ea_dim <= fb[0][1]`
  so that autoincrement and scaled-index addressing step by the character size
  rather than by four.
- `CMPCS` starts with `CY` set, `MOVCF`/`CMPCF` use `r[26]` as the filler and
  `MOVCS`/`CMPCS` use it as the stopper — R26's two roles are exactly the two
  the `F` and `S` suffixes name.
- `CMPCF` fills **before** the compare and `MOVCF` fills **after** the copy,
  which is what the two pages describe (the compare "continues until ... both
  strings are exhausted" over the extended length; the move fills "additional
  positions in the destination string").

## What the pages do not settle

1. **How a resume actually works.** The pages say the instructions are
   resumable and that R28/R27 carry the addresses, but not whether the
   exception frame's return PC points at the instruction or past it, whether
   the length operands are consumed as work proceeds (they are named in the
   extension field, which is in the instruction stream and cannot be updated),
   or how the remaining count is reconstructed on resume. For `MOVC` the
   copied count is `min(slen, dlen)` and the pages give no register that holds
   the residue. This is the single largest gap and a sequencer cannot be
   written without deciding it.

2. **`SKPC`'s `Z`.** "Set if the skip character is found, otherwise cleared" is
   copied from `SCHC`'s page, but `SKPC` terminates when a character is *not*
   the skip character. Whether `Z` means "the string was entirely the skip
   character" (exhausted) or "a skip character was seen at all" (true for any
   non-empty run) is not resolvable from the page, and the two readings differ
   on every input that starts with a non-matching character.

3. **What raises Illegal Data Field here.** §8's definition is generic ("an
   error is detected in the size of an operand") and its example is a bit
   field wider than 32. §2's only character-string size restriction is the
   `address + byte length < 2^32 − 1` rule. No page connects the two.

4. **Whether a zero length is legal**, and what the flags are if it is. `CMPC`
   of two empty strings is "identical length and contents", so `Z` should set,
   but no page says a zero-length string is a valid operand rather than an
   Illegal Data Field.

5. **Overlapping source and destination.** The bit string group's `MOVBS` page
   explicitly discusses overlap ("the correct result to be computed when the
   two bit strings overlap"); no page in *this* group mentions it, even though
   the direction bit exists precisely to make overlapping copies work. Whether
   a downward `MOVC` is guaranteed correct for a forward-overlapping copy is
   implied by the direction machinery and stated nowhere.

6. **Whether the `char` operand of `SCHC`/`SKPC` is fetched once or per
   element**, which decides whether a memory-resident search character
   produces one single-mode cycle or `slen` of them interleaved with the
   string-mode ones.

7. **What DL1-DL0 and FAS\* do on the non-string cycles of a string
   instruction** — the `char` fetch, an address indirection. The pages give
   the rule per cycle ("bus cycles for variable length data types"), which
   implies single mode with a normal data length, but no page walks an example
   instruction's cycle sequence.

8. **Timing**, as everywhere: the plate's Clocks column is blank on all eight
   rows (`docs/v60/INSTRUCTION-TIMING.md`).
