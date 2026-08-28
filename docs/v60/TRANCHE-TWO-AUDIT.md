# Tranche two, audited against the pages

An independent check of the ten tranche-two instructions in the RTL — `PUSH`,
`POP`, `PUSHM`, `POPM`, `PREPARE`, `DISPOSE`, `XCH`, `TASI`, `CAXI`, `CHLVL` —
against the Programmer's Reference and the databook plates, done by someone who
read the pages and did not write the code.

**The audit is not clean.** Three live defects, one pre-existing defect of the
same class found beside them, four things the pages do not settle that the RTL
decides silently, and three weak tests. Everything below was found by reading.

## The baseline, and a warning about the tree you are standing in

`verif/v60x/run_v60x.sh` was run twice.

- **At the audited commit `3fd9c1b`: 34 passed, 0 failed.** So tranche two is
  green, and **every finding below is a case the existing tests do not catch.**
  Run from a clean export of `3fd9c1b`, because —
- **In the current working tree it is 32 passed, 1 BUILDFAIL.** The failure is
  `tb_v60_alu`, which does not compile: *"port `y_hi` is not a port of dut"*,
  *"port `result_hi` is not a port of dut"*. That is **not** a tranche-two
  defect. `verif/v60x/tb_v60_alu.sv` was last committed at `05d3b98`, which
  predates this range, and the working tree is dirty with in-progress work on
  `v60_alu_pkg.sv`, `v60_muldiv.sv`, `v60_ea.sv`, `v60_op_pkg.sv`,
  `v60_seq.sv`, `insn_table.py` and six benches — doubleword ports being added
  ahead of `MULX`/`DIVX`. It is worth knowing that the ALU bench is currently
  dead, because while it is, nothing checks `v60_alu` at all.

**Line numbers are as of `3fd9c1b`, not the working tree**, which has moved
247 lines in `v60_seq.sv` alone since. The **construct** named beside each line
is the durable reference.

Scope audited: `rtl/cpu/v60x/v60_seq.sv`, `v60_alu.sv`, `v60_alu_pkg.sv`,
`v60_ea.sv`, `v60_dmux.sv`, `v60_dxu.sv`, `v60_bus_arb.sv`, `v60_biu.sv`,
`v60_exc.sv`, `v60_op_pkg.sv`, `tools/v60x/insn_table.py`,
`verif/v60x/tb_v60_seq.sv`, `tb_v60_dmux.sv`. The "checked and correct" list at
the end is the coverage, itemised, because a clean result is worth nothing
unless what was looked at is visible.

---

## Defects

### D1 — `ea_lock` is set on one of the eight paths that start an access, so the bus lock leaks into the next instruction

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:1542` (the only assignment), `:1443` `:1974` `:2106` `:2319` `:2464` (the paths that do not) |
| **Construct** | `ea_lock <= is_lockop;` in `S_OP2`'s descriptor set-up |
| **Page** | databook **p. 3.236**, read on the plate |
| **Verdict** | **defect** |

`ea_lock` has exactly three occurrences in the file: the port declaration at
`:265`, the reset at `:1109`, and one assignment at `:1542`. Eight states start
an effective-address access. Only one of them sets the lock:

| state | `ea_start` at | sets `ea_io` | sets `ea_lock` |
|---|---|---|---|
| `S_OP1S` — every memory **source** | `:1443` | yes (`:1418`) | **no** |
| `S_OP2S` — the destination | `:1572` | yes (`:1538`) | yes (`:1542`) |
| `S_WB` ×2 — the write-back, reusing `S_OP2`'s descriptor | `:1674` `:1706` | inherited | inherited |
| `S_CTRL_EAS` — `JMP`/`JSR`/`CALL`/`RET`… | `:1974` | **no** | **no** |
| `S_STK_S` — the control-transfer stack engine | `:2106` | **no** | **no** |
| `S_PSH_S` — `PUSH`/`POP`/`PREPARE`/`DISPOSE` | `:2319` | yes (`:2284`) | **no** |
| `S_PSM_S` — `PUSHM`/`POPM` | `:2464` | yes (`:2445`) | **no** |

`v60_ea` latches `lock` into `lock_r` on `start` (`v60_ea.sv:215`), so every one
of those accesses inherits whatever `ea_lock` was left at. After a `TASI` or a
`CAXI` it is left at **1**, and nothing clears it until the next instruction
reaches `S_OP2`.

The page defines the pin as meaning one specific thing and nothing else:

> "The BLOCK\* output is asserted during a bus cycle to indicate an indivisible
> read-modify-write bus cycle (TASI, CAXI instructions) is taking place."

**Failure scenario.** Two instructions:

```
    tasi  [R1]          ; E0 ... — sets ea_lock = 1 at S_OP2
    mov.w [R2], R3      ; its SOURCE read runs through S_OP1S
