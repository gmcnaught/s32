# The clk_ram domain is the tight one

Working notes for closing timing on `clk_ram`. The hypotheses below were
written while a bisect fit was still running. `verif/timing/worst_paths.tcl`
has since reported the endpoints, and **hypothesis 1 is the answer** — see
"Result", below.

## Measured

| build | `clk_ram` slack | TNS | other domains |
|---|---|---|---|
| `DATABOOK_TIMING=0` (shipping) | **+0.224 ns** | 0.000 | all clean, ≥ +0.326 |
| `DATABOOK_TIMING=1` + half-clock | **−0.546 ns** | −1.501 | all clean |

Utilisation is the same either way: 37,423 → 37,446 ALMs (+23), 546/553 RAM
blocks unchanged. **It is not an area problem.**

`clk_ram` is 96.634615 MHz — a 10.348 ns period. It is by a wide margin the
tightest domain in the design; the next worst is HDMI at +0.326 and everything
else is ≥ +1.38.

## The assumption to be careful about

It is tempting to say "the BIU moved to `clk_ram`, the BIU changed, therefore
the BIU is the failing path". That does not follow. `clk_ram` also clocks:

- the tilemap engine (`s32_core.sv`: "tilemap engine (clk_ram domain)")
- the sprite engine's port-B reads
- the SDRAM controller and `s32_fb_if`
- the line buffers
- the V60 bus adapter and its timebase

The **baseline** already sat at +0.224 ns, so this domain was within a quarter
of a nanosecond of failing *before* the T-state work. A pre-existing
near-critical path in the sprite or tilemap engine, perturbed by placement,
would produce exactly the observed result with the adapter entirely innocent.

+23 ALMs on a 37,000-ALM design at 89% utilisation is well inside the range
where placement changes on its own. The sibling Maldita project records the
same fragility on its own `emu` clock.

So: **do not optimise the adapter until the report says the path is in the
adapter.**

## Result: the worst paths are in the video engines, not the adapter

Shipping configuration (`DATABOOK_TIMING=0`, `HALF_CLOCK_SAMPLING=0`,
`PROT_INTERLOCK=0`), Quartus Lite 17.0, CI run 32886972031, from
`output_files/worst_paths.txt` in the `quartus-reports` artifact:

| slack | from | to |
|---|---|---|
| **+0.224** | `s32_tilemap\|lay[0]` | `s32_tilemap\|Mult1~349\|ENA_DFF1` |
| +0.298 | `s32_tilemap\|lay[0]` | `s32_tilemap\|Mult1~349\|ENA_DFF1` |
| +0.379 | `s32_sprite\|pixel_scrx[2]` | `s32_sprite\|indtab_rtl_0_bypass[8]` |
| +0.419 | `s32_sprite\|pixel_scrx[4]` | `s32_sprite\|indtab_rtl_0_bypass[8]` |
| +0.420 | `s32_tilemap\|lay[0]` | `s32_tilemap\|Mult1~349\|ENA_DFF1` |
| +0.466 | `s32_sprite\|xacc[17]` | `s32_sprite\|indtab_rtl_0_bypass[6]` |
| +0.493 | `s32_tilemap\|lay[0]` | `s32_tilemap\|Mult1~349\|ENA_DFF1` |
| +0.500 | `s32_sprite\|pixel_scrx[0]` | `s32_sprite\|indtab_rtl_0_bypass[8]` |

That is the entire top eight, and **no `s32_v60_bus` register appears in it**.
Two structures carry the whole margin: the tilemap's `Mult1` clock enable, fed
by the layer select `lay`, and the sprite engine's index-table bypass, fed by
the horizontal position and the `xacc` accumulator.

So hypothesis 1 is confirmed and 2, 3 and 4 are ruled out. The T-state work did
not create the tightness; the domain was already at +0.224 ns with the adapter
innocent, which is what this note said not to assume away. `clk_ram` is the
tight domain because it clocks the video engines, at 89% ALMs and 99% RAM
blocks.

One limit on the claim. This is the *shipping* build. The `DB=1 HCS=1` build
that measured −0.546 ns predates `worst_paths.tcl` and was never reported this
way, so which path failed *there* is still unknown. It does not matter for the
roadmap — `HALF_CLOCK_SAMPLING` is off, and it buys nothing while
`DATABOOK_TIMING` is off — but do not carry this result across to that
configuration without re-running the report.

## Hypotheses, in the order the report can discriminate them

1. **CONFIRMED — a pre-existing sprite/tilemap/SDRAM path**, pushed over by
   placement.
   Evidence for: the baseline is already at +0.224 ns; the failure is not
   game-specific; area barely moved. Fix: unrelated to the T-state work.
2. **Ruled out — the adapter's next-state logic.** Databook mode adds T2 and T4 branches,
   the `short_cycle` decision and the `io_recover` counter to the `ts`
   transition. `ts` → next-state → `ts` is adapter-internal, and the SDC gives
   adapter-internal paths a **single** `clk_ram` cycle (10.348 ns) on purpose —
   the broad two-cycle relaxation is deliberately overridden for them, so this
   is the one part of the adapter with no slack to spare.
3. **Ruled out — `drive_cycle`'s address adder.** `addr_r[23:1] + {21'b0, cyc}` plus the
   byte-lane decode, registered into `m_addr`/`m_be`/`m_wdata`. Also
   adapter-internal, so also a single cycle. Note the first cycle adds zero, so
   specialising `cyc == 0` to skip the adder is a cheap win *if* this is it.
4. **Ruled out — the CPU-side payload path.** `c_addr` originates in the CPU's 57-way
   `dbus_addr` mux on `clk_sys`. That is a `-to $v60_bus_regs` path and already
   has two `clk_ram` cycles (20.696 ns) from the stage-04 exception, so it is
   the least likely of the four — but worth confirming rather than assuming.

## What the SDC gives each class

From `Arcade-SegaSystem32.sdc`:

    -from v60_bus_regs                     setup 2   (20.696 ns)
    -to   v60_bus_regs                     setup 2   (20.696 ns)
    -from v60_bus_regs -to v60_bus_regs    setup 1   (10.348 ns)   <-- tight

The last rule is more specific and wins. It exists so that moving the BIU to
`clk_ram` could not quietly hand its own state machine twice the time it has.
That was the right call, and it is also why hypotheses 2 and 3 are the ones
with no margin.

## If the adapter had been the path

It was not, so none of these is worth doing today. Kept because §07.5 and
§07.6 both re-touch the adapter, and if a later report does put it on the
critical path, this is the order to try things in. Cheapest first:

- **Specialise the first cycle.** `cyc == 0` needs no adder at all.
- **Decode then mux, rather than mux then decode.** Compute the byte-lane
  payload for both the first-cycle and continuation cases in parallel and
  select at the register input. Costs a few ALMs, removes a mux from in front
  of the decode.
- **Precompute the next state.** Register a one-hot "what comes after T3"
  decision during T2, so the T3 edge is a select rather than a decision tree.
- Only then consider relaxing the single-cycle rule — and if that is the
  answer, it must come with an argument for why the adapter genuinely has two
  cycles, not merely a wish that it did.

## It is not the adapter, so:

The T-state work is exonerated, and the question becomes whether this
design has any `clk_ram` headroom at all at 89% ALMs and 99% RAM blocks. That
is a fitting problem, and the lever recorded elsewhere is audit step §07.5:
retiring `FAST_IFETCH` removes the 64×8-byte ROM instruction cache, which frees
M10K — the constraint at 99% — and removes its lookup from the fetch path.
