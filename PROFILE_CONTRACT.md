# Sega System 32 global profile contract

This is the persistent cross-chat routing record for the core.

## Outputs

- `s32.rbf` / `s32.qsf`: standard image for the active parents `holo`, `jpark`,
  `radm`, `radr`, `sonic`, and `spidman`.
- `s32v25.rbf` / `s32v25.qsf`: universal real-V25 image for `ga2` and
  `arabfgt`. The descriptor's `v25_table` bit selects the table and cadence.
- No production image supports Multi 32 sets.

## User-requested exclusions (2026-08-03)

The following parents are intentionally ignored and must not be emitted as
MRAs, staged by the active profile sweep, or treated as supported in future
profile work: `brival`, `darkedge`, `dbzvrvs`, `f1en`, `f1lap`, `slipstrm`,
`svf`, and `jleague`. Local ROMs and historical captures may remain on disk;
they are outside the production profile.

## Source of truth

`tools/gen_mra.py:RBF_BY_PARENT` is authoritative for MRA-to-RBF routing.
`s32.qsf` and `s32v25.qsf` are the only production Quartus revisions.
`S32_PROFILE_STANDARD` and `S32_PROFILE_V25` are the only production profile
macros. Any other game-named macro is a test legacy and must not be used to
route a shipped game. `S32_PCB_TIMING` is a common, profile-independent
behavior flag in both QSFs; it selects the shared ce-gated V60 fetch boundary
and never selects a game or RBF.

## Feature placement

| Feature/change | `s32` | `s32v25` |
|---|---:|---:|
| Shared V60, video, sprite, audio, I/O, loader, and HLE protection fixes | yes | yes |
| Descriptor-driven ADC/trackball/gun/PPI/dual-PCB/link-HLE paths | yes | profile-pruned where physically absent |
| Real NEC V25 core, program SDRAM, cache, FIFO, internal data RAM | no | yes |
| V25 table/cadence selection | no | descriptor-driven GA2/Arabian |
| Multi 32 second screen/peripheral hardware | no | no |

## Evidence status (2026-08-01)

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
- Resource-focused RTL change: `s32_dualpcb` now uses lazy reset defaults and
  a written bitmap so its 2,048 x 16-bit communication store can infer RAM;
  the F1 bridge contract remains covered by tier 36. Quartus ALM
  and M10K impact is still unmeasured until the authorized profile builds.
- The pinned-MAME EPR-14084 link-status HLE is source-integrated for the radr
  descriptor, reuses the existing communication RAM, and passes focused map
  plus byte/wide ROM-loader tests. Full-core radr attract verification now
  passes the screenshot gate at frame 360 in the retained 420-frame run.

## Current goal acceptance scope (2026-08-02)

The current user-directed gameplay/attract acceptance matrix covers true parent
sets only. Clone and regional revisions, all Multi 32 parents, `holo`, and
`spidman` are excluded from this audit. The remaining active Standard parents
are `jpark`, `radm`, `radr`, and `sonic`; the two V25 parents remain `ga2` and
`arabfgt`.

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
| `holo` | excluded | — | explicitly excluded from the current audit; production routing retained |
| `ga2` | no | 50% | staged V25 parent image; real-V25 attract and MAME frame-diff gate pending |
| `arabfgt` | no | 50% | staged V25 parent image; real-V25 attract and MAME frame-diff gate pending |
| `jpark` | no | 50% | 150-frame Verilator smoke; run the corresponding 1200-frame Verilator title window selected from MAME |
| `radm` | no | 50% | 150-frame Verilator smoke; prepared 660-frame full-core run with frame-600 capture selected from MAME, but the safe scheduler has not yet admitted it |
| `radr` | yes | 100% | 420-frame full-core Verilator attract run passed; retained frame-360 Rad Rally capture, `ROMBOOT DONE`, screenshot gate, IRQ-only vectors 40/41, and zero freeze/tile/FB overruns; MAME-derived CN/FG plus EPR-14084 link-status HLE remains descriptor-routed and focused-tested |
| `sonic` | no | 75% | deterministic visible gameplay reached through frame 2200 with sprites/HUD closely aligned; NBG floor is absent because the post-clear low name-table writes diverge, now isolated below the renderer and under focused V60 caller-path analysis |
| `spidman` | excluded | — | explicitly excluded from the current audit; production routing retained |

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
