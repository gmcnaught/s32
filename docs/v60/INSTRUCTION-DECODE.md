# The opcode table, and the instruction decode unit

**Written 2026-08-27**, with `tools/v60x/insn_table.py`, `v60_op_pkg` and
`v60_idu`. This finishes what `docs/v60/INSTRUCTION-FORMATS.md` left open.

## The table

`tools/v60x/insn_table.py` is the instruction-set summary's opcode and
**Instruction Format** columns, databook pp. 3.296–3.299, as data: 134 rows,
which expand to **284 encodings**. `tools/v60x/gen_op_pkg.py` generates
`rtl/cpu/v60x/v60_op_pkg.sv` from it, and `run_v60x.sh` regenerates and diffs
before running anything, so a table edited without regenerating fails the bench
run rather than shipping an RTL that says something the table does not.

It is data rather than a hand-written case statement because the printed opcode
is a **pattern**. Placeholder fields stand for small tables on p. 3.295 — `siz`
(2 bits), `ext` (2), `cccc` (4), `s`, `c`, `d`, `b` and `-` (1 each) — so one
row is a family of up to sixteen byte values. `siz` and `ext` exclude their
reserved code, which is exactly what lets other instructions occupy those
slots, and they do: `TEST1` sits on `MUL`'s `siz`=11, `SET1` on `MULU`'s,
`CLR1` on `SHL`'s, `NOT1` on `SHA`'s.

### What the validation caught

Two instructions cannot share an encoding, so expanding the patterns and
checking for collisions finds transcription errors. It found four, and the
check is the only reason they are not in the RTL:

| | what happened |
|---|---|
| **SHL, SHA** | read off the page as `10100·siz·1` and `10110·siz·1`, which collide with `DIV` and `DIVU`. The operand-access CSV — compiled separately from the Programmer's Reference — gives `A9 AB AD` and `B9 BB BD`, i.e. `10101·siz·1` and `10111·siz·1`. One bit each, and the corrected values pair with `SUB` and `CMP` exactly as every other bit-0 pair does. |
| **TRAP** | the databook table prints `1110100-`, which is **JSR's encoding on the same page**. The Programmer's Reference §7 page for TRAP prints "Opcode F8/9". Taken from the Reference. |
| **MOVCS** | the databook prints `01011000`, a fixed byte; the Reference gives `58-0C` *and* `5A-0C`, so the `c` bit is live and the pattern is `010110·c·0`. |
| **DBcc, TB** | both are `C7`. Not an error: they are both Format VI and are told apart by the subop in the base word — the Reference prints TB's opcode as "C7-5". Recorded as a known shared encoding rather than silenced. |

66 of the rows can be cross-checked against
`docs/v60/v60_operand_access.csv`, whose `opcodes` column comes from the
Programmer's Reference. The check is that the two sets **intersect** — the CSV
lists whole groups for some mnemonics (all three `CHKA*` rows carry
`4D 4E 4F`), which is not a disagreement.

### Where the two NEC documents disagree

**IN and OUT.** The databook prints `IN` as `00100·siz·0` (20 22 24) and `OUT`
as `00100·siz·1`. The Programmer's Reference §7 page for `IN` prints "Opcode
21 23 25" — the other half of the pair. Neither is fixed against the other;
both are first-hand. Nothing in the RTL depends on it: both are Format I,II
either way, and the format is all `v60_op_pkg` reports.

### Format IV's displacement width

No longer an input. The Reference prints Bcc as "Branch on Condition (byte
displacement) **6x** / (halfword displacement) **7x**" — the same `b` bit the
databook shows at p. 3.295 — and BSR's syntax as "**bsr disp16**". Those are
the only two Format IV opcodes, so `op_iv_disp_bytes()` covers the format.

### Still unresolved

Three **subops** in the bit-string group (`ORNBS`, `XORNBS`, `SCH1BS`) could
not be read reliably off the scan and are recorded in `UNRESOLVED_SUBOP`. They
are placed where the group's numbering and the collision check allow. Their
**format** is not in doubt — the format column is a word, not a bit string, and
all of Bit String is VIIb — so nothing `v60_op_pkg` reports depends on them.
Resolving them needs a better scan or the Reference's own pages for those
instructions.

## The decode unit

> "The IDU (instruction decode unit) … examines the instruction for operand
> references and passes the operand addressing mode information to the logic
> performing the effective address calculation." — p. 3.246

`v60_idu` owns no format knowledge. It takes bytes from `v60_pfu` one at a
time and walks the plan `v60_fmt_decode` produces —
**base → mod → ext → mod' → ext'** — running `v60_am_decode` once per mod
field with that operand's own `m`, and reports two operand descriptions in the
shape `v60_ea` takes, the instruction's length, and the PC it started at.

`tb_v60_idu` runs the whole front end: `v60_biu` fetching from a two-bank
memory through `v60_bus_arb`, `v60_pfu` filling its queue, and the decoder
taking a ten-instruction program off that stream — all seven formats, both
extension fields, a reserved opcode, and one instruction whose `m` and `m'`
differ so that the same mod byte means different things to its two operands.

The property that no single instruction's checks can see is asserted across all
of them: **each instruction's PC is the previous one's PC plus its length.**
Boundaries that do not chain mean a byte was taken by the wrong stage.

## Boundaries

- **The operand data length is not decoded.** An immediate's width comes from
  the instruction's data type, which lives in the opcode's `siz` / `s` / `c`
  field and belongs to execution; `v60_idu` hands `v60_am_decode` four bytes
  until there is something to ask.
- **Which operand is source and which is destination** is semantics, not
  encoding. Format I carries a `d` bit for exactly that, and it is reported
  rather than acted on.
- **Nothing executes.** The decoder describes; `v60_ea` can already resolve
  what it describes.
