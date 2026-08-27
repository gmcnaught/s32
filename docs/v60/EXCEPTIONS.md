# Exceptions: the vectors, the codes, and the frame

What `v60_seq` raises and `v60_exc` takes, and where each number came from.
The three sources are all in the Programmer's Reference §8: Figure 8-2 (the
system base table's layout), the exception-code table in the same section, and
Table 8-1's frame diagrams.

## The vector is the offset over four

Figure 8-2 prints the SBT as offsets from SBR, and `v60_exc` reads the entry at
`SBR + 4 × vector`, so the vector is the printed offset over four. The entries
this tree can reach:

| offset | exception | vector | code |
|---|---|---|---|
| `+64` | Reserved Opcode | 16 | `1000` |
| `+68` | Privileged Instruction | 17 | `1100` |
| `+72` | Reserved Addressing Mode | 18 | `1200` |
| `+76` | Illegal Addressing Mode | 19 | `1300` |
| `+80` | Illegal Data Field | 20 | `1400` |
| `+84` | Integer Arithmetic | 21 | — |

The codes are the "Instruction Exceptions" rows of the exception-code table,
which prints its names and its codes in two separate columns:

```
reserved instruction        1000
privileged instruction      1100
reserved address mode       1200
illegal addressing mode     1300
illegal instruction format  1301
illegal data field          1400
```

Two of those rows are worth noticing. "Reserved instruction" is the name the
code table uses for what Figure 8-2 calls the Reserved *Opcode* Exception —
one exception, two names. And "illegal instruction format" has its own code
(`1301`) but no separate SBT entry: it shares vector 19 with the illegal
addressing mode.

Vector 21's row has no code in that table because the Integer Arithmetic
Exception's codes are in the Arithmetic Exceptions group (`integer zero
divide`, `integer overflow`), and BRKV's own page confirms the vector
independently: "PC ← [ Exception Vector 21 ]", against Figure 8-2's `+84`.
84 = 4 × 21, so the two pages check each other.

## The frame

Table 8-1 draws one frame per exception group. The Instruction Exceptions
group — vectors 16 to 20 — is:

```
   +8    Exception Code  |  Parameter Count = 4
   +4    PSW
    0    PC (Current PC)
```

**The code and the count share one word.** Both books draw the exception frame
under a `31 ... 0` ruler with a row that reads `Exception Code   Parameter
Count` — Figure 8-3 in the Reference and the same figure in the databook at
p. 3.269 — so that is one 32-bit word with the code in the high half and the
count in the low half, not two words and not the code alone. Every exception
code in the table is four hex digits, which is exactly the high half.

Three more things follow from that diagram and none of them is inferred:

- **The count includes that word.** "The parameter count indicates the number
  of bytes of exception information in addition to the PC and PSW", the
  Instruction Exceptions group prints 4 and has nothing above the code word,
  and the Change Execution Level group prints 8 and has one `Parameter` word
  above it. So the count is `4 × (parameter words + 1)`.
- **The Current PC**, not the Next PC: "an exception during the execution of an
  instruction stacks the PC of the instruction causing the exception (Current
  PC)", and the diagram says so again. The Change Execution Level frames, by
  contrast, print "PC (Next PC)".
- **The order.** The frame grows downward with the PC on top, which is the
  order BRKV's operation prints as pseudo-code: `[-SP] ← CurrentPC ; [-SP] ←
  Exception Code ; [-SP] ← PSW ; [-SP] ← NextPC`. So the parameters go down
  first, then the code word, then the PSW, then the return PC — the code word
  is always the one under the PSW, whatever else is below it.
- **An interrupt has neither.** Figure 8-3 draws the interrupt stack format
  beside the exception one as the PSW and the PC and nothing else: no code
  word, no parameters. `v60_exc` takes `nparams` as the words *above* the code
  word, forces it to zero for an interrupt, and says so if a caller asks for
  parameters on one.

## The recognition sequence, and a scan defect worth knowing about

Both books print the eight steps an exception performs. The Programmer's
Reference's copy loses three digits to the scan — `PSW.TP <- `, `PSW.AE <- `
and `PSW.EM <- (native mode)` with nothing between the arrow and the
parenthesis — and the databook's second printing of the same sequence
(pp. 3.269–3.270) has all of them:

```
  (i)    PSW.EL <- 00        (CHLVL or an ATT sets the specified level instead)
  (ii)   interrupt: PSW.IE <- 0 ;  exception: unchanged
         (bus error and stack invalid exceptions disable interrupts)
  (iii)  PSW.TE <- 0 ; PSW.TP <- 0 ; PSW.AE <- 0
  (iv)   PSW.EM <- 0 (native mode)
  (v)    PSW.ASA <- 1        (if an ATT occurs then AST are enabled)
  (vi)   temp <- SBT[ vector ]
  (vii)  interrupt: IS (interrupt stack)
         exception: L0SP (IS if the previous stack was the interrupt stack,
                    or LnSP if a change execution level or ATT exception)
  (viii) PC <- temp
```

So a handler starts with tracing off, no trace pending, address traps off, in
native mode, and with asynchronous system traps held off — "an asynchronous
system trap will be disregarded while the PSW.ASA field indicates an earlier
AST is being serviced", so setting ASA is what stops one nesting inside the
handler. `v60_exc` sets all five, and `tb_v60_exc` starts each of them the
other way round so every one has to move.

The lesson is not about these five bits: when a page in one book is illegible,
**look for the same material in the other one before deciding it cannot be
read**. Three of these were recorded as unread for exactly as long as it took
to check the second printing.

## Which stack

Step (vii) above says it exactly: an interrupt's frame goes on the interrupt
stack, and an exception's on `L0SP` — "IS if the previous stack was the
interrupt stack". The frame goes on the stack the handler will run with, so
`v60_seq` asks the register file to switch R31 *before* `v60_exc` pushes
anything, with the new level 0 and the interrupt-stack flag carried over,
which is what selects `L0SP` or `IS` respectively. `v60_regfile` already implements that switch —
save into the entry the old `{IS, EL}` names, load from the entry the new one
does — and a switch to the same entry is a no-op there, which is the ordinary
case in this tree: it runs at execution level 0 and these exceptions handle at
execution level 0.

## What is not covered, and where it is covered instead

The PSW the handler runs with is not observable from `tb_v60_seq`. `v60_exc`
computes it and this sequencer runs at execution level 0 already, so for these
three exceptions the new PSW equals the old one and a sequencer that ignored
it would behave identically. `tb_v60_exc` holds that claim directly: it drives
execution level 3, an interrupt and a bus-error-style disable, and checks the
PSW that comes back each time. Nothing reachable from reset in this tree sets
the execution level to anything but 0 — there is no LDPSW, no task switch, and
`RETIU`/`RETIS` are not implemented — so this is a gap in what the tree can
*reach*, not one in what the bench bothers to check.
