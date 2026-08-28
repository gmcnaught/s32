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
| BERR* and RT/EP* sampled at the FALLING edge of T4 | p. 3.239-40 + the p. 3.243 plate | `tb_v60_biu_pins` |
| RT/EP* = 1 retries the cycle; RT/EP* = 0 raises | p. 3.237 | `tb_v60_biu_pins` |
| NMI* is an event and latches; INT is a level and does not | p. 3.237 | `tb_v60_biu_pins` |

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
| an interrupt acknowledge cycle drives MRQ + ST2-ST0 = 1110 | p. 3.234 | `tb_v60_dxu` |

The memory in both benches is modelled as the databook describes it — two
byte-wide banks reached only through those three lane encodings — so an access
that picks the wrong lane moves the wrong byte rather than merely looking wrong.

### The data unit's two masters

`v60_ea` and `v60_exc` both want `v60_dxu`, and `v60_dmux` gives it to one of
them. It is a mux and not a third `v60_bus_arb` port on purpose: `tb_v60_pfu`
asserts continuously that bus ownership does not change between BCY* and the
ack and that an ack reaches exactly one master, and a third port would put
that proof back on the table for nothing.

| | source | checked by |
|---|---|---|
| the requesting master's address, length, direction and data reach `v60_dxu` | — | `tb_v60_dmux` |
| a completion reaches the master that asked and no other | — | `tb_v60_dmux` |
| two masters asking at once is reported rather than resolved silently | — | `tb_v60_dmux` |

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
| both hold over a third kind of cycle: the interrupt acknowledge | — | `tb_v60_pfu` |

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
| the bit-string group's ten subops, against the Reference's Opcode lines | PgmRef §7 `5B-nn` | read directly |
| 66 rows agreeing with a separately compiled reference | Programmer's Reference | same, `cross_check()` |
| the generated package matching its table | — | `run_v60x.sh`, before any bench |
| "I, II" resolved by bit 15; escape opcodes by their subop | p. 3.293, p. 3.297 | `tb_v60_fmt_decode` |
| Format IV's width, both opcodes | p. 3.295 + Reference §7 | `tb_v60_fmt_decode` |
| a nineteen-instruction program decoded off the real bus | pp. 3.293-3.299 | `tb_v60_idu` |
| an immediate's width, from the suffix, the `siz` field and the `s` bit | p. 3.295, p. 3.294 | `tb_v60_idu` |
| a conversion instruction's two operands having different widths | p. 3.261 | `tb_v60_idu` |
| each instruction's PC is the last one's PC plus its length | — | `tb_v60_idu`, across all ten |

### The execution stage

**Instructions execute.** `v60_seq` sequences a fetched instruction through the
register file, the address unit and the ALU, and retires it.

