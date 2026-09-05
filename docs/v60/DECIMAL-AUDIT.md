# The decimal group, audited against the pages

An independent check of `ADDDC`, `SUBDC`, `SUBRDC`, `CVTD.PZ` and `CVTD.ZP` at
commit `cbac86e`, against the Programmer's Reference and the databook plates,
done by someone who read the pages and did not write the code.

**One defect, and it is the finding the commit message got backwards.** The
arithmetic three's BCD check is *not* unreachable: it fires on **29,472 of the
131,072** `(src, dst, CY)` triples an `ADDDC` can be given, and the smallest
case is two bytes long. The rest of the group is in good shape — the adder is
exhaustively correct, the flag rule is right, the exception is right, and the
mask's absence is correctly reasoned and can be argued more strongly than
`docs/v60/DECIMAL.md` currently does.

Everything below was found by reading, and the two arithmetic findings were
then **confirmed by simulation** against `v60_alu` as committed, using a
throwaway bench in `/tmp` that instantiates the module read-only. No RTL was
changed and the mutation harness was not run.

`verif/v60x/run_v60x.sh` reports **34 passed, 0 failed** at this commit, so
every finding below is a case the existing tests do not catch.

Line numbers are as of `cbac86e`; the **construct** named beside each is the
durable reference.

Scope audited: `rtl/cpu/v60x/v60_alu.sv`, `v60_alu_pkg.sv`, `v60_seq.sv`,
`v60_op_pkg.sv`, `tools/v60x/insn_table.py`, `tools/v60x/gen_op_pkg.py`,
`verif/v60x/tb_v60_alu.sv`, `tb_v60_seq.sv`. The "checked and correct" list is
the coverage, itemised.

---

## Defect

### D1 — the BCD result check is reachable, and it catches an arbitrary subset of what §3 forbids

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_alu.sv:246` (`dec_res_hi`), `:248` (`dec_res_bad`) |
| **Construct** | `wire [3:0] dec_res_hi = dec_val / 8'd10;` and the `UNREACHABLE BY CONSTRUCTION` comment above `dec_res_bad` |
| **Page** | PgmRef §3, "Decimal Data Type"; §7 `ADDDC`/`SUBDC`/`SUBRDC` |
| **Verdict** | **defect** — in the reasoning and the documentation; the RTL's behaviour is half right by accident |

**The claim.** The commit message says the check is "UNREACHABLE BY
CONSTRUCTION … `dec_res` is valid BCD for every input, including an input whose
own nibbles are not. A mutation deleting this check passes every test, and no
test can be written that makes it fire." The same claim is in the code comment
at `:238`-`:245` and in `docs/v60/DECIMAL.md`.

**It is false.** Simulated against `v60_alu` as committed:

```
ADDDC  x=A0 y=A0 cy=0 -> result=a0 cy=1 dec_bad=1
SUBDC  x=00 y=A0 cy=0 -> result=a0 cy=0 dec_bad=1
SUBRDC x=A0 y=00 cy=0 -> result=a0 cy=0 dec_bad=1
```

**Failure scenario.** `adddc` with a source byte of `0xA0` and a destination
byte of `0xA0`, carry clear. `dec_res` comes out `0xA0`, whose high nibble is
not a digit, and `dec_bad` asserts — so `eff_writes` goes low, the destination
is left alone, and vector 23 is taken. A test *can* be written; the bench's
existing one simply picks a value that does not fire.

**Why, mechanically.** The adder converts to values, but the values are not
bounded by 99 when the input nibbles are not digits:

- `dec_xv = x[7:4]*10 + x[3:0]` reaches **165** for `x = 0xFF`, not 99.
- so `dec_val` — after the ±100 correction — can land anywhere in 0…255.
- `dec_res_hi = dec_val / 8'd10` is assigned to a **4-bit** wire. For
  `dec_val` in **100…159** the quotient is 10…15 and survives the truncation as
  a non-digit → `dec_bad` fires. For `dec_val` ≥ 160 the quotient is 16…25 and
  the truncation folds it back to 0…9 → **`dec_bad` stays low and the result is
  silently wrong**.

Exhaustively, over all 131,072 `(x, y, CY)` triples for `ADDDC`:

| | count |
|---|---:|
| `dec_bad` fires | **29,472** (22.5%) |
| at least one invalid input nibble, yet valid BCD out and no fault | **81,600** |

