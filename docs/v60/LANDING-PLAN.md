# Clean-room V60 landing plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land `v60/cleanroom` on `main`, give the clean-room core a top level and a fit, and run it in lockstep against the shipping core so its page-backed findings flow into `rtl/cpu/v60/s32_v60.sv` one PR at a time.

**Architecture:** Stage 1 makes the branch mergeable (CI-runnable suite, current documents, the four plate readings folded in). Stage 2 lifts the wiring that lives in `verif/v60x/tb_v60_seq.sv` into `rtl/cpu/v60x/v60_top.sv` and fits it standalone in Quartus. Stage 3 puts both cores on one generated program image and compares architectural state per retired instruction; disagreements are adjudicated by the pages, and the runner reports them per opcode.

**Tech Stack:** SystemVerilog, Icarus Verilog (CI) and Verilator (local), Python 3, Quartus Lite 17.0, GitHub Actions. Simulators on this Windows machine run in Docker `hdlc/sim:osvb` with `MSYS_NO_PATHCONV=1` on a CRLF-normalised copy of the tree (see the memory note `sim-via-docker`).

**Spec:** the status report published 2026-09-05 (artifact `788e931e`), sections "Remaining work" and "Recommendation", stages 1–3.

## Global Constraints

- Every claim in `rtl/cpu/v60x/` carries the page it came from; anything not from a page is marked at the point of decision (`rtl/cpu/v60x/README.md`).
- Every clean-room bench runs under both Icarus and Verilator locally; CI has Icarus only.
- Nothing under `rtl/cpu/v60x/` enters `files.qip`. The bitstream must not change.
- The shipping core's regression gates stay as they are: `verif/v60/run_v60_icarus.sh`, `verif/cosim/run_diff.sh 50`, `verif/run_core_gate.sh`.
- NEC scans stay in the private submodule `docs/reference/`. Never copy them into the tree. `v60_operand_access.csv` is our own derived data and may be tracked.
- Commit messages end with the `Co-Authored-By` and `Claude-Session` trailers used in this session. Branch from `main` for shipping-core changes; the clean-room work goes on `v60/cleanroom`.
- Lint: `verible-verilog-syntax.exe <file>` after every HDL edit (`CLAUDE.md`).

---

## Stage 1 — make `v60/cleanroom` mergeable

### Task 1: Track the operand-access table and point the generator at it

**Files:**
- Create: `tools/v60x/v60_operand_access.csv` (copy of `docs/reference/v60_operand_access.csv`)
- Modify: `tools/v60x/insn_table.py:809-817` (the `_csv_path` computation)

**Interfaces:**
- Produces: `python3 tools/v60x/insn_table.py` exits 0 with `66 cross-checked` on a bare checkout, no submodule needed.

- [ ] **Step 1: Reproduce the failure on a bare tree**

Run: `python tools/v60x/insn_table.py; echo rc=$?`
Expected: `ERROR    the operand-access cross-check did not run`, `rc=1`.

- [ ] **Step 2: Copy the table and repoint the generator**

```bash
cp /c/Users/mcnut/projects/nec-v60-references/v60_operand_access.csv tools/v60x/v60_operand_access.csv
```

In `insn_table.py` replace the `_csv_path` lines with:

```python
    # The table lives beside this script.  It is our own extraction from the
    # Reference's §7 operand lines (see docs/reference/V60_instruction_timing_2026-08-25.md),
    # not NEC's text, so it is tracked here rather than left in the private
    # submodule -- CI has no access to that submodule and this check must run there.
    _csv_path = _os.path.join(_here, 'v60_operand_access.csv')
```

Also fix the docstring of `cross_check()` (`docs/v60/v60_operand_access.csv` → `tools/v60x/v60_operand_access.csv`).

- [ ] **Step 3: Verify**

Run: `python tools/v60x/insn_table.py | tail -2; echo rc=$?`
Expected: `135 rows, 285 encodings, 0 errors, 0 collisions, 66 cross-checked`, `rc=0`.

