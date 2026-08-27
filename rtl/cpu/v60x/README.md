# Clean-room V60 — what is verified, and what is not

Branch `v60/cleanroom`. Built from NEC's documents under `docs/reference/`, not
from `rtl/cpu/v60/s32_v60*.sv`.

## Verified against the databook

**The bus interface unit is complete.** `v60_biu` implements databook §4 —
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

Everything above the bus. No sequencer, no instruction decode, no MMU, no FPU,
no exception model. §5 of the databook (instruction set, from p. 3.293) gives
encodings; execution semantics come from the Programmer's Reference and from
MAME as an architectural oracle, and timing comes from nowhere.

`docs/v60/v60_operand_access.csv` is the asset to build the next stage against:
220 instruction variants, 118 mnemonics, each with its read/write/RMW counts and
total data bus cycles, 161 marked `ok` and 59 `review`. That is a per-instruction
**bus transaction** golden — how many cycles of what kind an instruction must
generate — which is checkable against this BIU without needing the cycle counts
that do not exist.

## The one thing here that is not from a page

The databook scopes the three-TI recovery gap to "any consecutive pair of I/O
bus cycles" (p. 3.291) but does not say what an intervening memory cycle does.
`v60_biu` takes it to break the pair and clear the counter. Marked in the source
at the point of decision.
