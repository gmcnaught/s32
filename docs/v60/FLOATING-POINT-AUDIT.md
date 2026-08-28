# The floating point three, audited against the pages

An independent check of `a84698c`, "MOVF, NEGF and ABSF — and the floating
point flags become live", against the Programmer's Reference and the databook
plates, done by someone who did not write the code. Research doc:
`docs/v60/FLOATING-POINT.md`.

**The audit is not clean.** One high-severity defect, one decision generalised
past its page, two weak tests — and **one finding that resolves the item-4
tension outright rather than leaving it open**, which is the most useful thing
here.

The resolution and the defect are the same page. §8's *Floating Point
Exceptions* section — which neither `FLOATING-POINT.md` nor the commit cites —
states that **every floating point exception is gated by a TKCW enable bit,
and that when the trap is disabled the flag is still set and execution
continues with a defined result**. That single mechanism makes MOVF's FIV
sentence reachable, explains why its Description lacks the trap sentence, and
makes the current unconditional trap wrong.

No RTL was changed and the mutation harness was not run. Line numbers are as
of `7594727` (`v60_fpu.sv`, `v60_seq.sv` and `tb_v60_alu.sv` are clean at that
commit; `tb_v60_seq.sv` is under edit); the **construct** named beside each is
the durable reference.

---

## Defects

### D1 — the reserved-operand trap is unconditional; §8 makes every FP exception TKCW-gated

| | |
|---|---|
| **Severity** | **High** — wrong control flow on a defined, reachable input |
| **File** | `rtl/cpu/v60x/v60_fpu.sv:129`, `:141`, `:156` (`resv_operand = is_nan \|\| is_inf`); consumed at `rtl/cpu/v60x/v60_seq.sv:1241` (`fp_resv`) and `:2144`–`:2150` |
| **Page** | Reference **§8, Floating Point Exceptions** (pp. 8-7/8-8) |
| **Verdict** | **defect** |

§8 states the mechanism four separate times, and it is the same mechanism each
time:

> **Floating Point Zero Divide** … The PSW.FZD flag will be set if a zero
> divide takes place. Floating point zero divide exceptions are **enabled by
> the TKCW.FZT bit. If this bit is set, then the exception will occur
> immediately and the destination will remain unchanged. If zero divide
> exceptions are disabled, an infinite result will be placed in the destination
> operand and program execution will continue.**

> **Floating Point Overflow / Underflow** … When floating point overflow
> occurs, the PSW.FOV flag is set. An overflow exception will occur immediately
> **if the TKCW.FOT bit is set** or will be **delayed** and an infinite result
> will be placed in the destination operand. When floating point underflow
> occurs, the PSW.FUD flag is set. An underflow exception will occur
> immediately **if the TKCW.FUT bit is set** or will be delayed and a denormal
> result will be placed in the destination operand.

> **\[Invalid operation\]** — **The PSW.FIV flag will be set as a result of an
> invalid operation. If the exception is enabled, the destination operand
> remains unchanged. If disabled, a QuietNaN is stored in the destination and
> execution continues.**

So the architecture's shape is: **the flag is set unconditionally; a TKCW bit
decides whether that becomes a trap; and when it does not, execution continues
with a stated result.** `TRAPFL`'s operation corroborates the enable field
from the other end — `if ( TKCW[8:4] ∧ PSW[12:8] ) ≠ 0` — and the bit
alignment is exact: `TKCW[8]↔PSW[12]=FIV`, `[7]↔FZD`, `[6]↔FOV`,
`[5]↔FUD`, `[4]↔FPR`, with §3's named `TKCW` bits confirming the two ends
(bit 4 `FPT` = precision ↔ FPR, bit 5 `FUT` = underflow ↔ FUD).

`v60_fpu` raises on the operand class alone, with no TKCW input at all — the
module has no `tkcw` port — and `v60_seq:2144`–`:2150` vectors on it unconditionally.

**Concrete failure scenario.** `TKCW` is `0x0000_0000` out of reset (databook
p. 3.238, "PSW 00000000H", and nothing in this tree writes `TKCW` except
`LDPR`), so every FP trap is disabled. Execute

