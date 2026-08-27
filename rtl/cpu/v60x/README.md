# Clean-room V60 — what is verified, and what is not

Branch `v60/cleanroom`. Built from NEC's documents under `docs/reference/`, not
from `rtl/cpu/v60/s32_v60*.sv`.

## Verified against the databook

### The bus interface unit

**Complete.** `v60_biu` implements databook §4 —
pages 3.280 to 3.292, the whole section — and `v60_bus_pkg` carries the §1 pin
tables it needs.

| | source | checked by |
|---|---|---|
| seven bus states, two cycle modes | p. 3.280 | `tb_v60_biu_tstates` |
| read cycle, every pin at its named edge | p. 3.283 | `tb_v60_biu_pins` |
| write cycle, data driven falling T1, held to end of T4 | p. 3.283-4 | both |
| short cycle: BMODE low at falling T2, T3 skipped, READY ignored | p. 3.280, 3.283 | `tb_v60_biu_tstates` |
| TW insertion between T3 and T4 on READY | p. 3.283 | `tb_v60_biu_tstates` |
| three TI states between consecutive I/O cycles | p. 3.291 | `tb_v60_biu_pins` |
| bus hold: TH, high-Z at rising TH, HLDAK a half clock later, exit via TI | p. 3.292 | `tb_v60_biu_pins` |
| all sixteen MRQ + ST2-ST0 codes | p. 3.233 | `tb_v60_biu_pins` |
| FAS* first vs subsequent bus cycle | p. 3.235 | `tb_v60_biu_pins` |
| UBE* + A0 byte lane decode | p. 3.236 | `tb_v60_biu_pins` |
| reset output pin states | p. 3.282 | in `v60_biu`'s reset branch |

### The addressing-mode decoder

**The mod-field encoding is complete** — every row of the figure on p. 3.294.
`v60_am_pkg` is the encoding; `v60_am_decode` consumes a mod field one byte at
a time and says what the operand is, including whether the effective-address
calculation reads a pointer. It does not compute an address.

| | source | checked by |
|---|---|---|
| all 14 basic modes, 21 byte addressing modes with their indexed forms | p. 3.294 | `tb_v60_am_decode` |
| mod field byte order: index byte, mode byte, inner disp, outer disp | p. 3.294 ruler + p. 3.293 formats | `tb_v60_am_decode` |
| displacements signed, multi-byte fields little endian | p. 3.294 | `tb_v60_am_decode` |
| `immed.N` takes its width from the operand, not the mode byte | p. 3.294 (one code, three rows) | `tb_v60_am_decode` |
| unprinted encodings are the reserved-addressing-mode exception | Programmer's Reference §8 | `tb_v60_am_decode` |
| which modes read an EA pointer, and which touch no memory at all | p. 3.294 right-hand column | `tb_v60_am_decode` |

Three cells of that figure are implemented as `docs/v60/ADDRESSING-MODES.md`
argues they must be rather than as printed: as printed, `[Rn]` collides with
`disp.16[Rn]` and the two 16-bit indexed indirect rows collide with their 8-bit
neighbours, so no decoder can exist for the table as it stands. The bench
checks what the printed bytes decode to as well, so the difference is visible.

Every bench runs under **both** Icarus and Verilator on every invocation
(`verif/v60x/run_v60x.sh`), and every claim above has been mutation-checked:
the bench fails when the RTL is broken in the corresponding way.

## Not verified, because the documents do not say

- **Per-instruction cycle counts.** The databook's instruction-set summary has a
  "Clocks" column and every cell is blank; so does the V70 document; the
  308-page Programmer's Reference contains the word "clock" zero times. Two NEC
  publications decline to state it. This needs silicon measurement or the
  IEEE Micro 1988 paper. See `docs/v60/INSTRUCTION-TIMING.md`.
- **Several AC parameters** read TBD in this preliminary edition, `tCYK` and the
  clock high/low widths among them. They matter for driving a real V60, not for
  reimplementing one.
- **The 20-clock reset minimum** — real, and deliberately unenforced here. See
  the open item in `docs/v60/BUS-CYCLE-TIMING.md` for why it cannot live in this
  module.

## Not built yet

No sequencer, no opcode decode, no effective-address unit, no MMU, no FPU, no
exception model. What exists is the bus and the operand vocabulary that sits
directly on top of it; nothing yet issues a bus cycle on an instruction's
behalf.

The next stage is the piece between them: an **effective-address unit** that
takes a description from `v60_am_decode`, scales the index register by the
operand's data type (databook p. 3.261), adds the base, issues the pointer read
that the indirect modes need through `v60_biu`, and then makes the operand's own
access. At that point an operand reference costs a countable number of bus
cycles, and `docs/v60/v60_operand_access.csv` becomes a runnable golden: 220
instruction variants, 118 mnemonics, each with its read/write/RMW counts and
total data bus cycles, 161 marked `ok` and 59 `review`. That is a
per-instruction **bus transaction** golden — how many cycles of what kind an
instruction must generate — checkable against this BIU without the per-
instruction cycle counts that no NEC document publishes.

Opcode decode (databook §5 from p. 3.296, the seven instruction formats on
p. 3.293) is what turns that into whole instructions. Execution semantics come
from the Programmer's Reference and from MAME as an architectural oracle, and
timing comes from nowhere.

## The two things here that are not from a page

The databook scopes the three-TI recovery gap to "any consecutive pair of I/O
bus cycles" (p. 3.291) but does not say what an intervening memory cycle does.
`v60_biu` takes it to break the pair and clear the counter.

The p. 3.294 figure prints every `111`-group row — PC relative, absolute,
immediate — with `m` = 0 and prints no `m` = 1 row for the group at all.
`v60_am_pkg` decodes that group ignoring `m`. It is unreachable through the
FSM, so `tb_v60_am_decode` checks it against the encoding function directly
rather than leaving a claim no test can fail.

Both are marked in the source at the point of decision.
