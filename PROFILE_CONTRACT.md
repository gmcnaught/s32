# Sega System 32 global profile contract

This is the persistent cross-chat routing record for the core.

## 2026-08-17: direct positional driving wheel

Rad Mobile hardware testing reported that continuous left-stick sweeps could
pause at arbitrary intermediate steering positions until the stick moved
again. Rad Mobile, Rad Rally, and Slip Stream use the MSM6253 `ANALOG1` paddle
for steering, and pinned MAME 0.289 defines the same `0x80`-centred,
`0x00..0xff` Paddle for Rad Mobile and Rad Rally. The universal top inserted a
stateful low-rate IIR (`wheel_sm`) between MiSTer's current left-stick X report
and the ADC even though a positional wheel requires the current coordinate.

The established signed-to-offset conversion and centred subtractive deadzone
now feed MSM6253 channel 1 combinationally. The IIR register, divider, update
tick, and their retained intermediate coordinate are removed. This shared
change applies to every `ANALOG_DRIVING` descriptor; ADC serialization, channel
order, pedal mapping, player-port buttons, clocks, resets, and constraints are
unchanged. `tb_driving_controls` sweeps all 255 valid signed stick coordinates,
checks exact monotonic output, reverses directly between intermediate left and
right positions, and requires an immediate return to centre.

## 2026-08-17: Rad Mobile moving-controller response

Rad Mobile's Deluxe cabinet uses the 837-7753 moving controller over the first
315-5296: port G selects shared byte `C000-C010` as address `80-90`, port C is
the bidirectional data bus, and port D bit 4 is the active-low transfer strobe.
The EPR-13686 firmware uses `C008` bit 0 for a main-board request and bit 1 for
the controller response.  The universal core now implements the 315-5296's
per-port output latches/direction behavior and a descriptor-selected stationary,
healthy mailbox responder.  It does not model the Deluxe cabinet's analog motor
plant or energize physical motion.

Rad Mobile descriptor byte 0 is now `48`: bit 3 selects the MSM6253 ADC and bit
6 selects the moving-controller responder.  A guarded headless 40-frame
Verilator replay read `C008=02`, advanced from the old retry boundary at
`0x068236` through success PCs `0x068243` and `0x068251`, and repeated with an
identical normalized mailbox event stream.  The same model with descriptor bit
6 disabled did not reach `0x068243`.  Pinned MAME is retained as a reference-gap
lane because its driver explicitly does not emulate the motor board.

## 2026-08-14: Rad Mobile restored to the supported set

Rad Mobile (`radm`, `radmu`) is a first-class System 32 analog driving board
and is back in the production scope. It was dropped on 2026-08-05 while the
profile was temporarily narrowed to `ga2`+`arabfgt`; the narrowing was
explicitly temporary and the other standard parents have since been returned
one at a time (`holo`, `radr`, `spidman`, `slipstrm`, `darkedge`).

The 2026-08-14 scope restoration itself required no RTL change: the universal profile compiled with
`S32_GAME_ONLY_STD=1` already keeps the descriptor-gated MSM6253 driving ADC,
the shared driving analog defaults, and the `DIGITAL_RADM` player-port layout
in `Arcade-SegaSystem32.sv` (`radm_p1a`, `s32_pkg.sv:DIGITAL_RADM`). MAME's
`init_radm` installs no protection handler or ROM poke.  Its lack of a moving
controller is a known MAME emulation gap addressed by the 2026-08-17 work above.

Descriptor: `48 10 00 81 01` — b0 bit3 = MSM6253 ADC and bit6 = 837-7753
mailbox responder; b1[5:4] = `ANALOG_DRIVING`;
b2 = no protection and no EPR-14084 link; b3 = sprite metadata valid with a
2-bank (`0x800000`) sprite region; byte 4 = `DIGITAL_RADM`.

This restoration is a scope/packaging change. No RBF was built and no hardware
run was performed, so Rad Mobile carries no attract/frame-diff acceptance
evidence yet — see the acceptance matrix below.

## 2026-08-13: four game families removed

Alien3: The Gun, Burning Rival, Jurassic Park, and SegaSonic The Hedgehog are
outside the production profile. Their parents and clones are not emitted as
MRAs or swept as supported software. The production RTL no longer contains
their gun/aim and coin wiring, trackball/uPD4701 path, protection responders,
Jurassic Park ROM patch, Burning Rival PPI map, or Alien3 framebuffer blend.
Historical evidence below is retained only as an engineering record and does
not indicate current support.

## 2026-08-12: universal-profile memory-budget reduction