```
movf.s [R10], R9      with the word at [R10] = 0x7FC0_0000   (a quiet NaN)
```

- **Architecturally:** FIV is set in `PSW[12]`, the NaN is stored in R9, and
  the instruction retires. A later `TRAPFL` — or a program that enables
  `TKCW[8]` — is what turns it into an exception.
- **This tree:** vector 22 is taken, `PSW` is left entirely unchanged (so FIV
  is *not* set), and R9 is not written.

`tb_v60_seq.sv:3806`–`:3815` asserts the current behaviour, so the suite locks
it in.

**Why this is the answer to item 4, not just a defect.** The brief asks whether
MOVF trapping is defensible given the tension that a trapping MOVF makes its
own FIV sentence — *"Set if the destination is a NaN or infinite, otherwise
unchanged"* — unreachable. Under §8 there is no tension:

- MOVF **sets FIV** on a NaN or infinite destination, always. Its sentence is
  reachable, and it is phrased as it is — naming NaN and infinity directly,
  where every other page in the group says "an invalid operation is attempted"
  — precisely because for MOVF the *destination's class* is the condition.
- MOVF's Exceptions block lists Reserved Floating Point Operand because with
  the enable set it does raise one.
- MOVF's Description omits the "the flags and destination will remain
  unchanged" sentence that `ADDF`, `ABSF` and `CMPF` carry because that
  sentence describes the *enabled* case, and MOVF's page simply does not
  restate it.

All three observations are satisfied at once. The decision as recorded —
"MOVF is treated like the other two" — is right about *what happens when the
trap is enabled* and wrong about it happening unconditionally.

**What a fix needs**, for information only: a `tkcw` input to `v60_fpu` (or the
gate in `v60_seq`), `resv_operand` qualified by `tkcw[8]`, and the
disabled path storing the value and committing the flags. §8 gives the stored
result for the *invalid operation* case ("a QuietNaN is stored") but **not**
for Reserved Floating Point Operand, whose paragraph says only "The
destination operand is unchanged as a result of this exception" — so the
disabled-path result for a NaN/infinity source is itself unsettled and would be
a new decision. That is worth knowing before starting.

### D2 — "the flags will remain unchanged" is generalised from one page to three

| | |
|---|---|
| **Severity** | **Medium** — over-broad flag suppression on two of the three |
| **File** | `rtl/cpu/v60x/v60_seq.sv:2094`–`:2101` (`else if (fp_resv) psw <= psw;`) |
| **Page** | Reference §7 `ABSF` / `MOVF` / `NEGF`; §8's Reserved FP Operand paragraph |
| **Verdict** | **defect (over-broad), or at minimum an unmarked decision** |

The comment says *"'the flags … will remain unchanged'. … When NEC wants the
flags preserved it says so in the same sentence, and here it does."* That is
true of exactly one of the three instructions.

- **`ABSF`** — carries it: *"If the source operand is a NaN or an infinity, a
  Reserved Floating Point Operand exception will occur and **the flags and
  destination** will remain unchanged."*
- **`MOVF`** — Description in full: *"The source operand is copied to the
  destination operand and the flags updated to reflect the state of the
  destination."* No NaN/infinity sentence at all.
- **`NEGF`** — Description in full: *"The negation of the source operand is
  stored in the destination operand. Both the integer and floating point
  condition codes are updated to reflect the result of the operation."* No
  NaN/infinity sentence at all.

And §8's own paragraph for this exception protects only the destination:

> A reserved floating point operand exception occurs when a NaN or infinity is
> used as the operand in an instruction. **The destination operand is unchanged
> as a result of this exception.**

— with the invalid-operation paragraph immediately above it saying the flag
**is** set first.

