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
JSR through a register, a TB taken and a TB not taken, and a conditional branch
that is not taken whose target is the *second* byte of the instruction below it
— so a branch wrongly taken decodes garbage rather than landing somewhere
harmless. What ran, and in what order, is read back out of one byte of memory.

Nineteen mutations of the control path were run against it and all nineteen
fail the bench, including the two that only cost bus cycles: a JMP that reads
its operand, and a MOV that keeps a previous JMP's `addr_only`.
