# The 120 plates, read against the clean room

**Run 2026-09-07**, after `docs/reference` moved from `308e881` to `86921c1`
and brought the adjudicated docling extract with it.

The point of this pass is that the Programmer's Reference is now
*machine-readable*. `NEC_V60_ProgrammersRef_1986_docling.instructions.json`
carries 120 instruction plates with, per field, a `from` saying how the value
was obtained — `ocr`, `ink`, `normalised`, `reviewed`, or `unresolved`. That
turns "read the pages against the RTL" from a reading exercise into a diff, and
a diff can be run again.

Two columns were diffed: the **Addressing Modes** table and the **Condition
Codes** block. A third, **Opcode**, was diffed as a control.

## What is in range

The core does not implement all 120. `tools/v60x/insn_table.py`'s `EXEC_OP` maps
71 mnemonics to a `v60_alu`/`v60_muldiv` operation and `CTRL_OP` maps 11 more to
a control transfer; everything else reaches `S_EXEC`, gets `ALU_NONE` from
`op_alu_all()` and stops with `STOP_NO_ALU`. An instruction that stops cannot
have a wrong flag or accept a wrong mode, so the bit string group, the character
string group and the MMU instructions are out of range here — not audited and
not defective, just absent. They are listed under "Not in range" below so the
next pass does not re-derive it.

## Opcode: the control

226 syntax rows carry an opcode. Expanded against the table's own patterns,
**203 agree exactly** and the remaining 23 all resolve without touching the RTL:

- 18 are naming, not encoding — the plate's `andnbsu`/`andnbsd` against the
  table's one `ANDNBS` row over `0001001{d}`, and the same for `CMPBF`, `MOVC`,
  `MOVCF`, `SKPC`. Same bytes, one row instead of two.
- `cvt.ls` at `5F-08` is the table's `CVTF`, which is the encoding the databook
  summary omits and §7 supplies. Same byte, different name.
- DBcc `C6·x/C7·x` and TB `C7·5` are the table's `C6`/`C7` without a subop,
  which `SHARED_ENCODINGS` already records as the one legitimately shared
  encoding, told apart by the subop field.
- IN's three are the known `DISAGREEMENTS` entry, resolved in the databook's
  favour because the Reference prints OUT's opcodes on IN's page.

So the opcode column is not the problem, which is what makes the other two
columns worth reading.

## Condition Codes: no defect

All four integer flags were classified for all 120 plates and diffed against
`v60_alu.sv`'s flag resolution — `keep_all`, `keep_but_ov`, `dec_op`,
`cmpbf_op`, `tasi_op`, `bit_op` and the default `{f_cy, f_ov, f_s, f_z}` — and
against `v60_muldiv.sv`'s. **No disagreement survived adjudication.** Five rows
looked like disagreements and all five were the extract, not the RTL:

| Row | What it looked like | What it was |
|---|---|---|
| CHLVL Z | prose neither Unchanged nor conditional | OCR: "Unchan**ğ**ed" |
| POPM ×4 | RTL keeps all four, plate does not say Unchanged | "Restored if list:31 is set" — and `S_PSM_WB` **does** restore the PSW's low halfword, so the RTL is right and the classifier was wrong |
| TEST1, CLR1 CY/Z | prose neither Unchanged nor conditional | the plate prints the *formula*, `← bit( base, offset )` and `← ~bit( base, offset )`, which is exactly `bit_op`'s two lines |
| DIVU OV | RTL reads `f_ov = r_divov`, plate says Cleared | `r_divov` is gated on `is_sgn`, which excludes DIVU, so it is constant 0 — cleared, as printed |

The one thing this pass wanted and did not find: my note
`v60-flag-audit-method` predicted OV was "the likeliest to turn something up",
because 15 pages say Cleared and the ALU's default is to clear. It turned up
nothing, because every instruction whose page says **OV Unchanged** is already
in `keep_all`, `bit_op` or `dec_op` — the 43 of them were checked one by one.
SHA's conditional OV, which the shipping core still lacks, is already correct
here (`sha_ov`).

## Addressing Modes: three defects, all one shape

The marks are `O` valid, `X` illegal, `Δ` reserved, `-` unavailable. Over the 95
plates in the `standard` family there are 275 `X` and 41 `Δ`. Almost all of the
`X` marks are one rule — an immediate cannot be a destination, 86 plates — which
the tree implements. What is left, on instructions the core actually executes,
is a short list, and three entries of it were not enforced.

All three are the same shape, and it is the shape audit item M1 (MOVEA) and
commit `656531b` (JMP/JSR/CALL) had:

