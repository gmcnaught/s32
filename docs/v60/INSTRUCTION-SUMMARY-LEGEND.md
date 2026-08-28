# The instruction summary's last column, decoded

The databook's instruction summary (pp. 3.296–3.299) has an `Exceptions` column
carrying bare numbers, and the legend for them is printed **once**, at the foot
of p. 3.299, under the Privileged Instructions block. Read off that plate:

| | exception |
|---|---|
| 1 | Illegal Addressing Mode |
| 2 | Illegal Data Type |
| 3 | Reserved Addressing Mode |
| 4 | Integer Zero Divide |
| 5 | Illegal Decimal Format |
| 6 | Floating Point Overflow |
| 7 | Floating Point Underflow |
| 8 | Floating Point Precision |
| 9 | Reserved Floating Point Operand |
| 10 | Invalid Floating Point Operation |
| 11 | Floating Point Zero Divide |
| 12 | Privileged Instruction |

That one table makes the summary's last column readable for every instruction
in the book, and it is a second source for things this tree had only from the
Programmer's Reference's per-instruction `Exceptions` blocks. Two immediate
cross-confirmations:

- **`DIV`, `DIVU`, `DIVX`, `DIVUX`, `REM`, `REMU` all carry `1, 4`** — Illegal
  Addressing Mode and **Integer Zero Divide**. The databook says, in its own
  summary, that a divide by zero raises. `docs/v60/MULTIPLY-DIVIDE.md` had that
  from the Reference's per-instruction blocks alone; this is the second book
  saying it, and it is the divergence from MAME that `v60_muldiv` implements.
- **`RETIS` carries `2, 12`** — Illegal Data Type and **Privileged
  Instruction**. `docs/v60/RETURN-PAIRS.md` established that `RETIS` is
  privileged and `RETIU` is not from the Reference's Exceptions blocks; the
  databook's summary says the same thing from the other side, and `RETIU`'s
  row (p. 3.298) carries no 12.

The same column also settles the flags for the multiplies and divides
independently of the Reference: p. 3.296 prints `DIVU`, `REM` and `REMU` with a
literal **`0`** in the OV column — "cleared", not "unchanged" — where `DIV`,
`MUL`, `MULU`, `MULX`, `MULUX`, `DIVX` and `DIVUX` print `•`. That is what
`v60_muldiv` implements.

## Everything in the Privileged Instructions block

p. 3.299 groups these under one heading, and every one of them carries `12`:

`LDPR` `STPR` `CLRTLB` `CLRTLBA` `GETATE` `UPDATE` `GETPTE` `UPDPTE` `GETRA`
`IN` `OUT` `LDTASK` `STTASK` `RETIS` `UPDPSW.W` `HALT`

So a sequencer that implements any of them owes it the execution-level check
that `v60_seq` already performs for `RETIS`: "programs executing at other
execution levels (levels 1, 2 and 3) are said to be non-privileged and attempts
to execute a privileged instruction will cause an exception" (PgmRef §6), which
is vector 17, code `1100`.

Note that `UPDPSW.H` is **not** in that block — it is on p. 3.298 under
Miscellaneous with no `12` — which matches p. 3.248's rule that "the lower
halfword is accessible to all programs ... the upper halfword ... can only be
modified by programs running at execution level 0".

## Encodings confirmed off the plates

Every opcode `tools/v60x/insn_table.py` carries for the instructions below was
checked against pp. 3.296 and 3.299 at 300 dpi and agrees. Recorded because the
next tranche of work is executing them, and it is worth knowing the table did
not need touching:

`XCH 01000siz1` · `MOVEA 01000siz0` · `RVBYT 00101100` · `RVBIT 00001000` ·
`INC 11011siz-` (III) · `DEC 11010siz-` (III) · `TEST 11110siz-` (III) ·
`SETF 01000111` · `LDPR 00010010` · `STPR 00000010` · `IN 00100siz0` ·
`OUT 00100siz1` · `UPDPSW.W 00010011` · `HALT 00000000` · `NOP 11001101` ·
`GETPSW 1111011-` · `UPDPSW.H 01001010` · `BRK 11001000` · `BRKV 11001001`

`TRAP` is the exception, and the table already records why: p. 3.298 prints
`1110100-` for it, which is `JSR`'s encoding on the same page, and the
Programmer's Reference gives `F8/F9`. p. 3.299 confirms `1111100-` is claimed
by nothing else — `STTASK` is `1111110-`, `CLRTLB` `1111111-`, `RETIS`
`1111101-` — so the Reference's reading stands and the databook's row is a
misprint.
