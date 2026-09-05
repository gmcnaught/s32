# Tranche three, audited against the pages

An independent check of two commit ranges against the Programmer's Reference
and the databook plates, done by someone who read the pages and did not write
the code:

- **A — the doubleword work**, `3332170`, "the doubleword register pair, and
  MULX / MULUX / DIVX / DIVUX". Research: `docs/v60/DOUBLEWORD.md`.
- **B — the bit field group**, `2d37fb3`, "the bit field group, and a sum that
  wrapped past its own check". Research: `docs/v60/BIT-FIELD.md`.

**The audit is not clean.** One correctness defect, three weak tests, one
decision that needs its counter-evidence recorded, and two notes. Everything
below was found by reading; no RTL was changed and the mutation harness was not
run.

Line numbers are as of `8dbca31`; the **construct** named beside each is the
durable reference if a number has drifted.

---

## Defects

### D1 — `v60_ea`'s `S_PTR` ignores `bit_mode`: every indirect bit-addressed operand is wrong

| | |
|---|---|
| **Severity** | **High** on correctness; low exposure on this target |
| **File** | `rtl/cpu/v60x/v60_ea.sv:360`–`:367` (`S_PTR`), with `:231`–`:250` (`bit_byte_base`, `bit_offset`, `bit_resid`) |
| **Page** | Databook **p. 3.261**, the *Bit Addressing Modes* table and the bit-address rule |
| **Verdict** | **defect** |

This is the suspicion flagged in the brief, and it **confirms** — and it is
larger than "the residual I check is the wrong one". The address is wrong too.

**What the page requires.** p. 3.261 states the arithmetic:

> To compute a bit address, the 32-bit base address is zero extended on the
> right to 35 bit length. Next the 32-bit bit offset is sign extended to
> 35-bit length and the sum of these two identify the starting address of the
> bit field or bit string.

and its *Bit Addressing Modes* table lists **sixteen** modes, of which **six
are indirect**:

| Mode | Assembler encoding | bit offset |
|---|---|---|
| Displacement Indirect | `@[disp[Rn]]` | "defaults to 0" |
| PC Displacement Indirect | `@[disp[PC]]` | "defaults to 0" |
| **Double Displacement** | **`offset@[disp[Rn]]`** | the **outer** displacement |
| **PC Double Displacement** | **`offset@[disp[PC]]`** | the outer displacement |
| Direct Address Deferred | `@[/addr]` | "defaults to 0" |
| **Direct Address Deferred Indexed** | **`Rx@[/addr]`** | **Rx**, unscaled |

(The table underlines the bit-offset component; the three bolded rows carry a
non-zero one.)

**What the RTL does.** `S_PTR` is where an indirect mode finishes, and it has
no `bit_mode` term at all:

```
S_PTR: if (dx_done) begin
    ea         <= dx_rdata[31:0] + outer_r + scaled_r;
    dx_addr    <= dx_rdata[23:0] + outer_r[23:0] + scaled_r[23:0];
```

Compare the non-indirect branch three lines above it, which does have one:
`ea <= bit_mode ? bit_byte_addr : (addr1 + scaled);`

Two independent consequences:

1. **The operand address is a byte address with no bit arithmetic applied.**
   The outer displacement is added as *bytes* where p. 3.261 makes it the
   **bit** offset — an error of a factor of eight — and `scaled_r` is the index
   *scaled by `opbytes` (4)* where the page makes `Rx` a raw, unscaled bit
   offset. There is no `<< 3` on the pointer and no `>> 3` on the sum.

2. **`bit_resid` is computed from an address that is not the operand's.**
   `bit_addr` is built from `bit_byte_base`/`bit_offset`, i.e. from `base`,
   `disp` and `rx_val` — the *pre-pointer* values. For an indirect mode `base`
   is the register holding the pointer's address, not the operand's base, so
   the residual the sequencer reads bears no relation to the operand. Both
   consumers are affected: the Illegal Data Field test at `v60_seq.sv:1023`
   (`({4'd0, ea_bit_resid} + {1'b0, bf_len_r}) > 7'd32`) and the extraction
   shift latched at `v60_seq.sv:~1717` / `:~1863` (`bf_resid_r <= ea_bit_resid`).

