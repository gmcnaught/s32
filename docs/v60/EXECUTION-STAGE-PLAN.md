# The execution stage: what it needs, and in what order

**Written 2026-08-27**, after the front end was finished. **All six increments
below are now built** — see `rtl/cpu/v60x/README.md` for what they assert and
`git log` for what each one turned up. Kept as written, because what a plan got
wrong is worth keeping next to what it got right:

- E1's "type the variable-length instructions from the extension field" was
  wrong: p. 3.261's unit size and the extension field's length are different
  quantities, and only the first is `opbytes`.
- E3's "R31 read and written at all eight {IS, EL} combinations resolves to the
  documented pointer" describes an alias model the Programmer's Reference rules
  out in as many words: the two "can differ during the execution of a program".
- §4.7's integer-overflow silence was not one — BRKV raises it.
- The vector numbering here was off by one for the reserved opcode: Figure 8-2
  puts it at offset +64, so vector 16.

Drafted by a scoping pass over the two documents and reviewed against them.
Claims marked **verified** were re-read on the page while reviewing; the rest
are the scoping pass's reading and are to be re-read when their increment is
built, not trusted from here.

## The state, and how well it is documented

**The PSW is the best-sourced object in this project.** The Programmer's
Reference gives it as a prose bit list (§3) and the databook as a table
(p. 3.248), and these are two genuinely independent renderings — unlike the
p. 3.294 mod-field figure, which is one figure printed in two books. They
agree bit for bit:

| bits | | bits | |
|---|---|---|---|
| 0 Z, 1 S, 2 OV, 3 CY | integer flags | 16 TE, 17 AE, 18 IE | enables |
| 4:7 | RFU | 19:23 | RFU |
| 8 FPR, 9 FUD, 10 FOV, 11 FZD, 12 FIV | float flags | 24:25 EL | execution level |
| 13:15 | RFU | 26 IP, 27 TP, 28 IS, 29 EM, 30 ATA, 31 ASA | |

Also specified: the 32 general registers with R29/R30/R31 as AP/FP/SP; the
five-deep stack-pointer cache selected by `{PSW.IS, PSW.EL}`; the privileged
register IDs and their per-ID LDPR/STPR permissions; per-instruction condition
codes (PgmRef §7 gives every instruction a Condition Codes block); the 16
condition encodings, which cross-check against the `cccc` field this tree
already has in `tools/v60x/insn_table.py`; the reset state (PSW = 0,
PC = FFFFFFF0H); and the exception model — a 256-entry system base table, an
eight-step recognition sequence, and Table 8-1's per-code parameter counts and
Current-PC/Next-PC column.

**Verified while reviewing:** the PC "contains the memory address of the first
byte of the instruction currently being executed" (PgmRef §3). That closes an
open item recorded in `docs/v60/DATA-ACCESS-SPLIT.md` — *which* PC a
PC-relative operand is relative to — and `v60_idu.insn_pc` is already exactly
that value.

**Verified while reviewing, and it corrects the scoping pass:** there is no
trap-enable bit for integer overflow -- PSW bits 19:23 are RFU -- and that is
not the gap it looks like.
`BRKV` (opcode **C9**, Format V) is the instruction that raises it — "The OV
flag is tested and if set, an Integer Overflow Exception occurs. Otherwise,
instruction execution continues with the next instruction" (PgmRef §7).
Arithmetic sets OV; software tests it, which is why no enable bit is needed.
The same page prints the frame it builds, which is the concrete layout E5
needs:

    [-SP] <- CurrentPC ; [-SP] <- Exception Code ; [-SP] <- PSW ; [-SP] <- NextPC
    PC <- [ Exception Vector 21 ]

Out of scope for this stage though specified: the MMU, the FPU (the five float
flags are *held* here, nothing sets them), task and context switching, address
traps, and V20/V30 emulation mode.

## Six increments, smallest first

E1–E5 are independent of each other's RTL; only E6 joins them.

**E1 — the operand data type.** The smallest real gap, and it blocks
correctness below it: `v60_idu.sv` passes `opbytes = 4` unconditionally, and
`opbytes` fixes an `immed.N`'s width (p. 3.294), the scaled-index constant
(p. 3.257), the `[Rn+]` / `[-Rn]` step (p. 3.261) and the bus-cycle count. A
`MOV.B` with an immediate currently reads four bytes where the page says one.
No new transcription: `insn_table.py` already expands `siz` / `s` / `c`, so
the generator can emit `op_data_bytes()` from the same 284 encodings. The
bench asserts `insn_len` per data type, so a wrong width changes an
instruction's *length* — which the existing PC-chain property already checks.

