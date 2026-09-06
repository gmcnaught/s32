# Control flow: what the pages say, and the two things they do not

`v60_seq`'s second path — the one that ends by redirecting `v60_pfu` instead of
by writing a result. Every operation below is quoted from the Programmer's
Reference §7, which prints each instruction's operation as a line of
pseudo-code; the encodings are p. 3.293 (the formats) and pp. 3.296–3.299 (the
table), both already transcribed in `tools/v60x/insn_table.py`.

## The seven that are implemented

| | operation, as §7 prints it | format |
|---|---|---|
| `Bcc` | `if condition then PC <- PC + sign_extended( disp ) else PC <- NextPC` | IV |
| `BSR` | `[-SP] <- NextPC ; PC <- PC + sign_extended( disp16 )` | IV |
| `JMP` | `PC <- target` | III |
| `JSR` | `temp <- target ; [-SP] <- NextPC ; PC <- temp` | III |
| `RSR` | `PC <- [SP+]` | VII |
| `DBcc` | `Rn <- Rn - 1 ; if ( condition and Rn != 0 ) then PC <- PC + sign_extended( disp16 )` | VI |
| `TB` | `if Rn = 0 then PC <- PC + sign_extended( disp16 )` | VI |

Five things in that table are load-bearing and none of them is a guess:

**Which PC a displacement is measured from.** Bcc's page says it outright: "the
value of the PC used to compute the target address is the first byte of the
branch instruction". That is `v60_idu.insn_pc` — the same PC a PC-relative
operand is relative to (§3: "the memory address of the first byte of the
instruction currently being executed") — and *not* NextPC. The two differ by
the instruction's length, so a bench that only ever branched backwards by a
multiple of that length would not tell them apart; the loop in `tb_v60_seq`
branches back five bytes over a four-byte instruction.

**What gets pushed.** NextPC, which is `insn_pc + insn_len`, and `v60_idu`
measures that length rather than assuming it.

**The push and the pop are addressing modes.** `[-SP]` and `[SP+]` are the
autodecrement and autoincrement modes on R31, so BSR and RSR go through
`v60_ea` like any other operand: the address arithmetic, the register
writeback and the bus cycles are the ones p. 3.261 and p. 3.236 already
specify, and a word push costs two bus cycles on a sixteen-bit bus.

**JMP and JSR want the address, not the operand.** §7: "the effective address
of the destination is computed and program control is transferred". Their
operand's own access never happens, which is why `v60_ea` has `addr_only`. The
page also settles the size question that raises — "the destination operand is
treated as byte data for the purpose of computing pointer changes for the
autoincrement, autodecrement, or scaled indexed addressing modes" — so the
operand's length is one byte, and `jmp [R1+]` steps R1 by one.

**JSR computes before it pushes.** `temp <- target` comes first in the line,
which matters exactly when the operand itself touches the stack.

**DBcc's condition is split across the encoding.** Format VI's base word is
`opcode(7) c0 | subop(3) reg(5)`, so the condition's low bit rides in the
opcode byte and its other three are the subop. `TB` occupies the subop that
would spell condition 1011 — "False", the branch that never branches — which is
what makes `C7` a shared encoding rather than a collision, and
`tools/v60x/insn_table.py` records it as one.

## The operand modes JMP, JSR and CALL may not use

`JMP`, `JSR` and `CALL` are given their operand's effective **address**, never
its value — `target.b.ex`, and `CALL`'s `arg` the same way — so a mode that
names no address cannot be one of theirs. All three §7 pages say so in the same
column, and all three mark the same three rows `X`:

| page | operand | `Rn` | `Immediate` | `Immediate.Quick` |
|---|---|---|---|---|
| 7-50 `JMP` | `target` | X | X | X |
| 7-51 `JSR` | `target` | X | X | X |
| 7-15 `CALL` | `target` **and** `arg` | X | X | X |

`RET`, `RETIU`, `RETIS`, `PUSH` and `PUSHM` carry no `X` at all — every mode is
legal for them, register direct included — so this is a property of the three
that take an address, not of control transfers generally.

**DEFECT, fixed 2026-09-06.** Nothing raised it, and it is audit item M1 in the
one other place the same question is asked. `MOVEA`'s `src.b.n` had exactly
this restriction, was found to be unenforced, and was fixed; the three control
transfers ask for an address the same way — four operand columns between them —
and were left. They failed the same way and for the same reason: `v60_ea`'s
reg-direct and immediate branches both
return `ea = 0` without consulting `addr_only`, and its `illegal` output is
driven from `we`, which an address-only access never sets — and `v60_top`
leaves that output unconnected anyway. So

- `jmp R5`, `jmp #addr`, `jsr R5` transferred to **address zero**, and
- `call target, Rn` did not even do that: it retired having done nothing at
  all, pushing nothing and leaving `AP` unwritten. A call that silently is not
  a call.

The check is `ctrl_mode_bad` in `v60_seq.sv`, raised in `S_CTRL` — the
transfer's first state, and the last one before the operand reaches the address
unit, which is where `MOVEA`'s sits relative to its own access.

**`S_CTRL` and not the decode state**, and that is load-bearing rather than
stylistic: `op2_mode` is the last field `v60_idu` latches and it is not settled
a cycle earlier. Placed in the decode state the check sees `JMP`'s and `JSR`'s
operand and `CALL`'s *target*, and misses `CALL`'s *argument* — a half-fix that
passes seven of the nine assertions. `tb_v60_seq` holds the argument case
separately for that reason, and the `no_call_arg` mutation is the one that
catches a regression to it.

## Deliberately not implemented

`CALL` and `RET` pass the argument pointer (`RET`: `tmp1 <- num ; tmp2 <- [SP+]
; AP <- [SP+] ; SP <- SP + tmp1 ; PC <- tmp2`). They are each other's partner
and neither is here; BSR and JSR pair with RSR, which is. `RETIU` and `RETIS`
restore the PSW as well as the PC and belong with `v60_exc`, which is not wired
in yet.

## The two things not from a page

Neither is architectural: no control-transfer semantics here were invented.
Both are decisions about the *sequencer's* structure, and both are visible
rather than silent.

- An addressing mode's register writeback (`[Rn+]`, `[-Rn]`) is retired from a
  single slot, so an instruction with two of them — `mov.w [R1+], [R2+]` —
  stops the sequencer with `STOP_TWO_WB` rather than dropping one. The V60
  executes that instruction; this sequencer says it cannot.
- The order the redirect reaches `v60_pfu` in: the sequencer asserts it in the
  same cycle it retires, so the queue is flushed before the next `idu_start`.
  The databook fixes the *effect* ("the instruction queue contents are flushed
  and a demand mode instruction fetch is made", p. 3.246) and not the cycle,
  and the bench holds it to the effect: the instruction after a taken branch is
  the one at the target, and the fall-through never executes.

## What the benches hold this to

`tb_v60_seq`'s third program is a running program rather than a list of cases:
a counted loop whose DBcc branches twice and falls through on the third pass,
a BSR/RSR subroutine, an unconditional branch over that subroutine's bytes, a
JSR through `[R10]` — register INDIRECT, which is legal, and not the register
direct mode the section above forbids — a TB taken and a TB not taken, and a
conditional branch that is not taken whose target is the *second* byte of the
instruction below it
— so a branch wrongly taken decodes garbage rather than landing somewhere
harmless. What ran, and in what order, is read back out of one byte of memory.

Nineteen mutations of the control path were run against it and all nineteen
fail the bench, including the two that only cost bus cycles: a JMP that reads
its operand, and a MOV that keeps a previous JMP's `addr_only`.

The illegal-operand-mode cases above are held separately, at 0x694 and 0x6A4,
with a legal `JMP [R10]` beside them so the check cannot pass by refusing every
control transfer that has an operand. Four mutations were run against those:
disabling the check, dropping its `CALL`-argument arm, dropping its immediate
arm, and moving it back to the decode state. Each fails exactly the assertions
it should and no others.

**The lockstep is not evidence here.** A 20-seed run after the fix reports the
same six divergence classes and no new one, and that is absence of coverage
rather than agreement: `verif/v60x/gen_lockstep_program.py` emits no control
transfer at all and no `MOV.D`, so neither fix is reachable from it. It is the
`NOT` carry lesson again — that generator's ALU pool did not contain `NOT`
either, and the 50-seed gate passed with and without the defect. `tb_v60_seq`
is the whole of the evidence for both fixes.

Two placement traps were fallen into writing them, and both present as a decode
bug rather than a placement one. The programs must sit **above** 0x680: the
level stack is 0x600 and the interrupt stack 0x680, both grow down, and the
exception frames these very tests push rewrite anything under them. They must
also avoid 0x6A0 and 0x6B0, which are `put_word` targets — data written at run
time, which a grep for `mem[11'h...]` does not show. The `CALL` at 0x69E read
0xDEADBEEF as its two mod fields and decoded a perfectly plausible
immediate-quick.