**Reachability.** Nothing gates it. `v60_seq.sv:1619` sets
`ea_bit_mode <= bf_src_is_bit` from the instruction alone, with no test of the
addressing mode, and `am_is_indirect()` admits `AM_DISP8/16/32_IND`,
`AM_PCDISP8/16/32_IND` and `AM_ADDR_IND`. p. 3.261 establishes that these
modes are architecturally available for bit operands.

**Concrete failure scenario.**
`extbfz @[disp32[R1]], #8, R9`, with `R1 = 0x1000`, `disp = 0x10`, and the
pointer at `0x1010` holding `0x2000`.

- Correct: pointer `0x2000` is the byte base, bit offset 0, so the field is
  bits 0-7 at byte `0x2000`, `resid = 0`, no exception.
- Actual: `bit_addr = (0x1000 << 3) + 0x10 = 0x8010`, so `bit_resid = 0`
  *by luck here*; the address becomes `ea = 0x2000 + outer + scaled`. With
  `disp` in the *outer* slot for a double displacement the byte address is off
  by `disp` bytes instead of `disp` bits.

A sharper one, where the residual alone breaks it:
`extbfz @[disp32[R1]], #8, R9` with `R1 = 0x1001`. Then
`bit_addr = (0x1001 << 3) + disp`, and `bit_resid` becomes a function of
`R1`'s low bits — so the same instruction reading the same pointer extracts a
*different* bit position depending on the value of a register that only ever
addressed the pointer. With `bf_len_r = 30` and a residual that lands at 3,
`3 + 30 = 33 > 32` raises Illegal Data Field on an operand that is perfectly
legal.

**Not recorded anywhere.** `docs/v60/BIT-FIELD.md` does not contain the word
"indirect"; its "what the pages do not settle" list does not mention this. And
no test reaches it — every bit-field case in `tb_v60_seq.sv` uses a
displacement or register-indirect mode (see W4).

**Cheapest correct shape**, for information only: `S_PTR` needs the same
`bit_mode` ternary the direct branch has, with the bit address formed from the
*pointer* as the byte base, the outer displacement as the bit offset when
there is no index, and `rx_val` unscaled when there is — i.e. the `:231`–`:236`
computation re-expressed over `dx_rdata` instead of `base`. That also makes
`bit_resid` correct, because it is the low three bits of the same sum.

---

## Weak tests

### W1 — DIVX's negative overflow bound is untested at its boundary

| | |
|---|---|
| **File** | `verif/v60x/tb_v60_muldiv.sv:384`, `:390` |
| **Construct under test** | `v60_muldiv.sv:233` `divx_fit_bad` |
| **Verdict** | **weak test** |

`divx_fit_bad` is asymmetric by design, and correctly so:

```
r_qneg64 ? (acc[31:0] > 32'h8000_0000)      // -2^31 is representable
         : (acc[31:0] > 32'h7FFF_FFFF)      // +2^31 is not
```

The bench tests the **positive** arm on both sides — `runx(ALU_DIVX, 1,
64'h0000_0000_8000_0000)` expects overflow and `runx(ALU_DIVX, 1,
64'h0000_0000_7FFF_FFFF)` expects none — and tests a negative dividend away
from the boundary (`-64'd12345 / 10`). **The negative arm's boundary is never
exercised**, so a mutation collapsing the ternary to
`(acc[31:0] > 32'h7FFF_FFFF)` on both arms passes the suite.

**Exposing values.** `runx(ALU_DIVX, 32'd1, 64'hFFFF_FFFF_8000_0000)` —
that is −2^31 ÷ 1:

```
chk(result === 32'h8000_0000, "DIVX -2^31 / 1 is -2^31");
chk(flags_out[PSW_OV] === 1'b0, "which fits a signed word exactly");
chk(writes === 1'b1,            "so the destination is written");
```

