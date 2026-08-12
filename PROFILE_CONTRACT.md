# Sega System 32 global profile contract

This is the persistent cross-chat routing record for the core.

## 2026-08-12: Air Rescue removed from production scope

Air Rescue requires two complete linked System 32 PCBs. The production core
does not claim that hardware boundary, so `arescue`, `arescueu`, and `arescuej`
are intentionally excluded from `tools/gen_mra.py`, tracked MRAs, releases, and
the supported-game table. The experimental peer-board, dual-V60, dual-PCB RAM,
peer-DDR, and uPD77P25 shadow paths have been removed from production sources
and manifests. This exclusion is a scope decision, not a claim that a
single-board mailbox substitute is sufficient.

## 2026-08-11: integrated CPU, memory and renderer throughput package

Both production profiles keep the PCB V60 clock and every external data/I/O
bus cadence unchanged.  `V60 Fetch: Fast / PCB (Reset)` now defaults to the
existing ROM-only wide instruction path; PCB fetch remains selectable.  Work
RAM code, data, I/O, interrupts and protection transactions always use the
ordinary hardware-timed bus.

The shared V60 overlaps the execute edge with sequential retirement only for
explicitly allowlisted register-result and no-writeback operations.  Memory,
RMW, iterative, privileged, exception and control-transfer paths retain their
general states.  The MOVW/DBR fixture improved from 2,101 to 1,845 clocks
(-12.2 %) with the same 12 physical reads; an unrolled register stream improved
from 2,370 to 2,114 clocks (-10.8 %) with identical ordered bus payloads.

V60 cache misses now request one aligned four-word p0 transaction instead of
four independent SDRAM transactions.  The transport improved from 52 to 16
`clk_ram` cycles (3.25x) and from four ACT commands to one, while exact
protection reads remain single-word non-bursts.  The production synchronous
cache is 64 lines instead of 32: a measured alternating conflict fixture drops
from eight misses to zero after warm-up.  The previous accepted report shows
this cache class uses MLABs rather than M10Ks; the estimated increase is about
40 memory ALMs, but the new inference and timing remain Quartus-unverified.

The tilemap retains tagged bitmap VRAM words for all lanes and caches exact
NBG0/NBG1 reciprocal results by their complete effective zoom-denominator key.
A 320-pixel 4bpp bitmap line improves from 969 to 490 renderer clocks and a
repeated NBG line from 555 to 493 with identical pixel/hash results.  The sprite
engine uses a guarded same-cache 1:1 continuation that sustains one pixel per
clock; cache boundaries, scaling, clipping and END handling retain the general
fallback, which is regression-run against the same 24-case pixel suite.

The demand-only sound-ROM cache is now four two-way sets with per-set LRU and
single-consumption stretched-ACK handling.  A two-stream conflict fixture drops
from 160 to eight SDRAM requests and from 1,119 to 359 system clocks, while the
LDIR-like demand count remains exactly 33.  Sparse framebuffer flushes skip only
64-bit words whose four-lane valid mask is zero: the normal fixture drops from
128 to two DDR writes, and shadow RMW from 128 reads plus 128 writes to two plus
two.  Dense flush, erase and scanout transaction counts are unchanged.

Focused Icarus/ModelSim equivalence, fallback, contention, backpressure and
profile-boot tests pass, as do 126 Python tests and all three release/MRA gates.
No Quartus build, RBF, STA or MiSTer hardware verification covers this package
yet; the previously built RBF predates these RTL changes.

## 2026-08-11: direct retained-loop DBcc/TB restore

The shared V60 now restores a complete retained fetch window directly from the
DBcc/TB decode edge when the taken branch target exactly matches the saved
window, the PFU is idle, and the target instruction's conservative predecode
length is present. Unknown target forms retain the ordinary `S_FILL` path;
there is no cross-instruction register speculation, no change to physical PCB
bus acceptance or cadence, and no change to non-loop branches. The 256-iteration
immediate-MOVW/DBR fixture improved from 2,609 to 2,101 `clk_sys` cycles
(-19.5%) with the same 12 physical fetch reads. The focused Sonic burst
fixture now reports 36,225 cycles for its overlap-A case.

## 2026-08-10: V60 throughput improvements