```

The `mov.w`'s source read of `[R2]` starts with `ea_lock` still 1, so
`v60_ea` raises `dx_lock` across it, `v60_bus_arb` refuses the prefetch unit
the bus for its duration (`:96`, `p_req && !d_lock`), and `v60_biu` drives
`block_n` low at that access's T1. **`BLOCK*` is asserted on an ordinary
word read that is not a read-modify-write and not interlocked** — which is
precisely the assertion p. 3.236 says the pin makes to other bus masters.

The same happens for `tasi` followed by any of `push`, `pop`, `pushm`, `popm`,
`prepare`, `dispose`, `jsr`, `jmp`, `ret`, `retis`, `rsr`, `call`.

On System 32 this cannot corrupt anything — `docs/v60/BUS-PINS-171-5964D.md`
records `/BLOCK` as an unterminated no-connect on 171-5964D — so the visible
cost here is only the spurious prefetch hold-off. The correctness cost is
against the page.

**Why no test catches it.** `verif/v60x/tb_v60_seq.sv:399` and `:412` check that
a prefetch is *not* acknowledged inside a locked operation and that `BLOCK*` is
*not* released inside one, and `:2968` counts `n_block == 2` across `TASI`'s
pair. **Nothing anywhere asserts that `BLOCK*` is inactive on an access that is
not interlocked**, which is exactly the half D1 falls in. See W1.

Fix is one line per path, the way `ea_io` is already done in six of the eight.

### D2 — `CHLVL`'s range check reads an unmasked register, so a legal level in a dirty register raises

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:874` |
| **Construct** | `wire chlvl_bad = is_chlvl && ((val1[31:2] != 30'd0) \|\| …)` |
| **Page** | PgmRef §7 `CHLVL` — `chlvl level.b.r, arg.b.r` |
| **Verdict** | **defect** |