Traced by hand against the RTL this passes today — `ydm = 0x0000000080000000`,
`ydm[63:32] = 0 < 1` so `divx_ovf` is clear, the quotient magnitude is
`0x80000000`, `r_qneg64 = 1`, and `0x80000000 > 0x80000000` is false. The
implementation is right; the test that would keep it right is missing.

I checked the other three bounds the brief asked about and all are correct:
`-2^63 ÷ anything` always overflows via `divx_ovf` (`ydm[63:32] = 0x80000000`
≥ every possible 32-bit magnitude); DIVUX at exactly `0xFFFFFFFF` is right and
**is** tested (`runx(ALU_DIVUX, 2, 64'h0000_0001_FFFF_FFFE)` → quotient
`0xFFFFFFFF`, no overflow); and `divx_ovf`'s `ydm[63:32] >= xm` is an exact
test for "magnitude quotient ≥ 2^32", in both directions.

### W2 — the divider's 33-bit comparison is never exercised

| | |
|---|---|
| **File** | `verif/v60x/tb_v60_muldiv.sv:345`–`:395` |
| **Construct under test** | `v60_muldiv.sv:206`–`:210` `div_sh` / `div_fits` / `div_next` |
| **Verdict** | **weak test** |

The brief asks to "construct a dividend that exercises it". None of the
existing X-divide cases does: every divisor in the file is `10`, `0x10000`,
`1`, `2` or `0`, so `div_sh[64:32]` never exceeds 32 bits and the 33rd bit of
the comparison is dead in simulation.

**Exposing values.** `runx(ALU_DIVUX, 32'hFFFF_FFFF, 64'hFFFF_FFFE_0000_0001)`.
Traced: `ydm[63:32] = 0xFFFFFFFE < 0xFFFFFFFF`, so no pre-loop overflow; on
step 1 `div_sh[64:32] = 2 × 0xFFFFFFFE = 0x1FFFF_FFFC`, which **needs
thirty-three bits**, and the subtract yields `0xFFFFFFFD`. The exact answer is
`0xFFFFFFFF × 0xFFFFFFFF = 0xFFFFFFFE00000001`, so:

```
chk(result === 32'hFFFF_FFFF, "DIVUX at the widest divisor: the 33-bit compare is live");
chk(result_hi === 32'd0,      "with an exact remainder");
```

### W3 — the `acc[64]` assertion lost coverage it did not need to lose

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_muldiv.sv:431` |
| **Construct** | `if (!rst && (state == S_RUN) && !r_mul && !r_divx && acc[64])` |
| **Verdict** | **weak test** (a weakened assertion), and a **documentation error** |

The `!r_divx` term was added on the header's argument that the 33rd bit is
"reachable on every step" for a doubleword dividend. **That is true of the
comparison and false of the stored bit**, and the distinction matters because
the assertion watches the stored bit.

Proof, from the RTL's own invariant. For a divide that did **not** trip
`divx_ovf`, the initial remainder satisfies `acc[63:32] = ydm[63:32] < opnd`.
Inductively, before each step the remainder is `< opnd`, so
`div_sh[64:32] = 2·rem + bit < 2·opnd ≤ 2^33` — thirty-three bits, hence the
wide comparison — and then:

- `div_fits`: `div_next[64:32] = div_sh[64:32] − opnd < opnd ≤ 2^32`, so
  bit 64 is **0**;
- `!div_fits`: `div_next = div_sh` and `div_sh[64:32] < opnd ≤ 2^32`, so
  bit 64 is **0**.

So `acc[64]` is never stored non-zero for a valid X divide either, and the
assertion would still have held. Excluding `r_divx` means a future bug that
does set `acc[64]` during an X divide goes unreported.

The one case where `acc[64]` genuinely can be set is an **overflowing** X
divide, where `ydm[63:32] ≥ xm` breaks the invariant on the first step. That
is a real reason for a guard — but the guard should be `!r_divov`, not
`!r_divx`, which is both narrower and says what is actually true.

### W4 — no bit-field test uses an indirect mode, which is why D1 survived

| | |
|---|---|
| **File** | `verif/v60x/tb_v60_seq.sv:~1306`, `:~1340`, `:~3466` |
| **Verdict** | **weak test (coverage)** |

Every bit-addressed operand in the suite uses a displacement or plain
register-indirect mode. The comment at `:1306` says the displacement mode was
chosen "on purpose", to prove the displacement *is* the bit offset — a good
test, and it is the reason the direct path is solid. But six of p. 3.261's
sixteen modes are untested, and they are exactly the six D1 breaks.

**Exposing values.** The `extbfz @[disp32[R1]], #8, R9` case in D1, asserting
the extracted value against the byte at the *pointer*, fails today.

