# Tranche one, audited against the pages

An independent check of the eleven tranche-one instructions in the RTL —
`NOP`, `MOVEA`, `RVBIT`, `RVBYT`, `SETF`, `INC`, `DEC`, `TEST`, `GETPSW`,
`UPDPSW.H`, `UPDPSW.W` — against the Programmer's Reference and the databook
plates, done by someone who read the pages and did not write the code.

**The audit is not clean.** Two live defects, one missing exception, four
assertions that would survive the RTL being wrong, and two nits. Everything
here was found by reading; `verif/v60x/run_v60x.sh` was run once to establish
the baseline and reports **34 passed, 0 failed** — so *every finding below is
a case the existing tests do not catch.*

Line numbers are as of the working tree at `1d5702a` with tranche one applied,
and `v60_seq.sv` is under active edit — the **construct** named beside each
line is the durable reference if a number has drifted.

Scope audited: `rtl/cpu/v60x/v60_alu.sv`, `v60_alu_pkg.sv`, `v60_psw_pkg.sv`,
`v60_seq.sv`, `v60_ea.sv`, `tools/v60x/insn_table.py`,
`verif/v60x/tb_v60_alu.sv`, `tb_v60_seq.sv`, `tb_v60_psw.sv`. The "checked and
correct" list at the end is the coverage, and it is deliberately itemised: a
clean result is worth nothing unless what was looked at is visible.

---

## Defects

### D1 — `UPDPSW_H_FIELDS` is wrong: four flags that should move do not

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:562` |
| **Construct** | `localparam logic [31:0] UPDPSW_H_FIELDS = 32'h0000_10FF;` |
| **Page** | PgmRef §3, pp. 3-3 / 3-4 |
| **Verdict** | **defect** |

§3 says what `UPDPSW.H` may write:

> the integer and floating point condition codes can be modified using the
> UPDPSW.H instruction

and the PSW bit map on the same pages says where those live: `CY OV S Z` at
bits 3:0, and `FPR` (8), `FUD` (9), `FOV` (10), `FZD` (11), `FIV` (12). The
union is **`0x0000_1F0F`**.

The second possible reading — the two 8-bit *fields* the page draws (integer
7:0, float 15:8) minus the RFU bits at 4:7 and 13:15 — gives `0x1F0F` as well.
**Both readings agree, and neither produces `0x10FF`.**

`0x10FF` sets bits `{0,1,2,3,4,5,6,7,12}`. Against `0x1F0F` that is:

- **bits 8–11 excluded** — `FPR`, `FUD`, `FOV`, `FZD`. Four of the five
  floating-point condition codes the page explicitly permits. `updpsw.h` with
  a mask of `0x0000_0F00` writes **nothing**.
- **bits 4–7 included** — RFU, which the page does not permit. Neutralised
  downstream by the `& ~PSW_RFU` in `updpsw_next`, so this half is harmless by
  accident rather than by design.

The live half is the exclusion. It looks like a transposition: reading "12:8"
and "3:0" and forming `0x1000 | 0x00FF` instead of `0x1F00 | 0x000F`.

**The tree already contains the right answer, unused.**
`rtl/cpu/v60x/v60_psw_pkg.sv:99`'s `psw_update_h` computes
`val[15:0] & ~PSW_RFU[15:0]`, which is exactly `0x1F0F`, and
`verif/v60x/tb_v60_psw.sv:138` tests it — but nothing calls that function. The
package holds the correct mask and the sequencer holds the wrong one.

Fix is the constant alone: `32'h0000_1F0F`.

