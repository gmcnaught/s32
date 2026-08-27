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

### The data access unit and the effective-address unit

**An operand reference now costs a countable number of bus cycles.** `v60_dxu`
turns one logical access into the bus cycles the `{UBE*, A0}` encoding allows;
`v60_ea` computes the address a mode names, makes the pointer read the indirect
modes need, and hands back the operand.

| | source | checked by |
|---|---|---|
| a halfword cycle needs A0 low; three legal lane encodings, no fourth | p. 3.235-6 | `tb_v60_dxu` |
| 1 / 1-2 / 2-3 / 4-5 bus cycles for byte / halfword / word / doubleword | p. 3.236 + PgmRef §3 | `tb_v60_dxu` |
| DL1-DL0 is the logical length and holds across the access | p. 3.235 | `tb_v60_dxu` |
| FAS* marks the first bus cycle and only the first | p. 3.235 | `tb_v60_dxu` |
| unaligned operands are legal and are assembled in order | PgmRef §3 | `tb_v60_dxu`, `tb_v60_ea` |
| every addressing mode's effective address, against real memory | p. 3.294 | `tb_v60_ea` |
| the scaled index is the operand's size, and is added after an indirection | p. 3.257, p. 3.294 | `tb_v60_ea` |
| `[Rn+]` / `[-Rn]` step by the operand's size, decrement before the access | p. 3.261 | `tb_v60_ea` |
| writing an immediate is the illegal-addressing-mode exception | PgmRef §8 | `tb_v60_ea` |

The memory in both benches is modelled as the databook describes it — two
byte-wide banks reached only through those three lane encodings — so an access
that picks the wrong lane moves the wrong byte rather than merely looking wrong.

### The prefetch unit and the bus arbiter

**Instructions reach the decoder.** `v60_pfu` keeps the databook's 16-byte
queue filled from idle bus cycles and hands the decoder one byte at a time;
`v60_bus_arb` is the "lowest priority bus requester" rule.

| | source | checked by |
|---|---|---|
| a 16 byte queue, which stops fetching when it is full | p. 3.246 | `tb_v60_pfu` |
| bytes delivered in program order, each with its own PC | p. 3.246 | `tb_v60_pfu` |
| a control transfer flushes the queue | p. 3.246 | `tb_v60_pfu` |
| the fetch after a flush is a DEMAND fetch, the rest PREFETCH | p. 3.233-4, 3.246 | `tb_v60_pfu` |
| the first fetch out of reset is from 0FFFFF0H | p. 3.282 | `tb_v60_pfu` |
| a fetch never runs while the data unit wants the bus | p. 3.246 | `tb_v60_pfu` |
| the grant is held from BCY* to the ack, and an ack reaches one master | p. 3.283 | `tb_v60_pfu`, continuously |
| a request withdrawn before its cycle starts does not wedge the bus | — | `tb_v60_pfu` |

The arbiter's hold rule is not defensive programming: an earlier version
released the grant when a master dropped its request, and a data read at
`0x800` was delivered into the instruction queue. See `docs/v60/PREFETCH.md`.

### The instruction formats

**The seven formats are decoded**, minus the mod fields. `v60_fmt_decode`
consumes everything else an instruction carries — the opcode byte, the second
half of the base word, the displacements of Formats IV and VI — and reports
which mod fields follow and which `m` each is decoded with.

| | source | checked by |
|---|---|---|
| all seven formats' field positions and base lengths | p. 3.293 | `tb_v60_fmt_decode` |
| Format III's one-byte base, with `m` as bit 0 of the opcode | p. 3.293 | `tb_v60_fmt_decode` |
| Format I's second operand is `reg`, not a mod field | p. 3.293 | `tb_v60_fmt_decode` |
| the mod/ext order, and which of VIIa/b/c carries which | p. 3.293 | `tb_v60_fmt_decode` |
| Format IV and VI displacements, signed and little endian | p. 3.293-5 | `tb_v60_fmt_decode` |
| the extension field's length-or-register-id encoding | p. 3.293 | `tb_v60_fmt_decode` |
| a whole instruction's length, format decoder plus mod decoder | p. 3.293-4 | `tb_v60_fmt_decode` |

### The opcode table and the decode unit

**An instruction decodes end to end.** The instruction-set table
(pp. 3.296–3.299) is data in `tools/v60x/insn_table.py`, generated into
`v60_op_pkg`; `v60_fmt_decode` looks opcodes up itself; `v60_idu` walks the
plan and runs `v60_am_decode` once per mod field.