System 32 does not load or execute MultiPCM sample ROMs, so the universal
profile now uses that otherwise-empty SDRAM aperture as mutable backing for the
RF5C68's 64 KiB wave RAM. The Z80-visible byte address, WAIT behavior, voice
fetches, writes, and logical `0xff` power-up contents are preserved. Before
releasing the ROM-load reset, the loader clears all 32,768 words in the
aperture; inverted byte storage then makes zero read as logical `0xff`, exactly
like the former internal memory. The SDRAM write port has a held-payload,
owner-tagged serializer with ROM-download priority; RF reads continue through
p4. No RF wave-data M10Ks or validity-map M10Ks remain.

The production-only, non-authoritative EPR-14084 native diagnostic shadow was
also removed from the source manifest and core integration. Rad Rally's
descriptor-selected behavioral link responder remains authoritative and its
MRAs no longer download unused diagnostic firmware planes.

The production protection RTL now contains the Dark Edge sequence, the
descriptor-selected J.League write hook, and the descriptor-selected real V25
path. Dormant and excluded-title responders are not synthesized; reserved
descriptor values resolve to no action.

These changes are estimated to save roughly 64 RAM blocks from RF wave memory,
plus any resources formerly retained by the disabled diagnostic shadow. The
estimate projects the universal design below the 90% RAM-block ceiling, while
the last accepted no-FP standard fit already put ALMs below 90%. No Quartus
map/fit, RBF, Verilator run, or MiSTer hardware validation has been performed;
the exact universal percentages remain unproven until the user authorizes the
FPGA-tool optimization pass.

## 2026-08-12: Air Rescue removed from production scope

Air Rescue requires two complete linked System 32 PCBs. The production core
does not claim that hardware boundary, so `arescue`, `arescueu`, and `arescuej`
are intentionally excluded from `tools/gen_mra.py`, tracked MRAs, releases, and
the supported-game table. The experimental peer-board, dual-V60, dual-PCB RAM,
peer-DDR, and uPD77P25 shadow paths have been removed from production sources
and manifests. This exclusion is a scope decision, not a claim that a
single-board mailbox substitute is sufficient.

## 2026-08-11: integrated CPU, memory and renderer throughput package

The universal production profile keeps the PCB V60 clock and every external data/I/O
bus cadence unchanged.  Instruction fetch, work RAM code, data, I/O, interrupts
and protection transactions all use the ordinary hardware-timed bus.

**2026-08-14 update:** the `V60 Fetch: Fast / PCB (Reset)` option described in
this and the 2026-08-10 entry below has been REMOVED, along with the wide
instruction-fetch datapath it selected.  The core always uses the PCB fetch
path.  The OSD entry is gone and `status[29]` is reserved/unused so every later
option keeps its bit assignment.  The entries below are retained as history.

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
this cache class used MLABs rather than M10Ks. The universal profile now returns
the cache to M10K storage to preserve memory-ALM slack; the new inference and
timing remain Quartus-unverified.

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
(-19.5%) with the same 12 physical fetch reads. The focused burst fixture
reported 36,225 cycles for its overlap-A case before that title-specific
fixture was retired.

## 2026-08-10: V60 throughput improvements

The universal production profile compiles the existing 8-byte ROM-cache instruction
port and exposed `V60 Fetch: Fast / PCB (Reset)`.  **Superseded 2026-08-14:**
that option and its wide instruction-fetch datapath have been removed; every
instruction prefetch now uses the shared, ce-gated 16-bit V60 adapter, the same
path the `PCB` setting selected.  Data, I/O, interrupt, video, audio and
protection traffic retain their PCB clocks and bus ordering, as they always
did.

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
buffer. Both corrections are part of the universal production profile and are
not game-gated.

Hardware recordings from Jurassic Park and Rad Rally showed the causal shape:
quiet/short sprite lists were smooth, while all trees, roadside objects, cars
and dinosaurs in dense scenes stepped together.  Road/tile scanout continued
smoothly, isolating the sprite renderer's field budget rather than V60 cadence
or one object's transparency.  The overrun regression also requires the third
slot and asserts that scanout cannot change until a complete field is
published.  Quartus/RBF and post-fix MiSTer hardware verification remain
pending.

## 2026-08-12: one universal production profile

The former split revisions are retired. `Arcade-SegaSystem32.qsf` is the only production
Quartus revision and contains the standard-board peripherals together with the
real NEC V25 core/cache/program memories. Descriptor fields select the V25
path for `ga2`/`arabfgt` and the existing HLE or optional I/O/protection paths
for other supported parents. This is a source/routing unification; it is not a
claim that the new combined shape has already been fit or timing-closed.

`rtl/s32_core.sv` is compiled once with the universal shape. `GAME_ONLY_STD`
keeps the descriptor-gated driving ADC, PPI, Dark Edge protection, and real
V25 path while still allowing single-screen resource trimming. Do not name a
macro after a specific game.

## Outputs