### D2 — `MOVEA` is missing from `dst_write_only`

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:526` (list), `:1003` (`ea_rmw`) |
| **Construct** | `wire dst_write_only = (aop == ALU_MOV) \|\| ALU_RVBIT \|\| ALU_RVBYT \|\| ALU_SETF \|\| ALU_GETPSW;` |
| **Page** | PgmRef §7 `MOVEA` — `movea.b src.b.n, dst.w.w` |
| **Verdict** | **defect** |

`MOVEA`'s destination access type is `.w` — write-only, exactly like the five
operations that *are* in the list. It is also absent from `dst_read_only`, so
`ea_rmw <= !dst_write_only && !dst_read_only` is **1**, and a `MOVEA` with a
**memory** destination reads that destination before writing it.

Cost: one extra logical access — two extra bus cycles for an aligned word —
and a **read on the pins that the page does not describe**. This is the same
class as the `CMP`/`TEST` read-modify-write defect the comment immediately
above the list documents, one notch less severe: a spurious *read* rather than
a spurious write, but still a real side effect against a read-sensitive
location.

The comment names `MOVS`, `MOVZ` and `MOVT` as deliberate omissions pending
their bus-cycle counts, and does not mention `MOVEA` at all — which reads as
an omission rather than a decision. `MOVEA` was added in the same commit
series that created the list.

---

## Missing exception

### M1 — `MOVEA`'s illegal source modes are not enforced, and fail two different ways

| | |
|---|---|
| **Files** | `rtl/cpu/v60x/v60_ea.sv:185` and `:194`; `v60_seq.sv:~905` (`S_OP1R`, `src_is_reg`) |
| **Page** | PgmRef §7 `MOVEA`, Addressing Modes table; §8 for the vector |
| **Verdict** | **defect (missing exception)** |

`MOVEA`'s Addressing Modes table marks **`Rn`, `Immediate` and
`Immediate.Quick` as `X` — Illegal Addressing Mode** for its `src` column,
with the page's own legend line `X Illegal Addressing Mode`. That is vector
**#19** (§8's Instruction Exceptions list). Nothing in this tree raises it.

Two distinct wrong behaviours, from the same illegal operand:

- **Through `v60_ea`** (Format II, or Format I with `d = 1`): the
  `am_is_reg_direct` branch at `:185` and the `am_is_immediate` branch at
  `:194` both set `ea <= 32'd0` and neither consults `addr_only`;
  `illegal <= we` is 0 because a source is not a write. `S_OP1W` (`:949`) then does
  `val1 <= src_addr_only ? {32'd0, ea_ea} : ea_rdata`, so **`movea.w R5, R9`
  and `movea.w #5, R9` write `0` into R9.**
- **Not through `v60_ea` at all** (Format I with `d = 0`): `src_is_reg`
  short-circuits in `S_OP1R` with `val1 <= rf_ra`, so the same illegal
  encoding writes **R5's value**.

So one illegal operand produces two different silently-wrong answers depending
on which format encodes it. `v60_ea` already has the vocabulary for this — an
`illegal` output and a `$display` WARN for the doubleword register-direct case
at `:302`.

Related, and outside the eleven: `ea <= 32'd0` for a register-direct operand
is a general `addr_only` hazard — `JMP` and `JSR` take the same path.

---

## Weak tests

Each of these is an assertion, or an absent assertion, that would not change if
the RTL were wrong. The operand values that expose each one are given so they
can be turned into tests directly.

### W1 — the `UPDPSW.H` field tests cannot see D1

| | |
|---|---|
| **File** | `verif/v60x/tb_v60_seq.sv:1801`, `:1811` (program at `0x230`, encoded at `:940`–`:966`) |
| **Verdict** | **weak test** |

Every mask bit the three `UPDPSW` tests use is either in **bits 3:0** —
permitted under both `0x10FF` and the correct `0x1F0F` — or **bit 16
(`PSW_TE`)** — denied under both. **Nothing probes bits 4–15**, which is
precisely where D1 lives.

`chk(seq_psw[3:0] === 4'b1111, ...)` and
`chk(seq_psw[PSW_TE] === 1'b0, ...)` both pass with `UPDPSW_H_FIELDS` set to
`0x10FF`, `0x1F0F`, or even `0x000F`.

**Exposing values.** A `UPDPSW.H` with

```
newPSW = 0x0000_1F00
mask   = 0x0000_1F00
```

then

```
chk(seq_psw[12:8] === 5'b11111, "UPDPSW.H may write all five FP condition codes");
```

Today that reads `5'b10000`: `updpsw_mask = 0x1F00 & 0x10FF = 0x1000`, so only
`FIV` is written and `FPR`/`FUD`/`FOV`/`FZD` stay clear.

Note also that the bits-4–7 half of D1 **cannot** be tested from outside,
because `& ~PSW_RFU` clears them again on the way out. That is worth knowing
before someone tries.

The one thing this program does test well: the second `UPDPSW.H`
(`newPSW = 0x00010005`, `mask = 0x0001000F`, against a PSW whose low nibble is
already `1111`) yields `0101` where the reversed operand order would yield
`1111`, so **operand order is genuinely pinned**. That assertion is sound.

### W2 — `MOVEA` is never tested with a memory destination, so D2 is invisible

| | |
|---|---|
| **File** | `verif/v60x/tb_v60_seq.sv:1768`, `:1785` (program at `0x1D0`, encoded at `:901`–`:937`) |
| **Verdict** | **weak test** |