So `psw <= psw` is supported by a page for `ABSF` and by no page for `MOVF` and
`NEGF`. **Failure scenario:** `negf.s` of a NaN with `TKCW[8]` set should (on
§8's reading) leave the destination alone with `PSW.FIV` set; this tree leaves
`PSW` entirely untouched, so a handler cannot tell which flag caused the
trap — which is what `PSW[12:8]` is for, and what makes the `0x1680` code word
and the flag field agree.

This is subsumed by D1 in practice: fix the gating and the disabled path
commits the flags anyway. It is listed separately because the *enabled* path
still has to decide, and because the comment presents a one-page rule as a
three-page one.

---

## Weak tests

### W1 — `NEGF` and `ABSF` are never exercised at long-real width

| | |
|---|---|
| **File** | `verif/v60x/tb_v60_alu.sv:1046`–`:1073` |
| **Construct under test** | `v60_fpu.sv:90`–`:94` (`neg_res`, `abs_res`) |
| **Verdict** | **weak test** |

The long-real section sets `f_bytes = 4'd8` and then `op = ALU_MOVF`, and
**never changes `op` again**. Every double-precision assertion in the file is a
MOVF. So the `is_long` ternaries in

```
wire [63:0] neg_res = is_long ? {~a[63], a[62:0]} : {32'd0, ~a[31], a[30:0]};
wire [63:0] abs_res = is_long ? {1'b0,   a[62:0]} : {32'd0, 1'b0,   a[30:0]};
```

are untested for both operations. A mutation collapsing either to its
short-real arm returns a completely wrong 64-bit value for `negf.l` / `absf.l`
— the sign bit taken from bit 31 and the upper word zeroed — and the whole
suite still passes. `tb_v60_seq.sv` does not close the gap either: its FP
programs are `5C`-prefixed (short real) only.

This is the same class of gap the commit message says the bench was written to
close ("the bench proves the width is really an input by …"), and it does close
it — for MOVF.

**Exposing values.**

```
f_bytes = 4'd8;
op = ALU_NEGF; f_a = 64'h3FF0_0000_0000_0000;
#1 chk(f_res === 64'hBFF0_0000_0000_0000, "NEGF.l 1.0 gives -1.0 at double width");
op = ALU_ABSF; f_a = 64'hBFF0_0000_0000_0000;
#1 chk(f_res === 64'h3FF0_0000_0000_0000, "ABSF.l -1.0 gives 1.0 at double width");
```

### W2 — `NEGF` of a zero is untested, and it is the one input where its S and Z disagree with the source's

| | |
|---|---|
| **File** | `verif/v60x/tb_v60_alu.sv:1024`–`:1032` |
| **Construct under test** | `v60_fpu.sv:100` (`res_sign`) against `is_zero` |
| **Verdict** | **weak test** |

`res_sign` is the **result's** sign and `is_zero` is the **source's** class,
and for `NEGF` they are deliberately drawn from different values. The bench
tests `NEGF` at ±1.0 only, where `is_zero` is false and the interaction cannot
show. `NEGF` of `+0.0` is the only input in the group that produces `S = 1`
with `Z = 1` and `CY = 0` simultaneously.

**Exposing values.**

```
op = ALU_NEGF; f_a = 64'd0;
#1 chk(f_res[31:0] === 32'h8000_0000, "NEGF of +0.0 gives -0.0");
#1 chk(f_flags[PSW_S] === 1'b1, "whose sign BIT is set");
#1 chk(f_flags[PSW_Z] === 1'b1, "and which is still zero");
#1 chk(f_flags[PSW_CY] === 1'b0, "so CY stays clear: negative AND non-zero");
```

(Traced by hand against the RTL this passes today — `res_sign = ~f_sign = 1`,
`is_zero = 1`, so `CY = 1 && !1 = 0`, `S = 1`, `Z = 1`. The implementation is
right; the test that would keep it right is missing.)

---

## Item 6 — what was left out, checked per instruction

The brief asks whether any of the ten omitted instructions is **actually**
implementable from the pages alone. **Two of them are**, and one of those is
implementable with no open questions at all.

| | needs | verdict |
|---|---|---|
| `ADDF` `SUBF` `MULF` `DIVF` | rounding of a real result; `SUBF` also has the unsettled operand order | correctly excluded |
| `SCLF` | exponent-only for a result that stays normal, but subnormal production at the bottom and `FOV` at the top; the quick-immediate extension is unsettled | correctly excluded |
| `CVTF` (`5F-08`, long→short) | narrowing a 52-bit mantissa to 23 — rounding | correctly excluded |
| `CVT.WS` (word→short real) | 32 significant bits into a 24-bit mantissa — rounding | correctly excluded |
| `CVT.SW` `CVT.LW` (real→word) | `TKCW.RDI`/`RD`, **and** the stored value on overflow, which no page gives | correctly excluded |
| **`CMPF`** | an ordered comparison plus one `TKCW.RD` term | **implementable** — see below |
| **`CVT.WL`** (word→long real) | **nothing** | **implementable, exactly** |

### `CVT.WL` is exact and fully specified

`cvt.wl src.w.r, dst.l.w`, "Convert Word to Long Real", `5F-11`. A signed
32-bit integer has at most 31 significant bits; a long real's mantissa is 52.
**Every** `int32` is representable exactly, so there is no rounding, no
overflow, no underflow and no denormal. Its own flag block confirms it: `FIV`,
`FZD`, `FOV` and `FUD` are all "Unchanged", and `FPR` is "Set if a precision
error occurs" — a sentence that on this instruction can never fire. Its
Exceptions block lists **Floating Point Precision alone**, which is likewise
unreachable. `CY`/`OV`/`S`/`Z` are the group's usual four over the result.

None of the six gaps `FLOATING-POINT.md` records touches it. It is the one
conversion in the set that is a pure format change.

### `CMPF` needs no rounding except in one case, and that case is decided

The brief's instinct is right. `CMPF`'s three moving flags reduce to an
**exact ordered comparison**:

> `Operation: Flags ← src2 - src1`
> `CY  Set if the result is negative, otherwise cleared`
> `OV  Set if unordered, otherwise cleared`
> `S   Set to the MSB of the result`
> `Z   Set if the result is zero, otherwise cleared`

- `Z` ⟺ `src2 == src1`, comparable exactly on the bit patterns (with `+0 == −0`).
- `CY` and `S` ⟺ `src2 < src1`, an exact ordered comparison.
- `OV` ⟺ unordered, i.e. a NaN operand — which is the same trap/flag question
  as D1 and no worse.

**The one place rounding leaks in** is `S` at exact equality. `S` is "the MSB
of the *result*", and the result of `x − x` is `+0` or `−0` depending on the
rounding mode — `ADDF`'s page says so outright: *"If the absolute values of the
source and destination operands are equal but differ in sign, the sign of the
zero result will be determined by the programmed rounding mode."* Under
`TKCW.RD` = `00` (nearest), `10` (+∞) or `11` (zero) the answer is `+0` and
`S = 0`; only `01` (toward −∞) gives `−0` and `S = 1`.

That is a **complete** specification given `TKCW[1:0]`, not a gap — it is one
term reading two bits, not a rounder. So `CMPF` is implementable, and its cost
is the `TKCW` plumbing D1 needs anyway.

**One caveat worth stating before it is built:** `CMPF` is the only
instruction in the group whose `OV` moves, and the plate's `CMPF` row prints
`• • • •` where the Reference gives four sentences — the two agree here, which
`FLOATING-POINT.md` verified at 600 dpi. But the shipping core hardwires
`CMPF`'s `CY` and `OV` to zero, so **the cosim oracle will diverge on `CMPF`
from the first instruction**. It must not be fed to the oracle.

---

## Checked and found correct

Listed so the coverage of this audit is visible.

**Item 1 — classification, both widths.** `v60_fpu.sv:73`–`:86`.

- `f_man = is_long ? a[51:0] : {a[22:0], 29'd0}` is **sound**, and the specific
  worry in the brief does not bite: left-shifting by 29 is injective on zero,
  so `{a[22:0], 29'd0} == 0` ⟺ `a[22:0] == 0` exactly. A short real with any
  low mantissa bit set gives a non-zero `f_man`, hence `is_denorm` or `is_nan`
  as appropriate. Checked at `a[22:0] = 1` (the bench's `0x0000_0001`, a
  minimal denormal) and at `0x7FC0_0000` (a quiet NaN, only bit 22 set).
- `f_exp = is_long ? a[62:52] : {3'd0, a[30:23]}` widened against
  `exp_max = is_long ? 11'h7FF : 11'h0FF` — the comparison is against the
  width's own all-ones value, not a fixed one, so a short real with exponent
  `0xFF` classifies as inf/NaN and a long real with `0x0FF` does not. The
  bench's `0x7FF8_0000_0000_0000` case ("the same low word read as a short real
  does not") is the right test and it is present.
- The four classes are mutually exclusive and exhaustive over `{exp==0,
  exp==max, else} × {man==0, man!=0}` ✓.
- The upper 32 bits of `a` are ignored for a short real in every path —
  `f_sign` takes `a[31]`, `f_exp` `a[30:23]`, `f_man` `a[22:0]`, and `mov_res`
  zeroes them — so a stale high word cannot leak into a class or a result.

**Item 2 — the flag sentences.** All nine assignments match their sentences
term for term:

- `CY = res_sign && !is_zero` ↔ "Set if the destination is negative **and
  non-zero**"; `S = res_sign` ↔ "Set if the destination **mantissa sign bit**
  is set". The two genuinely part company at negative zero, and the bench tests
  exactly that (`tb_v60_alu.sv:990`–`:996`).
- `Z = is_zero` ↔ "Set if the destination is zero"; `OV = 0` ↔ "Cleared".
- `ABSF` clears `CY`, `OV` **and** `S` unconditionally ↔ its distinctive block,
  which p. 3.297 corroborates as the only row in the Floating Point block with
  a literal `0` in the `CY` and `S` columns.
- **The "destination" vs "result" reading is correct.** MOVF's block says
  destination and NEGF's/ABSF's say result; for all three the value described
  is the one about to be written, `res_sign` implements exactly that
  (`ABSF`→0, `NEGF`→`~f_sign`, `MOVF`→`f_sign`), and only `ABSF`'s differs from
  the source — in the sign bit, which no classification depends on. No page
  distinguishes the two words anywhere in the group.

**Item 3 — FUD.** `if (is_denorm) ffl_out[1] = 1'b1` on all three.

- Denormal-ness is preserved by all three operations: none changes the exponent
  or the mantissa, only the sign bit. So the source's class **is** the result's
  class, including `MOVF` at both widths — and `MOVF` cannot convert, since
  `movf.s` is `.s`→`.s` and `movf.l` is `.l`→`.l`.
- **`FIV` and `FUD` can never both be live here.** A denormal has
  `exp == 0`; a NaN or infinity has `exp == exp_max`. The two are mutually
  exclusive by construction, so the "can both be set" question does not arise
  for these three. (It would for the arithmetic four, where a result can be
  inexact *and* denormal — and Table 8-1's codes are bit flags for exactly that
  reason: `1601` precision, `1602` underflow, `1604` overflow, `1608` zero
  divide, `1610` invalid, `1680` reserved operand, with the note "these
  exception codes can combine in the case of simultaneous exceptions".)
- The `ffl` bit order `{FIV, FZD, FOV, FUD, FPR}` matches `PSW[12:8]` MSB-down
  (bit 12 FIV … bit 8 FPR), so `ffl_out[4]`→FIV and `ffl_out[1]`→FUD are right,
  and `v60_seq.sv:1181`/`:2112` wire `psw[PSW_FIV:PSW_FPR]` to the same field.
- The flags are **sticky** — every sentence in the group is "otherwise
  unchanged", `ffl_out` starts at `ffl_in`, and only `if` clauses set bits.
  `tb_v60_alu.sv:1020` tests it.

**Item 5 — the exception code and vector.**

- **Vector 22 is right.** §8's Instruction Exceptions list prints
  "**#22 Floating Point Exceptions** — Zero Divide, Overflow, Underflow,
  Precision, Invalid Floating Point Operation, **Reserved Floating Point
  Operand**".
- **Code `0x1680` is right.** Table 8-1's Arithmetic Exceptions block, read
  against its name column: `1500` integer zero divide, `1501` integer overflow,
  `1601` floating point precision, `1602` underflow, `1604` overflow, `1608`
  floating point zero divide, `1610` invalid floating point operation,
  **`1680` reserved floating point operand**, `1780` decimal format.
- **`EK_ARITH` is the right frame.** Figure 8-5 groups #21, #22 and #23 under
  one Arithmetic Exceptions heading with one frame shape — Current PC as a
  parameter above the code word, Next PC on top.
- **The gate does cover `PSW[12:8]`.** `fp_resv` is tested *before* the
  `is_fp` branch at `v60_seq.sv:2094`, and `psw <= psw` replaces both the
  integer-flag write and the `psw[PSW_FIV:PSW_FPR] <= fpu_ffl` write. So the
  suppression is complete rather than integer-only. Whether it should be that
  broad is D2; that it *is* that broad is correct as implemented.

**Decode and widths.**

- `op_alu_escape` emits `5C08/09/0A` and `5E08/09/0A` → `ALU_MOVF`/`NEGF`/
  `ABSF`, matching p. 3.297's `010111{s}0` primary with sub-ops `00001000`,
  `00001001`, `00001010` and the Reference's Opcode lines (`5C-08`/`5E-08`
  etc.). Both widths present.
- `op_data_bytes_escape` gives **4** for every `5C` entry and **8** for every
  `5E` entry, on both operands — which is `DATA_TYPE`'s `('s','s')` resolved
  through p. 3.295's "Floating Point Data Type Selection: 0 short real, 1 long
  real".
- `fbytes` is driven from `w_dst`, which for these three equals `w_src`
  (`movf.s src.s.r, dst.s.w`), so the width the FPU classifies at is the
  width the operand was fetched at.
- **`EXEC_OP_ESCAPE`'s key is `s & 3`**, not a variant index — `gen_op_pkg.py:155`
  does `EXEC_OP_ESCAPE[(mnemonic, s & 3)]`. `('MOVF',0)`, `('NEGF',1)`,
  `('ABSF',2)` are therefore correct, because their sub-ops `0x08`/`0x09`/`0x0A`
  have low two bits `0`/`1`/`2`. Verified in the generated output. See N1.

**`resv_operand` is not raised for a denormal** — `tb_v60_alu.sv:1013` asserts
it, and it is right: §8 scopes Reserved Floating Point Operand to "when a NaN
or infinity is used as the operand".

---

## Notes, not findings

**N1 — `EXEC_OP_ESCAPE`'s `s & 3` key is fragile and its comment is wrong.**
The comment above the decimal entries says "Keyed by (mnemonic, 0) because each
has one sub-op of its own", but `SUBDC` is keyed `1`, `SUBRDC` `2`, `NEGF` `1`
and `ABSF` `2` — they are keyed by the sub-op's **low two bits**, which happens
to be distinct for every mnemonic currently in the table. It silently collides
for any future mnemonic with two sub-ops four apart (`0x08` and `0x0C`, say).
Correct today; worth a comment that says what the key actually is.

**N2 — the cosim oracle is unusable for this whole group, and the header says
so.** `v60_fpu.sv`'s header records that `s32_v60.sv` sets no flags for MOVF,
implements no long real, and raises no FP exception. Worth restating here
because D1's fix changes MOVF's control flow, and the oracle cannot arbitrate.

## What was not checked

- The **arithmetic four, `SCLF`, `CVTF` and the four `CVT` forms** beyond the
  implementability question in item 6 — none is implemented.
- **`TRAPFL`'s** own behaviour now that `PSW[12:8]` is live; `BREAK-AND-TRAP.md`
  owns it, and the commit's claim that this makes its AND non-zero is correct
  but out of scope here.
- **Timing**, as everywhere: p. 3.297's Clocks column is blank for all three.
