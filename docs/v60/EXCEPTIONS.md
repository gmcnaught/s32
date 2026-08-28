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
| `+8` | Non-Maskable Interrupt | 2 | — |
| `+12` | Serious System Fault (bus error) | 3 | `0300`–`031E` |
| `+16` | System Fault (invalid interrupt) | 4 | `0400` |
| `+64` | Reserved Opcode | 16 | `1000` |
| `+68` | Privileged Instruction | 17 | `1100` |
| `+72` | Reserved Addressing Mode | 18 | `1200` |
| `+76` | Illegal Addressing Mode | 19 | `1300` |
| `+80` | Illegal Data Field | 20 | `1400` |
| `+84` | Integer Arithmetic | 21 | `1500` zero divide |
| `+256`–`+1020` | Application Interrupt Vectors | 64–255 | — |

### The low end of that figure, and why it needs the plate

The first three rows above are the part of Figure 8-2 that cannot be taken from
either book's OCR. Both extracts render the low end of the table as a bare run
of names and a bare run of offsets in separate columns, and one dropped row
shifts every vector in the group by one. The rows were read off the **plate**
at databook p. 3.270, which prints the vector NUMBER in its own column beside
the offset — so the plate is self-checking where the OCR is not:

```
  vector   name                       offset
    7      Stack Invalid Exception     +28
    6      RFU                         +24
    5      RFU                         +20
    4      System Fault                +16
    3      Serious System Fault        +12
    2      Non-Maskable Interrupt      +8
    1      Bus Freeze                  +4
    0      RFU                         (SBR)
```

The Programmer's Reference's Figure 8-2 prints the same rows as name/offset
pairs and agrees: NMI at `+8`, the Serious System Fault at `+12`. Two books,
two independent renderings, and 4 × 2 = 8 and 4 × 3 = 12.

**A correction, because it was written down wrong before it was read.**
`docs/v60/GOALS.md` set this work going with "NMI\* ... its SBT entry is +12, so
vector 3". It is not: `+12` is the Serious System Fault, which is where a bus
error goes, and NMI is `+8`, vector 2. The goal text also told whoever picked
it up to check the plate before using the low end, which is what turned it up.

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

## The three frames the externally raised conditions use

Figure 8-5 draws one frame per group, and these three are not the Instruction
Exceptions' shape:

```
  #2 Non-Maskable Interrupt          #3 Bus Fault
  #64-255 Maskable Interrupts          (the exception address is physical)

     +4  PSW                            +12  Exception Address
      0  PC (Next PC)                    +8  Exception Code |  8
                                         +4  PSW
  #4 System Fault                         0  PC
     Invalid Interrupt

     +8  Exception Code |  4
     +4  PSW
      0  PC
```

Three things follow, and each is checked rather than assumed:

- **An interrupt stacks the Next PC**, where an instruction exception stacks
  the Current PC. Figure 8-5 says so on the row itself, and the difference is
  visible: the frame carries the address of the instruction that has *not* run.
- **The bus fault is the only frame in this tree with a parameter word above
  the code**, and its count is 8 — `4 × (1 parameter + 1)`. The word is "the
  physical address that generated the exception" (§8), which `v60_biu` reports
  with the fault as the failed cycle's `A23-A0`.
- **All three go on the interrupt stack.** Step (vii) of the recognition
  sequence covers the interrupts; §8's prose covers the other two, once per
  group — the serious system faults' "exception information is pushed onto the
  interrupt stack" and the system faults' "exception information is pushed on
  the interrupt stack". So `v60_exc` takes `int_stack` separately from
  `is_interrupt`, and sets `PSW.IS` for either.

### The bus error's code says which kind of cycle failed

Table 8-1's Serious System Exceptions group is thirteen codes, one per kind of
bus cycle — which is exactly what `MRQ` + `ST2-ST0` already carries, so the map
in `v60_seq` is the two tables laid against each other rather than a choice:

