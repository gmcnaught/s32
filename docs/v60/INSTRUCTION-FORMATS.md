# The seven instruction formats

**Written 2026-08-27**, with `v60_fmt_pkg` and `v60_fmt_decode`.

> "The µPD70616 instruction set operation codes are described by seven
> instruction formats." — databook p. 3.293

The figure on that page gives every field's bit position. Byte order is the
same rule as the mod field's: bit 0 is the lowest address, so `op` — always at
bits 7:0 — is the **first byte of every instruction**.

| | layout, low address on the right | base bytes |
|---|---|---|
| **I** | `[mod] [0 m d reg] [op]` | 2 |
| **II** | `[mod'] [mod] [1 m m' subop] [op]` | 2 |
| **III** | `[mod] [op(7:1) m]` | **1** |
| **IV** | `[disp8/disp16] [op]` | 2 or 3 |
| **V** | `[op]` | 1 |
| **VI** | `[disp16] [subop(3) reg] [op]` | 4 |
| **VIIa** | `[ext'] [mod'] [ext] [mod] [1 m m' subop] [op]` | 2 |
| **VIIb** | `[mod'] [ext] [mod] [1 m m' subop] [op]` | 2 |
| **VIIc** | `[ext'] [mod'] [mod] [1 m m' subop] [op]` | 2 |

Three things worth stating because they are easy to get wrong:

- **Format III has a one-byte base.** Its opcode is seven bits and the `m` that
  its mod field is decoded with is bit 0 of the opcode byte itself.
- **Format I's second operand is the `reg` field**, not a second mod field.
  Only II and VII carry two.
- **The mod/ext order is always mod, ext, mod', ext'** — the three Format VII
  variants differ only in which of the two extension fields they carry, so
  four flags describe all three without an explicit order.

The extension field, quoted whole (p. 3.293):

> bit 7 (ext) = 0 → bits 6:0 (ext) are the operand length
> bit 7 (ext) = 1 → bits 6:0 (ext) contain a pointer (register ID) to the
> general purpose register containing the operand length

## What decides which format an opcode is

**Bit 15 of the base word, for the common case.** The instruction-set table
lists most opcodes as "I, II", and the figure resolves which: Format I is
`0 m d reg` and Format II is `1 m m' subop` in that same position. So the two
are told apart by the instruction itself, not by a table — one opcode byte, two
layouts, chosen by a bit.

**A table, for the rest.** Formats III–VII are named per opcode in the
instruction-set table on pp. 3.296–3.299. **That table now exists** —
`tools/v60x/insn_table.py`, generated into `rtl/cpu/v60x/v60_op_pkg.sv`, and
`v60_fmt_decode` looks the opcode up itself. See
`docs/v60/INSTRUCTION-DECODE.md` for what building it turned up. What made it a
job of its own:

1. **The printed "opcode" is a pattern, not a byte.** The bit strings contain
   placeholder fields, each of which is a small table on p. 3.295: `siz` (2
   bits, integer data type), `s` (float: short/long real), `c` (character:
   byte/halfword), `d` (string direction), `b` (branch displacement: byte or
   halfword), `ext` (bit-field extension type), and `c3c2c1c0` (condition
   code). One printed row is a family of up to sixteen byte values.
2. **It is not an 8-bit lookup.** The escape opcodes — `0x58`, `0x59`, `0x5B`,
   `0x5C`/`0x5E`, `0x5D`, `0x5F` and their `c`/`s` variants — take a *subop*
   byte, and the format depends on it. On p. 3.297 opcode `0x5D` is Format
   **VIIb** for `EXTBF` and `CMPBF` but **VIIc** for `INSBF`, distinguished
   only by the subop.
3. **The subop column does not survive being read at scan resolution.**
   Reading pp. 3.298's bit-string and character groups produced several
   duplicate subops — `ORNBS` and `XORNBS` both as `0001001d`, `NOTBS` and
   `SCH1BS` both as `0000101d`, `JSR` and `TRAP` both as `1110100-` — and two
   instructions cannot share an encoding. A transcription pass has to
   cross-check every row, not eyeball it.
4. **`docs/v60/v60_operand_access.csv` is a partial second source.** Its
   `opcodes` column is drawn from the Programmer's Reference and corroborates
   exactly: `EXTBF` = `5D-08 5D-09 5D-0A` matches `01011101` + `000010·ext`
   with the two ext bits enumerated, and `ABSF` = `5C-0A 5E-0A` matches
   `010111·s·0` + subop `00001010`. But it is **blank for many mnemonics**
   (`PUSH`, `POP`, `JMP`, `JSR`, `TRAP`, `TB`, …) and does not carry the
   format, so it can confirm rows, not supply them.
5. **Format III opcodes occupy bits 7:1**, so both byte values with bit 0 set
   and clear belong to the same instruction. Any opcode → format table has to
   be built with that in mind or half its Format III entries will look missing.

What *is* recorded from the reading done so far, as structure rather than a
half-table: the escape opcodes above, the "I, II" rule, and the format letters
seen on pp. 3.296–3.298 (Data Transfer, Integer Arithmetic, Logical and
Shift/Rotate are all "I, II" except `INC`, `DEC`, `TEST` which are III; the
floating-point group is II; the decimal group is VIIc; bit-field is VIIb except
`INSBF` which is VIIc; bit-string is VIIb; character manipulation is VIIa
except `SCHC`/`SKPC` which are VIIb; the stack group is II except `DISPOSE`
which is V; control transfer is a mix of III, IV, V, VI and II).

## Format IV's displacement width

Settled, and no longer an input. The Programmer's Reference prints `Bcc` as
"Branch on Condition (byte displacement) **6x** / (halfword displacement)
**7x**" — the same `b` bit the databook shows at p. 3.295 — and `BSR`'s syntax
as "**bsr disp16**". Those are the only two Format IV opcodes, so
`op_iv_disp_bytes()` in `v60_op_pkg` covers the format.

## Boundary

`v60_fmt_decode` consumes everything in an instruction that is *not* a mod
field: the opcode byte, the second half of the base word, and the
displacements of Formats IV and VI. It then reports which mod fields follow and
which `m` each is decoded with. `v60_idu` walks that plan — see
`docs/v60/INSTRUCTION-DECODE.md`.