---

## Decisions

### S1 — "the sum must not exceed thirty-two" over the residual: a real decision, with counter-evidence not recorded

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:1023`; recorded at `docs/v60/BIT-FIELD.md:343`–`:358` |
| **Page** | Reference §7 `EXTBF`/`INSBF`/`CMPBF`, and §7 `TEST1` |
| **Verdict** | **the decision is genuine — the doc should carry the argument against it** |

The sentence is identical on all three pages:

> The sum of the bit offset and the bit field length must not exceed
> thirty-two, otherwise an Illegal Data Field exception will occur.

`BIT-FIELD.md` reads "the bit offset" as the **residual 0..7** and says "No
page states that the constraint is over the residual. It is the only reading
\[that works\]". The mechanical argument is sound: the machine fetches one
32-bit word at `bit_addr[34:3]` and extracts `len` bits starting at
`bit_addr[2:0]`, so `resid + len ≤ 32` is exactly "the field fits the word
that was fetched".

**But there is direct counter-evidence and the doc does not mention it.**
`TEST1`, `SET1`, `CLR1` and `NOT1` print the parallel sentence:

> An Illegal Data Field exception occurs if the bit offset is outside the
> range 0 to 31.

There "the bit offset" is unambiguously **the operand**, and for a one-bit
field `offset ≤ 31` is the same rule as `offset + 1 ≤ 32`. So the phrase "the
bit offset" demonstrably means the operand elsewhere in the same section, one
instruction group away. Under that reading the bit-field constraint would bound
the *offset operand*, not the residual — which would make the signed 35-bit bit
address pointless, which is why I agree with the residual reading.

**Verdict: the decision stands, and it is correctly marked as a decision.**
What is missing is that `BIT-FIELD.md` presents it as the only possible
reading; it is the better of two readings, and the other one has a page behind
it. Recording the `TEST1` sentence as the counter-argument would make the
decision auditable rather than merely stated.

### S2 — MULX/MULUX read eight bytes; permitted, but the decision is unmarked

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:1765` (`ea_opbytes <= w_dst`, `w_dst = 8`) |
| **Page** | Reference §7 `MULX` / `MULUX` |
| **Verdict** | **fine — but should be marked** |

`MULX`'s Description is *"The **word** designated by the destination operand is
multiplied by the word contents of the source operand"* and `MULUX`'s is *"The
unsigned **word** contents of the destination operand"*. Only the low word is
an input. With a **memory** destination the RMW read fetches `w_dst = 8` bytes,
so the high word is read — two extra bus cycles, and a read of an address the
Description does not make an input.

This is **permitted**: the operand is declared `dst.d.rw`, and
`docs/v60/DOUBLEWORD.md` §9 item 5 already records that "nothing on either page
says the upper word must be fetched, and nothing says it must not." Reading
eight is the literal reading of `.d.rw`. **No change is warranted** — but this
is a bus-observable choice made in a line that reads as generic width plumbing,
and it deserves a comment saying it was a choice.

---

## Checked and found correct

Listed so the coverage of this audit is visible.

**A — the doubleword work**

- **The register-pair order.** `v60_seq.sv:~1794` `val2 <= dst_is_dbl ?
  rf_ra_pair : {32'd0, rf_ra}` and `S_WB_HI`'s `rf_wr_sel <= reg_operand +
  5'd1`. Low word in `Rn`, high in `Rn+1`, **no evenness masking** — which is
  what §2 and §3 both require and what `DOUBLEWORD.md` §1 flags as the thing
  most machines get wrong.