- [ ] **Step 4: Commit**

```bash
git add tools/v60x/v60_operand_access.csv tools/v60x/insn_table.py
git commit -m "v60x: track the operand-access table beside the generator that checks against it"
```

### Task 2: Make the benches build on Verilator 5.027

**Files:**
- Modify: whichever of `verif/v60x/tb_v60_*.sv` Verilator reports `%Error-LIFETIME` on. Known: `tb_v60_biu_tstates.sv:162` (`repeat` inside a `fork … join_none` branch).

**Interfaces:**
- Produces: `WORK=/tmp/v60x bash verif/v60x/run_v60x.sh` reports `34 passed, 0 failed` in the Docker container.

- [ ] **Step 1: Collect every error**

Run (Docker, normalised copy): for each bench, `verilator --binary --timing -Wno-fatal -Wno-lint --top-module <tb> …` and grep `%Error`. Save the list to the scratchpad.

- [ ] **Step 2: Fix each site with a static loop variable**

Pattern. Before:

```systemverilog
        begin : release_ready
            @(negedge clk);
            wait (state === T_TW);
            repeat (DIV*2) @(negedge clk);   // hold for two TW states
            ready_n = 1'b0;
        end
```

After:

```systemverilog
        begin : release_ready
            integer k;                       // static: Verilator 5.027 rejects
                                             // a repeat counter here (LIFETIME)
            @(negedge clk);
            wait (state === T_TW);
            for (k = 0; k < DIV*2; k = k + 1) @(negedge clk);   // two TW states
            ready_n = 1'b0;
        end
```

Only sites Verilator names are changed. `repeat` elsewhere stays.

- [ ] **Step 3: Verify both simulators**

Run: the Docker suite. Expected: `V60X: 34 passed, 0 failed` and `V60X: ALL PASS`.

- [ ] **Step 4: Commit**

```bash
git add verif/v60x/
git commit -m "v60x: a repeat inside a forked branch does not build on Verilator 5.027"
```

### Task 3: Icarus-only mode for the runner, and a CI job

**Files:**
- Modify: `verif/v60x/run_v60x.sh` (the `run()` function and the `WORK` default)
- Modify: `.github/workflows/v60-gate.yml` (new job after `v60-unit`)

**Interfaces:**
- Produces: `V60X_SIMS=icarus bash verif/v60x/run_v60x.sh` runs 17 benches under Icarus only and exits 0. Default is unchanged: both.

- [ ] **Step 1: Add the switch**

At the top of `run_v60x.sh`, after `export PYTHONDONTWRITEBYTECODE=1`:

```bash
# Which simulators to run.  Default both, on purpose (see the header).  CI has
# no Verilator, so it sets V60X_SIMS=icarus; a bench that passes there and
# fails locally under Verilator is still a failure.
SIMS="${V60X_SIMS:-icarus verilator}"
```

Wrap the Icarus half of `run()` in `if [[ " $SIMS " == *" icarus "* ]]; then … fi` and the Verilator half in `if [[ " $SIMS " == *" verilator "* ]]; then … fi`. Change `WORK="${WORK:-/tmp/v60x}"` to `WORK="${WORK:-$(mktemp -d)}"`.

- [ ] **Step 2: Add the job**

```yaml
  v60x-unit:
    name: Clean-room V60 suite (Icarus)
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Install Icarus Verilog
        run: |
          sudo apt-get update -qq
          sudo apt-get install -y --no-install-recommends iverilog
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      # Both simulators locally; Icarus alone here.  The runner regenerates the
      # opcode package first and fails if the checked-in copy is stale.
      - name: Clean-room benches
        run: V60X_SIMS=icarus bash verif/v60x/run_v60x.sh
```

- [ ] **Step 3: Verify**

Run (Docker): `V60X_SIMS=icarus bash verif/v60x/run_v60x.sh | tail -3`. Expected: `V60X: 17 passed, 0 failed`. Then the default: `34 passed`.

