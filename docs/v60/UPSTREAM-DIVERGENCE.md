# What this core's V60 does that upstream's does not, and whether any game notices

**Measured 2026-09-05.** The question this answers is the one the hardware gate
raised: the four gate games behave differently on this core than expected, and
the clean-room merge (PR #24) was the suspect. It is not the suspect. Neither
is anything else in the V60.

Three trees are involved and it is worth naming them once:

| | what it is |
|---|---|
| **upstream** | `meathax/s32`, `rtl/cpu/v60/s32_v60.sv` |
| **ship** | this fork's `rtl/cpu/v60/s32_v60.sv` — what the RBF contains |
| **clean** | `rtl/cpu/v60x/` — the clean-room core |

## The first finding is that `clean` is not in the bitstream

`rtl/cpu/v60x/` appears in no `.qip` and no `.qsf` for the game revision, and
nothing outside `verif/` instantiates `v60_top`. The only mention of it in
shipping RTL is a comment at `rtl/cpu/v60/s32_v60.sv:1467`. The one QSF that
does compile it, `verif/quartus_v60x/v60x_fit.qsf`, is the standalone fit.

Worth stating precisely, because reading `files.qip` alone gets this wrong: the
shipping source list is `files.qip` **plus** the QSF's own two entries,
`rtl/prot/s32_prot.sv` and `rtl/cpu/v25/v25.qip`. There is one revision,
`Arcade-SegaSystem32`. With those three lists in hand, every synthesized source
is accounted for and `rtl/cpu/v60x/` is in none of them.

So the clean-room core cannot change any game's behaviour. What PR #24 changed
in the bitstream is one commit, `e9fc86d`, 62 lines: **`6B` and `7B` decode as
`Bcc` instead of raising the reserved-opcode exception.** Everything else in
that PR is `v60x/`, `verif/`, `docs/` and `tools/`.

## What `ship` and `upstream` actually differ by

451 lines across 23 hunks in `s32_v60.sv`, plus a near-total rewrite of
`s32_v60_bus.sv`. Most of it cannot reach a game:

| difference | why it is inert |
|---|---|
| bus rewritten from `I_IDLE/I_CYC/I_WAIT` to NEC T-states `T_TI…T_TH` | `s32_core.sv:505` instantiates it with `DATABOOK_TIMING=0`, `HALF_CLOCK_SAMPLING=0`, `ready_n=1'b0`, `hldrq=1'b0`, `bfrez_n=1'b1`. It collapses to TI→T1→T3→TI, which *is* upstream's three states, and `ready_now` reduces to `m_ack`. |
| NEC status pins `st`, `mrq_n`, `rw_n`, `bcy`, `ds`, `ube`, `hldak`, `block_n`, `rt_ep` | all unconnected at `s32_core.sv:518` |
| NMI edge counter replacing `nmi_r`/`nmi_seen` | `.nmi_n(1'b1)` — `s32_core.sv:409`. Dead. |
| `seq_idx` clamp, `fb[total_len[2:0]]` → `fb[total_len<24 ? total_len : 0]` | `seq_required` is consumed only under `seq_dispatch_now`, which requires `total_len <= 4`; the two expressions agree below 8. Defensive, not behavioural. |
| `dbg_pc` / `dbg_st` / `dbg_halted` | observation-only outputs |
| ~220 lines of handshake assertions in both files | inside `` `ifndef SYNTHESIS `` |

Four differences *are* live, and they are what had to be measured:

- **D1 — external-write prefetch invalidation.** Upstream invalidates the
  prefetch buffer only on the CPU's own writes. `ship` adds `ext_wr` snooping
  (`s32_v60.sv:4105`), wired at `s32_core.sv:727` to
  `work_pr_we | sh_z80_wr | ext_hold`.
- **D2 — HALT wake refills.** `st <= S_DECODE` became
  `st <= S_FILL; st_after_fill <= S_DECODE` (`s32_v60.sv:4008`).
- **D3 — interrupt vector width.** Upstream `exc_vector <= irq_vector + 8'h40`
  into `reg [7:0]`; `ship` `{1'b0, irq_vector} + 9'h40` into `reg [8:0]`
  (`s32_v60.sv:1406`). `irq_vector` is `ctl[i]` from `rtl/io/s32_io.sv:774` — a
  register the *game* programs — so a vector ≥ `0xC0` wraps upstream.
- **D4 — `6B`/`7B` as `Bcc`.** The whole of PR #24's shipping change.

Minor, and not separately measured: `CHLVL`'s `exc_code` moved the level from
the top byte to the second (`s32_v60.sv:4974`), and `bus_lock_r` now deasserts
on the last cycle of an indivisible operation.

## The measurement

Each game was booted on `ship` under Verilator 5.052 **in its own shipping
protection configuration** — the real V25 for `ga2`, the HLE responders for the
other three — for 180 frames, with `+OPTRACE` for D4 and
`verif/v60/tb_v60_delta_probe.sv` bound into `s32_v60` for D1–D3. The probe
drives nothing and prints once at `$finish`.

**25,965,036 instructions.** All four reached `ROMBOOT DONE`.

| | ga2 | spidman | radr | darkedge |
|---|---|---|---|---|
| instructions | 4,909,043 | 4,533,299 | 11,119,759 | 5,402,935 |
| **D4** `6B`/`7B` executed | **0** | **0** | **0** | **0** |
| **D2** HALT entered | 0 | 0 | 0 | 0 |
| **D3** IRQ dispatches | 23 | 338 | 1,280 | 1,286 |
| **D3** vectors that wrap upstream | **0** | **0** | **0** | **0** |
| **D1** external writes | 0 | 0 | 0 | 537 |
| **D1** prefetch invalidations | **0** | **0** | **0** | **0** |

Across all 2,927 interrupt dispatches the only vectors seen are `00`, `01`,
`03` and `04`. Upstream's truncation needs `≥ 0xC0`; nothing comes within
`0xBB` of it. (The INTC resets `ctl[]` to `0xFF` — `s32_io.sv:783` — which
*would* wrap, but `ctl[6]=0xFF` masks every source until the game programs
both, and all four games program vectors before unmasking.)

D1 needs its own line, because `darkedge` drives 537 external writes and still
invalidates nothing. Executed PCs, by address region:

```
ga2       4,904,884 @ region 1      4,158 @ region 0      1 @ region f
spidman   4,533,298 @ region 0                            1 @ region f
radr     11,119,758 @ region 0                            1 @ region f
darkedge  5,402,934 @ region 0                            1 @ region f
```

(The single region-`f` entry per game is the reset vector, before the first
fetch.) **Every game executes entirely out of ROM.** Every external write
targets region 2 (`pr_wr_paddr = 24'h200000 | …`) or region 7
(`sh_wr_paddr = 24'h700000 | …`), and `fw_overlap()` returns 0 whenever
`wa[23:20] != ba[23:20]`. No game executes from work RAM or shared RAM, so the
coherency path cannot fire.

That argument also disposes of the one hole in the method. The Z80 is stubbed
in this sim — `s32_soundsys.sv:87` auto-defines `S32_Z80_STUB` under
`SIMULATION`, and lines 117-119 tie `z_mreq_n`/`z_wr_n` high — so the
`sh_z80_wr` term of `ext_wr` is never exercised. It does not matter: its writes
land in region 7 and are region-gated out of `fw_overlap` for any code running
from ROM.

## What it settles

`6B`/`7B` is the only shipping change between `e852cb2` and `e10968c`. Zero
executions in any of the four games means those two commits are behaviourally
identical on all four **over the window these traces cover**, which is 180
frames — about three seconds of game time, boot and attract entry.

**That is narrower than it first appears, and this document originally
overstated it** as "the clean-room merge cannot be the cause of the gate
failures". The gate samples at 30 s and 78 s after core load, and Dark Edge's
freeze is in by the first of those; radr's reported freeze is around three
minutes. A three-second trace cannot speak to any of them, and the sentence
claimed it did.

The conclusion happens to hold, but it was established later and by other
means — see the addendum.

More broadly: none of the four live differences between `ship`'s V60 and
`upstream`'s is reachable in any of these games. On this workload the two cores
compute the same thing.

That converges with a conclusion already recorded in the tree.
`rtl/s32_core.sv:626-640` documents an earlier A/B in which the `ga2` and
`spidman` hardware difference was "total and reproducible" while `work_pr_we`
was "provably constant-0 for them", and concludes it "points away from function
and towards synthesis/placement". This measurement is an independent
confirmation of that constant-0 claim, and rules out the other three
differences as well.

## What it does not settle

The window is boot plus attract entry — roughly three seconds of game time.
`radr`'s reported freeze is about three minutes in, which is out of reach:
180 frames took ~6 minutes per game, so three minutes of game time is ~6 hours
each. So this bounds the **functional** explanation and says nothing about a
timing one. If a divergence exists deep in attract it is not one of these four
firing for the first time; it would have to be something that only appears
under sustained run, which is the direction `s32_core.sv:626-640` already
points.

Two smaller caveats. The sim used the runners' define sets, which omit the
shipping QSF's `S32_PCB_TIMING` and `S32_V60_NO_FP`; neither affects the four
differences measured, and no game executed a floating-point opcode. And 180
frames is one path through boot — a different coin/start sequence reaches
different code.

## Incidental: what the clean room is missing, measured

`tools/v60x/exposure.py` on the same traces, which is what its docstring asks
for and what `NEXT-STEPS.md`'s ordering should rest on instead of a guess:

| game | mnemonics | clean-room coverage | not executed |
|---|---|---|---|
| ga2 | 49 | 99.99% | `MOVC` (362), `SKPC` (164) |
| spidman | 43 | 99.98% | `MOVC` (704), `SKPC` (326) |
| radr | 41 | 100.00% | `MOVC` (536) |
| darkedge | 47 | 99.99% | `MOVC` (652), `SKPC` (81), `MOVCF` (1) |

The entire gap is the character-manipulation group —
`docs/v60/CHARACTER-STRING.md` is its research.

## Repeating it

Needs ROM images, so it does not run in CI:

```sh
python tools/make_sim_images.py "releases/<mra>" roms/<game>.zip roms/sim/<game>
verilator --binary --timing ... \
  -f verif/verilator/romboot.f verif/v60/tb_v60_delta_probe.sv
./romboot +IMG=roms/sim/<game> +DESC=roms/sim/<game>/desc.txt \
          +FRAMES=180 +OPTRACE=optrace_<game>.txt
```

`verif/verilator/romboot.f` was an uncommitted scratch file that four runners
required and none produced; it is checked in now, and those runners point at
it. `docs/v60/LOCKSTEP.md` is the other half of the `ship`-vs-`clean`
comparison — this file is `ship` vs `upstream`.

## Addendum, 2026-09-05 evening: the gate was run, and it says more than this

Everything above was measured in simulation. The four-game gate was then run on
real hardware for the first time in this line of work, and three things came
out of it that this document could not have known.

**Dark Edge is wedged on `e10968c`, and it is not the clean-room merge.** It
boots, renders its high-score table, and stops advancing — byte-identical
frames for minutes where the `20260831` release and a 2026-08-26 build both
cycle through the attract demo. `6B`/`7B` was the obvious suspect and is **ruled
out** twice over: `e10968c` with only `e9fc86d`'s shipping half reverted (built
at fitter seed 6, timing clean) still wedges, 7 samples and 1 distinct frame;
and a `tb_core_romboot` run reached 73.5M instructions — 2,449 frames, **40.8
seconds of game time**, past the freeze — with zero `6B`/`7B` executed. So the
three-second figure above is now a forty-second figure, and the answer did not
change.