| code | cycle | | code | cycle |
|---|---|---|---|---|
| `0301` | string data write | | `0313` | fixed length data read |
| `0303` | fixed length data write | | `0314` | system base table read |
| `0305` | translation table write | | `0315` | translation table read |
| `0309` | string I/O write | | `0317` | instruction fetch |
| `030B` | fixed length I/O write | | `0319` | string I/O read |
| `0311` | string data read | | `031B` | fixed length I/O read |
| | | | `031E` | interrupt vector read |

A short path access "is substituted for a single mode data access" (p. 3.233),
so it takes the fixed length codes. There is no system base table *write* code,
and nothing writes one.

## A maskable interrupt's vector is not chosen by the processor

"If set, the µPD70616 will perform a pair of back-to-back interrupt
acknowledge cycles.  On the second interrupt acknowledge cycle, an 8-bit
interrupt vector is read from the external µPD71059 Interrupt Controller and
used as an offset into the System Base Table" (p. 3.237).

`v60_exc` makes both cycles through the same data unit as everything else, with
`BST_INTERRUPT_ACK` on the status pins. Their back-to-backness is not arranged
anywhere: that status code has `MRQ` = 1, so `v60_biu`'s own p. 3.291 rule puts
the three TI states between them.

The address the two cycles drive is **not on any page held here** — the
databook names the status code and says nothing about `A23-A0` during it — so
it is driven at zero and marked at the point of decision.

What comes back is checked before it is used, because §8 makes that a named
exception rather than a diagnostic: "An invalid interrupt exception occurs when
an external interrupt controller supplies a system base table vector in the
range of 0 to 63.  These interrupt/exception vectors are reserved for system
use and attempted use will result in an exception." So a vector under 64
becomes the System Fault — vector 4, code `0400`, and an *exception's* frame
rather than an interrupt's.

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

## The Arithmetic Exceptions frame is a different shape again

Figure 8-5 gives vector 21 the frame BRKV's operation prints:

```
   +12   PC (Current PC)
   +8    Exception Code  |  8
   +4    PSW
    0    PC (Next PC)
```

The Current PC is a **parameter** above the code word, and the return address
on top is the **Next** PC — the opposite way round from the Instruction
Exceptions, whose return address is the Current PC and which have no parameter
at all. So a zero-divide handler returns past the instruction that divided.
`docs/v60/MULTIPLY-DIVIDE.md` has the rest.

## The frame is popped by RETIS and RETIU

They are the other end of this. `v60_exc` pushes the return PC last, so it is on
top, which is the order `PC <- [SP+] ; PSW <- [SP+]` needs; and what is left
under them — the code word and any parameters — is discarded by the count
operand the handler supplies. That count is not read out of the frame by the
processor: the handler reads the frame's parameter-count field and passes it.
`docs/v60/RETURN-PAIRS.md` has the pages.

## What is still not raised, and why

- **A double bus error.** "When a bus error involves the interrupt stack or a
  second bus error occurs during the processing of the initial bus error, the
  situation is deemed unrecoverable and the processor will halt" (§8). Nothing
  in this tree halts, and `BST_MACHINE_FAULT` — which is what the databook says
  a fatal double bus error puts on the pins (p. 3.234) — is never issued. A
  second fault while `v60_exc` is pushing is reported like any other and raised
  again afterwards.
- **The bus freeze interrupt**, vector 1. `v60_biu` has no `BFREZ` pin.
- **NMI's own masking rule.** "Additional non-maskable interrupts will not be
  acknowledged until the processing of the first NMI completes and the RETIS
  instruction is executed" (p. 3.271). There is no RETIS.
- **A clean abort.** Figure 8-5 marks the bus fault "Abort", and what `v60_seq`
  does is abandon the instruction at the first access completion after the
  fault: it does not retire and its addressing-mode writeback is dropped, but a
  read-modify-write whose read had already completed still closes with its
  write, one bus cycle later. `v60_biu` acknowledges the failed cycle for the
  same reason — see `docs/v60/BUS-CYCLE-TIMING.md`.

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
