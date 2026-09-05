# The shift group: SHL, SHA, ROT, ROTC

Four instructions, twelve opcodes, one shape. Everything below is from the
Programmer's Reference §7 pages for each of them; the opcodes are also in the
databook's table on p. 3.297.

| | left (count > 0) | right (count < 0) | opcodes `.b .h .w` |
|---|---|---|---|
| `SHL` | zeros in at the LSB | zeros in at the MSB | `A9 AB AD` |
| `SHA` | zeros in at the LSB | "the MSB being shifted into itself" | `B9 BB BD` |
| `ROT` | the MSB comes round to the LSB | the LSB comes round to the MSB | `89 8B 8D` |
| `ROTC` | the MSB goes through CY into the LSB | the LSB goes through CY into the MSB | `99 9B 9D` |

## What the pages fix

**The count is a signed byte, and it is the source operand.** The syntax lines
are `sha.b count.b.r, dst.b.rw`, `sha.h count.b.r, dst.h.rw`, `sha.w
count.b.r, dst.w.rw` — `.b` on the count in all three, `siz` on the
destination. So one instruction's two operands are at *different widths*,
which nothing else this tree executes does. "The shift count is specified as
signed byte data in a range from -128 to +127."

**A count of zero changes nothing and still sets the flags.** "The destination
will remain unchanged if a shift count of zero is specified but the flags will
be updated." CY is one of them, and the Condition Codes block says it is
*cleared* in that case — so `rotc` by zero clears the carry rather than leaving
it.

**A count past the operand's width.** "If the absolute value of the shift count
exceeds the destination operand length, zero (positive shift counts) or data
consisting of the sign of the destination (negative shift counts) is stored in
the destination" — SHA's page; SHL's says simply "zero is stored". The rotates
say nothing, because a rotate by more than the width is the same rotate
reduced: modulo the operand's width for `ROT`, and modulo the width **plus
one** for `ROTC`, whose rotated object is "the concatentation of the
destination operand and CY flag".

**Immediate quick counts are zero extended.** "If the immediate quick
addressing mode is specified for the count operand, the immediate data is zero
extended to byte length before its use as the shift count" — so a 4-bit
immediate is 0 to 15 and never negative.

## The flags

`SHL`, `ROT` and `ROTC` print the same block, with "rotated" for "shifted":

```
CY  Set if the last shifted bit was set, cleared if the last shifted bit
    was zero or the shift count was zero
OV  Cleared
S   Set if the MSB of the result is set, otherwise cleared
Z   Set if the result is zero, otherwise cleared
```

`SHA` differs in two: `OV  Set if integer overflow occurs, otherwise cleared`,
with the Description saying what that means — "integer overflow occurs if the
sign of the result changes at anytime during the execution of this
instruction" — and `S  Set if the result is negative`, which is the same bit
said the other way.

"The last shifted bit" is the last one to leave: for a left shift the last bit
to cross the MSB, for a right shift the last to cross the LSB. Past the
operand's width it is a zero for a logical shift and the sign for an
arithmetic right one, because those are what is being shifted out by then.

## How this is implemented, and how it is checked

`v60_alu` does all four with barrel shifts: the value in the low half of a
64-bit word for a left shift so that what crosses bit `nbits` is the last bit
out, and in the high half for a right shift so that what crosses bit 31 is.
The rotates duplicate the operand and take a window of it. `ROTC`'s modulus is
`nbits + 1`, which is not a power of two, so it is reduced by repeated
subtraction rather than by masking.

`tb_v60_alu` checks it against a model that does what the Description sentences
literally say — **one bit per iteration**, keeping the last bit to leave and
testing the sign after every step — over three widths, four operations, counts
from -34 to +34, twelve values chosen for their edges and both states of the
incoming carry. That is 132,135 checks, and the two formulations have nothing
in common but the page.

## What using them turned up

The instruction table had the shift group's two operand widths **the wrong way
round** — `('siz', 1)`, the count taking the size field and the destination
fixed at a byte, where the syntax lines say the opposite. Nothing noticed
while nothing executed them: the widths only reach the bus when an operand is
addressed. It is `(1, 'siz')` now, and `tb_v60_seq` executes a `shl.w` whose
one-byte immediate would be four bytes under the old reading — which moves
every following instruction, so the program counter says so.