- `Arcade-SegaSystem32.rbf` / `Arcade-SegaSystem32.qsf`: every supported parent, including `ga2` and
  `arabfgt` (descriptor-selected real V25).
- No production image supports Multi 32 sets.

## 2026-08-17: Super Visual Football family restored

The universal profile now emits the five standard-board football sets `svf`,
`svfo`, `svs`, `jleague`, and `jleagueo`. All use the `svf` two-player,
8-way/three-button input layout; the MRA labels are Shoot, Pass-A, and Pass-B.
The two J.League sets select `PROT_JLEAGUE` in descriptor byte 2 because MAME's
`init_jleague` installs the `0x20f700-0x20f705` protection write handler. The
European and Soccer sets retain `PROT_NONE`.

The production RBF remains `Arcade-SegaSystem32.rbf`; this is a descriptor and
shared protection-path extension, not a new Quartus revision or game macro.

## User-requested exclusions (2026-08-03)

The following parents/sets are intentionally ignored and must not be emitted
as MRAs, staged by the active profile sweep, or treated as supported in future
profile work: `alien3`, `arescue`, `brival`, `dbzvrvs`, `f1en`, `f1lap`,
`jpark`, and `sonic`. Local private media and historical captures may remain
on disk; they are outside the production profile.

## Source of truth

`tools/gen_mra.py:RBF_BY_PARENT` is authoritative for MRA-to-RBF routing and
maps every supported parent to `"Arcade-SegaSystem32"`. `Arcade-SegaSystem32.qsf` is the only
production Quartus revision. `S32_PROFILE_STANDARD`, `S32_UNIVERSAL`,
`S32_V25_HW`, and `S32_GAME_ONLY_STD` define the universal hardware shape.
`S32_PROFILE_V25` and `S32_REAL_V25` must never be defined again. Any macro
named after a specific game (`S32_GA2_ONLY`,
`S32_SONIC_ONLY`, etc.) is a test legacy and must not be used to route a
shipped game. `S32_PCB_TIMING` is a common behavior flag for fixed production
timing and never selects a game or RBF.

## Feature placement (universal profile)

| Feature/change | `Arcade-SegaSystem32` |
|---|---:|---:|
| Shared V60, video, sprite, audio, I/O, loader, and dedicated V60 ROM cache | yes |
| MSM6253 driving ADC, PPI, Dark Edge, and J.League protection | descriptor-driven |
| Rad Rally communication HLE | descriptor-driven |
| Real NEC V25 core, program SDRAM, cache, FIFO, internal data RAM | compiled in via `rtl/cpu/v25/v25.qip` (`S32_V25_HW=1`), enabled by `has_v25` |
| V25 table/cadence selection | descriptor-driven (`v25_table`) |
| CPU Turbo | removed (V60 timing relies on fixed CE spacing) |
| V60 Fetch | removed; instruction fetch always uses the PCB bus (`status[29]` reserved) |
| Multi 32 second screen/peripheral hardware | no |
| HDMI shadow-mask post-process | compiled out (`MISTER_DISABLE_SHADOWMASK`) |
| CRT Adjust | not instantiated; native video and 4:3/custom aspect pass directly to the framework |
| Integer scaling | framework `video_freak` target-size calculation retained for Normal, V-Integer, and HV-Integer OSD modes |

The production QSF no longer forces the JT12 shift stores, V25 FIFOs, or V25
EEPROM replicas into MLABs. The V25 internal data-memory byte lanes and the
main-ROM cache explicitly target M10Ks. Sprite-ROM read verification remains
compiled for the universal real-V25 hardware and is enabled only when the
descriptor selects `has_v25 && !v25_table` (GA2, not Arabian Fight or standard
HLE titles).

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
- Python verification on 2026-08-13: 132 tests passed, with one
  environment-only skip; GA2, Arabian Fight, and Holosseum release checks
  passed.
- Native headless regression on 2026-08-13: all 41/41 tiers passed with one
  differential seed, including full-core soak, Dark Edge protection, driving
  I/O, real encrypted V25 firmware, and production SDRAM integration.
- The universal profile includes the V25 path, but no Quartus, Verilator, or
  hardware qualification is claimed for this source-only merge.
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
- 2026-08-16 direct-CRT timing audit: the production `s32_video.sv` path keeps
  416-mode lines at exactly 3,072 `clk_sys` cycles and 320-mode lines at
  exactly 3,075 cycles, with stable raw HSync pulse widths of 192/240 cycles.
  This preserves the earlier hardware-informed fix for consumer-CRT wobble
  caused by non-repeating NCO line cadence. `tb_video_mode` now measures both
  line periods and pulse-width stability. Focused strict headless Verilator
  validation passed; no Quartus build, RBF, or physical CRT test was run here.

## Current goal acceptance scope (2026-08-02)