Both `MOVEA` tests use a **register** destination (`MOVEA.b [R8], R9` and
`MOVEA.b [R8+], R9`), so `dst_is_reg` short-circuits in `S_OP2` and the
`ea_rmw` path is never entered. No destination-side cycle count is asserted
for `MOVEA` anywhere.

**Exposing values.** `MOVEA.b [R8], [R9]` — a memory destination, so a
word-wide write to whatever `R9` points at — with

```
chk(insn_cycles === 5'd2, "a .w destination is written and not read first");
```

An aligned word write is two bus cycles and the `.n` source is zero. Today
this reads **4**: the destination is read (2) and then written (2).

### W3 — `DEC`'s overflow-set case is never exercised

| | |
|---|---|
| **File** | `verif/v60x/tb_v60_seq.sv:1704`–`:1707` |
| **Verdict** | **weak test** |

The bench covers `DEC.b 0x00 → 0xFF` and asserts `OV === 1'b0`. The
overflow-set case is absent, so `v60_alu.sv:294`'s `f_ov` term for the
subtract path is only ever observed **false** on a `DEC`. A mutation forcing
`DEC`'s OV to 0 passes the suite.

`INC`'s overflow-set case *is* covered (`0x7F → 0x80` at `:1690`), which is
what makes the gap specific to `DEC`.

**Exposing values.** `DEC.b R9` with `R9 = 0x0000_0080`:

```
chk(rf.gpr[9] === 32'h0000_007F, "DEC.b 0x80 gives 0x7F");
chk(seq_psw[PSW_OV] === 1'b1,    "which overflows a signed byte");
chk(seq_psw[PSW_CY] === 1'b0,    "without borrowing");
chk(seq_psw[PSW_S]  === 1'b0,    "and the result is positive");
```

### W4 — `INC` and `DEC` are tested at byte width only

| | |
|---|---|
| **File** | `verif/v60x/tb_v60_seq.sv:1684`–`:1722` |
| **Verdict** | **weak test** |

Every `INC`/`DEC` case in the suite is `.b`. `v60_alu`'s `carry_of()` and the
`sign_of()` overflow terms are width-parameterised on `opbytes`, and only
`opbytes = 1` is driven through them on this path. A width-selection mutation
in `carry_of` — `4'd2` returning `v[8]`, say — would not be caught here.

Lower value than W1–W3, because `ADD` and `SUB` share those exact terms and
are exercised more widely; recorded because the `INC`/`DEC` path reaches them
with `xa` forced to 1, which `ADD`/`SUB` never do.

**Exposing values.** `INC.h R9` with `R9 = 0x0000_7FFF` (expect `0x8000`,
`OV = 1`, `CY = 0`) and `INC.w R9` with `R9 = 0xFFFF_FFFF` (expect `0`,
`CY = 1`, `Z = 1`).

### W5 — coverage gap: six of the eleven have no `tb_v60_alu` case at all

| | |
|---|---|
| **File** | `verif/v60x/tb_v60_alu.sv` |
| **Verdict** | **weak test (coverage)** |

`tb_v60_alu` covers `ALU_TEST`, `ALU_RVBIT`, `ALU_RVBYT` and `ALU_SETF`.
`ALU_INC`, `ALU_DEC`, `ALU_NOP`, `ALU_MOVEA`, `ALU_GETPSW`, `ALU_UPDPSWH` and
`ALU_UPDPSWW` appear **nowhere** in it — they are exercised only through
`tb_v60_seq`, where every check also depends on the sequencer, the address
unit and the register file being right.

That is not a defect and the seq-level tests are good ones, but it means the
ALU-level contract for those seven (`writes`, `flags_out`, `result` at each
`opbytes`) has no direct assertion. In particular nothing asserts at ALU level
that `ALU_UPDPSWH`/`ALU_UPDPSWW` set `writes = 0`, which is the only thing
stopping their stray `flags_out` from mattering.

---

## Decisions marked in comments that a page actually settles

