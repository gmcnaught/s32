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

## 1. Control flow — **done**, except two pairs

Landed. `Bcc`, `BSR`, `JMP`, `JSR`, `RSR`, `DBcc` and `TB` execute in
`v60_seq` and drive `v60_pfu.redirect`; `tb_v60_seq`'s third program is a
counted loop, two subroutine calls and returns, a jump through a register, a TB
taken and not taken, and a conditional branch that is not taken. Nineteen
mutations of that path are caught. The pages it rests on, and the two decisions
it forced, are `docs/v60/CONTROL-FLOW.md`.

Still open in the group, and neither is a branch:

- **`CALL` and `RET`**, which pass the argument pointer: `tmp1 <- num ; tmp2 <-
  [SP+] ; AP <- [SP+] ; SP <- SP + tmp1 ; PC <- tmp2` (RET, §7). They are each
  other's partner, so they land together.
- **`RETIU` and `RETIS`**, which restore the PSW as well as the PC. They pair
  with item 2 below.

Two defects in the already-benched code came out of doing this, both now fixed
and both mutation-checked:

- An addressing mode's register writeback (`[Rn+]`, `[-Rn]`) was read only in
  the cycle the access *finished*, and `v60_ea` raises it when the access
  *starts*. Every mode that reached memory therefore lost its writeback; only
  register-direct operands, where the two coincide, worked. It is now taken
  wherever it appears, and an instruction carrying two of them stops with
  `STOP_TWO_WB` rather than dropping one.
- `ea_addr_only` was set by `JMP` and never cleared, so the *next* instruction
  computed its destination address and never wrote to it. Every field of the
  address descriptor is now set before an access starts.

## 2. Wire `v60_exc` in — **done**

Landed. `v60_seq` raises three of Table 8-1's Instruction Exceptions instead of
stopping on them — reserved opcode (vector 16), reserved addressing mode
(vector 18) and an immediate used as a destination (vector 19) — and
`v60_exc` takes them: the SBT read, the frame, the PSW, the redirect. The
vectors, codes and frame layout are `docs/v60/EXCEPTIONS.md`.

The structural change is the one the plan asked for: **`v60_dmux`, a mux above
`v60_dxu`**, not a third `v60_bus_arb` port, so `tb_v60_pfu`'s bus-ownership
proof is untouched. The two masters are never live at once, which makes the
mux's own behaviour invisible from `tb_v60_seq` — `tb_v60_dmux` holds it
directly, the way `tb_v60_am_decode` holds the encodings no FSM can reach.

A defect in `v60_exc` came out of using it, now fixed and covered: with a
single parameter word it pushed `param1` rather than `param0`, because the
first push was identified as "two left" rather than "none pushed yet".
`tb_v60_exc` had only ever asked for none or two.

What is still not raised anywhere: every exception that needs a pin (`berr`,
`int`, `nmi`), an MMU, or the trace and breakpoint machinery. And `RETIU` /
`RETIS`, which are how a handler would return.

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
