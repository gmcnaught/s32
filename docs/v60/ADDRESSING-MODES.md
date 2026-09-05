# V60 addressing modes: the mod-field encoding

**Recovered 2026-08-27.** The source is one figure — *mod Field – Addressing
Mode Encoding* — printed twice:

- `NEC_uPD70616_V60_DataBook_1986.pdf` **databook p. 3.294** (PDF p. 66 of the
  73-page extract), §5 Instruction Set.
- `NEC_V60pgmRef_djvu.txt` — the µPD70616 Programmer's Reference Manual,
  **Appendix C**, and again in §6 at **p. 6-13**. Same figure, same cells.

Both are held under `docs/reference/` (gitignored, not redistributed).

Printing the same figure twice is not two sources. Everything below that goes
beyond transcription is argued from the figure's own internal structure, and
the three cells where the figure contradicts itself are named.

## The field

> "Instructions formats have a 1 to 9 byte mod (modifier) field to specify
> along with the m field the addressing mode for each operand reference within
> an instruction." — p. 3.294

> "The minimum encoding of any of the fourteen basic addressing modes requires
> nine bits. It is convenient to divide these nine bits into three fields, mod,
> Rn and m. The m and mod fields together define the addressing mode." — p. 6-13

So the mode is a **4-bit** decision: three bits of the first mod byte plus the
`m` bit, which lives in the instruction word (Format I bit 13, Format II bits
13/12 — p. 3.293), not in the mod field. Bits 4:0 of the byte are Rn.

**Byte order.** The figure's ruler runs 71 … 7 … 0 with the mode byte at bits
7:0, and the instruction-format diagrams put `op` at bits 7:0 likewise. Bit 0
is the lowest address, so the mod field arrives in this order:

    [index byte] [mode byte] [disp2 / val / addr] [disp1]

The index byte comes **first** — `[Rn](Rx)` is printed `011←Rn` at bits 15:8
over `110←Rx` at bits 7:0 — and for a double displacement the *inner*
displacement (disp2) precedes the outer one (disp1).

## The slot map

Seven register-form codes × two values of `m`, plus `111` reserved for the
forms that need no register:

| mod | m = 0 | m = 1 |
|:---:|---|---|
| `000` | `disp.8[Rn]` | `disp1.8[disp2.8[Rn]]` |
| `001` | `disp.16[Rn]` | `disp1.16[disp2.16[Rn]]` |
| `010` | `disp.32[Rn]` | `disp1.32[disp2.32[Rn]]` |
| `011` | `[Rn]` | `Rn` |
| `100` | `[disp.8[Rn]]` | `[Rn+]` |
| `101` | `[disp.16[Rn]]` | `[-Rn]` |
| `110` | `[disp.32[Rn]]` | index byte: `(Rx)` |
| `111` | see below | see below |

The `111` group is self-describing; decoding it without consulting `m` is a
decision, not a transcription — see "The one thing here that is not from a
page" below:

| byte | mode | extra bytes |
|---|---|---|
| `1110vvvv` | `immed.4`, value in bits 3:0 | 0 |
| `11110000` | `disp.8[PC]` | 1 |
| `11110001` | `disp.16[PC]` | 2 |
| `11110010` | `disp.32[PC]` | 4 |
| `11110011` | `/addr` | 4 |
| `11110100` | `immed.N` — **N is the operand's data length**, not in the byte | 1 / 2 / 4 (/ 8) |
| `11111000` | `[disp.8[PC]]` | 1 |
| `11111001` | `[disp.16[PC]]` | 2 |
| `11111010` | `[disp.32[PC]]` | 4 |
| `11111011` | `[/addr]` | 4 |
| `11111100` | `disp1.8[disp2.8[PC]]` | 2 |
| `11111101` | `disp1.16[disp2.16[PC]]` | 4 |
| `11111110` | `disp1.32[disp2.32[PC]]` | 8 |
| `11110101`, `11110110`, `11110111`, `11111111` | not printed — **reserved** | — |

The reserved encodings are not an inference: the Programmer's Reference lists
*Reserved Addressing Mode* as an instruction exception, "These addressing mode
encodings are reserved for future extensions to the addressing modes" (§8,
Interrupts and Exceptions).

The same `11110100` appears in the figure's 2-byte, 3-byte and 5-byte groups as
`immed.8`, `immed.16` and `immed.32`. The immediate's width is therefore the
operand's data length and cannot be decoded from the mod field alone.

## Three cells where the figure contradicts itself

Each is a printing that makes the table **undecodable** — two different modes
sharing one encoding — and each resolves to the slot map above.

