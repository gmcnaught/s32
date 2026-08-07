# Sega System 32 profile contract

This repository has exactly two production FPGA profiles. Every change to RTL,
MRA generation, tests, build scripts, or release metadata must be routed using
this contract; do not create a new per-game Quartus revision or silently add a
game-only macro.

## Global profile routing

| Profile | Production macros | RBF | MRA parents | Hardware boundary |
|---|---|---|---|---|
| `segas32v25` | `S32_PROFILE_STANDARD=1`, `S32_GAME_ONLY=1`, `S32_REAL_V25=1` | `segas32v25.rbf` | `ga2`, `arabfgt` | Real NEC V25 core/cache/program memories compiled in; ADC, trackball, generic protection HLE, dual-PCB, Burning Rival all tied off (neither game uses any of them). |
| `segas32` | `S32_PROFILE_STANDARD=1`, `S32_GAME_ONLY_STD=1` | `segas32.rbf` | `sonic` today; `holo`, `jpark`, `radm`, `radr`, `spidman` return one at a time | No real V25 hardware at all (HLE responder `s32_v25` only). Trackball and generic protection HLE live (`GAME_ONLY_STD`); ADC, dual-PCB, Burning Rival still tied off. |

Both profiles share `rtl/s32_core.sv`; `S32_GAME_ONLY_STD` implies
`GAME_ONLY` (dual-PCB/Burning Rival tie-off applies to both profiles).
`harddunk`, `orunners`, `scross`, and `titlef` families are Multi 32 and are
not supported or emitted.

## Change-routing rules

1. A common emulation or accuracy enhancement belongs in the shared RTL and
   must be valid in both profiles. Run both profiles' lint/boot tests before
   considering it integrated.
2. A resource or hardware change belongs in the relevant profile QSF and must
   use only `S32_PROFILE_STANDARD`, `S32_GAME_ONLY`, or `S32_GAME_ONLY_STD` in
   production RTL. Descriptor fields select differences between games inside
   a profile. `S32_PROFILE_V25` is retired and must never be defined again.
3. Never reintroduce `S32_GA2_ONLY`, `S32_GOLDENAXE_ONLY`,
   `S32_ARABFIGHT_ONLY`, `S32_SONIC_ONLY`, or `S32_V25_GAME_ONLY` in a
   production source, QSF, MRA, or release script. Test-only feature macros
   must not alter production game routing.
4. `tools/gen_mra.py`'s `RBF_BY_PARENT` is the only source of `<rbf>`
   routing. Golden Axe and Arabian Fight must resolve to `segas32v25`; every
   other emitted System 32 MRA must resolve to `segas32`.
5. Use `tools/build-segas32v25.bat` or `tools/build-segas32.bat` for hardware
   builds (thin wrappers around `tools/build.bat`). Preserve Quartus
   databases, obey the eight-worker Fast Fit policy, and do not build merely
   to explore source. A build requires an explicit user request.

## Required validation

Source/profile routing:

```powershell
python -B -m unittest discover -s verif -p 'test_*.py'
python -B verif/check_ga2_release.py
python -B verif/check_arabianfight_release.py
python -B verif/check_holo_release.py
```

`check_holo_release.py` is expected to fail on the MRA-count assertion while
`holo` remains in `tools/gen_mra.py:IGNORED_PARENTS` -- that is the current,
intentional state, not a regression to chase.

Native HDL regression:

```powershell
& .\verif\run_regression.ps1
```

The real-V25 firmware runner must call `verilator-safe status` first and use
`verilator-safe` / `verilator-sim-safe`; never invoke an original Verilator
binary directly.

## Persistent status

The current profile matrix and evidence are recorded in `PROFILE_CONTRACT.md`.
Update that file when a hardware family, supported set, or validation gate
changes. Keep private ROMs, NVRAM, captures, generated models, and Quartus
databases local.
