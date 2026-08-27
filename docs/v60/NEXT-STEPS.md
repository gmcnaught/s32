# What is open, in the order it is worth doing

**Written 2026-08-27**, after `docs/v60/EXECUTION-STAGE-PLAN.md`'s six
increments landed and Format I was wired in. `rtl/cpu/v60x/README.md` is the
boundary statement — what is verified, against which page, by which bench. This
file is the other half: what is *not*, and what each piece would take.

The rules every item below inherits, from that README: a claim carries the page
it came from, every bench runs under both simulators, every bench is
mutation-checked and what survives is closed rather than noted, and anything not
from a page is marked at the point of decision.

---

## 1. Control flow

**The largest functional gap, and the one that turns "executes instructions"
into "runs a program".** Nothing drives `v60_pfu.redirect` today: the PC
advances by the instruction's length and no other way, so a program is a
straight line.

What it needs:

- **Formats III, IV, V and VI executed** in `v60_seq`, which currently stops on
  all four. The decode side is already done — `v60_fmt_decode` extracts their
  fields and `tb_v60_fmt_decode` checks them — so this is sequencing, not
  decoding.
- **The condition**, which exists: `v60_psw_pkg.cond_true(cc, flags)`, checked
  over all 16 conditions × 16 flag combinations against a second statement of
  them, and indexed the way a `Bcc` opcode's low nibble is.
- **The displacement**, which exists: `v60_idu.br_disp`, sign-extended, with
  Format IV's width already settled by `op_iv_disp_bytes()` (Bcc is `6x`/`7x`,
  BSR is `disp16`).
- **`v60_pfu.redirect` / `redirect_pc`**, which exist and are benched: a
  control transfer flushes the queue and the next fetch is a DEMAND fetch.

Instructions: `Bcc`, `BSR`, `JMP`, `JSR`, `RET`, `RETIU`, `DBcc`, `TB`. The
subroutine ones push and pop through the stack the way `v60_exc` already does,
so that frame code is a model for them.

What to watch for: `JMP`/`JSR` are Format III, whose `m` rides in the opcode
byte; `DBcc` and `TB` share opcode `C7` and are told apart by the Format VI
subop, which `v60_op_pkg` already handles.

## 2. Wire `v60_exc` in

It works and is benched against real memory, and nothing calls it. `v60_seq`
stops on a reserved opcode or addressing mode instead of raising vector 16 or
18.

The structural change is the one `EXECUTION-STAGE-PLAN.md` describes: **mux
`v60_exc` and `v60_ea` above `v60_dxu`**, not as a third `v60_bus_arb` port.
`tb_v60_pfu` asserts continuously that bus ownership does not change between
BCY* and the ack and that an ack reaches exactly one master; a third port
invalidates that proof and would require re-establishing it.

## 3. Three recorded gaps, each small

- **The shifts and rotates.** `SHA`, `SHL`, `ROT`, `ROTC` are in the table with
  their formats and widths; what is missing is their Condition Codes blocks,
  which have not been read off the page. `v60_alu` says so in its header.
- **The extending moves.** `MOVS.*` and `MOVZ.*` sign- and zero-extend, and
  `MOVT.*` truncates — distinct operations `v60_alu` does not have. Adding them
  would also make one thing observable that is not today: `tb_v60_seq` records
  that swapping the source and destination widths changes nothing, because
  every operation currently implemented has them equal. These are the
  instructions whose widths differ.
- **Table 8-1's TE / TP / AE / EM / ASA columns.** `v60_exc` sets the execution
  level and the interrupt enable and leaves those five alone, because the
  columns have not been read off the scan. Guessing them was the easy half of
  the work and was not done.

Also still unresolved from the transcription: three bit-string subops
(`ORNBS`, `XORNBS`, `SCH1BS`), recorded in `tools/v60x/insn_table.py`'s
`UNRESOLVED_SUBOP`. Their *format* is not in doubt, so nothing the RTL uses
depends on them.

---

## Two things not on the list, and why

**Synthesis.** Nothing in `rtl/cpu/v60x/` has been through Quartus. Area and
timing are unknown, on a core whose *existing* V60 already sits at the edge of
closure and whose placement marginality is an open problem. Any claim about
whether this could replace `rtl/cpu/v60/` starts with a fit, not with more RTL.

**A co-simulation oracle.** The clean-room decoder can consume the same
instruction stream as the shipping core and assert instruction boundaries and
lengths against it. That needs no new RTL, carries no integration risk, and
tests `s32_v60.sv` in a way nothing currently does — the cheapest useful thing
on this page, and the only one that pays off for the shipping core rather than
for this one.

## What a swap would still need

Beyond everything above: the `berr`, `int` and `nmi` pins `v60_biu` does not
have — System 32 raises interrupts, and the bus unit cannot receive one — plus
the MMU, the FPU, task and context switching, address traps and emulation mode.
`rtl/cpu/v60/s32_v60.sv` is 5,703 lines and executes the full integer ISA; this
tree is 4,600 lines and executes the integer two-operand instructions of
Formats I and II.