| | source | checked by |
|---|---|---|
| the PSW's twenty fields, from two independent renderings that agree | p. 3.248, PgmRef §3 | `tb_v60_psw` |
| all 16 conditions over all 16 flag combinations, twice over | p. 3.295 + PgmRef §7 Bcc | `tb_v60_psw` |
| 32 registers, and R31 as five stack pointers switched on {IS, EL} | p. 3.249, PgmRef §8 | `tb_v60_regfile` |
| that R31 and its stack pointer register may differ mid-program | PgmRef §8 | `tb_v60_regfile` |
| the LDPR / STPR permission per privileged register id | PgmRef Fig 3-2 | `tb_v60_regfile` |
| CY / OV / S / Z for eleven operations, byte width exhaustively | PgmRef §7 blocks, p. 3.296 | `tb_v60_alu` |
| SHL / SHA / ROT / ROTC against a one-bit-per-step model, 132,135 checks | PgmRef §7 blocks | `tb_v60_alu` |
| a signed byte count, a zero count clearing CY, and counts past the width | PgmRef §7 | `tb_v60_alu` |
| an instruction whose two operands are at different widths | PgmRef §7 syntax lines | `tb_v60_seq` |
| MOVS sign extending, MOVZ not, and both leaving all four flags alone | PgmRef §7 blocks | `tb_v60_alu`, `tb_v60_seq` |
| MOVT keeping the low bits and overflowing when the dropped ones disagree | PgmRef §7 MOVT | `tb_v60_alu`, `tb_v60_seq` |
| the SBT read at `SBR + 4 × vector`, and the frame BRKV prints | PgmRef §8 | `tb_v60_exc` |
| execution level 0 and the interrupt-enable rules for a handler | PgmRef §8 | `tb_v60_exc` |
| the rest of the recognition sequence: TE, TP, AE, EM cleared and ASA set | pp. 3.269-3.270 | `tb_v60_exc` |
| a program: immediate, add, compare, store, read-modify-write | all of the above | `tb_v60_seq` |
| an indirect destination costing one pointer read, not two | p. 3.294 | `tb_v60_seq` |
| Format I in both directions of its `d` bit | MAME, via `s32_v60.sv` | `tb_v60_seq` |
| a branch measured from its own first byte, taken and not taken | PgmRef §7 Bcc | `tb_v60_seq` |
| a counted loop: DBcc decrements, then tests, with its split condition | PgmRef §7 DBcc, p. 3.293 | `tb_v60_seq` |
| TB testing the same register without decrementing it | PgmRef §7 TB | `tb_v60_seq` |
| BSR / JSR pushing NextPC through `[-SP]`, RSR popping through `[SP+]` | PgmRef §7 | `tb_v60_seq` |
| JMP and JSR transferring to the effective ADDRESS, not to what is at it | PgmRef §7 | `tb_v60_seq` |
| a taken branch flushing the queue, so the fall-through is not executed | p. 3.246 | `tb_v60_seq` |
| a stack push costing two bus cycles and a branch costing none | p. 3.236 | `tb_v60_seq` |
| a reserved opcode and a reserved addressing mode raising *different* vectors | Fig 8-2 | `tb_v60_seq` |
| an immediate used as a destination raising the illegal-mode exception | PgmRef §8 | `tb_v60_seq` |
| each frame's exception code, from the code table's Instruction Exceptions | PgmRef §8 | `tb_v60_seq` |
| the Current PC on top of the frame, under a code word that carries the count | Table 8-1, Fig 8-3 | `tb_v60_seq`, `tb_v60_exc` |
| an interrupt's frame being the PSW and the PC, with no code word | Fig 8-3 | `tb_v60_exc` |
| the handler reached through the SBT and the queue flushed for it | Fig 8-2, p. 3.246 | `tb_v60_seq` |
| one master at a time on the data unit, and completions reaching only it | — | `tb_v60_dmux` |
| NMI is vector 2 and the bus fault vector 3, off the p. 3.270 plate | p. 3.270, Fig 8-2 | `tb_v60_seq` |
| an interrupt stacks the PSW and the NEXT PC, and nothing else | Fig 8-5 | `tb_v60_seq`, `tb_v60_exc` |
| INT held off while PSW.IE is clear, taken at the next boundary when set | p. 3.237 | `tb_v60_seq` |
| a maskable interrupt's vector read off the SECOND acknowledge cycle | p. 3.237 | `tb_v60_exc`, `tb_v60_seq` |
| a vector under 64 is the Invalid Interrupt: vector 4, code 0400 | PgmRef §8, Fig 8-5 | `tb_v60_exc` |
| the bus fault's frame, the failed cycle's physical address above the code | Fig 8-5 | `tb_v60_seq`, `tb_v60_exc` |
| its code naming which KIND of cycle failed, read against write | Table 8-1 | `tb_v60_seq` |
| a faulting instruction not retiring, and the handler running instead | Fig 8-5 "Abort" | `tb_v60_seq` |
| all three frames landing on the INTERRUPT stack, not the level stack | §8 + step (vii) | `tb_v60_seq`, `tb_v60_exc` |
| CALL saving AP and the Next PC, in that order, and passing an ADDRESS | §7 CALL | `tb_v60_seq` |
| RET restoring AP as well as the PC, and discarding `num` bytes | §7 RET | `tb_v60_seq` |
| RETIS/RETIU popping the PC then the PSW, which is what `v60_exc` pushed | §7, Fig 8-3 | `tb_v60_seq` |
| their count being an OPERAND, a halfword, costing one bus cycle | §7 `count.h.r` | `tb_v60_seq` |
| the whole PSW restored, so the stack switches back on the way out | §7 "Restored" | `tb_v60_seq` |
| RETIS privileged and RETIU not, which is their only difference | §7 Exceptions | `tb_v60_seq` |
| returning to a more privileged level raising Illegal Data Field | §7 RETIU | `tb_v60_seq` |
| AP being R29 | §7 RET, p. 3.247 | `tb_v60_seq` |
| MUL / MULU / DIV / DIVU / REM / REMU, byte width exhaustively | §7 blocks | `tb_v60_muldiv` |
| and halfword and word at their boundaries — 394,416 checks | §7 blocks | `tb_v60_muldiv` |
| MUL's overflow being a SIGNED fit, where MAME's is unsigned | §7 MUL | `tb_v60_muldiv` |
| the negative maximum divided by −1 setting OV and writing nothing | §7 DIV | `tb_v60_muldiv` |
| a remainder taking the sign of the dividend | §7 REM | `tb_v60_muldiv` |
| a divide by zero raising vector 21, where MAME does not trap | §7 + Table 8-1 | `tb_v60_muldiv`, `tb_v60_seq` |
| its frame: the Current PC as a PARAMETER and the Next PC on top | Fig 8-5 | `tb_v60_seq` |
| the sequencer waiting for a unit that is not combinational | — | `tb_v60_seq`, `tb_v60_muldiv` |