So the same class of illegal input is caught about a quarter of the time and
silently miscomputed the rest of the time, and which happens depends on the
magnitude rather than on anything architectural.

**What the pages actually require — this answers the question directly.** The
brief asks whether the page is describing a nibble-wise adder whose result can
genuinely be invalid. **It is not, and the group should be checking its
operands.** §3, "Decimal Data Type", states the rule as a property of the *data*
and not of any instruction:

> "When a nibble is expected to contain a digit, only the valid BCD values
> [0..9] can be specified. **Any other value will cause an illegal decimal
> format exception to occur.** There is no restriction on the contents of the
> zone field."

That is an **operand** rule, in the data-type section, and it applies to all
five. The per-instruction sentence — "Following the addition operation, the
result is checked to verify that a valid BCD representation exists in the
unmasked portion of the result" — is an *additional* check on the way out, and
it makes sense for hardware whose adder is nibble-wise and can produce a
non-digit from digits (a BCD adder without a decimal-adjust step does exactly
that). It does not replace §3.

Note also that the two conversions already follow §3: `dec_pz_bad` and
`dec_zp_bad` check their **source** nibbles. The arithmetic three are the only
three in the group that do not, and they are the three §3's sentence most
obviously covers.

**Recommended.** Add the operand check the §3 sentence requires —
`(x[7:4] > 9) || (x[3:0] > 9) || (y[7:4] > 9) || (y[3:0] > 9)` — which is total
where the result check is partial, and keep the result check as the page's own
extra rule. That also makes the reachability question moot: with invalid
operands rejected on the way in, the result check becomes genuinely unreachable
*and the claim that it is becomes true*.

**Documentation to correct with it.** The commit message, the comment at
`v60_alu.sv:238`-`:245`, `docs/v60/DECIMAL.md`'s account of the unreachable
check, and `verif/v60x/tb_v60_alu.sv`'s assertion "an input nibble of A does not
raise: the check is on the result, not the operands" — which is true of `0x1A +
0x00` and false of `0xA0 + 0xA0` two lines away.

---

## Decided silently

### S1 — the flags commit on a faulting decimal instruction, and nothing marks the choice

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:1972` (`S_RETIRE`), `:2060` (the `dec_fault` branch below it) |
| **Construct** | `psw <= psw_set_flags(psw, eff_flags);` precedes `else if (dec_fault)` |
| **Page** | §7, all five: "a Decimal Format exception will occur and the destination will remain unchanged" |
| **Verdict** | undecided by the pages; the RTL chooses and does not say so |

`S_RETIRE` writes the flags unconditionally at the top, then falls into the
chain that raises the fault. Simulated: `ADDDC` `0xA0 + 0xA0` with `Z` preset
gives `dec_bad = 1`, and `CY = 1` and `Z = 0` are committed anyway.

Every page in the group protects **the destination** and says nothing about the
flags. The zero divide beside it in the same `S_RETIRE` chain is not a
precedent: §8 explicitly says "A zero divide exception **sets the PSW.OV
flag**", so flags moving there is required rather than assumed.

**Concrete consequence.** The Arithmetic Exceptions frame carries the **Next**
PC, so a handler returns *past* the faulting instruction. A multi-byte decimal
chain whose middle byte faults therefore resumes with a `CY` computed from a
result that was discarded, and the next `ADDDC` consumes it — `CY` being an
input is the whole design of this group. Whether that is right is genuinely
open; that it was chosen is not recorded anywhere.

Everything else in this tree marks a decision at the point of decision — the
`CAXI` write, the `pat[3:0]` corruption, the mask itself. This one is the
exception.

---

## The four areas, and what I found in each

### 1. The decimal adder — **clean, exhaustively**

Checked by simulation over **all 60,000 valid-BCD cases**: every packed pair
`(0…99, 0…99)`, both carry-ins, all three operations, against an integer
reference computed independently of the RTL's expressions.

```
valid-BCD exhaustive: 60000 cases, 0 mismatches
```

That covers result, decimal carry-out and the absence of a spurious fault. The
boundaries the brief names, individually:

| case | result | CY | correct |
|---|---|---|---|
| `ADDDC` 99 + 99 + 1 | `0x99` | 1 | ✓ 199 → 99 carry |
| `SUBDC` 00 − 00 − 1 | `0x99` | 1 | ✓ −1 → 99 borrow |
| `SUBDC` 42 − 42 − 0 | `0x00` | **0** | ✓ exact zero, **no** borrow — and `Z` is left alone, which is the sticky rule working |
| `SUBDC` 42 − 42 − 1 | `0x99` | 1 | ✓ borrow |

**`SUBRDC`'s carry is the borrow of `src − dst`, not `dst − src`.** `dec_subr =
dec_xv − dec_yv − cy` with `x` = operand 1 = `src` and `y` = operand 2 = `dst`,
and `dec_cy_out = (dec_raw < 0)` selects `dec_subr` for that op. That matches
`dst ← src − dst − CY` and the Description's "The CY flag and destination
operand are subtracted from the source operand". The sign of the subtraction
and the sign of the borrow are the same quantity, so they cannot disagree.

The widths hold for legal inputs too: `dec_add` is 9 bits and tops out at
99+99+1 = 199; `dec_sub`/`dec_subr` are 9-bit signed with a range of −100…99.
(For *illegal* inputs they reach 331 and −166, which is D1's territory, not
this one's.)

### 2. `Z` on the conversions — **clean, and the carry clause is moot**

`dec_z_clear` transcribes the asymmetry exactly as printed: the arithmetic
three test `dec_res` **or** `dec_cy_out`; `CVTD.PZ` tests `x[7:0]`, its
**source**; `CVTD.ZP` tests `dec_zp`, its **destination**. Those are the three
Operation blocks verbatim.

**The carry clause cannot apply to the conversions, and it is moot rather than
arguable.** Three reasons, all from pages:

- Neither conversion's page has the Description sentence the clause comes from.
  The clause is `ADDDC`'s "If the result is non-zero **or a carry is
  generated**"; the conversions have no such sentence at all — their `Z` is
  defined only by the `if src = 0` / `if dst = 0` line in the Operation block.
- Neither can generate one. There is no addition in either: `.PZ` is an OR and
  a nibble crossing, `.ZP` is a nibble crossing.
- p. 3.297 prints `– – – •` on both rows against `• – – •` on the arithmetic
  three, so `CY` is Unchanged on the conversions — and `v60_alu.sv:731` enforces
  it, `if (dec_is_arith) flags_out[PSW_CY] = dec_cy_out`. A quantity that is
  architecturally Unchanged cannot be a clearing condition.

So the literal transcription is right and no reading was lost.

`Z` never being *set* is also right and is checked: `flags_out = flags_in` then
`if (dec_z_clear) flags_out[PSW_Z] = 1'b0` — one direction only.

### 3. The unreachable BCD check — **refuted; see D1**

### 4. The mask — **confirmed, and the argument can be made stronger**

The conclusion in `docs/v60/DECIMAL.md` stands: nothing in either book defines
the pattern's encoding. Re-checked exhaustively rather than by recall — every
occurrence of "mask" in both OCR texts was enumerated. Outside the four decimal
mentions already recorded, the only hits are the **Address Trap Mask
Registers** (`ADTMR0`/`ADTMR1`), the `OTM` operand-trap-mask flag, and
`UPDPSW`'s register-list "mask operand". None of them is this field.

The three places the brief asks about specifically:

- **§6's Format VII prose adds nothing.** Its field breakdown is written
  entirely in terms of the length — "bit 7 **r** … the length field contains the
  operand length … bits 6:0 **length** The length operand (0-127) or the
  register ID (0-31)". The pattern is admitted in one appended clause with no
  breakdown of its own.
- **p. 3.261 has nothing.** That plate is the scaling-constant table and the
  bit-addressing figure; it does not mention masks.
- **The `CVTD` Operation blocks constrain their own use only.**

**And here is the stronger argument, which DECIMAL.md does not currently
make.** The two uses cannot share one encoding, and this is demonstrable rather
than merely unproven. Under any "set bit = masked out" reading — the sense
`ADTMR` uses, "marks the corresponding bits … as *don't care*" — a `CVTD.PZ`
pattern of `0x30` would mask bits 5:4 and nothing else, which is not a nibble
and not a zone. But `0x30` is precisely the value `CVTD.PZ` needs, because it is
OR'd in *as* the ASCII zone. **The same byte value is contributed data in one
use and would be a two-bit mask in the other**, so no single interpretation
covers both, and the arithmetic three's meaning cannot be recovered from the
conversions'. That is a positive reason the gap is real, not just an absence.