- [ ] **Step 4: Commit**

```bash
git add verif/v60x/run_v60x.sh .github/workflows/v60-gate.yml
git commit -m "ci: gate the clean-room suite, Icarus only where that is all there is"
```

### Task 4: Bring the documents current and fold in the four plate readings

**Files:**
- Modify: `rtl/cpu/v60x/README.md` ("Not built yet", lines 266–284)
- Modify: `docs/v60/EXCEPTIONS.md:283-287` (NMI masking bullet)
- Modify: `docs/v60/NEXT-STEPS.md` (header note; item 3's bit-string bullet; the FP bullet)
- Modify: `docs/v60/FLOATING-POINT.md` (item 1 of "What the pages do not settle", line 634; the addendum's close)
- Modify: `docs/v60/MMU-AND-TASKS.md:832-842` (item 1 of §12)
- Modify: `docs/v60/TRANCHE-TWO.md:538-546` and `:572-580` (CHLVL inequality)
- Modify: `docs/v60/BIT-FIELD.md:515-522`, `docs/v60/BREAK-AND-TRAP.md:5-14`, `docs/v60/INTERRUPTIBILITY.md:428-438` ("PDF is not held" → held)

**Interfaces:**
- Produces: no document says the Reference PDF is not held; the four plate results are recorded where the open item was.

- [ ] **Step 1: README "Not built yet"** — replace the two paragraphs from "No MMU, no FPU" through "waiting on." with:

```markdown
No MMU translation, no task switching, no address traps, no emulation mode.
**93 of the instruction table's 135 mnemonics execute** and are benched; the
42 that do not are four groups, each its own subsystem: the floating point
arithmetic (twelve — `MOVF`, `NEGF` and `ABSF` are done), the character
strings (eight), the bit strings (ten) and the MMU and task group (twelve).
`tools/v60x/insn_table.py`'s `EXEC_OP`, `EXEC_OP_ESCAPE` and `CTRL_OP` are the
authority on which is which.

`docs/v60/NEXT-STEPS.md` is the ordered list of what is open and what each
piece would take; `docs/v60/LANDING-PLAN.md` is how this tree reaches `main`
and the shipping core.
```

- [ ] **Step 2: EXCEPTIONS.md NMI bullet** — replace "There is no RETIS." with "`RETIS` exists now (`docs/v60/RETURN-PAIRS.md`); the hold-off itself is not implemented: nothing records that an NMI is in progress."

- [ ] **Step 3: NEXT-STEPS.md** — under the header, after the first paragraph, add:

```markdown
**Updated 2026-09-05.** The Programmer's Reference scan is held now, as
`docs/reference/NEC_V60_ProgrammersRef_1986.pdf` (private submodule), and four
items that were waiting on its plates are closed: `SUBF`'s operand order
(p. 7-108, `dst ← src − dst`), the TCB layout direction (Figure 5-1, base at
`TKCW`, ascending), `CHLVL`'s inequality (p. 7-18 contradicts itself; the
prose stands) and the SBT's low end (Figure 8-2 confirms every vector this
tree uses). Each is recorded in the document that raised it.
```

In item 3, change the FP bullet to: "**The floating point arithmetic** — `ADDF` `SUBF` `MULF` `DIVF` `CMPF` `SCLF` `CVTF` and the five `CVT` forms. `MOVF`, `NEGF`, `ABSF` are done (`docs/v60/FLOATING-POINT-AUDIT.md`). Five decisions remain recorded in `FLOATING-POINT.md`; `SUBF`'s order is no longer one of them. The MMU, task and context switching, address traps and emulation mode each remain their own subsystem."

- [ ] **Step 4: FLOATING-POINT.md item 1** — append to the item: "**Settled 2026-09-05 on the plate.** p. 7-108 prints `dst ← src − dst` and its Description says 'the difference of the source operand and destination operand'. The OCR was faithful; `SUBF` is source-first, the sole such operation in the integer or floating point sets. Implement it that way and cite the page." Append the same two sentences at the end of the addendum under a heading `## 8. Read on the plate`.

- [ ] **Step 5: MMU-AND-TASKS.md §12 item 1** — append: "**Settled 2026-09-05 on the plate.** Figure 5-1 (p. 5-2) draws the 'TCB Base Address' arrow at `TKCW`, the bottom row, with `L0SP..L3SP`, `R0..R30`, then `ATBR0..ATLR3` above it: addresses ascend up the figure. `s32_v60.sv`'s layout is correct."

- [ ] **Step 6: TRANCHE-TWO.md CHLVL** — after "Recorded as OCR-suspect rather than resolved." append: "**Read on the plate 2026-09-05** (p. 7-18): the printed expression really is `level < PSW.EL` beneath prose that says the opposite. The book contradicts itself; the prose reading, the only one under which the instruction can reach a more privileged level, stands." In the "What the pages do not settle" list change the CHLVL bullet's tail to "the prose and the printed expression are negations on the plate itself; the prose is taken".

- [ ] **Step 7: "PDF is not held" sites** — BIT-FIELD.md: replace "The figure has not been read on a plate: … does not contain §8." with "Read on the plate 2026-09-05 (Figure 8-2, p. 8-2): Illegal Data Field is vector 20 at +80, Reserved Opcode 16 at +64, Area Not Present 8 at +32. The anchor holds." BREAK-AND-TRAP.md: change "PDF is not held" to "PDF was not held when this was written; it is now `docs/reference/NEC_V60_ProgrammersRef_1986.pdf`, and Figure 8-5 and BRK's page remain to be read on it." INTERRUPTIBILITY.md: change "The Programmer's Reference PDF is not held (only its OCR)" to "The Programmer's Reference PDF is held now (`docs/reference/`)".

- [ ] **Step 8: Commit**

```bash
git add rtl/cpu/v60x/README.md docs/v60/
git commit -m "docs: the Reference is held; four plates read, and the tree's own status brought current"
```

### Task 5: Push, open the PR, merge when green

- [ ] **Step 1:** `git push -u origin v60/cleanroom`
- [ ] **Step 2:** `gh pr create --base main --head v60/cleanroom` with a body that lists: 93/135, the 6B/7B shipping-core change and its bench, the CI job, what the four plates settled, and that the four-game hardware check has not been run for the 6B/7B change.
- [ ] **Step 3:** Wait for the gate (`gh pr checks --watch`). Merge with a merge commit, as the repository does (`gh pr merge --merge`). Do the same for PR #23 first.

## Stage 2 — a top level and a fit

### Task 6: `v60_top.sv`

**Files:**
- Create: `rtl/cpu/v60x/v60_top.sv`
- Create: `verif/v60x/tb_v60_top.sv`
- Modify: `verif/v60x/run_v60x.sh` (add `v60_top.sv` to `RTL`; add `run tb_v60_top "V60 TOP PASS"`)

**Interfaces:**
- Produces module `v60_top`:

```systemverilog
module v60_top #(parameter logic [31:0] START_PC = 32'h00FF_FFF0) (
    input  logic        clk, rst, ce_rise, ce_fall,
    input  logic        run,                  // execute while high
    // databook pins
    output logic [23:0] a,        output logic [1:0] dl_o,   output logic [2:0] st,
    output logic        mrq_n, rw_n, ube_n, fas_n, bcy_n, ds_n, block_n, hldak_n, bus_hiz,
    output logic [15:0] d_out,    output logic       d_oe,   input  logic [15:0] d_in,
    input  logic        ready_n, bmode, hldrq_n, berr_n, rt_ep_n, nmi_n, int_req,
    // observation
    output logic [31:0] pc, psw,  output logic retired, stopped,
    output logic  [1:0] stop_reason, output logic [4:0] insn_cycles,
    output bus_state_e  state,
    // placement of privileged registers before run (a bench's LDPR substitute)
    input  logic  [4:0] pr_id, input logic pr_wr, input logic [31:0] pr_wdata
);
```

Internally: the exact instantiations from `tb_v60_seq.sv` lines 62–420 (`pfu`, `idu`, `rf`, `ea`, `exc`, `dmux`, `dxu`, `seq`, `arb`, `biu`), with the bench's `redirect` replaced by a one-shot `redirect` to `START_PC` on the first cycle out of reset and the bench's `pr_wr` mux kept as the port above. Hierarchical names `u_rf.gpr`, `u_seq`, `u_biu` for benches to observe.

- [ ] **Step 1: Write `tb_v60_top.sv`** — the failing test: instantiate `v60_top` with `START_PC = 0`, a 64 KB byte-bank RAM driven from the pins exactly as `tb_v60_seq.sv` models it (`bank_even`), `$readmemh` a `+hex=` image in the `gen_diff_program.py` format (16-bit words), run until `stopped` or `u_seq` executes HALT (`pc` stops advancing and `retired` stays low for 64 cycles), then `$display` `R%0d=%08x` for R0..R7 and `M%0d=%08x` for the eight scratch words at `0x8000`, and `V60 TOP PASS` if the run ended by HALT. Generate the image with `python verif/cosim/gen_diff_program.py 1 /tmp/p1` and compare the printed lines against `/tmp/p1.expected` in the runner.
- [ ] **Step 2: Run it** — fails: `v60_top` not found.
- [ ] **Step 3: Write `v60_top.sv`** as specified.
- [ ] **Step 4: Run** under both simulators: `V60 TOP PASS`. Expect the register lines to match `p1.expected` except where a page-backed divergence is known (`MUL` overflow → the PSW captured in R7). Record any mismatch; do not "fix" the clean-room to match.
- [ ] **Step 5: Lint** both files with Verible; commit `v60x: a top level, lifted from the bench that had been the only one`.

### Task 7: Standalone Quartus fit

**Files:**
- Create: `verif/quartus_v60x/v60x_fit.qpf`, `v60x_fit.qsf`, `v60x_fit.sdc`, `v60x_probe.sv`
- Create: `docs/v60/FIT-RESULT.md`

- [ ] **Step 1: Project** — `v60x_probe` wraps `v60_top` with every port at the boundary (as `verif/quartus_v60/top.sv` does for the shipping core). QSF: `FAMILY "Cyclone V"`, `DEVICE 5CSEBA6U23I7`, all `rtl/cpu/v60x/*.sv` in package order, `TOP_LEVEL_ENTITY v60x_probe`. SDC: `create_clock -period 10.348 [get_ports clk]` (clk_ram), `set_false_path` on `rst`.
- [ ] **Step 2: Run** `quartus_map`, `quartus_fit`, `quartus_sta` from `C:\intelFPGA_lite\17.0\quartus\bin64` in the background; expect 20–40 minutes.
- [ ] **Step 3: Record** ALMs, registers, M10K, Fmax on `clk`, and the worst ten setup paths in `FIT-RESULT.md`, beside the shipping core's 37,423-ALM whole-design figure for scale. Commit `v60x: the first fit, and what it says about area and closure`.

## Stage 3 — lockstep against the shipping core

### Task 8: `tb_v60_lockstep.sv` and its runner

**Files:**
- Create: `verif/v60x/tb_v60_lockstep.sv`
- Create: `verif/v60x/run_lockstep.sh`
- Create: `verif/v60x/gen_lockstep_program.py`

**Interfaces:**
- Consumes: `v60_top` (Task 6); `s32_v60` + `s32_v60_bus` as in `verif/v60/tb_v60_diff.sv`.
- Produces: `bash verif/v60x/run_lockstep.sh N` prints one line per divergence class, `DIVERGE op=<hex> mnemonic=<name> field=<R7|PSW.OV|M3|PC> seeds=<k>`, then `V60 LOCKSTEP: <n> seeds, <m> diverging, <p> stops` and exits 0 when every divergence is in the known list `verif/v60x/lockstep_known.txt` (one `op field` pair per line, each with the page that adjudicates it).

- [ ] **Step 1: The bench.** Two RAM copies loaded from the same `+hex=`. Shipping core wired as `tb_v60_diff.sv` does, clean-room as `tb_v60_top.sv` does. A retire event for the shipping core is `cpu.st == S_DECODE` on a `ce` edge with `cpu.pc` changed since the last one; for the clean-room it is `retired`. Keep two instruction counters; after each side's k-th retire, snapshot `{pc, psw[3:0], r[0..30]}`; when both have the k-th snapshot, compare and `$display("DIVERGE k=%0d pc=%08x op=%02x field=…")` with the opcode byte read from RAM at that pc. Stop the comparison at the first `stopped` from the clean-room (`STOP …` line with the opcode) and at HALT. At the end compare the 64 scratch bytes at `0x8000`.
- [ ] **Step 2: The generator.** Start from `gen_diff_program.py`'s `Asm` and add: byte and halfword forms of the ALU ops (`0x80/0x82` ADD.B/H etc. from `insn_table.py`), `INC`/`DEC`/`NEG`/`NOT`/`TEST`, the shift group (`SHL`/`SHA`/`ROT`/`ROTC` with quick counts), `MOVS`/`MOVZ`/`MOVT`, register-indirect and `disp8[Rn]` operands against the scratch area, and `SETF`. Every emitted instruction gets a comment with its page. No control flow yet.
- [ ] **Step 3: Run 50 seeds** under Icarus (Docker). Expected divergences, each page-backed and each to be entered in `lockstep_known.txt`: `MUL` overflow (`PSW.OV`, §7 MUL, signed fit), and whatever else appears. Anything not page-backed is a defect in one core and is written up rather than hidden.
- [ ] **Step 4: Commit** `v60x: the two cores on one program, compared where each instruction ends`.

### Task 9: Exposure trace for the romboot bench (ready for a ROM-equipped machine)

**Files:**
- Modify: `verif/common/tb_core_romboot.sv` (near the `PFTRACE` block, line ~992): `+OPTRACE=<file>` writes one `%08x %02x %02x` line (pc, opcode byte, second byte) per shipping-core instruction boundary.
- Create: `tools/v60x/exposure.py`: reads that file, maps opcode (and sub-op for `58/59/5A/5B/5C/5D/5E/5F`) to a mnemonic through `insn_table.py`'s `TABLE`, and prints counts per mnemonic with a column saying whether the clean-room executes it. Unit test with a hand-written six-line trace in `verif/v60x/test_exposure.py` (pytest, like `verif/test_*.py`).

- [ ] Steps: write test, run (fails), write tool, run (passes), lint the bench edit, commit `verif: count which V60 instructions a game actually executes`.

### Task 10: Record and open the PR

- [ ] `docs/v60/LOCKSTEP.md`: what the bench compares, the 50-seed result, the known list with pages, and the command to run the exposure tool on `roms/sim/<game>` once ROMs are present.
- [ ] Update `NEXT-STEPS.md` item ordering from the measured divergences.
- [ ] PR `v60/cleanroom` → `main` (second PR), gate green, merge.

## Self-review

- Spec coverage: stage 1 items 1–5 (docs, plates, CSV, Verilator, CI) → Tasks 1–5. Stage 2 (top, adapter, fit) → Tasks 6–7; the adapter to `s32_core`'s memory contract is deferred: the lockstep bench drives the pins directly and nothing else consumes them yet (YAGNI). Stage 3 (lockstep, exposure) → Tasks 8–9; game-code lockstep needs ROMs, which this machine lacks, so Task 9 delivers the tool and Task 8 the evidence on generated programs.
- Names: `v60_top`, `u_rf`, `u_seq`, `retired`, `stopped`, `stop_reason`, `START_PC`, `V60X_SIMS`, `lockstep_known.txt`, `exposure.py` used consistently above.