**1. `[Rn]` is printed `001←Rn` with m = 0.** So is `disp.16[Rn]`. One
encoding, two modes, three bytes apart in length: no decoder can exist. The
free slot is `011` with m = 0 — `011` with m = 1 is `Rn` — so register indirect
is `011`, and register direct/indirect share a mod code and are separated by
`m`, exactly as autoincrement/autodecrement share theirs with the 8/16-bit
displacement-indirect forms.

This is confirmed *by the figure*, not by preference: `[Rn](Rx)` is printed as
the index byte `110←Rx` followed by base byte **`011←Rn`**, and its mode column
says `[Rn](Rx)`. The base byte in an indexed operand is decoded with the m = 0
column (see below), so `011` with m = 0 is `[Rn]` on the page's own showing.

**2 and 3. The 16-bit indexed indirect rows are printed with the 8-bit codes.**
`[disp.16[Rn]](Rx)` is printed `100←Rn` and `[disp.16[PC]](Rx)` is printed
`11111000` — the encodings the figure has *already* assigned, four rows earlier,
to `[disp.8[Rn]](Rx)` and `[disp.8[PC]](Rx)`. The 32-bit indexed group directly
below is internally consistent (`110←Rn`, `11111010`), which is what the 16-bit
group has to look like: `101←Rn` and `11111001`.

`rtl/cpu/v60x/v60_am_pkg.sv` implements the slot map and marks all three
departures in the source at the point of decision.

## What `m` reaches

The byte **after** an index byte is decoded with the **m = 0** column. Every
indexed row in the figure is consistent with that — `000`→disp.8,
`001`→disp.16, `010`→disp.32, `011`→`[Rn]`, `100`/`101`/`110`→the
displacement-indirect forms (cells 2 and 3 above excepted) — and it is what
makes `[Rn](Rx)` an index byte over `011←Rn`: the index byte has spent the
m = 1 slot.

## The one thing here that is not from a page

**The `111` group is decoded ignoring `m`.** The figure prints every `111` row
with m = 0 and prints no m = 1 row for the group at all, so what an m = 1
operand whose first mod byte is `1110vvvv` or `1111xxxx` means is not on the
page. Two things argue for decoding it the same way: the group needs no
register, so `m` has no second interpretation to select; and the figure's own
indexed rows already decode these bytes inside an m = 1 operand, though there
the index byte has spent the m = 1 slot before they are reached.

`v60_am_pkg` marks it at the point of decision. It is not reachable through
`v60_am_decode` — no byte stream the FSM accepts presents a `111` byte with
m = 1 — so `tb_v60_am_decode` checks it against `am_mode_of()` directly rather
than leaving a claim that no test can fail.

## What an operand costs in bus cycles

The reason this table is the next thing to build after the bus unit: the mode
determines how many memory accesses an operand reference makes, before the
instruction's own read/write is counted.

| | EA pointer fetch | operand access |
|---|---|---|
| `Rn` | — | none — the operand is the register |
| `[Rn]`, `[Rn+]`, `[-Rn]`, `disp.N[Rn]`, `disp.N[PC]`, `/addr` | — | 1 |
| `[disp.N[Rn]]`, `[disp.N[PC]]`, `[/addr]` | 1 × 32-bit | 1 |
| `disp1.N[disp2.N[Rn]]`, `disp1.N[disp2.N[PC]]` | 1 × 32-bit | 1 |
| `immed.N`, `immed.4` | — | none — the operand is in the instruction stream |

A 32-bit pointer fetch is **two** bus cycles on System 32's 16-bit bus. That is
the quantity `docs/v60/v60_operand_access.csv` counts per instruction, and it is
checkable against `v60_biu` without the per-instruction cycle counts that no NEC
document publishes (`docs/v60/INSTRUCTION-TIMING.md`).

## Scaling, for the stage that computes addresses

Not implemented by the decoder — `v60_ea` does it, and the p. 3.261 table has a
defect of its own (it prints a scaled index constant of **3** for Word). See
`docs/v60/DATA-ACCESS-SPLIT.md`. `Rx` in an indexed mode and the
step of `[Rn+]`/`[-Rn]` are scaled by the operand's data type (databook
p. 3.261): byte 1, halfword 2, word 4, doubleword 8, packed decimal 1, unpacked
decimal 2, byte character 1, halfword character 2, bit 4, bit field 4 (scaled
index: not available), bit string 4.

## Open

- **`immed.64`.** The figure stops at `immed.32`. A `long real` operand is 8
  bytes; whether `11110100` may carry eight immediate bytes is not printed.
  The decoder takes its immediate width from the operand length it is given and
  will emit 8 if asked for 8.
- **Bit addressing modes** re-interpret eighteen of these encodings for bit
  field and bit string operands (p. 6-13, databook p. 3.262): same encodings,
  displacement read as a *bit* offset, index register read as a bit
  displacement. Nothing in the mod field distinguishes them — the instruction's
  data type does. Not implemented.