### S1 — which bits `UPDPSW.H` may write is not a decision

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:554`–`:562` |
| **Comment** | *"DECISION, because the page does not say: a mask bit outside that set is silently ignored rather than raising."* |
| **Page** | PgmRef §3, pp. 3-3 / 3-4 |
| **Verdict** | **half settled — recharacterise** |

The decision as stated is sound and should stay: the page really is silent on
whether an out-of-field mask bit *raises*, and the Exceptions block offers
nothing to raise (`Privileged Instruction`, and only for the `.W` form), so
silent masking is the right reading.

But the comment's scope slips. **Which bits are in-field is settled by §3**,
and the comment itself quotes the answer correctly — "CY OV S Z at 3:0 and FIV
FZD FOV FUD FPR at 12:8" — while the constant beneath it does not implement
that. See D1. The decision is about the *response* to an out-of-field bit, not
about the *set*.

### S2 — the RFU bits are settled; only the mask's placement is a choice

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:565`–`:568` |
| **Construct** | `updpsw_next = (((psw & ~updpsw_mask) \| (val1 & updpsw_mask)) & ~PSW_RFU);` |
| **Page** | PgmRef §3 (RFU rows at 4:7, 13:15, 19:23); databook p. 3.248 "(Must be 0)" |
| **Verdict** | **settled; the placement is a nit** |

That the merge must not write RFU is a page fact, not a decision, and
`PSW_RFU = 32'h00F8_E0F0` matches the three RFU ranges exactly.

The **placement** is the choice, and it is stronger than the stated intent.
`& ~PSW_RFU` is applied to the whole merged word, so an `UPDPSW` clears RFU
bits that were already set in the PSW **and that the mask did not select** —
including with a mask of zero, which the Operation line makes a no-op. The
formulation matching "the merge cannot write them" puts it in the mask:

```
mask' = mask & ~PSW_RFU;   PSW <- (PSW & ~mask') | (newPSW & mask')
```

Unobservable while RFU stays 0 — reset is `0x0000_0000` (databook p. 3.238)
and nothing else sets them — unless a `RETIS` restores a stacked PSW with RFU
bits set. Low severity on its own; recorded mainly because **it is what
conceals the bits-4–7 half of D1.**

### S3 — `dst_is_reg` being unobservable for Format III is correct as marked

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:500`–`:508` |
| **Comment** | *"NOT a correctness requirement for Format III, and marked so nobody proves it with a test that cannot fail."* |
| **Verdict** | **fine — no page overrides it** |

Confirmed by reading `v60_ea`: the `am_is_reg_direct` branch at `:185` writes a
register destination back through its own `rn_wb` slot with `bus_cycles <= 0`,
so a Format III instruction with a register operand reaches the same
architectural result and the same zero bus cycles down either path, and with
one operand there is no second writeback to collide with. The comment is
right, including its reason, and no page bears on it.

---

## Nits

### N1 — `privileged_op` is declared and never used

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:578` |
| **Verdict** | **fine, but a trap** |