Recommend adding that sentence to `docs/v60/DECIMAL.md`; the gap is
better-founded than the doc claims.

### 5. The exception — **clean**, with one untested path

- **Vector 23** — `VEC_DEC_ARITH = 8'd23`, off databook p. 3.270's SBT plate
  ("23 Decimal Arithmetic Exception").
- **Code `0x1780`** — off p. 3.272's Exception Codes plate ("1780 decimal
  format exception", last row of the Arithmetic block).
- **The frame is right for a decimal fault specifically.** Figure 8-5's
  Arithmetic Exceptions row-group heads `#21 Integer`, `#22 Floating Point` and
  `#23 Decimal Exceptions / Decimal Format` over **one** frame:
  `+12 PC (Current PC)` / `+8 Exception Code | 8` / `+4 PSW` /
  `PC (Next PC)`. `EK_ARITH` builds exactly that — `exc_param0 <= idu_pc`,
  `exc_nparams <= 2'd1`, `exc_ret_pc <= idu_pc + idu_len`.
- **The parameter and the count are both checked end to end.**
  `tb_v60_seq.sv` asserts `mem_word(13'h5F8) === 32'h1780_0008` — code `0x1780`
  in the high half and count **8** in the low half, which is
  `4 × (1 parameter + 1)` and what `RETIS #8` needs.

**`CVTD.PZ`'s destination-unchanged gating holds.** Traced, because this is the
one path where the destination is a *halfword* reached through the write-only
route rather than a read-modify-write:

1. `dst_write_only` now includes `ALU_CVTDPZ` (`v60_seq.sv:679`), so `S_OP2`
   takes the "written and not read" branch — the descriptor is set but **no
   access is started**.
2. `eff_writes = alu_writes && !dec_fault` (`:1186`) goes low on the fault.
3. `S_WB`'s `!eff_writes` branch finds `ea_rmw_pending` low — there is no open
   access to close, precisely because step 1 started none — and goes straight
   to `S_RETIRE`.

So no bus cycle is issued at all and the halfword destination is untouched.
Correct, and correct for a different reason from `CVTD.ZP`'s, whose byte
destination the bench does check (`mem[11'h700] === 8'hCC` after the fault).

**But there is no test for a faulting `CVTD.PZ`** — the end-to-end fault case
is `CVTD.ZP`'s zone mismatch. See W1.

---

## The bit-7 question: your decision is right, and better founded than "no page says"

You declined §6's register redirection for the pattern byte on the grounds that
it is defined in terms of the length operand; `s32_v60.sv` applies it anyway.
**The pages do not merely fail to extend it — one of them contradicts it.**

`CVTD.PZ`'s Operation block reads:

```
dst[7:0]   ← tmp[7:0]  ∨ pat[7:0]
dst[15:8]  ← tmp[15:8] ∨ pat[7:0]
```

`pat[7:0]` — **the whole byte, bit 7 included**, OR'd into the zoned result. If
bit 7 were the `r` mode bit it could not simultaneously be zone data, and a
pattern of `0xF0` — an entirely ordinary zone, EBCDIC's — would be
uninterpretable. The Operation block is a printed page saying bit 7 is data for
at least one of the five.

`v60_alu.sv:220` implements it that way (`dec_pz_lo = {4'd0, dec_x_hi} |
dec_pat`), so the RTL and the page agree and `s32_v60.sv` is the outlier.

Worth promoting in `docs/v60/DECIMAL.md` from "undefined by the documents" to
"contradicted for `CVTD.PZ`, and undefined for the arithmetic three".

---

## Weak tests and nits

### W1 — no faulting `CVTD.PZ`