> an operand that must name an **address** accepted a mode that has none, and
> nothing raised, because `v60_ea`'s reg-direct and immediate branches both
> return `ea = 0` and drive `illegal` from `we` — which a READ never sets.

### D1 — IN's port operand accepted an immediate

`in.b port.b.r, dst.b.w`. The port is the source, its I/O address is that
operand's effective address, and PgmRef 7-47 marks `Rn`, `Immediate` and
`Immediate.Quick` all `X`. `io_src_bad` named only the two register spellings.

`in.b #0x5B, R9` therefore issued **no I/O cycle at all** and loaded the literal
`0x5B` into R9. An IN that reads no input.

OUT was already covered and that is why the gap was easy to miss: its port is
the *destination*, so the general immediate-destination rule catches it. Only
the source side had no check.

### D2 — TEST1's base operand accepted an immediate

`test1 offset.w.r, base.w.r`. Its three siblings SET1, CLR1 and NOT1 print
`base.w.rw`, so they write their base and the immediate-destination rule catches
them. TEST1 is the only one of the four that reads its base — and the tree's
`dst_read_only` exemption, added so that `cmp src, #imm` and UPDPSW's immediate
mask would execute, carried it past the check as well.

The exemption conflated two different questions. "Is this operand written?" and
"may an immediate stand here?" have the same answer for every other member of
that list — CMP's `src2`, TEST's `src`, UPDPSW's `mask`, TRAP's vector, LDPR's
`regID`, CHLVL's `arg` are all **values** — and the opposite answer for TEST1,
whose base is a bit string's **address**. PgmRef 7-113 marks both immediate rows
`X` exactly as 7-98 does for SET1.

`test1 #9, #0x12345678` tested bit 9 of the literal and set CY and Z from it,
with no bus cycle.

### D3 — the bit field group's base accepted a register, and an immediate

`bsrc` is a bit address. The family's mode column is a different vocabulary —
`@[Rn]`, `offset@[Rn]`, `Rx@/addr` — in which the plain `Rn` row and both
immediate rows are marked `X`. **Five plates print that column and all five
agree**: 7-23 (CMPBF), 7-41 (EXTBF), 7-49 (INSBF), 7-94 and 7-95 (SCH0BS and
SCH1BS, which this tree does not implement). That is five independent readings
of the same rule, which is why it is acted on despite every mark being `ocr`.

The group is not consistent about *which* operand its base is — EXTBF's and
CMPBF's is the first, INSBF's is the second, which is what `bf_src_is_bit` and
`bf_dst_is_bit` already say — so the check is asked on both sides. A check on
one side alone passes the other, and the bench holds both cases for that reason.

INSBF's *immediate* base was already caught, because it writes its base. Its
**register** base was not: `dst_is_reg` is false for a Format VIIc operand, so
`op2_mode == AM_RN` went to `v60_ea`'s reg-direct branch and the field was
inserted into a register the instruction never names as a bit string.

## Not in range, and why

- **Bit string** (ANDBS, ANDNBS, ORBS, ORNBS, XORBS, XORNBS, MOVBS, NOTBS,
  SCH0BS, SCH1BS) and **character string** (MOVC, MOVCF, MOVCS, CMPC, CMPCF,
  CMPCS, SKPC) — `STOP_NO_ALU`.
- **MMU and task** (GETATE, GETPTE, UPDATE, UPDPTE, LDTASK, STTASK, CLRTLB,
  CLRTLBA) — same.
- **UPDPSW** — the extract's one `review_required` entry: its plate has no
  condition-code strip and no flag prose. Nothing to diff. The tree writes the
  whole PSW under the mask and does not go through the flag path at all.
- Two pages the extract declined to type (PDF 16 and 94), both outside chapter 7.

## Open, and deliberately not acted on

**CAXI's direction bit.** `caxi Rn.w.rw, dst.w.rwi` is Format I only, and its
page says "this instruction is not allowed to use Format II and furthermore, the
Format I direction field must be zero". The table has it as Format I, but
nothing checks `d`. With `d = 1` the operands invert. This was left alone
because the page states a *constraint* without naming an exception, and the
architecture's vocabulary for that — Illegal Addressing Mode, Reserved
Addressing Mode, Reserved Instruction — is not interchangeable. Inventing one
would be a decision dressed as a transcription. The addressing-mode column
reaches the same restriction from the other side, marking every mode but `Rn`
as `X` for the src, and the syntax line literally prints `Rn` — so the
constraint is real; only its consequence is unstated.

**XCH's format.** The same shape, already recorded as a `DISAGREEMENTS` entry:
the databook prints "I, II" and the Reference prints Format I.
