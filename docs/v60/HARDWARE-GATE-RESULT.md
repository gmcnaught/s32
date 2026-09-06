# The four-game hardware gate, run on PR #24 — and what it exposed

Result of running `tools/hwgate.sh`'s sequence against the bitstreams around
PR #24 on a real DE10-Nano (192.168.20.62), 2026-09-05. PR #24 merged as
`e10968c` on the strength of its seven green CI checks; this document records
why those checks are not a hardware verdict, what the hardware said, and the
gaps that leaves. It is a companion to `docs/v60/DATABOOK-TIMING-RESULT.md`,
which established the method: same tree, same toolchain, same device, one
variable at a time.

## Method

Each run is the on-device script `tools/hwgate_remote.sh`: load Golden Axe:
The Revenge of Death Adder, Spider-Man, Rad Rally and Dark Edge in turn from
the repository's MRAs in `releases/`, two screenshots per title, ~30 s and
~78 s after the load. `tools/hwgate_score.py` decides. Where a title looked
wrong, a second script loaded it alone and sampled every 30 s out to five
minutes. Every other System 32 bitstream on the device was moved into
`_Arcade/cores/.hwgate-hold/` for the duration of each run, so the MRAs'
`<rbf>Arcade-SegaSystem32</rbf>` could resolve to only one file; the active
file's SHA-256 was printed before each run.

## The builds