The syntax line makes `level` a **byte**, and `tools/v60x/insn_table.py` now
says so — the same commit range corrected `'CHLVL': (1, 4)` to `(1, 1)` and
`v60_op_pkg.sv:486`'s `9'h097` from `4'd4` to `4'd1`. The range check did not
follow.

`val1` is not masked to the operand's width when the source is a register:
`S_OP1R` does `val1 <= {32'd0, rf_ra}` (`:1430`), the whole 32-bit register.
For a **memory** source `v60_ea` returns `opbytes` bytes zero-extended, so
`val1[31:8]` is zero and the check behaves. For a **register** source it is
whatever the register holds.

**Failure scenario.**

```
    R5 = 0x0000_0102
    chlvl R5, R6
```

`level` is a byte operand, so its value is `0x02` and the page permits it —
level 2 is in range, and from level 3 the privilege test passes. The RTL
computes `val1[31:2] = 0x40 ≠ 0` and raises **Illegal Data Field** instead of
vectoring through SBT entry 26.

That this is an oversight rather than a decision is visible one screen away:
the *argument* operand **is** masked, at `:2637`, `exc_param0 <= {24'd0,
val2[7:0]}`, with the page quoted beside it. One of the two byte operands is
truncated and the other is not.

`chlvl_lvl = val1[1:0]` is unaffected — it already takes the low two bits — so
the fix is `val1[7:2]` in the range test, or masking `val1` at the source.

### D3 — `POP` writes R31 before its destination access, against the equivalence its own page states

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:2340` (`S_PSH_FIN`) |
| **Construct** | `rf_wr_sel <= 5'd31; rf_wr_data <= sp_r + 32'd4; … else state <= S_OP2;` |
| **Page** | PgmRef §7 `POP` |
| **Verdict** | **defect**, low reachability — and it needs a decision, not just an edit |

`POP`'s page says two things:

> "The word data located on the top of the stack is copied to the destination
> operand. The stack pointer (R31) is **then** incremented by four."
>
> "The POP instruction is a shorter encoding of the more general instruction
> `mov.w [ sp+ ], dst`"

`S_PSH_FIN` writes R31 with `sp_r + 4` and *then* routes to `S_OP2` for the
destination. So the stack pointer moves **before** the destination is written,
where the page's own word is "then" and where the general form it names moves
Rn last — an addressing-mode writeback is applied at `S_RETIRE` (`:1808`),
after the destination write.

**Failure scenario.** `pop sp` — the destination is R31, which is a real idiom
for switching stacks:

```
    R31 = 0x600, [0x600] = 0x0000_9000

    pop  sp            ; RTL:              R31 = 0x0000_9000
    mov.w [sp+], sp    ; the form the page says it IS:  R31 = 0x604
```

Two encodings the page calls the same instruction, two different results.

**The mirror case shows which one is the odd one out.** `PUSH` reads its source
at `S_OP1S` before `S_PSH_SP` touches anything, so `push sp` pushes the old SP
— exactly what `mov.w sp, [-sp]` does in this same sequencer. `PUSH` matches
the equivalence and `POP` does not.

Marked as needing a decision because the pages do not name the collision: no
page says what happens when `POP`'s destination *is* the stack pointer. What
the page does say is that `POP` is `mov.w [sp+], dst`, and this implementation
executes the two differently. That is a self-consistency argument, not a
quotation, and it is recorded as one.

---

## A pre-existing defect of the same class, found beside D1

### P1 — `ea_io` leaks into the control-transfer and stack-engine accesses

| | |
|---|---|
| **File** | `rtl/cpu/v60x/v60_seq.sv:1974` (`S_CTRL_EAS`), `:2106` (`S_STK_S`) |
| **Construct** | both start an access without setting `ea_io` |
| **Page** | PgmRef §4 — "input/output space … is accessed only by the privileged IN and OUT instructions" |
| **Verdict** | **defect, pre-existing** — `S_CTRL_*` and `S_STK_*` predate this range |

Exactly the omission D1 is, one signal over. `ea_io` is set at `:1418`,
`:1538`, `:2284` and `:2445` — the source path, the destination path, and both
**new** stack paths, which do set it. The control-transfer path never has.

**Failure scenario.**

```
    out.b R1, R2       ; ea_io <= io_dst = 1 at S_OP2
    jsr   [R3]         ; its return-address push runs through S_CTRL_EAS
```

`JSR`'s `[-SP]` push of the return address is issued with `ea_io` still 1, so
`v60_dxu` drives an **I/O** bus status for a stack write to memory. On this
target the I/O space is unused and `v60_bus_pkg`'s three-`TI` recovery rule
fires spuriously; on a machine that decoded the status it would write the
return address into I/O space.

Reported rather than fixed, and reported at all because a fix for D1 that
touches those two states should fix both while it is there.

---

## Four things the pages do not settle, which the RTL decides silently

None of these is a defect. Each is a place where the implementation chose, and
the choice is not marked at the point of decision the way the rest of this
tree's are.

### Q1 — `BLOCK*` is pulsed per interrupt-acknowledge cycle, not across the pair

`v60_biu.sv:298` raises `block_n` at T1 for `status == BST_INTERRUPT_ACK`, and
`:327` drops it at `T_TI` because `lock` is low. The two acknowledge cycles are
separate logical accesses, so `BLOCK*` **falls between them**.

The page is singular and supports that reading: *"BLOCK\* is also asserted for
the duration of an interrupt acknowledge bus cycle"* (p. 3.236). But
`v60_dxu.sv`'s own comment quotes p. 3.234 — *"the interrupt acknowledge status
is generated during the pair of interrupt acknowledge bus cycles"* — and
`docs/v60/INSTRUCTION-TIMING.md` §4.1's µPD70632 rule is *"asserted during T1 of
the first bus cycle of the indivisible operation, and deasserted on the trailing
edge of the last clock period of the last bus cycle of the operation"*, under
which a pair that is one operation should hold it across both.

Nothing held decides it, and nothing tests it. Worth one line of comment
recording the reading taken.

### Q2 — `CAXI`'s encoding restriction is not enforced

`CAXI`'s page: *"This instruction is not allowed to use Format II and
furthermore, the Format I direction field must be zero."* Nothing checks
either. `S_CAXI_W` (`:2394`) writes `rf_wr_sel <= idu_reg` unconditionally,
which is right only because the restriction holds; with `d = 1` or Format II the
register the page calls `Rn` is not in that field and the mismatch result lands
in the wrong register.

The page says "not allowed" without naming an exception, so what *should*
happen is genuinely undecided — but silently doing something else is a third
option nobody chose.

### Q3 — `CHLVL` to the level you are already at is permitted

`chlvl_bad`'s privilege half is `psw[PSW_EL_HI:PSW_EL_LO] < chlvl_lvl`, which
is the prose reading — *"the current execution level is less than the level
operand"* — and `docs/v60/TRANCHE-TWO.md` is right that it is the only reading
consistent with the instruction's stated purpose. Equality therefore passes: a
level-2 program may `chlvl #2`. The page neither permits nor forbids it. It is
harmless (the handler runs at the same level, on the same stack) and worth a
line saying it was noticed.

### Q4 — an autoincrement on R31 collides with the stack engine's own R31 write, unguarded

`push [sp+]`, `pushm [sp+]`: the operand's addressing-mode writeback targets
R31 and is applied at `S_RETIRE` (`:1808`), **after** `S_PSH_FIN`/`S_PSM_SEL`
have written R31 with the stack pointer the engine computed. The engine's value
is silently overwritten.

The sequencer has an explicit policy for the analogous case — two *addressing
mode* writebacks stop it with `STOP_TWO_WB` (`:1188`), under a comment saying
"it is this sequencer refusing to drop one silently". An addressing-mode
writeback racing the sequencer's own register write is the same hazard and is
not covered. `S_PSH_SP`'s comment reasons carefully about why `AM_RN_IND`
raises no writeback of its own — which is correct and checked below — but that
argument is about the *stack* access, not about the operand's.

---

## Weak tests

### W1 — nothing asserts `BLOCK*` is inactive when it should be

`tb_v60_seq.sv:399`, `:412`, `:2968` and `:3125` all check the pin is asserted,
or held, or counted, **during** `TASI` and `CAXI`. There is no negative test.
A single `chk` that `n_block == 0` across an ordinary `mov.w [R2], R3` would
catch D1, and the same assertion on the instruction *after* a `TASI` would
catch it exactly.

### W2 — `tb_v60_dmux` ties `a_lock` low, so the new lock path is untested at unit level

`verif/v60x/tb_v60_dmux.sv:42` instantiates the DUT with `.a_lock(1'b0)` and
`:47` leaves `.dx_lock()` unconnected. The two new lines in `v60_dmux` — the
pass-through and the `dx_lock = 1'b0` on the `b_req` branch — have no unit
coverage at all. The bench already has the shape to test them: `:101` drives
both masters and checks `overlap === 1'b1`.

That matters more than it looks, because the `b_req` branch forcing `dx_lock`
low is only safe if the two ports never overlap while a lock is held. **They do
not** — see C7 below, where that is checked and is correct — but the invariant
is *reported* by `overlap` and not enforced, and the bench's own comment says
so: "The mux does not make an overlap safe. It reports it".

### W3 — `PUSHM` clobbers `val2` with the read data of a write access

`S_PSM_W` (`:2470`) does `val2 <= ea_rdata` for both directions. On a `PUSHM`
the access is a write and `ea_rdata` is stale. Harmless — `ALU_PUSHM` is in
`keep_all` and sets `writes = 0`, so nothing downstream reads `val2` — but it
is an accident rather than a decision, and no assertion would notice if
something later started depending on `val2`.

---

## Checked and correct

Itemised, because the four areas asked about are only worth "clean" if the
looking is visible.

**C1 — Area 2, siblings of the `exc_el_r` leak: none.** Every register latched
at one raise and read at the next was traced.

- `exc_code_r` is read by `EK_ARITH`, `EK_TRAP`, `EK_CHLVL` and the `EK_INSN`
  default. Every raise that selects one of those four sets it in the same
  statement — `:1243` `:1246` `:1263` `:1285` `:1299` `:1371` `:1379` `:1388`
  `:1492` `:1502` `:1507` `:1616` `:1774` `:1781` `:1792` `:1862` `:2147`
  `:2224` `:2250`. The nine raises that do **not** set it are all `EK_BERR`
  (`:1183` `:1226` `:1453` `:1589` `:1716` `:1983` `:2113` `:2328` `:2471`) or
  `EK_INT` (`:1187` `:1202`), and those two branches use `berr_code_r` and the
  literal `16'd0` instead. Correct by construction, not by luck.
- `exc_ack_r` is read only by `EK_INT`, and both `EK_INT` raises set it
  (`:1189` NMI → 0, `:1204` IRQ → 1).
- `berr_addr_r` / `berr_code_r` are read only by `EK_BERR`, which also clears
  `berr_r` in the same branch.
- **The return path sets its own level.** `S_STK_FIN2` (`:2200`) does
  `rf_new_el <= stk_val[PSW_EL_HI:PSW_EL_LO]` for `RETIU`/`RETIS` — this was
  the most likely sibling, a `RETIS` after a `CHLVL` inheriting the leftover
  level, and it does not happen.
- `rf_new_is` at `:2538` is derived from `exc_kind`, like the fixed
  `rf_new_el`.
- Every one of the six `EK_*` branches of the frame `case` (`:2566`-`:2657`)
  assigns **all eight** frame fields, so no field carries over from the
  previous exception. `exc_param1 <= 32'd0` is hoisted above the case.

**C2 — Area 3, the mask walk: correct in every particular.** Against both
pages' diagram and Descriptions:

- bit *n* is R*n* for *n* = 0…30, bit 31 is the PSW, R31 has no bit —
  `S_PSM_SET` (`:2437`) writes `psw` and not `rf_ra` when `idx_r == 5'd31`.
- `PUSHM` scans MSB→LSB (`msk_highest`, `:960`) and `POPM` LSB→MSB
  (`msk_lowest`, `:970`), matching "from the MSB (PSW) to the LSB (R0)" and
  "from the LSB (R0) to the MSB (PSW)". The two round-trip.
- `POPM`'s PSW restore is half-width — `psw <= {psw[31:16], val2[15:0]}`
  (`:2482`) — which is p. 3.248's rule, and it also means `PSW.EL` and
  `PSW.IS` cannot change mid-instruction. The PSW is bit 31, so it is `POPM`'s
  **last** iteration; the restored flags are visible at `S_RETIRE`, where
  `ALU_POPM`'s `keep_all` passes `flags_in` straight back, so `S_RETIRE` does
  not undo them.
- The stack pointer is written **once**, at `S_PSM_SEL` when the mask empties
  (`:2414`). `PUSHM` leaves it at the lowest address written — "points to the
  last register pushed on the stack".
- **An empty mask** falls straight into that branch and writes R31 back
  unchanged: a no-op. The pages describe "1 to 32 registers" and say nothing
  about zero; a no-op is the only reading that does not invent behaviour.
- **The interaction with the operand's own addressing mode is right, and the
  reasoning in the comment holds.** `AM_RN_IND` raises no `rn_wb` — `v60_ea`
  raises it only for `am_is_reg_direct` with `we` (`:249`), `AM_RN_INC`
  (`:266`) and `AM_RN_DEC` (`:269`) — so the stack access consumes no
  writeback slot and `pushm [R5+]` does not trip `STOP_TWO_WB`. Tested at
  `tb_v60_seq.sv:2791` for `PUSH`. (Q4 above is the one case this argument does
  not reach.)

**C3 — Area 4, the frame rule, applied consistently and nowhere it does not
belong.** Instruction Exceptions carry the Current PC and restart, so nothing
may be committed; Arithmetic, Software Trap and Change Execution Level frames
carry the Next PC, so writebacks stand. Every raise site was classified:

| raised at | what | kind | before or after commit |
|---|---|---|---|
| `S_OP1` `:1370` `:1379` | `XCH` dst1 memory / immediate | `EK_INSN` | before — the source is not even read |
| `S_OP1` `:1388` | `IN` port, `MOVEA` source | `EK_INSN` | before |
| `S_OP2` `:1492` `:1502` `:1507` | immediate destination, bit offset, illegal mode | `EK_INSN` | before the destination access |
| `S_EXEC` `:1616` | `LDPR` id, **`CHLVL` level** | `EK_INSN` | before — both operands read, nothing written |
| `S_STK_WB` `:2147` | `RETIS` at a non-zero level | `EK_INSN` | before |
| `S_PR_SEL` `:2250` | `STPR` id | `EK_INSN` | before, with the reasoning in the comment |
| `S_RETIRE` `:1774` | zero divide | `EK_ARITH` | after — Next PC |
| `S_RETIRE` `:1781` | **`CHLVL` success** | `EK_CHLVL` | after — Next PC |
| `S_RETIRE` `:1792` | `TRAP` | `EK_TRAP` | after — Next PC |
| `S_TRAPFL` `:2224` | `TRAPFL` | `EK_ARITH` | after — Next PC |
| `S_IDLE` `:1285` | `BRK` | `EK_INSN` | Current PC, which `docs/v60/BREAK-AND-TRAP.md` settles against `BRK`'s own Operation block |
| `S_IDLE` `:1299` | `BRKV` | `EK_ARITH` | after — Next PC |

`CHLVL` is the interesting one and it is right both ways: its **failure** is an
Instruction Exception raised at `S_EXEC`, before the addressing-mode writeback
at `S_RETIRE`; its **success** is raised at `S_RETIRE` after it, because the
Change Execution Level frame carries the Next PC and the instruction has
completed. Both halves of one instruction, on opposite sides of the rule, and
both correct.

**C4 — Area 1, the lock's span during a locked operation.** `dx_lock =
lock_r && (S_ACC || S_RMW || S_RMW_GO || S_ACC2)` (`v60_ea.sv:153`). Traced
edge by edge:

- `S_ACC` → `S_RMW` is a single transition with both states in the set, so
  there is **no gap** at the point that matters — the boundary between the
  read and the wait for `rmw_go`.
- `S_RMW` waits for `rmw_go` for as long as the sequencer needs (`S_EXEC`,
  `S_CAXI_R`, `S_WB`), and the lock is held throughout.
- `v60_bus_arb` releases the grant at **every** `biu_ack` (`:83`), so it
  re-arbitrates in the gap — which is exactly the window `d_lock` has to close,
  and it does (`:96`).
- `v60_biu` raises `block_n` at T1 and drops it at `T_TI` **only if `lock` is
  low** (`:325`), so the pin does not fall between the two bus cycles of one
  read-modify-write.
- The lock falls when `v60_ea` leaves `S_ACC2` on `dx_done`, which is the
  completion of the last bus cycle — the µPD70632 rule's "deasserted … of the
  last bus cycle of the operation".

**C5 — excluding `S_PTR` is correct, and nothing that should be included is
excluded.** The pointer chase of an indirect mode is address computation, and
the rule is "assert at T1 of the **first bus cycle of the indivisible
operation**" — the pointer read is not part of it. `S_ISSUE`, the one-cycle
state between `S_PTR` and `S_ACC`, is also outside the set and also correct: no
bus cycle happens in it, so the only effect is that the arbiter may grant the
prefetch unit one fetch *before* the locked operation starts, which is not
inside it.

**C6 — a `TASI` with a register destination asserts nothing, correctly.** The
page says "If the register addressing mode is specified for the destination,
the execution of the instruction is meaningless but the operation is carried
out." `v60_ea` takes the reg-direct path with no bus cycle, and p. 3.236 says
`BLOCK*` is "asserted **during a bus cycle**" — no cycle, no assertion. Right
by construction rather than by a check.

**C7 — the `dx_lock = 1'b0` on `v60_dmux`'s B branch cannot fire inside a
locked operation.** This was the most promising-looking hole and it is closed,
by a deliberate piece of design elsewhere. `v60_seq`'s `S_OP2W` (`:1577`) takes
the read-modify-write completion through `ea_rmw_pending`, **not** `ea_done`,
under the comment "the access is still open and closing it is the only way out,
so a fault here is taken one bus cycle later, at `S_WBW`". So a bus error on
the read half of a `TASI` does not abandon the access: `S_WB` still issues
`rmw_go`, `v60_ea` runs `S_ACC2` and returns to `S_IDLE`, and only then does
`S_WBW` raise `EK_BERR` and `v60_exc` assert `b_req`. There is no reachable
state in which port B asks while `v60_ea` holds `dx_lock`. (Had that comment
not been there, `v60_ea` would have wedged in `S_RMW` for ever — its only exit
is `rmw_go`.)

**C8 — `v60_alu`'s five new operations.** Checked against the pages, and
untested at present because the ALU bench does not build in the working tree
(see the baseline note).

- `ALU_TASI`: `xa` is forced to `0xFF & mask` (`:161`), which makes `diff` the
  page's `dst - 0FFH`; `raw = 0xFF` unconditionally, matching "dst ← 0FFH …
  whatever the comparison said"; and `tasi_op` (`:496`) takes `S` and `Z` from
  `diff` rather than from `raw`, which is required — "Set if the comparison
  results are zero", where the value written is always `0xFF`. The flag
  concatenation `{f_cy, f_ov, S, Z}` matches `{PSW_CY, PSW_OV, PSW_S, PSW_Z}` =
  bits 3:0. `OV` uses the standard subtract test; spot-checked at the one case
  that separates it, a byte destination of `0x7F`, where `0x7F - 0xFF` is
  `0x7F + 1` and overflows.
- `ALU_CAXI`: `diff` is `y - x` with `x` = operand 1 = `Rn` and `y` = operand 2
  = `dst`, i.e. the page's `flags ← dst - Rn` — the right way round, which is
  the thing worth checking. `writes = 0`, and `S_WB`'s `is_caxi` branch is
  tested **before** `!eff_writes`, so the sequencer's own write is not
  suppressed.
- `ALU_XCH`: `raw = x` sends dst1's value to dst2; `xch_wdata` (`v60_seq:999`)
  masks dst2's value to `w_dst` for dst1. Both operands are the same size on
  every syntax line, so one width is right for both.
- `keep_all` gains all seven of the flag-free additions, matching seven
  all-Unchanged Condition Codes blocks.

**C9 — `XCH`'s two exceptions from one operand column.** `xch_d1_mem` →
Reserved Addressing Mode, `xch_d1_imm` → Illegal Addressing Mode, both at
`S_OP1` before anything is read. That is the page's own legend — "`X` Illegal
Addressing Mode / `A` Reserved Addressing Mode", printed under the `XCH` table
— and it is what p. 3.296's `1, 3` on that row decomposes into. `xch_rn =
src_is_reg ? idu_reg : op1_rn` covers both Format I and Format II placements.
An `XCH` whose memory destination faults does **not** write dst1: `S_WBW`
tests `berr_r` before `is_xch`.

**C10 — `PREPARE` and `DISPOSE`.** `FP <- sp_r - 4` uses the **updated** SP,
which is the word the Description leans on; `SP <- sp_r - 4 - val1` treats
`num` as a byte count, "adjusted by the specified number of bytes"; `DISPOSE`
reads at `rf_rb` (FP) and not at SP, which is why it needs no operand; and
`SP <- fp_r + 4` puts the stack back above the frame whatever it contained.
Neither touches R29 — correct, §3 gives the argument pointer to `CALL`.

**C11 — operand widths in `v60_op_pkg`.** `TASI` 1 byte (`9'h1C0`), `PUSH`,
`POP`, `PUSHM`, `POPM`, `PREPARE` 4 (`9'h1C8`…`9'h1DF`, `9'h1BC`), `DISPOSE`
none (`9'h198`), `CHLVL` 1 and 1 (`9'h096`/`9'h097`). All match their syntax
lines.

**C12 — the `CAXI` test is well built.** `tb_v60_seq.sv:3104`-`3140` checks the
match case installs R28 and leaves `Rn` alone, and the mismatch case uses a
**third** value distinct from both R28 and `Rn`, with the comment explaining
why — "with R28's value still sitting in memory, 'Rn takes what was there' and
'Rn takes R28' cannot be told apart". That is the kind of test that would have
caught a wrong answer, and it is worth saying so given W1–W3 above.

---

## The two `insn_table.py` changes you asked me to re-check

**`CHLVL` `(1, 4)` → `(1, 1)`: correct.** The syntax line is `chlvl level.b.r,
arg.b.r` — both operands are bytes, and the Reference's Instruction column and
`docs/v60/v60_operand_access.csv` agree. The new comment's reasoning is also
right: the zero-extension to word length is a property of the **push**, not of
the operand fetch, and reading `arg` as a word would fetch three bytes that are
not the operand's. `v60_op_pkg.sv:486` was moved in step. **D2 above is the
half of this correction that did not land in the RTL.**

**The `XCH` format disagreement: recorded correctly, but the table's policy is
now inconsistent with itself.** The `DISAGREEMENTS` entry is accurate and its
reasoning is sound. The problem is the sentence "the plate is the source this
table is built from", used to justify keeping `'I,II'` — because in the *same
commit range* the table stopped doing that for five rows: `PUSH`, `POP`,
`PUSHM`, `POPM` and `PREPARE` are now `'III'` with the page cited as
`'PgmRef §7 PUSH'` and so on, **against** p. 3.298's `II`.

So the table now resolves one plate-versus-Reference format conflict in the
Reference's favour and leaves an adjacent one in the plate's, on the stated
grounds that the plate is the source. Both individual calls are defensible —
the stack rows have the trailing `-` corroborating Format III and `XCH` has
nothing equivalent — but the *stated* reason for the `XCH` call is no longer
the table's practice. One sentence naming the distinguisher (the `-`) would
make the two consistent. **Nit, not a defect**; the encoding is unaffected
either way, which the entry already says.

---

## Also worth knowing

`docs/v60/v60_operand_access.csv` is **not tracked by git** — it exists on disk
but not in `3fd9c1b`. `insn_table.py`'s cross-check silently skips when it is
absent, and `run_v60x.sh` then reports `the instruction table does not
validate` with `0 cross-checked`. Locally it passes because the file is there;
on any fresh clone, and in CI, the cross-check does not run. That is a
different failure mode from the one this audit is about, but it means one of
the table's two validators is load-bearing only on this machine.
