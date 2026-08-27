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
   +8    Exception Code
   +4    PSW                    parameter count 4
    0    PC (Current PC)
```

Three things follow from that diagram and none of them is inferred:

- **One parameter word**, the exception code. "The parameter count indicates
  the number of bytes of exception information in addition to the PC and PSW",
  so a count of 4 is one 32-bit word.
- **The Current PC**, not the Next PC: "an exception during the execution of an
  instruction stacks the PC of the instruction causing the exception (Current
  PC)", and the diagram says so again. The Change Execution Level frames, by
  contrast, print "PC (Next PC)".
- **The order.** The frame grows downward with the PC on top, which is the
  order BRKV's operation prints as pseudo-code: `[-SP] ← CurrentPC ; [-SP] ←
  Exception Code ; [-SP] ← PSW ; [-SP] ← NextPC`. `v60_exc` pushes parameters
  first, then the PSW, then the return PC.

## Which stack

"Following the acknowledgement of an interrupt, the PC and PSW are saved on
the interrupt stack and program control is transferred to the predesignated or
supplied vector at execution level 0." The frame goes on the stack the handler
will run with, so `v60_seq` asks the register file to switch R31 *before*
`v60_exc` pushes anything. `v60_regfile` already implements that switch —
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