Both production profiles compile the existing 8-byte ROM-cache instruction
port and expose `V60 Fetch: Fast / PCB (Reset)`. The selection is latched only
while reset is asserted and Fast is the default. `PCB` keeps instruction
prefetch on the shared, ce-gated 16-bit V60 adapter; `Fast` uses the dedicated
cache port for the two main-ROM windows. Code executing from work/shared RAM
automatically stays on the ordinary V60 bus. Data, I/O,
interrupt, video, audio and protection traffic retain their PCB clocks and bus
ordering in both modes. This is an explicit selectable performance aid, not a
claim that an original V60 had an 8-byte external instruction bus.

The shared V60 now launches common displacement/register-indirect source reads,
destination reads and result writes as soon as their addresses/data are ready.
This removes serialized EA and request-setup bubbles while leaving acceptance,
completion and request re-arm on the unchanged physical bus. Standard MUL/MULU
uses an exact two-bit radix-4 step (16 iterations instead of 32); DIV/REM remain
unchanged because their existing latency is already at or faster than the
published V60 reference. Sequential fallback remains for complex modes.

The follow-up safe throughput package adds a registered exact-length successor
predecoder for common F2 and short instruction forms, retires resolved simple,
indexed, auto-update and deferred-address EAs directly from their producer
state, and uses a DBcc/TB hint to fill the existing retained-loop window to its
complete 24-byte capacity without increasing ordinary lookahead traffic. The
timing-sensitive live-window shift remains capped at four bytes;
there is no cross-instruction register-value speculation or external-bus timing
change. The 256-iteration loop fixture improved from 2,865 to 2,609 clocks and
from 14 to 12 physical fetch reads.

## 2026-08-10: restore busy-scene sprite throughput and completed ownership

System 32's cached-pixel path is again the algebraically identical two-stage
`R_PIXEL` -> `R_EMIT` pipeline.  A timing-oriented change had inserted
`R_PIXEL_DATA` between them, charging every ordinary destination pixel three
renderer clocks instead of two.  That 50% increase in pixel-stage work is
load-dependent: quiet scenes remain inside a field, while dense object lists
miss publication fields and make the entire sprite layer advance in steps.
Cache misses, sprite-RAM reads, skipped-word END scans, zoom, clipping,
priority and transparency retain their existing general paths and semantics.
The focused regression includes a cached-pixel cycle budget so the extra
per-pixel state cannot return silently.

Scanout also uses a completed physical sprite-framebuffer selector separate
from the CPU-visible logical A/B controller bit.  The renderer erases and draws
into a hidden work buffer, waits for the final framebuffer flush, marks it ready
at `R_DONE`, and publishes it at VBLANK start.  A third physical slot absorbs a
remaining overrun without erasing, rendering into, or exposing the scanned
buffer.  Both corrections are shared by both production profiles and are not
game-gated.

Hardware recordings from Jurassic Park and Rad Rally showed the causal shape:
quiet/short sprite lists were smooth, while all trees, roadside objects, cars
and dinosaurs in dense scenes stepped together.  Road/tile scanout continued
smoothly, isolating the sprite renderer's field budget rather than V60 cadence
or one object's transparency.  The overrun regression also requires the third
slot and asserts that scanout cannot change until a complete field is
published.  Quartus/RBF and post-fix MiSTer hardware verification remain
pending.

## 2026-08-06: split back into two dedicated profiles

The single merged `s32` profile (2026-08-05 below) is retired in favor of two
dedicated Quartus revisions, at explicit user direction after the merged
profile's resource growth (trackball + generic protection HLE, added to
prepare for Sonic) measurably regressed timing closure on the shared
`s32_vram`/`s32_tilemap`/`s32_sprite` critical paths for zero benefit to the
two games that were actually shipping:

- `segas32v25.rbf` / `segas32v25.qsf`: real NEC V25 hardware, for exactly
  `ga2` and `arabfgt`. Functionally identical in scope to the old merged
  profile's `S32_GAME_ONLY` trim -- same macros, same fitter settings, same
  seed (2) -- just under a new filename. `S32_REAL_V25` is compiled in here
  only.
