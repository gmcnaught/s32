# The two return pairs: CALL/RET and RETIU/RETIS

What `v60_seq`'s `S_STK_*` engine implements, and where each number came from.
`BSR` and `JSR` already paired with `RSR`; these are the other two pairs, and
`RETIU`/`RETIS` are the other end of `v60_exc` — they pop exactly the frame it
pushes.

The pages are the Programmer's Reference §7 pages for the four instructions,
the databook's instruction summary at pp. 3.298–3.299 for the encodings, and
p. 3.247 for which register is which.

## The four operations, as their own pages print them

```
CALL   tmp1 <- effective_address( target ) ; tmp2 <- effective_address( arg )
       [-SP] <- AP ; AP <- tmp2 ; [-SP] <- NextPC ; PC <- tmp1

RET    tmp1 <- num ; tmp2 <- [SP+] ; AP <- [SP+] ; SP <- SP + tmp1 ; PC <- tmp2

RETIS  PC <- [SP+] ; PSW <- [SP+] ; SP <- SP + count
RETIU  PC <- [SP+] ; PSW <- [SP+] ; SP <- SP + count
```

| | opcode | format | operand |
|---|---|---|---|
| `CALL` | `49` | II | `target.b.ex`, `arg.w.r` |
| `RET` | `E2`/`E3` | III | `num.w` |
| `RETIU` | `EA`/`EB` | III | `count.h.r` |
| `RETIS` | `FA`/`FB` | III | `count.h.r` |

Format III's `m` is bit 0 of the opcode, which is why three of the four print
as a pair.

## Three things the goal text got wrong, and what the pages say

`docs/v60/GOALS.md`'s Goal 2 set this work going. Three of its claims did not
survive reading the pages, and each was worth catching.

### The count is an operand, not something read out of the frame

The goal text said "the frame carries the parameter count they need, in the
same word as the exception code ... so read it off the frame rather than being
told". The processor does no such thing. Both pages print `retis count.h.r` and
`retiu count.h.r` — a halfword operand, read — and both Descriptions say the
count "allows the interrupt or exception handler to specify the number of bytes
to be automatically discarded from the stack".

§8's sentence — "the parameter count ... is used by exception handlers to
determine the number of bytes to discard from the stack following the
processing of the exception" — describes what the **handler** does with the
frame's count field: it reads it and passes it here. The two sentences fit
together exactly, and neither of them puts that read inside the processor.

`tb_v60_seq`'s bus-fault handler does it the way the pages describe: it points
a register at a count and executes `RETIS [R9]`.

### RETIU and RETIS differ by privilege, not by stack

The goal text said "the two differ in which stack they return to". They do not:
both pop from R31, and the PSW they restore is what selects the stack
afterwards — identically. Their Operation, Condition Codes and Addressing Modes
blocks are the same block twice.

The difference is one line of the Exceptions block. RETIS's begins

```
    Privileged Instruction
    Illegal Data Field
    Asynchronous System Trap
    Asynchronous Task Trap
```

and RETIU's begins at the second line. System against User, which is what the
two names say. "Programs executing at other execution levels (levels 1, 2 and
3) are said to be non-privileged and attempts to execute a privileged
instruction will cause an exception" (§6), so `RETIS` at any level but 0 is the
Privileged Instruction exception — vector 17, code `1100`.

### AP is R29

The goal text has it right and `docs/v60/NEXT-STEPS.md` had it wrong ("AP is R30
in the register file already"). RET's own Description settles it: "the return
address and argument pointer register (**R29**) are restored from the stack",
and the databook's p. 3.247 register assignment agrees — R29 AP, R30 FP,
R31 SP.

## A table defect the pages turned up

`tools/v60x/insn_table.py` gave `RETIU` and `RETIS` a **word** operand, from the
"the V60 stack moves words" reasoning that governs `PUSH` and `POP`. Their
operand is not a stack word. Both pages print a halfword, and MAME agrees
independently — `s32_v60.sv` drives `moddim = 1` for `EA/EB/FA/FB` against `2`
for `RET`'s `E2/E3`. Nothing could notice while nothing executed them; the
shift group's operand widths were wrong the same way for the same reason.

It is observable, and `tb_v60_seq` observes it: a halfword count read from an
even address costs **one** bus cycle where a word costs two.

## Illegal Data Field, and the clause that did not survive the scan

Both pages list it. RETIU's gives a condition:

> An Illegal Data Field exception will occur if the execution level field in the
> PSW is not \[ \] and the ISP flag is set or if an attempt is made to return to
> a more privileged execution level.

The digit after "is not" is gone in the copy held here, and the databook does
not reprint the page — so only the second clause is implemented: returning to a
numerically lower execution level, because "levels are numbered from 0 to 3
with level 0 being the most privileged" (§6). The first clause is recorded
unread rather than guessed at.

## One engine, three instructions

`S_STK_SP` through `S_STK_FIN3` is the shape all three share: read the stack
pointer, make two stack accesses, retire the addressing mode's own writeback,
then write two registers and redirect. Three properties of it are not
arbitrary:

- **The two register writes are two states**, because the register file has one
  write port and each of these instructions writes two registers — R29 and R31
  for `CALL` and `RET`, R31 and the PSW for the two RETIs.
- **The stack switch is a third state.** `rf_stack_switch` is a registered
  request that lands a cycle after it is made, and the register file saves R31
  into the entry the **old** PSW names — so R31 has to be finished before the
  switch, and the PSW has to still be the old one during it. This is the same
  ordering `S_EXC_SETTLE` exists for on the way in.
- **The stack accesses use `[Rn]` and not `[Rn+]`/`[-Rn]`.** The autoincrement
  modes would move R31 by four, and none of these instructions moves it by
  four: `RET` moves it by `8 + num` and the two RETIs by `8 + count`. The
  pointer is this module's to compute, so the accesses raise no
  addressing-mode writeback of their own and the one writeback slot stays free
  for the count operand's mode.

## What these still do not do

Both RETIs' pages say they check for the Asynchronous System Trap and the
Asynchronous Task Trap — "if a higher priority exception is detected,
processing will not return to the point of interruption but will instead be
vectored to the appropriate trap handler". There is no AST or ATT in this tree,
so there is nothing to check for.