| label | tree | built by | fitter seed | SHA-256 (first 16) |
|---|---|---|---|---|
| `repo-20260817` | `releases/Arcade-SegaSystem32_20260817.rbf`, the repository's known-good | the maintainer's Windows pipeline | — | `c7a58eb6c6f312bb` |
| `main-0826-ci` | `main` at `0574792` (RTL identical to `e852cb2`) | CI, `tools/build.sh` in `raetro/quartus:17.0`, run 33021076280 | 5 (QSF) | `179b294f99863368` |
| `pr24-ci` | `v60/cleanroom` at `b1b8579` | CI, same flow, run 33986984169 | 5 (QSF) | `8860d2f9ab344c7a` |
| `pr24-local` | same | `tools/build-segas32.bat`, Quartus Lite 17.0.2 on Windows | 2 (first in the pipeline's seed list) | `7085184986…` |
| `main-local-seed5` | `main` at `e852cb2` | `tools/build-segas32.bat` with `S32_FIT_SEEDS=5` | 5 | *pending — see below* |
| `dist-20260831` | **not this repository**: `Arcade-SegaSystem32_20260831.rbf` from the official MiSTer distribution (`distribution_mister`, tangle `arcade-segasystem32_core`) | — | — | — |

All three Quartus flows report the same version (17.0.2 Build 602), the same
PLL (445.5 MHz VCO from 50 MHz), timing met on every corner, and the same 37
unconstrained I/O ports.

## What the device said

| build | ga2 | spidman | radr | darkedge | scorer |
|---|---|---|---|---|---|
| `repo-20260817` | renders | renders | renders | renders | **PASS** |
| `dist-20260831` | renders | renders | renders | renders | **PASS** (and Rad Rally alone ran five minutes clean) |
| `main-0826-ci` | frozen on the title screen | frozen on the copyright card | flat, near-black | flat grey | INCONCLUSIVE — *every title hangs on its first screen* |
| `pr24-ci` | renders | **horizontal noise**, 416×224, both samples | renders | renders at 30 s, black at 78 s | PASS — **a false pass**, see gap 4 |
| `pr24-local`, run 1 | renders | renders | black, both samples | renders | FAIL |
| `pr24-local`, run 2 | renders | frozen on the intro artwork | black, both samples | renders | FAIL |
| `main-local-seed5` | | | | | *pending* |

Longer probes, one title alone:

- **Rad Rally on `pr24-local`**: attract mode healthy at 30, 60, 90 and 120 s
  (the course-record screen, then the demo drive, courses 3 and 4); at 180 s a
  corrupted frame — wrong palette, no text, no road — byte-identical at 240 s.
  A freeze in the third minute, invisible to the 78 s gate. Loaded alone it
  rendered at 30 s; in the gate's sequence, right after Spider-Man, it was
  black at 30 s and 78 s in both runs.
- **Dark Edge on `pr24-ci`**: renders at 30 s; from 60 s through 300 s one
  byte-identical frame with a magenta-corrupted palette. The gate's
  fade-in rule ("one black sample is allowed, Dark Edge is mid fade at 30 s")
  let this pass.
- **Rad Rally on `dist-20260831`**: seven samples over five minutes, all
  different, all healthy. Not a statement about this repository's RTL; it
  says the ROMs, the MRAs and the device are fine.

## Reading it

1. **The device is sound.** `repo-20260817` passes, with the same frame
   pattern as the distribution's core.
2. **Main's own CI bitstream fails harder than either PR #24 build.** So the
   6B/7B change in PR #24 — the only shipping-RTL change in the PR — is not
   the primary cause of what the PR builds do. It also has no clean verdict
   of its own yet; see gap 8.
3. **Two variables remain entangled: the build path and the fitter seed.**
   The repository's notes record main's Aug 25 RTL rendering all four titles
   on this device, from the maintainer's local builds. The CI build of the
   same RTL hangs everything. Same Quartus, same PLL, timing met in both —
   the difference is somewhere in the flow and is not known. The pending
   `main-local-seed5` run is the single-variable test against `main-0826-ci`.

## The gaps

1. **CI's `RBF (Quartus Lite 17.0)` check is a compile-and-timing check, not
   a hardware check.** No CI-built bitstream had been put on hardware before
   today; the first one, main's, fails every title. Until the flow difference
   is found, a CI RBF must not be shipped or used to qualify an RTL change.
   Hardware qualification stays on the Windows pipeline.
2. **The local pipeline's seed order disagrees with the QSF.** `tools/build.bat`
   tries seeds `2 3 4 6 1 5` and stops at the first that closes timing;
   `tools/build-s32.bat` pins 2. The QSF header records seed 5 as the winner
   for the current netlist (2026-08-18) after 2 missed. A seed-2 PR #24 build
   closes timing (+0.129 ns on `clk_ram`, against +0.287 ns for seed 5) and
   fails on hardware. On this design, STA met is necessary, not sufficient;
   the seed a build ran with must be part of any hardware result.
3. **The gate's window is 78 s.** Two of the failures found today start
   later: Rad Rally in the third minute, Dark Edge at 60 s. A five-minute
   single-title probe (the shape used above: load, sample every 30 s, compare
   consecutive samples) belongs in the gate for the two titles that die late.
4. **The scorer passes noise.** Spider-Man's two frames of horizontal static
   differ from each other and have high variance, which is exactly what
   `hwgate_score.py` takes as "renders and animates". It needs a structure
   test — row-to-row correlation, or the fraction of the frame made of runs
   longer than a few pixels — so that a picture and a noise field score
   differently. Its `STATIC` verdict on `main-0826-ci` was correct and is
   the verdict to trust; the fade-in allowance for Dark Edge should require
   the *first* sample to be the black one, which is what the rule describes.
5. **`tools/hwgate.sh` does not complete from this workstation.** Its ssh
   session to the device stayed open after the remote script printed
   `GATE-DONE`, its pull stage came back empty, and it calls `python3`, which
   on this machine is the Microsoft Store alias. What worked: copy
   `hwgate_remote.sh` to `/tmp`, start it detached with `nohup`, poll its log
   for `GATE-DONE`, `scp` the two named files per title, score with `python`.
6. **The core's name is no longer unique on a MiSTer.** The official
   distribution now ships `Arcade-SegaSystem32_20260831.rbf` and a `Multi`
   variant, which the repository's MRAs can resolve to by name. A development
   build must be the only `Arcade-SegaSystem32*.rbf` on the card during a
   measurement, or the MRAs used for the gate must name a different `<rbf>`.
7. **Screenshots are filed by `/tmp/CORENAME`, which can lag the load.** In
   the first run a Spider-Man frame landed in `screenshots/ga2/` and the
   remote log was garbled. Pull by timestamp from the run's window, not by
   folder alone.
8. **The 6B/7B change has no isolated hardware verdict.** Both builds that
   contain it fail; main without it fails too (CI). The clean A/B is
   `main-local-seed5` against a `pr24-local-seed5` built the same way. The
   first is pending; the second is the next build.
9. **update_all's arcade ROM database does not carry the System 32 sets**
   (their MRAs are not in the distribution). `ga2 spidman radr darkedge`
   go into `/media/fat/games/mame/` by hand.
10. **The late-freeze symptoms — a corrupted palette on a frozen frame — are
    the shape of the interlock arm-B failure recorded in `rtl/s32_core.sv`**
    (flat frames, byte-identical). Recorded as a resemblance, not an
    attribution; the A/B in gap 8 comes first.

## Next

- `main-local-seed5` on the device; then `pr24-local-seed5`, built with
  `S32_FIT_SEEDS=5 tools/build-segas32.bat` on `e10968c`. Those two runs
  close gap 8 and split gap 1's variables.
- If the local seed-5 builds pass: find what the CI flow does differently
  (start with the `.qsf` assignments the Linux path rewrites, and the
  `qsys-generate` PLL output it regenerates), and make the RBF workflow's
  artifact carry its seed and fit summary in its name.
- Gaps 3 and 4 in `tools/hwgate_remote.sh` and `tools/hwgate_score.py`;
  gap 5 in `tools/hwgate.sh`.
- Then stage 4 of `docs/v60/LANDING-PLAN.md` resumes, each PR gated by a
  local seed-5 build on this device.