- **The memory layout and the little-endian claim.** `yd = {y_hi, y}` at
  `v60_muldiv.sv:149` with the header quoting §2's "identified by the address
  of the low order byte".
- **`divx_ovf`** (`v60_muldiv.sv:168`) is an exact test for "magnitude quotient
  ≥ 2^32": `ydm[63:32] ≥ xm ⟺ ydm ≥ xm·2^32`, and the converse holds because
  `ydm < (ydm[63:32]+1)·2^32`. Checked in both directions, and at
  `-2^63 ÷ −2^31` (overflows, correctly: the true quotient is 2^32).
- **`divx_fit_bad`'s asymmetry is right** — `> 2^31` when negative, `> 2^31−1`
  when positive. `-2^31 ÷ 1` is handled and does not overflow (see W1).
- **The 32-step count for a doubleword dividend is correct**, not a bug: the
  accumulator is seeded `{1'b0, ydm}` so the high word *is* the initial
  remainder and the low word the dividend register, which is the standard 64/32
  form. Thirty-two steps produce a 32-bit quotient, and `divx_ovf` pre-rejects
  the cases where that is not enough.
- **MULX/MULUX flags are over the 64-bit product.** `v60_muldiv.sv:277`–`:279`:
  `f_s = prod[63]`, `f_z = (prod == 64'd0)`. Matches `MULX`'s "the result is
  negative" and `MULUX`'s "the MSB of the result is set" with "the result"
  being the doubleword, and the header's note about `0x1_00000000` reading as
  zero off the low word is the right worry.
- **`OV Cleared` for the X multiplies** (`:266`) — the Reference against the
  plate, correctly marked as a decision, with the mechanism (a 32×32 product
  always fits 64 bits) that makes the Reference's reading the coherent one.
- **`opbytes` into `v60_muldiv` is 4, not 8** — `alu_bytes` folds `w_dst = 8`
  down to `4'd4` (`v60_seq.sv:~1109`), so `mask`/`msb` give word semantics to
  the source and the low destination word, which is what all four X forms need.
- **Sign selection uses `yds` (bit 63), not `ys` (bit 31), in the DIVX branch**
  (`:367`–`:369`) — the dividend's sign is the doubleword's. This is the one
  place a copy-paste from the word divides would have been invisible in the
  common case and wrong at the boundary; it is right.
- **The destination survives overflow and zero divide.** `writes <=
  !(r_divov || divx_fit_bad)` at `S_FIN`, gating **both halves together**,
  which is what "The destination operand does not change when an overflow or a
  Zero Divide exception occurs" requires for an operand whose two halves carry
  different quantities.
- **The `!eff_writes` RMW close** (`v60_seq.sv:~1940`, the `!eff_writes` branch) writes `val2`
  back — the original eight bytes — so the destination's *contents* are
  unchanged. This puts a write cycle on the bus, but unlike the `CMP`/`TEST`
  case fixed in tranche one the operand here is declared `.rw`, so the machine
  is entitled to write it. **Not a defect.**

**B — the bit field group**

- **The bit-address arithmetic** (`v60_ea.sv:231`–`:236`) is p. 3.261's
  sentence exactly: base shifted left three, offset sign-extended to 35 bits,
  summed, `bit_byte_addr = bit_addr[34:3]`, `bit_resid = bit_addr[2:0]`.
- **The index/displacement split matches p. 3.261's mode table** for all ten
  non-indirect modes. `bit_byte_base = has_index ? (base + disp) : base` and
  `bit_offset = has_index ? rx_val : disp` reproduce `@[Rn]`, `Rx@[Rn]`,
  `offset@[Rn]`, `Rx@disp[Rn]`, `Rx@disp[PC]`, `@[Rn+]`, `@[-Rn]`, `@/addr`,
  `Rx@/addr` and the PC forms row for row — **including the both-index-and-
  displacement case the brief asked about**, where the table puts `disp` in the
  byte base and `Rx` in the bit offset.
- **The index is unscaled in bit mode** (`rx_val`, not `scaled`), which
  p. 3.261's scaling table corroborates from the other side: its *Scaled Index*
  column prints "—" for Bit Field.
