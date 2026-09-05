# The two cores in lockstep

`verif/v60x/tb_v60_lockstep.sv` puts the shipping core (`rtl/cpu/v60/s32_v60.sv`,
MAME's V60 in RTL) and the clean-room core (`rtl/cpu/v60x/v60_top.sv`, built
from the pages) on one program image, each with its own copy of memory, and
compares the general registers, the four integer flags and the PC after every
instruction. Neither is the oracle. Where they disagree the pages decide, and
`verif/v60x/lockstep_known.txt` records each adjudicated class with the page
that settles it. The runner fails on any class that file does not name.

```
bash verif/v60x/run_lockstep.sh 20        # Icarus; ~2 minutes for 20 seeds
```

`verif/v60x/gen_lockstep_program.py` writes the programs: forty-eight
*islands* per seed, each loading its operands from immediates, running one
instruction, storing the result and GETPSW, so a divergence in one island
does not leak into the next. The mix covers the integer two-operand group at
all three widths, register, immediate, quick-immediate, `[R8]` and
`disp.8[R8]` operands, the shift group with counts inside and beyond the
operand length in both directions, the extending moves, INC/DEC/TEST, NEG/NOT,
and MOV through memory. No control flow yet, no stack, no exceptions: the
generator avoids a zero divisor because neither side is given an SBT.

## First result, 2026-09-05

20 seeds, **6,249 instructions compared, 9 divergence classes, all
adjudicated**. It took four runs to get there, and the first three are the
point.

### Two defects in the clean-room, fixed

**Sub-word register writes zero-extended.** Every byte or halfword result
written to a register — `MOV.B`, `MOV.H`, `NEG.H`, `MULU.B`, `MOVZ.BH`,
`MOVT.WB`, and so on, 150 classes on the first run — came back with the
upper bits cleared, where the shipping core kept them. The Reference settles
it on p. 2-3: *"These access types are right justified within the register.
Only the lower portion of the register corresponding to the access type is
significant and the upper portion will remain unaffected."* `v60_regfile`
takes a byte-enable now and `v60_seq` derives it from the destination's
width. Nothing in `verif/v60x` had ever written a sub-word result into a
register whose upper bits were non-zero.

**The reset PSW.** `GETPSW` differed in bit 28 on every seed: the shipping
core starts with `PSW.IS` set, the clean-room did not. The databook prints
`00000000H` on p. 3.238 and `10000000H` on p. 3.282, and the clean-room had
taken the first. The Reference's §8 reset section prints `10000000H`. Two
pages against one: the processor comes out of reset on the interrupt stack.
`PSW_RESET` is `10000000H` now, `tb_v60_psw` asserts it, and `tb_v60_seq`'s
arming task places the level-stack state its programs assume, the way it
already placed `PSW.IE` by hand.

### Three divergences in the shipping core, page-backed, recorded

| opcode | instruction | field | the page | the shipping core |
|---|---|---|---|---|
| `38` `3A` `3C` | `NOT` | `CY` | "CY Unchanged, OV Cleared" (§7 NOT) | clears CY |
| `B9` `BB` `BD` | `SHA` | `CY`, `OV` | CY is the last bit shifted out, cleared for a zero count; OV if the sign changes *at any time during* the shift; a count beyond the length stores zero or the sign (§7 SHA) | both flags from the final result, and a different clamp |
| `81` `83` `85` | `MUL` | `OV` | a signed fit (§7 MUL, `docs/v60/MULTIPLY-DIVIDE.md`) | MAME's unsigned test |

These are stage 4 of `docs/v60/LANDING-PLAN.md`: one PR each into
`s32_v60.sv`, gated by the shipping suite, the 50-seed cosim and the
hardware detector games. `GETPSW`'s `R7` class is the same flag divergence
seen a second time through the register it copies the flags into, and is
listed as such.

### One encoding the generator does not emit

An immediate or absolute operand — the `111` group of the mod byte — is
printed by p. 3.294 with `m = 0` only. The clean-room decodes an `m = 1`
form of it as if `m` were 0 (a recorded decision in `v60_am_pkg`); the
shipping core reads it as something else entirely, and the first lockstep
run stopped on the first instruction because of it. What the encoding means
is not on the page, so the generator does not produce it. Worth knowing if a
game ever does.

## What it does not compare

`R31`, because the two cores are not given the same stack pointer and nothing
here uses the stack; PSW bits above the flags, because nothing here changes
them; timing of any kind. Memory is compared at the end over the result and
data areas, byte by byte, and the only bytes that differ are the stored
`GETPSW` words carrying the flag classes above.

## Next

- Control flow, the stack group and `PUSH`/`POP`, `CALL`/`RET`, in the
  generator, with an SBT placed on both sides so the exception classes —
  zero divide, and the `6B`/`7B` branches — can be compared rather than
  avoided.
- The same bench on game code. `tb_core_romboot`'s `+OPTRACE` and
  `tools/v60x/exposure.py` say which instructions a game executes; a
  lockstep on those programs needs the clean-room to speak to `s32_core`'s
  memory contract, which is the adapter stage 2 deferred.
