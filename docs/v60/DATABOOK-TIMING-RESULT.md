# Databook §4 timing: measured on hardware, and it breaks the games

Result of running the audit's own regression gate — the Golden Axe II /
Spider-Man / Rad Rally black-screen cases — on a real DE10-Nano, 2026-08-25.

## The three builds

All three from the same tree, same toolchain (Quartus Lite 17.0), same device.

| | `clk_ram` slack | TNS | ALMs | hardware |
|---|---|---|---|---|
| `DB=0 HCS=0` (shipping) | +0.224 ns | 0.000 | 37,423 | **all four render** |
| `DB=1 HCS=1` | **−0.546 ns** | −1.501 | 37,446 | all four fail |
| `DB=1 HCS=0` | **+0.648 ns** | 0.000 | 37,292 | **all four black** |

Games: Golden Axe: The Revenge of Death Adder, Spider-Man, Rad Rally, Dark
Edge. Screenshots captured over SSH; the third build's GA2 was sampled four
times across 90 seconds to rule out a slow boot or a fade-in — it stays black.

## Why the third build is the one that counts

The second build failed *and* missed timing, so it proved nothing: `clk_ram` is
the tightest domain in this design and also clocks the tilemap engine, the
sprite engine's port-B reads, the SDRAM controller and the line buffers. A
violated setup path there produces the same symptom as a functional
regression.

The third build **closes timing with more margin than the shipping build**
(+0.648 vs +0.224 ns) and is 131 ALMs *smaller*. The failure therefore cannot
be attributed to closure. It is the change itself.

This also settles the earlier question about `HALF_CLOCK_SAMPLING`: it is what
pushed `clk_ram` negative, and it buys nothing while `DATABOOK_TIMING` is off.

## What it means

The audit predicted this in as many words: *"changing the execute:bus ratio in
isolation breaks shipped games"*, and named these exact titles as "the most
sensitive detector in the project". They are.

Three clocks per physical cycle instead of two **is correct** per databook §4 —
`verif/v60/tb_v60_tstate.sv` measures the resulting costs as 3/3/6/9 clocks
against the audit's own table, and byte and aligned-16-bit accesses are
unaffected. The problem is not that the T-state machine is wrong. It is that
this core's *execution* rate was tuned against the old, too-cheap bus, and
making the bus honest without also making execution honest moves the ratio the
games depend on.

That is exactly the sequencing risk audit §07 warns about for steps 4–6.

## So it is not "a switch waiting for permission"

`DATABOOK_TIMING` is blocked on audit step §07.6 — attack execution timing with
measured data — and `docs/v60/REFERENCES.md` records why that is a research
project rather than an implementation step: the databook's instruction summary
has a "Clocks" column with every cell blank, confirmed across all nine pages
and independently on the V70 document. Per-instruction timing has to come from
hardware measurement, the 1988 IEEE Micro / IPSJ papers, or a die scan that
does not exist at usable resolution.

Until then the honest position is the one the code now takes: the T-state
machine and the pin-level status lines are live and correct, and the cycle-cost
change is off with a measured reason rather than a cautious one.

## Reproducing

```
# flip the parameters in rtl/s32_core.sv, then
gh workflow run "Build RBF"           # or push to a PR touching rtl/
gh run download <id> -D out
scp out/segasystem32-rbf/*.rbf root@<mister>:/media/fat/_Arcade/cores/Arcade-SegaSystem32.rbf
# MRAs from releases/, ROM zips in /media/fat/games/mame/
echo "load_core /media/fat/_Arcade/<game>.mra" > /dev/MiSTer_cmd
echo screenshot > /dev/MiSTer_cmd      # -> /media/fat/screenshots/<core>/
```

Sample any suspected black screen more than once, at least 60–90 seconds apart.
Dark Edge's first screenshot under the *working* build is also black — it is
mid fade-in — and calling that a failure would have been wrong.