`wire privileged_op = (aop == ALU_UPDPSWW);` has no reader. The live check at
`:832` tests `op_alu(idu_op) == ALU_UPDPSWW` directly, which is correct — it
runs before any operand is fetched, which is what the page wants ("the
exception is for attempting the instruction"). But whoever adds `LDPR`,
`STPR`, `IN`, `OUT` or `HALT` will reach for `privileged_op` first, extend it,
and get no effect. `docs/v60/TRANCHE-ONE.md`'s table lists those five as the
remaining privileged instructions in the tranche.

---

## Checked and correct

Each of these was read against its page and found right. Listed so the
coverage of this audit is visible.

**`RVBIT`** — `v60_alu.sv:132`, `rvbit_res = {x[0]…x[7]}`, and `raw = {24'd0,
rvbit_res}`. Reverses **eight** bits, matching `rvbit src.b.r, dst.b.w` and the
page's `B7…B0` / `B0…B7` diagram. `DATA_TYPE (1, 1)` gives `opbytes = 1`, so
the result is masked to a byte. In `keep_all`, so no flag moves — which is what
"CY Unchanged / OV Unchanged / S Unchanged / Z Unchanged" says, and means a
reversal producing zero does not set Z. One bus cycle to a memory destination,
asserted at `tb_v60_seq.sv:1680`.

**`RVBYT`** — `v60_alu.sv:135`, `{x[7:0], x[15:8], x[23:16], x[31:24]}`: the
input's byte 0 lands at bits 31:24, which is the page's diagram. `DATA_TYPE
(4, 4)`. In `keep_all`. The bench's `0x11223344 → 0x44332211` pins all four
byte positions because all four differ.

**`SETF`** — `v60_alu.sv:326`, `cond_true(x[3:0], flags_in) ? 32'd1 : 32'd0`.
The condition is the **low** nibble, per "The condition code field is found in
the lower four bits of the condition operand. The upper four bits are ignored";
the stored values are exactly `01H` and `00H`, not "non-zero" and "zero"; in
`keep_all`, so it sets a byte and not a flag. `tb_v60_alu.sv:523` distinguishes
`BA` from `AB`, which is the nibble check, and `tb_v60_seq.sv:1667` asserts one
bus cycle to a write-only destination.

**`INC` / `DEC`** — `v60_alu.sv:147`, `addend_one` forces `xa` to `1 & mask`
and both share the adder and the overflow terms with `ADD`/`SUB`. That is the
pages' own definition — "The INC instruction is a shorter encoding for the more
general instruction `add #1, dst`" and the same for `sub #1, dst` — so the flag
blocks cannot drift from `ADD`'s and `SUB`'s without a second derivation. `CY`
is a carry for `INC` and a borrow for `DEC`, matching the two pages' only
differing line. Two-byte length asserted at `tb_v60_seq.sv:1695`. Byte-width
flag behaviour verified against all four sentences.

**`TEST`** — `v60_alu.sv:327`, `raw = xm`, `f_cy = 0`, `f_ov = 0`,
`writes = 0`. The page's Operation is `flags ← src − 0`, which produces the
same `S`/`Z` as passing the operand through, with `CY` and `OV` cleared
outright — and the Condition Codes block says "CY Cleared / OV Cleared". One
bus cycle and no write against a memory operand, asserted at
`tb_v60_seq.sv:1737`.

**`TEST`'s exemption from the immediate-destination check** —
`v60_seq.sv:542`, `dst_read_only`. Correct on two grounds: §8 scopes the
exception to "an attempt to use an immediate addressing mode as the
**destination** operand", and `TEST`'s syntax line is `test.b src.b.r` with no
destination at all; and `TEST`'s own page describes what happens with one —
"If the immediate quick addressing mode is specified for the source operand,
the immediate data is zero extended to the source operand length" — so it is
explicitly legal.

**The `CMP`/`UPDPSW` half of the same fix** — both are `.r`-only in every
syntax line, and `UPDPSW`'s page says outright "If the immediate quick
addressing mode is specified, the immediate data is zero extended to 32-bit
length and used as the new PSW or mask operand", where the mask is the second
operand. Exempting them is right.

**`NOP`** — `v60_seq.sv:~866` retires directly; `v60_alu.sv:306` sets
`writes = 0` and it is in `keep_all`. One byte, zero bus cycles, no flag
moves — all three asserted at `tb_v60_seq.sv:1762`–`:1765`. Matches "No action
is taken" and `PC ← PC + 1`.

**`MOVEA`'s width handling** — `DATA_TYPE ('siz', 4)`. The destination is a
word whatever the size field says (`dst.w.w`), while `siz` still reaches
`ea_opbytes` so `[Rn+]` steps by it. Both halves are asserted: the `[R8]` test
at address `0x700` needs eleven bits and would read `0x00` under a byte mask,
and the `[R8+]` test at `tb_v60_seq.sv:1787` checks the pointer stepped by
**one**.

**`MOVEA`'s `.n` source** — `v60_seq.sv:550` `src_addr_only`, `:913`
`ea_addr_only`, `:949` `val1 <= ea_ea`. No bus cycle is issued for the source,
asserted as `insn_cycles === 5'd0` at `tb_v60_seq.sv:1771`. Matches "The source
operand is not referenced and remains unchanged". The `ea_addr_only` clear in
`S_OP1` closes a real leak, and the test at `:1780` (a memory source in the
instruction after a `JMP`) is the one that proves it.

**`GETPSW`** — `v60_seq.sv:862` loads `val1 <= psw` before the operand path,
and `ALU_GETPSW` is in **both** `dst_write_only` and `keep_all`. The
`dst_write_only` membership is genuinely load-bearing: `S_OP2R`'s
`if (fmt_iii && !dst_write_only) val1 <= rf_ra` would otherwise overwrite the
PSW with the destination register's old contents, and the register-destination
test at `tb_v60_seq.sv:1806` does exercise that guard. `DATA_TYPE (4, None)`
with the Format III `w_dst = w_src` rule gives `opbytes = 4`, so the **whole**
PSW is copied, matching "The contents of the Program Status Word (PSW) are
copied to the destination operand".

**`UPDPSW` operand roles** — `v60_seq.sv:567`, `val1` as `newPSW` and `val2`
as `mask`, which is the order the syntax line names them
(`updpsw.h newPSW.w.r, mask.w.r`). Pinned by the second bench case, whose
`newPSW` and `mask` differ (see W1).

**`UPDPSW` operand widths** — `DATA_TYPE (4, 4)` for **both** forms. The `.h`
names which half of the PSW may be modified, not the operand size; both syntax
lines are `.w.r, .w.r`. Asserted indirectly by the instruction-length check at
`tb_v60_seq.sv:1802`.

**`UPDPSW` writes no operand** — `v60_alu.sv:317` sets `writes = 0`, and
`dst_read_only` at `v60_seq.sv:542` keeps `ea_rmw` clear, so neither operand is
written. Both syntax lines are `.r`.

**`UPDPSW`'s flags bypass** — `v60_seq.sv:1138`,
`if (is_updpsw) psw <= updpsw_next; else psw <= psw_set_flags(psw, eff_flags)`.
This is what makes `v60_alu`'s stray `flags_out` for `ALU_UPDPSWH`/`W` dead
rather than harmful: they are not in `keep_all`, so the ALU emits
`{CY, 0, 0, 1}` for them, and nothing reads it. Correct, and matching the
page's one-line Condition Codes block, "Updated according to mask operand".

**Privilege** — `v60_seq.sv:832`, checked as `psw[PSW_EL_HI:PSW_EL_LO] !=
2'b00` **before any operand is fetched**, raising `VEC_PRIVILEGED = 17`.
Matches §6 ("programs executing at other execution levels (levels 1, 2 and 3)
are said to be non-privileged"), §8's `#17 Privileged Instruction`, the shared
Exceptions block "Privileged Instruction (updpsw.w)", and p. 3.299 putting
`UPDPSW.W` in the Privileged Instructions block while `UPDPSW.H` sits on
p. 3.298 with no `12`. Asserted at `tb_v60_seq.sv:1826`.

**Format III operand routing** — `v60_seq.sv:1025`, `:1048`, `:1060`. The one
operand goes to `val2` (which `v60_alu` reads as `y`) and is mirrored into
`val1` (`x`) unless the operation is write-only. That serves `INC`/`DEC`, which
read `y`, and `TEST`, which reads `x`, without the sequencer having to know
which — and skips the mirror for `GETPSW`, which needs `val1` intact. The
memory-operand `TEST` at `tb_v60_seq.sv:1733` is what proves the mirror
happens at all, because on that path the value arrives through `ea_rdata`
rather than the register file.

**`w_dst` for Format III** — `v60_seq.sv:597`, `w_dst = fmt_iii ? w_src :
w_dst_raw`. Correct: the table describes a one-operand instruction's operand as
the **first** (`'INC': ('siz', None)`, `'TEST': ('siz', None)`,
`'GETPSW': (4, None)`), so asking for the second operand's width would return
"none".

**`PSW_RFU`** — `v60_psw_pkg.sv:57`, `32'h00F8_E0F0` = bits 4:7, 13:15, 19:23.
Matches §3's three RFU rows exactly.

**`psw_set_flags`** — `v60_psw_pkg.sv:80`, `{psw[31:4], f}`. Writes bits 3:0
only, so no integer operation can disturb the floating-point condition codes at
12:8. Correct: every Condition Codes block in the tranche names only
`CY OV S Z`.

**`insn_table.py` widths for the eleven** — `'NOP': (None, None)`,
`'MOVEA': ('siz', 4)`, `'RVBIT': (1, 1)`, `'RVBYT': (4, 4)`, `'SETF': (1, 1)`,
`'INC'/'DEC'/'TEST': ('siz', None)`, `'GETPSW': (4, None)`,
`'UPDPSW.H'/'UPDPSW.W': (4, 4)`. All eleven agree with their syntax lines,
including the two that are easy to get wrong — `RVBIT` as a byte and both
`UPDPSW` forms as words.

**`insn_table.py` `EXEC_OP` for the eleven** — one entry each, all present, all
mapping to the `alu_op_e` the RTL implements.

---

## What was not checked

- The **encodings**, which were stated as already confirmed against
  pp. 3.296–3.299 and `insn_table.py`. Spot-checked against the Reference's
  Opcode lines only where a width or length claim depended on it.
- **`ADD`/`SUB`/logic/shift/multiply-divide**, except where `INC`/`DEC` reach
  their shared terms.
- **Verilator-vs-Icarus differences**; the suite runs both and both pass.
- **Timing**, as everywhere: the plates' Clocks column is blank for all eleven
  (`docs/v60/INSTRUCTION-TIMING.md`).