- **`bit_resid` is combinational, deliberately**, so the Illegal Data Field
  test can run before any access is started — correct, because the exception is
  an Instruction Exception with a Current-PC frame. (For direct modes. See D1.)
- **The autoincrement step is 4 for a bit field.** §6: *"The contents of Rn are
  then incremented by 1 for the bit string data type or by 4 for the bit field
  data type."* `v60_ea.sv:~325` steps by `opbytes`, and `DATA_TYPE` gives
  `'EXTBF'/'INSBF'/'CMPBF': (4, 4)` → **+4** ✓.
- **All eight escape encodings verified against the Reference's Opcode
  blocks**, which print them outright: `EXTBF` 5D-08 / 5D-09 / 5D-0A
  (`extbfs`/`extbfz`/`extbfl`), `CMPBF` 5D-00 / 5D-01 / 5D-02, `INSBF` **5D-18
  / 5D-19 only** (`insbfr`/`insbfl`). `op_alu_escape()`'s
  `5D00/01/02`, `5D08/09/0A`, `5D18/19` match all eight, and the sub-op low
  five bits derive correctly from p. 3.297's `000000{ext}` / `000010{ext}` /
  `000110{ext}`.
- **INSBF's `ext = 10` is genuinely absent, not dropped by the generator.**
  The Reference prints two `INSBF` forms and two opcodes; `5D-1A` appears
  nowhere. `insn_table.py` expands three encodings from `000110{ext}` and
  `EXEC_OP_ESCAPE` supplies two, so `5D1A` decodes with a format and no
  operation and stops with `STOP_NO_ALU` — the right behaviour for a variant
  the architecture does not define. **Worth noting as a page-vs-page item:**
  p. 3.295's generic `ext` legend is "00 signed / 01 unsigned / 10 right
  justified", which does not describe `INSBF`, whose `ext = 00` is *right
  justified*. The per-instruction Opcode blocks win, and the tree took them.
- **(b) `CVT.WL` and `CVT.LW` are floating point.** Confirmed from the
  Reference's `CVT` pages: `cvt.wl src.w.r, dst.l.w  Convert Word to **Long
  Real**  5F-11` and `cvt.lw src.l.r, dst.w.w  Convert **Long Real** to Word
  5F-09`, both listed in p. 3.297's **Floating Point Instructions** block.
  `insn_table.py:407` types them `(4, 8)` and `(8, 4)` and neither is in
  `EXEC_OP`. **Correct to exclude them from tranche three** — they need the
  doubleword datapath for their long-real side but they are conversions to and
  from an IEEE double, not doubleword integers.

---

## Notes, not findings

**N1 — the bit-string increment conflict is already recorded, but the table
still carries the databook's number.** Databook p. 3.261's scaling table prints
Increment/Decrement **4** for Bit String; Reference §6 says **1**.
`BIT-FIELD.md:302`–`:326` and `:385`–`:392` record the conflict and note that
`DATA_TYPE`'s comment mis-states it. `insn_table.py:417`-adjacent still gives
the bit-string group `(4, 4)`, so whichever way it is resolved, **the
bit-string tranche will step `[Rn+]` by 4** unless something changes. Out of
scope here; flagged because the brief asked about autoincrement and this is the
half of it that is not yet right.

**N2 — `r_qneg` and `r_qneg64` are set identically** (`v60_muldiv.sv:340` and
`:367`), both `is_sgn && (xs ^ yds)` on the DIVX path. Harmless redundancy; the
two names suggest a distinction that does not exist.

## What was not checked

- The **encodings of the doubleword group** against p. 3.296, which
  `DOUBLEWORD.md` already verified and which the brief did not raise.
- **`gen_op_pkg.py` itself** beyond confirming that its output for the eight
  escape encodings matches the Reference; the generator's other outputs were
  not re-derived.
- The **bit-field extraction and insertion datapath** (`S_BF_*` states) beyond
  its consumption of `bf_resid_r` — the brief scoped this audit to the six
  listed areas and the extraction logic is not among them.
- **Timing**, as everywhere: the plates' Clocks column is blank for all of
  these.
