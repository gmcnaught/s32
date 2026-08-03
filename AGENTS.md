# Sega System 32 profile contract

This repository has exactly two production FPGA profiles. Every change to RTL,
MRA generation, tests, build scripts, or release metadata must be routed using
this contract; do not create a new per-game Quartus revision or silently add a
game-only macro.

## Global profile routing

| Profile | Production macro | RBF | MRA parents | Hardware boundary |
|---|---|---|---|---|
| Standard | `S32_PROFILE_STANDARD=1` | `s32.rbf` | `holo`, `jpark`, `radm`, `radr`, `sonic`, `spidman` | Descriptor-driven System 32 peripherals; real V25 CPU/cache/program memories removed; Multi 32 removed. |
| Real V25 | `S32_PROFILE_V25=1` | `s32v25.rbf` | `ga2`, `arabfgt` | Real V25 and its memories retained; descriptor selects GA2 versus Arabian protection table and measured V60 cadence; unrelated peripherals removed. |

`harddunk`, `orunners`, `scross`, and `titlef` families are Multi 32 and are
not supported or emitted. The user-facing typo “s23.rbf” means `s32.rbf` in
this project.

## Change-routing rules

1. A common emulation or accuracy enhancement belongs in the shared RTL and
   must be valid in both profiles. Run standard and V25 profile lint/boot
   tests before considering it integrated.
2. A resource or hardware change belongs in the relevant profile QSF and must
   use only `S32_PROFILE_STANDARD` or `S32_PROFILE_V25` in production RTL.
   Descriptor fields select differences between games inside a profile.
3. Never reintroduce `S32_GA2_ONLY`, `S32_GOLDENAXE_ONLY`,
   `S32_ARABFIGHT_ONLY` or `S32_V25_GAME_ONLY` in a
   production source, QSF, MRA, or release script. Test-only feature macros
   must not alter production game routing.
4. `tools/gen_mra.py` is the only source of `<rbf>` routing. Golden Axe and
   Arabian Fight must resolve to `s32v25`; every other emitted System 32 MRA
   must resolve to `s32`.
5. Use `tools/build-s32.bat` or `tools/build-s32v25.bat` for hardware builds.
   Preserve Quartus databases, obey the six-worker Fast Fit policy, and do not
   build merely to explore source. A build requires an explicit user request.

## Required validation

Source/profile routing:

```powershell
python -B -m unittest discover -s verif -p 'test_*.py'
python -B verif/check_ga2_release.py
python -B verif/check_arabianfight_release.py
python -B verif/check_holo_release.py
```

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