The current user-directed gameplay/attract acceptance matrix covers true parent
sets only. Clone and regional revisions and all excluded or Multi 32 parents
are outside this audit. The active parents are `arabfgt`, `darkedge`, `ga2`,
`holo`, `radm`, `radr`, `slipstrm`, and `spidman`. (`radm` was added to
this list on 2026-08-14 when it was restored to the supported set; it has no
attract-gate evidence yet.)

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

| Parent | Universal descriptor path | Evidence | Status |
|---|---|---|---|
| `holo` | standard | 85 frames; frame 80 shows the FBI anti-drug attract screen; `scratch/vromboot_out/holo_frame80.png`; exact MAME RGB match after documented crop and -1 scanline alignment | proven |
| `radr` | standard | 420-frame full-core Verilator run; frame 360 retained PPM/PNG shows the Rad Rally `Free Play`/SEGA attract screen; `ROMBOOT DONE`, `VERILATOR SCREENSHOT PASS` with 71,680 non-black pixels, IRQ-only vectors 40/41, zero freeze/tile/FB overruns; `scratch/radr_attract_win_20260801p/dump360.ppm` | proven |
| `radm` | standard | 2026-08-17 deterministic motor-mailbox closure: `C008=02`, old `0x068236` retry boundary advances through `0x068243`/`0x068251`; MAME motor-board lane is a documented reference gap; full attract/frame-diff remains pending | partial |
| `ga2` | real V25 | staged parent image and MAME attract references; universal-profile attract/frame-diff gate pending | pending |
| `arabfgt` | real V25 | staged parent image and MAME attract references; universal-profile attract/frame-diff gate pending | pending |
| all other in-scope media-present parents | standard/HLE | staged sweep or media/structural triage exists, but the attract gate is not yet closed | pending |

`ga2` and `arabfgt` are descriptor-selected real-V25 rows in the one universal
profile.

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
| `radr` | no | not MAME-exact | **2026-08-05 pixel-exact MAME comparison** (`docs/radm-radr-bringup.md`) supersedes the "100%/screenshot-gate" verdict below, which also predates any MAME frame comparison. Frames 60-240 match MAME closely (0.67% differing, stable residual — static title/logo screen); from frame 300 onward the RTL diverges from MAME with no nearby-frame rescue (a genuine content divergence, not timing drift), recovering briefly at frame 480 then diverging again from 600 through 1740. Not yet root-caused. Historical context retained below since it reflects real, still-true findings (screenshot gate, IRQ vectors, zero overruns) — it just isn't evidence of MAME-exactness. 420-frame full-core Verilator attract run passed; retained frame-360 Rad Rally capture, `ROMBOOT DONE`, screenshot gate, IRQ-only vectors 40/41, and zero freeze/tile/FB overruns; MAME-derived CN/FG plus EPR-14084 link-status HLE remains descriptor-routed and focused-tested |
| `slipstrm` | no | Strict Verilator road continuation verified through RTL frame 4500 | **2026-08-09/11 deep trace** (`docs/slipstrm-bringup.md`): fixed a shared V60 RSR return that popped the correct PC but retained the CHLVL handler's stale prefetch window, then proved and fixed an MSM6253 bus-integration error that shifted neutral wheel `0x80` before the read mux sampled D7 (the game stored `0x00` and selected Time Trial instead of MAME's World Championship). Corrected RTL selects World Championship; scene-aligned car selection differs by 192/93,184 pixels (0.2065%) after the known one-pixel horizontal offset. An assertion-clean savable replay reached the post-stadium scene at RTL frame 4500; its forest edge, apron, road-to-horizon geometry, signs, and marshal align with pinned MAME frame 3600, so no draw-distance truncation was reproduced. Exact speed/frame alignment still requires MAME's pre-race HIGH-gear input state. |
| `spidman` | no | reactivated in the standard profile; current gate not rerun | run the Spider-Man attract gate |

MAME-only timing leads are retained for deterministic run planning of supported
parents. Spider-Man uses the 1200-frame title window; these windows replace old
short smoke assumptions when a parent is promoted through the full-core gate.

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
2. Keep common behavior in shared RTL; the one universal QSF contains both
   standard-board and V25 hardware.
3. Update `tools/gen_mra.py` if a set or parent changes; never hand-edit an
   MRA's `<rbf>`.
4. Run the source/profile validation commands in `AGENTS.md`.
5. Only run either build wrapper after explicit user authorization.

The next Rad Mobile acceptance run uses the repository adapter, which allocates
a unique `R:\Verilator` workspace and routes both build and simulation through
the installed safe launchers:

```bash
bash verif/verilator/run_romboot.sh radm 660 \
  +DUMPAT=600 +DUMPN=1 +REQUIRE_VERILATOR_SCREENSHOT +QUIET
```