| | source | checked by |
|---|---|---|
| 134 rows / 284 encodings, and no two instructions sharing one | pp. 3.296-3.299 | `tools/v60x/insn_table.py` |
| 66 rows agreeing with a separately compiled reference | Programmer's Reference | same, `cross_check()` |
| the generated package matching its table | — | `run_v60x.sh`, before any bench |
| "I, II" resolved by bit 15; escape opcodes by their subop | p. 3.293, p. 3.297 | `tb_v60_fmt_decode` |
| Format IV's width, both opcodes | p. 3.295 + Reference §7 | `tb_v60_fmt_decode` |
| a nineteen-instruction program decoded off the real bus | pp. 3.293-3.299 | `tb_v60_idu` |
| an immediate's width, from the suffix, the `siz` field and the `s` bit | p. 3.295, p. 3.294 | `tb_v60_idu` |
| a conversion instruction's two operands having different widths | p. 3.261 | `tb_v60_idu` |
| each instruction's PC is the last one's PC plus its length | — | `tb_v60_idu`, across all ten |

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

No execution: no register file, no PSW, no ALU, no MMU, no FPU, no exception
model. What exists is a bus, the operand vocabulary above it, the machinery
that turns one operand reference into bus cycles, an instruction stream
arriving a byte at a time, and a decoder that turns that stream into
instructions with described operands.

The next stage is **execution**: the register file, the PSW, the ALU and the
exception model. Everything below it now exists — an instruction arrives,
decodes, and its operands can be resolved to addresses and fetched (see
`tb_v60_front`) — so what is missing is the part that does something with them.
`docs/v60/EXECUTION-STAGE-PLAN.md` scopes it: six increments, what each one's
bench would assert, what has to change in the modules that exist, and the
traps — including that both PSW *figures* are unreadable at scan resolution
while both bit *lists* survive and agree.

Two smaller things are open and neither blocks that:

- **Three subops in the bit-string group** could not be read off the scan
  (`ORNBS`, `XORNBS`, `SCH1BS`). Their format is not in doubt; see
  `docs/v60/INSTRUCTION-DECODE.md`.
**E1 of that plan is done**: the operand data type comes from the same
generated table as the format, per operand and — for the escape opcodes — per
subop, and `v60_idu`'s `reserved` is now the two flags the two exception codes
need. What is left open is E2 onward: the PSW, the register file, the ALU, the
exception unit and the sequencer.

That closes the loop on `docs/v60/v60_operand_access.csv`: 220 instruction
variants, 118 mnemonics, each with its read/write/RMW counts and total data bus
cycles, 161 marked `ok` and 59 `review`. Per operand those counts are already
measurable (`tb_v60_ea`); per instruction needs the decode that says which
operands an opcode has.

Execution semantics come from the Programmer's Reference and from MAME as an
architectural oracle, and timing comes from nowhere.

## The things here that are not from a page

The databook scopes the three-TI recovery gap to "any consecutive pair of I/O
bus cycles" (p. 3.291) but does not say what an intervening memory cycle does.
`v60_biu` takes it to break the pair and clear the counter.

The p. 3.294 figure prints every `111`-group row — PC relative, absolute,
immediate — with `m` = 0 and prints no `m` = 1 row for the group at all.
`v60_am_pkg` decodes that group ignoring `m`. It is unreachable through the
FSM, so `tb_v60_am_decode` checks it against the encoding function directly
rather than leaving a claim no test can fail.

`v60_dxu` makes two more, both in `docs/v60/DATA-ACCESS-SPLIT.md`: DL1-DL0 has
no doubleword code, so an eight-byte operand is driven as `word` and treated as
two logical word accesses for FAS*; and the split walks upward from the
operand's address, which nothing observable here depends on but a bus analyser
would see.

A fourth figure defect turned up with `v60_ea`: the p. 3.261 scaling table
prints a scaled index constant of **3** for Word, against its own
increment/decrement of 4 and against the sentence on p. 3.257 that says the
index is scaled by the operand's size. It scales by 4.

`v60_pfu` makes two more, both in `docs/v60/PREFETCH.md`: what DL1-DL0 carries
during an instruction fetch (the databook says only that FAS* is undefined
there), and that a control transfer to an odd address drops the byte before the
target — which is why an odd instruction stream rests at fifteen queued bytes
rather than sixteen.

All are marked in the source at the point of decision.