### Against the shipping core

**They agree about where instructions end.** `tb_v60_cosim` puts
`rtl/cpu/v60/s32_v60.sv` and this decoder on one instruction stream and compares
instruction boundaries — the one question both answer for every instruction
without either having to implement the same operation. It is also the only
thing in this repository that tests the shipping core's length arithmetic
against a second opinion.

| | source | checked by |
|---|---|---|
| every mod field's length: immediate, quick, register, indirect, disp8/16/32, absolute, PC-relative | p. 3.294 | `tb_v60_cosim` |
| every format's base length and displacement: I, II, III, IV both widths, V, VI | p. 3.293 | `tb_v60_cosim` |
| the shipping core writing its PC once per instruction, forward | — | `tb_v60_cosim` |

One divergence is recorded rather than resolved: opcodes `6B` and `7B`, which
this tree decodes as Format IV branches with the "False / Never" condition and
`s32_v60.sv` raises on as reserved. See `docs/v60/COSIM.md`.

Every bench runs under **both** Icarus and Verilator on every invocation
(`verif/v60x/run_v60x.sh`), and every claim above has been mutation-checked:
the bench fails when the RTL is broken in the corresponding way.

The runner also regenerates `v60_op_pkg.sv` and fails if the checked-in copy
differs, because a table edited without regenerating is a table that says one
thing and an RTL that does another. That check has one way to be defeated, and
it was defeated: Python's bytecode cache keys on the source file's mtime and
size, so an edit to `tools/v60x/insn_table.py` that lands in the same second as
the previous one and leaves the file the same length — which is exactly what
reverting a one-character mutation does — leaves the cached `.pyc` valid. The
generator and the check then both read the old table and agree with each other
about a stale file. `run_v60x.sh` sets `PYTHONDONTWRITEBYTECODE=1`, which
removes the cache the trap needs.

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

No MMU, no FPU, no task or context switching, no address traps, no emulation
mode. What exists is a bus, the operand vocabulary above it, the machinery
that turns one operand reference into bus cycles, an instruction stream, a
decoder, enough architectural state and datapath to execute the integer
two-operand instructions of Formats I and II including the shift group and the
conversions, the control transfers that make a sequence of them a program —
all three return pairs among them — the multiplies and divides of the integer
set, four of the instruction exceptions, the integer arithmetic one, and the
three externally raised ones.

`docs/v60/NEXT-STEPS.md` is the ordered list of what is open and what each
piece would take. In short: everything outside the integer set, and a
doubleword operand's register pair — which is what the X forms of the
multiplies and divides are waiting on.