- `segas32.rbf` / `segas32.qsf`: no real V25 hardware at all (HLE responder
  only, `rtl/prot/s32_prot.sv`'s `s32_v25`), for every other in-scope System
  32 game. Currently scoped to `sonic` and `slipstrm` (Slip Stream uses the
  descriptor-gated MSM6253 ADC; Sonic's resource-fit blocker --
  the V60 ROM cache's `prot_rom_grant` tie-off assuming no game needed
  generic protection ROM-read arbitration -- is fixed, see
  `rtl/s32_core.sv`'s `s32_ga_rom_cache` arbiter). Holo, Spider-Man, Alien3,
  Burning Rival, Dark Edge, Jurassic Park, and Rad Rally are
  restored to this profile; `radm` remains staged. This profile has never been fit; its
  QSF's fitter/seed settings are starting points carried over from
  `segas32v25.qsf`, not validated for its own resource shape.

`rtl/s32_core.sv` is shared by both profiles. The scope trim is now
three-way: `GAME_ONLY` (the real-V25 shape ties off unrelated standard-board
hardware) and `GAME_ONLY_STD` (keeps the trackball, descriptor-gated ADC,
positional-gun conditioner, Burning Rival responder, and generic protection
HLE live in `segas32.qsf`,
while still implying `GAME_ONLY`). Do not name a
macro after a specific game (`S32_SONIC_ONLY` etc.) -- see the routing rule
below, unchanged since before the merge.

Sections below dated 2026-08-05 or earlier that describe the single merged
profile are historical; the underlying attract/gameplay evidence they record
remains valid regardless of which RBF file a game now loads from, but any
routing/macro-name detail in them refers to the retired merge, not current
state.

## Outputs

- `segas32v25.rbf` / `segas32v25.qsf`: `ga2`, `arabfgt` (real V25).
- `segas32.rbf` / `segas32.qsf`: `alien3`, `brival`, `darkedge`,
  `holo`, `jpark`, `radr`, `slipstrm`, `sonic`, and `spidman` (HLE only, no
  real V25 hardware). `radm` remains staged.
- No production image supports Multi 32 sets.

## User-requested exclusions (2026-08-03)

The following parents are intentionally ignored and must not be emitted as
MRAs, staged by the active profile sweep, or treated as supported in future
profile work: `arescue`, `dbzvrvs`, `f1en`, `f1lap`, `svf`, and `jleague`. Local ROMs
and historical captures may remain on disk;
they are outside the production profile.

## Source of truth

`tools/gen_mra.py:RBF_BY_PARENT` is authoritative for MRA-to-RBF routing:
`{"ga2": "segas32v25", "arabfgt": "segas32v25"}`, with every other emitted
parent defaulting to `"segas32"`. `segas32v25.qsf` and `segas32.qsf` are the
only two production Quartus revisions. `S32_PROFILE_STANDARD` is the only
production *profile-shape* macro (both revisions set it); `S32_PROFILE_V25`
must never be defined again (that was the pre-2026-08-05 dedicated-revision
macro, not the same thing as today's two-revision split). `S32_GAME_ONLY`
and `S32_GAME_ONLY_STD` are legitimate production *scope-trim* macros (not
game-named -- they describe a hardware-capability shape), each set by
exactly one QSF. Any macro named after a specific game (`S32_GA2_ONLY`,
`S32_SONIC_ONLY`, etc.) is a test legacy and must not be used to route a
shipped game. `S32_PCB_TIMING` is a common behavior flag for fixed production
timing and never selects a game or RBF. Runtime `V60 Fetch` selection is shared
by both profiles and never changes the external V60 bus clock.

## Feature placement (two profiles)

| Feature/change | `segas32v25` | `segas32` |
|---|---:|---:|
| Shared V60, video, sprite, audio, I/O, loader, and dedicated V60 ROM cache | yes | yes |
| MSM6253 ADC | no (`GAME_ONLY` tie-off; neither V25 game has an analog board) | yes, descriptor-driven for Slip Stream (`ANALOG_DRIVING`); right-stick up/down drive accelerator/brake, A/B are full-scale digital fallbacks, and X toggles gear; inactive games do not select the device |
| Trackball (`s32_upd4701`) | no (no game here has one) | yes, descriptor-driven (`GAME_ONLY_STD`); all three Sonic players use frame-paced nonlinear left-stick velocity (15-count deadzone, 30 counts/frame at full deflection) and exact action/start/coin wiring |
| Generic protection HLE (`s32_prot_hle`) | no (both games are `PROT_NONE`) | yes (`GAME_ONLY_STD`; descriptor-selected Sonic/Dark Edge paths) |
| Burning Rival protection responder | no | yes, descriptor-gated for `brival` |
| Real NEC V25 core, program SDRAM, cache, FIFO, internal data RAM | compiled in via `rtl/cpu/v25/v25.qip` (`S32_REAL_V25=1`), enabled per-game by the descriptor's `has_v25` bit | not compiled in at all; HLE responder `s32_v25` only |
| V25 table/cadence selection | descriptor-driven (`v25_table`) | n/a (no V25 hardware) |
| CPU Turbo | removed (V60 timing relies on fixed CE spacing) | removed (same) |
| V60 Fetch | reset-latched PCB/Fast instruction transport; data/I/O bus fixed at PCB cadence | same |
| Multi 32 second screen/peripheral hardware | no | no |
| HDMI shadow-mask post-process | compiled out (`MISTER_DISABLE_SHADOWMASK`; optional output effect) | compiled out (same) |

## Evidence status (2026-08-01)

- 2026-08-12 315-5242 digital-output audit: the pinned SiliconRE M71064
  decap-derived material establishes a pixel-clocked 5-bit RGB output latch,
  blanking, greyscale, and component-nonzero shade/highlight controls. It does
  not establish a mismatch in the upstream System 32 offset/blend/shadow
  arithmetic. Functional video RTL therefore remains unchanged; the directed
  mixer regression now pins offset -> blend -> shadow -> clamp and final
  5-bit-to-8-bit latch expansion. No remaining evidence-backed digital video
  correction was identified; analog DAC levels and exact latch phase remain
  outside the current digital equivalence claim.

- Source/profile checks: passed.
- Python verification: 102 tests passed, one environment-only WSL skip.
- Native ModelSim regression on 2026-08-01: tiers 1–37 passed, including the
  updated core-map test; tier 38 (real encrypted GA2 V25 firmware) failed in
  the excluded V25 runner and is outside this Standard-only goal.
- Safe Verilator V25 cache/internal-data checks previously passed; V25
  firmware is not part of the current user-directed acceptance matrix.
- The native full-core romboot model was rebuilt after correcting a
  verification-only bug that applied GA2 sprite/signature assertions to
  standard-profile descriptors. The GA2 predicate now uses the descriptor's
  V25/table boundary; a regression test protects that classification.
- Quartus fit/timing and physical hardware: intentionally not run for this
  profile-routing task.
- The pinned-MAME EPR-14084 link-status HLE is source-integrated for the radr
  descriptor, reuses the existing communication RAM, and passes focused map
  plus byte/wide ROM-loader tests. Full-core radr attract verification now
  passes the screenshot gate at frame 360 in the retained 420-frame run.

## Current goal acceptance scope (2026-08-02)

The current user-directed gameplay/attract acceptance matrix covers true parent
sets only. Clone and regional revisions and all Multi 32 parents are excluded
from this audit. The active Standard parents are `alien3`, `brival`,
`darkedge`, `holo`, `spidman`, `jpark`, `radr`, `slipstrm`, and `sonic`;
`radm` remains staged, and the two V25 parents remain `ga2` and `arabfgt`.

## Universal-profile attract evidence (2026-08-01, in progress)

The acceptance gate for a game is a deterministic full-core Verilator run with
the image's own descriptor, `ROMBOOT DONE`, zero unexpected (non-IRQ) V60
exceptions, no terminal CPU freeze, zero tile/FB overrun counters, and a
retained **Verilator-generated** non-black screenshot that is visually
identifiable as the game's attract/demo state. The screenshot must come from
the same full-core Verilator run that supplies the diagnostics; a MAME
screenshot, MAME-only attract result, or non-attract boot/warning screen never
counts toward progress or promotion. A promoted result also retains a
scene-matched MAME screenshot comparison using the frame-diff ledger in
`docs/debug/frame-diff/journal.md`; comparison may crop only verified black
padding and must state any measured emulator-frame or scanline alignment.

MAME remains the behavioural reference only: its source and captures select
the timing window, inputs, expected landmarks, and hardware behaviour that the
Verilator run must reproduce. MAME evidence is recorded separately and cannot
close the attract gate.

The executable harness gate is `+REQUIRE_VERILATOR_SCREENSHOT` together with
`+DUMPAT=<frame>`: it fails if the requested PPM is absent, incomplete, or
entirely black, and reports the captured frame's non-black pixel count before
`ROMBOOT DONE`.

Current matrix status: the active Standard parents and both V25 parents remain
subject to the combined attract/frame-diff gate. `holo` retains its exact
scene-matched MAME image comparison, but is outside the current audit.

| Parent | Profile | Evidence | Status |
|---|---|---|---|
| `holo` | standard | 85 frames; frame 80 shows the FBI anti-drug attract screen; `scratch/vromboot_out/holo_frame80.png`; exact MAME RGB match after documented crop and -1 scanline alignment | proven |
| `radr` | standard | 420-frame full-core Verilator run; frame 360 retained PPM/PNG shows the Rad Rally `Free Play`/SEGA attract screen; `ROMBOOT DONE`, `VERILATOR SCREENSHOT PASS` with 71,680 non-black pixels, IRQ-only vectors 40/41, zero freeze/tile/FB overruns; `scratch/radr_attract_win_20260801p/dump360.ppm` | proven |
| `ga2` | v25 | staged parent image and MAME attract references; combined real-V25 Verilator attract/frame-diff gate pending | pending |
| `arabfgt` | v25 | staged parent image and MAME attract references; combined real-V25 Verilator attract/frame-diff gate pending | pending |
| all other in-scope media-present standard parents | standard | staged sweep or media/structural triage exists, but the attract gate is not yet closed | pending |

`ga2` and `arabfgt` remain separate V25-profile rows in the active matrix, not
Standard-profile rows.

## Per-parent progress (2026-08-01)

The percentage is an evidence milestone, not an estimate of elapsed work:
25% = media staged/structural triage; 50% = rendered Verilator smoke boot with
no unexpected exception or video overrun; 75% = the MAME-selected timing
window was reached in Verilator but the Verilator attract marker, screenshot,
or visual review is still open; 100% = the full Verilator attract gate above is
closed. Only 100% counts as proven attract mode.

| Parent | Attract proven? | Progress | Current evidence / next gate |
|---|---:|---:|---|
| `holo` | no | historical attract capture retained; reactivated in the standard profile | rerun the combined attract/frame-diff gate |
| `ga2` | no | 50% | staged V25 parent image; real-V25 attract and MAME frame-diff gate pending |
| `arabfgt` | no | 50% | staged V25 parent image; real-V25 attract and MAME frame-diff gate pending |
| `jpark` | no | 50% | 150-frame Verilator smoke; run the corresponding 1200-frame Verilator title window selected from MAME |
| `radm` | no | not MAME-exact | **2026-08-05 pixel-exact MAME comparison** (`docs/radm-radr-bringup.md`): the earlier "50%/non-black-pixel" gate above did not compare against MAME frames. A 1740-frame sweep vs MAME shows the RTL matches MAME almost exactly at frame 900 (0.49% differing) — both sides show the "Motor warm up now !! Please wait" screen — but MAME transitions off it within the next 60-frame sample while the RTL is still on it at frame 1740 (the end of the capture). Interrupt delivery and the MSM6253 ADC were both traced live against MAME and are confirmed correct/identical; the remaining gap is not yet isolated past "likely another symptom of the known V60 throughput gap" — no RTL change made. |
| `radr` | no | not MAME-exact | **2026-08-05 pixel-exact MAME comparison** (`docs/radm-radr-bringup.md`) supersedes the "100%/screenshot-gate" verdict below, which also predates any MAME frame comparison. Frames 60-240 match MAME closely (0.67% differing, stable residual — static title/logo screen); from frame 300 onward the RTL diverges from MAME with no nearby-frame rescue (a genuine content divergence, not timing drift), recovering briefly at frame 480 then diverging again from 600 through 1740. Not yet root-caused. Historical context retained below since it reflects real, still-true findings (screenshot gate, IRQ vectors, zero overruns) — it just isn't evidence of MAME-exactness. 420-frame full-core Verilator attract run passed; retained frame-360 Rad Rally capture, `ROMBOOT DONE`, screenshot gate, IRQ-only vectors 40/41, and zero freeze/tile/FB overruns; MAME-derived CN/FG plus EPR-14084 link-status HLE remains descriptor-routed and focused-tested |
| `slipstrm` | no | Strict Verilator road continuation verified through RTL frame 4500 | **2026-08-09/11 deep trace** (`docs/slipstrm-bringup.md`): fixed a shared V60 RSR return that popped the correct PC but retained the CHLVL handler's stale prefetch window, then proved and fixed an MSM6253 bus-integration error that shifted neutral wheel `0x80` before the read mux sampled D7 (the game stored `0x00` and selected Time Trial instead of MAME's World Championship). Corrected RTL selects World Championship; scene-aligned car selection differs by 192/93,184 pixels (0.2065%) after the known one-pixel horizontal offset. An assertion-clean savable replay reached the post-stadium scene at RTL frame 4500; its forest edge, apron, road-to-horizon geometry, signs, and marshal align with pinned MAME frame 3600, so no draw-distance truncation was reproduced. Exact speed/frame alignment still requires MAME's pre-race HIGH-gear input state. |
| `sonic` | **yes (attract)** | 100% attract / gameplay: one known cosmetic gap, root-caused and accepted | **Attract gate closed 2026-08-04**: the whole attract cycle is pixel-exact against MAME — 9 sampled 416-wide frames (120–600) and 13 sampled 320-wide frames (660–1380), 0 differing pixels each, no x/y offset (`docs/segasonic-bringup.md`). Gameplay re-measured the same day with MAME's coin/start/button/trackball schedule: exact through RTL frame 1015 (0/71,680 at 955 and 1015), then the floor's palette bank1 (`0x3C01`–`0x3E6F`) reads black. **Root cause closed, not a video/logic bug**: a mixer write-both mirror race — our V60 clears blend-enable (`$4E`) a few cycles earlier, mid-loop, relative to the same palette-fill routine MAME runs; VRAM and palette bank0 are proven bit-identical to MAME. Classified as V60 timing-authenticity (same class as the tracked ga2/arabfgt work), not patched — see `docs/segasonic-bringup.md` for the full trace evidence and why a narrow patch was rejected. |
| `spidman` | no | reactivated in the standard profile; current gate not rerun | run the Spider-Man attract gate |

MAME-only timing leads (from the local 0.285 executable; not attract proof for
the pinned source or RTL) are retained for deterministic run planning:
`jpark` showed its title at 1200; `radm` showed its title/road attract at 600;
and `sonic` and `spidman` showed attract/title frames at 1200.
These windows replace the old 120/150-frame smoke assumptions when each parent
is promoted through the full-core Verilator gate.

An earlier local MAME 0.285 `-validate` sweep returned zero for the previously
routed Standard parents, but that command does not prove that the ROM files are
available. A follow-up `-verifyroms radr` and runtime attempt on 2026-08-01
reported `romset "radr" not found` in `D:\Arcade\AI\mame\roms`; therefore no
MAME runtime/media audit is claimed here. The staged `roms/sim` images remain
the current Verilator media baseline, and this does not promote the RTL
attract gate.

## Future-chat checklist

Before editing:

1. Identify whether the change is common RTL, standard-only resource pruning,
   or real-V25-only resource/protection logic.
2. Keep common behavior in shared RTL and compile-time boundaries in the two
   profile QSFs/macros.
3. Update `tools/gen_mra.py` if a set or parent changes; never hand-edit an
   MRA's `<rbf>`.
4. Run the source/profile validation commands in `AGENTS.md`.
5. Only run either build wrapper after explicit user authorization.

The next Rad Mobile acceptance run is a single safe Verilator simulation after
`verilator-safe status` reports no active or waiting tasks:

```powershell
verilator-sim-safe -- scratch/vromboot_obj_win_abi0/romboot_win_abi0.exe `
  +IMG=D:/Arcade/AI/s32/roms/sim/radm `
  +DESC=D:/Arcade/AI/s32/roms/sim/radm/desc.txt `
  +FRAMES=660 +DUMPAT=600 +DUMPN=1 +REQUIRE_VERILATOR_SCREENSHOT +QUIET
```