**E2 — `v60_psw_pkg`.** A package, the shape of `v60_am_pkg`: bit positions,
RFU write masks, the two UPDPSW widths, and `cond_true(cc, flags)`. Its bench
holds *both* documents' bit lists as separate arrays that must agree, so a
transcription slip in one is visible rather than absorbed, and evaluates all 16
conditions over all 16 flag combinations, indexed by the low nibble of the
6x/7x opcode so the condition table and the encoding cross-check each other.

**E3 — `v60_regfile`.** 32 registers, the five-deep SP cache, the LDPR/STPR
port, and the extension field's register-ID form. The bench reads *and writes*
R31 at all eight `{IS, EL}` combinations, asserts the three undefined ones only
as "does not corrupt the other four", and checks a doubleword pair assembles
low-register-first.

**E4 — `v60_alu`.** Combinational, width-selected by E1's `opbytes`, integer
only. Per operation × per width: the result and all four flags against the
printed sentence, with the boundaries those sentences pin — `0x7F + 1` at byte
width gives OV=1 S=1 CY=0; `0xFF + 1` gives CY=1 Z=1 OV=0; CMP computes
`src2 − src1` with CY as a borrow; TEST forces CY=0 OV=0; immediate-quick is
zero extended.

**E5 — `v60_exc`.** The eight-step recognition sequence, driving `v60_dxu` for
the SBT read and the frame pushes and `v60_pfu.redirect` for the vector. The
bench asserts the SBT read is at `SBR + 4·vector` and takes **two** bus cycles,
that frames match Figure 8-5 and the BRKV layout above, and that the whole
frame's bus-cycle count is what its word count predicts.

**E6 — `v60_seq`, the join.** Reads the registers `v60_idu` named, presents
`insn_pc` as `pc_val`, runs `v60_ea` per operand, applies `v60_alu`, retires.
Its bench asserts whole instructions out of real memory *and* the bus-cycle
count against `docs/v60/v60_operand_access.csv` — which is where that file's
220 rows finally close, per instruction rather than per operand.

## What has to change in what exists

- **`v60_idu`**: `a_opbytes` from `op_data_bytes()` (E1); and **split
  `reserved`** — one flag today, but Table 8-1 gives reserved *opcode* (1000)
  and reserved *addressing mode* (1200) different codes and different vectors,
  so a sequencer cannot choose between them.
- **`v60_ea`**: `rn_val` is 32 bits and a doubleword register-direct operand
  needs a register *pair*; the module only warns today.
- **`v60_dxu` / `v60_bus_arb`**: mux `v60_exc` and `v60_ea` **above**
  `v60_dxu`, not as a third arbiter port. `tb_v60_pfu` continuously asserts
  that bus ownership does not change between BCY* and the ack and that an ack
  reaches exactly one master; a third port invalidates that proof.
- **`v60_fmt_decode`, `v60_am_decode`, `v60_pfu`, `v60_biu`**: no changes.

## Traps to expect

- **Both PSW *figures* are unreadable at scan resolution** — the rulers OCR as
  `IS 1S 13 12 10 9S7S S4 3 2 10`. The bit *lists* survive in both books and
  agree. Build from the lists, and read the plates before writing anything down.
- **The reset-value digits are OCR-ambiguous** (`TKCW 0 OOOEOOOH`): do not
  transcribe them from the text layer.
- **Table 8-1's Stack Invalid block has drifted columns**, with stray dashes
  where codes belong and near-duplicate names in the block below. Whether those
  are two distinct groups is not readable at scan resolution.
- **The two printings disagree on step (vii)**: the Reference says an exception
  frames on L0SP, the databook adds a clause the Reference omits ("or LnSP if a
  change execution level or ATT exception occurs"). Take the superset and mark
  the divergence, the way `BUS-STATUS-ENCODING.md` handles code 000.
- **PSW.IS is never assigned by the eight-step sequence**, yet R31's identity
  depends on it and interrupts are said to push onto the interrupt stack. The
  strongest candidate for a fifth "not from a page" decision in this tree.
- **Flag width.** Nothing states that CY/OV/S/Z are evaluated at the operand's
  width rather than at 32 bits; every `.b/.h/.w` variant implies it. Fix the
  convention in `v60_alu`, mark it, and let the bench make it visible.
- **`RETIS` order**: whether the final SP adjustment uses the pre- or
  post-restore PSW's stack pointer is not stated, and they differ when the
  frame crossed a level.

## What this stage cannot verify

**Per-instruction cycle counts, still.** No NEC publication held gives them
(`docs/v60/INSTRUCTION-TIMING.md`), so no bench here may assert a clock count.
What it can assert is the currency the stage below already uses: **bus cycles**.

**The bus-error, NMI and maskable-interrupt families cannot be driven end to
end**, because `v60_biu` has `ready_n`, `bmode` and `hldrq_n` and no `berr`,
`int` or `nmi` pin. `v60_exc` can be built and benched on internally raised
exceptions; the externally raised ones need pins the bus unit does not have.