**The failure is placement-sensitive, not functional.** Three builds that all
pass the timing gate wedge on three *different* frames (1,316 B, 20,276 B,
11,134 B). A bad instruction would stop all three in the same place. And the
margin is nothing: the passing fit has **+0.075 ns** worst-case hold, at 89%
ALMs and **99% RAM blocks** — a 27-line revert flipped fitter seed 5 from
164 checks/0 fatal to four fatal hold violations, and the same RTL passes at
seed 6.

**So the gate is not currently a trustworthy instrument.** Build-to-build
placement noise exceeds the effects being attributed to commits. That is the
real finding, and it applies to `docs/v60/NEXT-STEPS.md`'s stage 4: those items
change flags that feed conditional branches, exactly the shape of change whose
game-visible effect cannot be measured on a fit this marginal.

One more measurement, because it redirects where the work goes: `report_timing`
on the passing fit puts **none of the 36 worst setup/hold paths in the V60**.
They belong to `s32_sprite` (23), `s32_soundsys` and `s32_rf5c68` (28 between
them), video timing (8) and the **V25's** prefetch (6). The shipping V60 may
well carry the timing debt its structure suggests — the clean room measures
20.58 MHz Fmax on a 46-level decode-to-ALU chain — but it is latent, not
binding, and pipelining it would add area to a design at 89% without touching
anything that is tight.
