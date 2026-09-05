# MUL, MULU, DIV, DIVU, REM and REMU

What `v60_muldiv` implements, which sentence each rule is, and the two places
this parts company with MAME. The pages are the Programmer's Reference §7 pages
for the six instructions, the databook's instruction summary at p. 3.296 for
the encodings, and §8 plus Figure 8-5 for the exception one of them raises.

## The six operations

| | opcodes | operation | OV | S | Z | CY |
|---|---|---|---|---|---|---|
| `MUL` | `81`/`83`/`85` | `dst * src`, signed | the double-length product does not fit | result negative | result zero | unchanged |
| `MULU` | `91`/`93`/`95` | `dst * src`, unsigned | the product cannot fit | MSB of the result | result zero | unchanged |
| `DIV` | `A1`/`A3`/`A5` | `dst / src`, signed | the negative maximum divided by −1 | result negative | result zero | unchanged |
| `DIVU` | `B1`/`B3`/`B5` | `dst / src`, unsigned | **cleared** | result negative | result zero | unchanged |
| `REM` | `50`/`52`/`54` | `dst % src`, signed | **cleared** | result negative | result zero | unchanged |
| `REMU` | `51`/`53`/`55` | `dst % src`, unsigned | **cleared** | MSB of the result | result zero | unchanged |

The destination is the dividend and the source the divisor, which the syntax
lines fix: `div.b src.b.r, dst.b.rw` with the operation `dst / src`.

Three sentences are worth quoting because they are the ones that decide
behaviour rather than describe it:

- **`REM`** — "The sign of the remainder is the same as the sign of the
  dividend." Which is Verilog's `%` and C's, and is not the only convention a
  divider could have.
- **`REMU`** — "All operands are treated as unsigned data, however, the
  condition code flags are set as if the remainder is a signed value." So `S`
  is the remainder's top bit at the operand's width, exactly as everywhere
  else.
- **`DIV`** — "The destination will remain unchanged if an integer overflow or
  Zero Divide exception occurs." Two different things in one sentence: the
  overflow is a *flag* and the zero divide is an *exception*, and the
  destination survives both.

## A zero divide raises, and this is where MAME does not

`DIV`, `DIVU`, `REM` and `REMU` each print an `Exceptions` block whose only
entry is **Zero Divide**. Table 8-1 gives it code `1500` in the Arithmetic
Exceptions group, and Figure 8-2 puts the Integer Arithmetic Exception at
vector 21 — which BRKV's page confirms from the other end, "PC ← [ Exception
Vector 21 ]", and 84 = 4 × 21.

MAME does not trap. It leaves the destination alone, sets Z and S from it and
clears OV, and the Sega System 32 core inherits that verbatim — `s32_v60.sv`
carries the comment "MAME divide-by-zero: destination unchanged and no trap".
Three NEC statements against an emulator's omission, and this tree is built
from the documents, so it raises.

The frame is Figure 8-5's Arithmetic Exceptions frame, which is BRKV's
operation printed as a diagram:

```
   +12   PC (Current PC)
   +8    Exception Code  |  8
   +4    PSW
    0    PC (Next PC)
```

Two things about it are unlike the Instruction Exceptions: the Current PC is a
**parameter** above the code word rather than the return address, and the
return address on top is the **Next** PC. So a zero-divide handler returns past
the instruction that divided, and the destination it left alone stays alone.
The parameter count is 8 — `4 × (1 parameter + 1)` — so a handler returns with
`RETIS #8`, which is what `tb_v60_seq` does.

## MUL's overflow is a signed fit, and this is the other place

The page's test is whether "the double length intermediate product does \[not\]
fit within the precision of the destination operand". For a signed multiply
into a signed destination that is a **signed** fit: the half that is discarded
has to be the sign extension of the half that is kept.

MAME tests `(product >> width) != 0` on the signed product's bit pattern, which
is an *unsigned* fit test. It therefore reports overflow for `MUL.W -1, 1` — a
product that fits a signed word exactly. `MULU`'s page says "cannot fit", its
destination is unsigned, and there the two tests are the same one; the
divergence is `MUL`'s alone.

`tb_v60_muldiv` checks both readings at the case that separates them.

## What the exhaustive sweep found

Byte width is checked exhaustively — all 65,536 operand pairs for each of the
six, which is what `tb_v60_alu` does for ADD and SUB — and halfword and word at
their boundaries. 394,416 checks.

The byte sweep passed on the first run and the **word edges did not**, on eight
cases: a 64-bit accumulator drops the carry out of bit 63, and a shift-add
multiplier's running high half is 33 bits before the shift brings it back down.
`MULU.w 0xFFFFFFFE × 0x7FFFFFFF` reported `OV` clear on a product that needs 63
bits. The accumulator is 65 bits now.

That is the whole argument for making the byte width exhaustive and then
checking the word's boundaries anyway: the defect was invisible at the width
that was checked most.

## The divider's 33rd bit, and why it is unreachable

The same accumulator serves the restoring divider, and there the extra bit
**cannot be reached at these widths**. A 32-bit dividend gives a running
remainder that is a prefix of the dividend reduced by the divisor, so after `k`
of the 32 steps it is below `2^k`, and it can only be at or above `2^31` on the
last step — where there is no further shift.

The bit is carried anyway, because `DIVX` and `DIVUX` divide a doubleword and
reach it on every step. Rather than leave that as a comment, `v60_muldiv`
asserts it: a divide whose accumulator reaches bit 64 says so. The assertion is
silent across all 394,416 cases, which is what makes the argument checkable
instead of merely plausible.

## What is not here

`MULX`, `MULUX`, `DIVX` and `DIVUX`. Their destination is a doubleword — "a
register pair, low register first" (§3) — and nothing in this tree addresses
one: `v60_regfile` has `ra_pair` and no caller, and `v60_ea` warns when asked
for an eight-byte register-direct operand. That is `docs/v60/NEXT-STEPS.md`'s
own item, and it is a datapath change rather than an arithmetic one: `DIVX`
writes a quotient into the low word of its destination and a remainder into the
high word.

They are still decoded and addressed, and `v60_seq` stops on them with
`STOP_NO_ALU` rather than inventing an answer — which is what `tb_v60_seq`'s
`MULX #2, R8` checks.

## Why it iterates

A shift-add multiplier and a restoring divider, 32 steps each, over one
accumulator — the two algorithms have the same shape, which is why they share
it. Not because the databook says so: it says nothing about how long any
instruction takes and every cell of its Clocks column is blank
(`docs/v60/INSTRUCTION-TIMING.md`). It iterates because `*` and `/` on variable
32-bit operands are not something to hand a fitter, and because the sequencer
needs a busy/done handshake either way.