The only end-to-end Decimal Format exception is `CVTD.ZP`'s zone mismatch. The
`CVTD.PZ` fault path is a **different mechanism** — a write-only halfword
destination that never starts an access, versus a byte destination — and it is
the one your brief singled out. A source byte of `0x5A` through the sequencer
would exercise it; the ALU bench already uses that value at unit level
(`tb_v60_alu.sv`, "a nibble of A is not a digit, and CVTD.PZ checks its
SOURCE"), so only the end-to-end half is missing.

### W2 — the ALU bench's invalid-input case is the one that does not fire

`x = 32'h1A; y = 32'h00;` gives `dec_val = 20`, comfortably inside 0…99, so it
cannot fire whatever the check does. The assertion beside it generalises from
that one point to "the check is on the result, not the operands", which D1
disproves. `x = 32'hA0; y = 32'hA0;` is two characters away and fires.

### N1 — `EXEC_OP_ESCAPE`'s comment does not describe its own keys

`tools/v60x/insn_table.py:612` says the decimal rows are "Keyed by (mnemonic,
0) because each has one sub-op of its own", but three of the five are keyed 1,
2 and 0. The **keys are correct** — `gen_op_pkg.py:155` looks up
`(mnemonic, s & 3)` where `s` is the sub-op byte, so `ADDDC` `0x00` → 0,
`SUBDC` `0x01` → 1, `SUBRDC` `0x02` → 2, `CVTD.PZ` `0x10` → 0, `CVTD.ZP`
`0x18` → 0. It is the explanation that is wrong, and misleadingly so: anyone
adding a sixth sub-op by following the comment would key it 0 and get a
`KeyError` or a silent miss.

---

## Checked and found nothing

Itemised, so "clean" means something.

- **The generated decode.** `v60_op_pkg.sv` gets `16'h5900/01/02/10/18` →
  `ALU_ADDDC/SUBDC/SUBRDC/CVTDPZ/CVTDZP`, and all five are `FMT_VIIC` — which
  is what p. 3.297 prints and what puts the extension byte in `op2_ext`, the
  third operand field, where `v60_seq.sv:1546` reads it. The same placement the
  bit field group's `INSBF` uses (`bf_ext_raw = fmt_viic ? op2_ext : op1_ext`).
- **Operand widths.** `op_data_bytes` gives `ADDDC`/`SUBDC`/`SUBRDC` (1, 1),
  `CVTD.PZ` (1, 2) and `CVTD.ZP` (2, 1), matching `DATA_TYPE`, the syntax lines
  `src.b.r, dst.b.rw` / `src.b.r, dst.h.w` / `src.h.r, dst.b.w`, and
  p. 3.261's Packed Decimal 1 / Unpacked Decimal 2.
- **`dec_pat_r` does not leak.** It is latched only on the `fmt_vii_dec` path,
  which is the same path every decimal instruction takes, and it is read only
  under a decimal `op` selector. Unlike `ea_lock` in
  `docs/v60/TRANCHE-TWO-AUDIT.md`, a stale value cannot reach a non-decimal
  instruction.
- **The nibble crossings, both directions.** `dec_pz = {dec_pz_hi, dec_pz_lo}`
  with `dec_pz_lo` from `x[7:4]` puts the packed byte's **high** digit in the
  halfword's **low** byte — the Operation block's `tmp[3:0] ← src[7:4]`, so a
  zoned string runs most-significant digit at the lowest address. `dec_zp =
  {x[3:0], x[11:8]}` is the exact inverse. Round trip checked at unit level:
  `0x59` → `0x3935` → `0x59`.
- **`CY` and the mask width.** `result = raw & mask` with `mask` from
  `opbytes`, which is 2 for `CVTD.PZ` and 1 for the other four — so the
  halfword result is not truncated and the byte results are.
- **`OV` and `S` never move**, on any of the five: `flags_out = flags_in` with
  only `PSW_CY` and `PSW_Z` touched. Matches both plate rows.
- **`CVTD.ZP`'s zone check is the only place in the group that raises for a
  well-formed digit position**, and it comes from the instruction rather than
  the data type — §3 says "There is no restriction on the contents of the zone
  field". `dec_zp_bad` compares both zones against `dec_pat[7:4]` and both
  digits against 9, which is the Operation block's two `if`s in order.
- **The fault is raised at `S_RETIRE`, after the addressing-mode writeback**,
  which is right for a Next-PC frame: the instruction completed, so an
  autoincrement stands even though the destination does not. That is the same
  split `docs/v60/TRANCHE-TWO-AUDIT.md` verified for `CHLVL`, applied the same
  way. (`S1` above is the part of it that is not settled.)
- **`writes` for the conversions.** Neither is forced to zero, so both write
  their destination on a clean run; both are in `dst_write_only`, so neither
  reads it first.