Of the externally raised group, what is missing is the bus freeze interrupt
(vector 1, and `v60_biu` has no `BFREZ` pin), the double bus error (§8 halts;
nothing here halts, and `BST_MACHINE_FAULT` is never issued), NMI's own "no
further NMI until RETIS" masking, and `BLOCK*` during an acknowledge cycle. All
four are recorded with their pages in `docs/v60/EXCEPTIONS.md` and
`docs/v60/BUS-CYCLE-TIMING.md`.

`docs/v60/EXECUTION-STAGE-PLAN.md`'s six increments are **done**: the operand
data type, the PSW package, the register file, the ALU, the exception unit and
the sequencer.

Two things this tree recorded as unreadable turned out to be readable in the
*other* book, and both are closed. The Programmer's Reference's printing of
the exception recognition sequence loses three digits to the scan, and the
databook's second printing at pp. 3.269–3.270 has all of them, so `v60_exc`
performs the whole sequence. The other way round, three bit-string subops the
databook's scan could not settle (`ORNBS`, `XORNBS`, `SCH1BS`) are printed
outright in the Reference's Opcode lines — `5B-16 / 5B-17` and so on — which
confirms all three placements and the seven around them. When a page in one
book is illegible, look for the same material in the other one before
recording it as unread.

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

`v60_muldiv` makes one, and it is not a reading of a page but a divergence
from MAME on two counts, both in `docs/v60/MULTIPLY-DIVIDE.md`: a divide by
zero **raises** here, where MAME leaves the destination alone and does not
trap; and `MUL`'s overflow is the **signed** fit its page describes, where
MAME's test is an unsigned one that reports overflow for `MUL.W -1, 1`. Three
NEC statements against an emulator's omission in the first case, and one
sentence against a different reading of it in the second.

A third table defect turned up with the return pairs, and it is the shift
group's twice over: `RETIU` and `RETIS` were given a **word** operand from the
"the V60 stack moves words" rule that governs `PUSH` and `POP`. Their operand
is not a stack word — both pages print `count.h.r`, and MAME drives
`moddim = 1` for their opcodes against `2` for `RET`'s. See
`docs/v60/RETURN-PAIRS.md`; a halfword read from an even address costs one bus
cycle where a word costs two, which is how `tb_v60_seq` holds it.

A fourth figure defect turned up with `v60_ea`: the p. 3.261 scaling table
prints a scaled index constant of **3** for Word, against its own
increment/decrement of 4 and against the sentence on p. 3.257 that says the
index is scaled by the operand's size. It scales by 4.

`v60_alu` makes one for MOVT: the Programmer's Reference's Condition Codes
block for it did not survive the scan — it OCRs as the two column headings and
nothing else — and its Description says only when OV is *set*. Every other
block in §7 that touches OV says "otherwise cleared", so MOVT clears it when
nothing was truncated away.

`v60_pfu` makes two more, both in `docs/v60/PREFETCH.md`: what DL1-DL0 carries
during an instruction fetch (the databook says only that FAS* is undefined
there), and that a control transfer to an odd address drops the byte before the
target — which is why an odd instruction stream rests at fifteen queued bytes
rather than sixteen.

The externally raised exceptions add three more, both documents carrying the
pages. `v60_biu` acknowledges a bus cycle it is raising a fault on, because an
ack is the only thing that releases the arbiter's grant and advances `v60_dxu`
and there is no abort path to a master — so the access completes and `berr`
says its data is meaningless. The address the interrupt acknowledge cycles
drive is not on a page at all, and is driven at zero. And `NMI*` and `INT` are
synchronised, which no page asks for: they are the only two inputs in §1 with
neither a setup parameter nor a waveform plate, which is what says they are
asynchronous.

One thing here is not a decision but a defect the new exceptions exposed.
`v60_seq`'s `rf_stack_switch` is a registered output, so the register file
performs the switch at the end of the cycle it is high in and R31 reads back as
the new stack pointer only in the cycle after — and `S_EXC_REQ` sampled it a
cycle too early, pushing the frame on the stack being switched away from. It
was invisible for as long as it existed, because the three instruction
exceptions switch to the entry they are already on and the register file makes
that a no-op. The first exception that genuinely changes stacks is an
externally raised one. `S_EXC_SETTLE` is the fix, and "seq loses the
stack-switch settle cycle" is one of the mutations `tb_v60_seq` catches.

All are marked in the source at the point of decision.
