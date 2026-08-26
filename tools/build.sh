#!/usr/bin/env bash
# Linux build of the Sega System 32 core, producing an RBF.
#
# History: this script used to refuse to run, on the grounds that a Linux/CI
# path must not produce or qualify a public bitstream.  That decision has been
# reversed by the maintainer.  The Windows pipeline (tools/build-s32.bat) is
# still the one that performs release staging and its per-game qualification
# gates; this path exists so the core can be built and tested from CI and from
# a Linux workstation without one.
#
# Usage:
#   tools/build.sh [output-dir]                  # Quartus already on PATH
#   docker run --rm -v "$PWD:/build" raetro/quartus:17.0 \
#       bash -c "cd /build && tools/build.sh _out"
#
# QUARTUS_ROOT may point at an install whose bin/ is not on PATH.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

PROJECT="Arcade-SegaSystem32"
OUTDIR="${1:-output_files}"

if [ -n "${QUARTUS_ROOT:-}" ] && [ -x "$QUARTUS_ROOT/bin/quartus_sh" ]; then
  export PATH="$QUARTUS_ROOT/bin:$PATH"
fi
command -v quartus_map >/dev/null 2>&1 || {
  echo "ERROR: quartus_map not on PATH. Set QUARTUS_ROOT, or run inside raetro/quartus:17.0." >&2
  exit 127
}

echo "== Quartus =="
quartus_sh --version | head -2
ver="$(quartus_sh --version | sed -n 's/.*Version \([0-9.]*\).*/\1/p' | head -1)"
case "$ver" in
  17.0*) : ;;
  *) echo "WARNING: Quartus $ver is not 17.0; this project is pinned to 17.0." >&2 ;;
esac

# rtl/pll/pll.qip points at rtl/pll/synthesis/pll.qip, and both that directory
# and rtl/pll/pll.qsys are gitignored because they are generated.  Without this
# step Analysis & Synthesis dies with
#   Error (12006): Node instance "pll" instantiates undefined entity "pll"
# rtl/pll/pll.v is only a simulation placeholder and is not in files.qip.
find_qsys() {
  local n=$1 p
  if command -v "$n" >/dev/null 2>&1; then command -v "$n"; return 0; fi
  local root="${QUARTUS_ROOTDIR:-$(dirname "$(dirname "$(command -v quartus_map)")")}"
  for p in "$root/sopc_builder/bin/$n" "$root/../qsys/bin/$n" "$root/qsys/bin/$n"; do
    [ -x "$p" ] && { echo "$p"; return 0; }
  done
  return 1
}
echo
echo "== Generate the PLL IP =="
QS="$(find_qsys qsys-script)"   || { echo "ERROR: qsys-script not found" >&2; exit 127; }
QG="$(find_qsys qsys-generate)" || { echo "ERROR: qsys-generate not found" >&2; exit 127; }
"$QS" --script=tools/make_pll.tcl
"$QG" rtl/pll/pll.qsys --synthesis=VERILOG --output-directory=rtl/pll
test -f rtl/pll/synthesis/pll.qip || { echo "ERROR: PLL IP not generated" >&2; exit 1; }

echo
# Fitter seed override, for a seed sweep.  The QSF header records a long
# history of one fact: the winning fitter seed changes whenever the netlist
# changes, so every netlist change needs a fresh exploration and a single
# rebuild is not a fair test of an RTL change.  S32_SEED rewrites the QSF
# assignment rather than passing quartus_fit --seed, because the assignment is
# what the QSF header documents and it cannot silently be an unsupported
# option on this Quartus version.
if [ -n "${S32_SEED:-}" ]; then
  case "$S32_SEED" in
    ''|*[!0-9]*) echo "ERROR: S32_SEED must be a non-negative integer, got '$S32_SEED'" >&2; exit 2 ;;
  esac
  echo
  echo "== Fitter seed override: $S32_SEED =="
  sed -i.seedbak "s/^set_global_assignment -name SEED .*/set_global_assignment -name SEED ${S32_SEED}/" "${PROJECT}.qsf"
  grep -q "^set_global_assignment -name SEED ${S32_SEED}\$" "${PROJECT}.qsf" || {
    echo "ERROR: could not set SEED in ${PROJECT}.qsf" >&2; exit 2; }
  grep -n "^set_global_assignment -name SEED" "${PROJECT}.qsf"
fi

# Extra Verilog macros, for a diagnostic build.  Same reasoning as S32_SEED:
# the alternative is a throwaway branch whose only content is three QSF lines
# (v60/exp-hud-on was exactly that), which cannot be dispatched against another
# ref and rots the moment main moves.  The debug HUD is the motivating case:
#
#   S32_DEFINES=S32_DEBUG_HUD=1,PROT_INTERLOCK_EN=1
#
# builds the HUD bitstream with the protection interlock armed -- the exact
# diagnostic build the PROT_INTERLOCK regression needs -- from any ref, with no
# branch to merge and nothing to revert afterwards.
#
# Appended rather than substituted: these are additions to the project's macro
# set, and a name that is already assigned is Quartus's conflict to report, not
# something to paper over here.
if [ -n "${S32_DEFINES:-}" ]; then
  echo
  echo "== Extra Verilog macros: $S32_DEFINES =="
  printf '\n# Added by tools/build.sh from S32_DEFINES for this build only.\n' \
      >> "${PROJECT}.qsf"
  IFS=','
  for macro in $S32_DEFINES; do
    unset IFS
    case "$macro" in
      *[!A-Za-z0-9_=]*|''|=*|*=*=*)
        echo "ERROR: bad macro '$macro' (want NAME or NAME=VALUE)" >&2; exit 2 ;;
    esac
    echo "set_global_assignment -name VERILOG_MACRO \"$macro\"" >> "${PROJECT}.qsf"
    echo "   + $macro"
    IFS=','
  done
  unset IFS
fi

echo "== Analysis & Synthesis =="
quartus_map "$PROJECT" --read_settings_files=on
echo
echo "== Fitter =="
quartus_fit "$PROJECT"
echo
echo "== Assembler =="
quartus_asm "$PROJECT"
echo
echo "== Timing analysis =="
# quartus_sta's own exit code stays non-fatal: this revision is recorded as NOT
# YET TIMING-CLOSED in the QSF header because of one vendored HDMI/ascal setup
# path that main itself misses and ships with.  Gating on quartus_sta directly
# would block every build including known-good ones.
#
# But "not a gate" used to mean NO gate, and the summary was only ever echoed
# `head -20` deep -- so on 2026-08-25 two builds reached hardware with HOLD
# violations on the core clock domains, both reported by CI as a passing RBF,
# and both blacked out every game.  check_timing_gate.py reads all four corners
# and applies the distinction that was missing: hold anywhere and setup on a
# core domain are fatal, the vendored HDMI setup path is tolerated.
quartus_sta "$PROJECT" || echo "(STA reported failing paths -- the gate below decides)"

# Where the failing paths actually are.  The summary alone says a domain misses
# and not which registers, which is not enough to fix anything and costs
# another fit to find out.
quartus_sta -t verif/timing/worst_paths.tcl || \
  echo "(worst-path report failed; summary above still stands)"

echo
echo "== Output =="
mkdir -p "$OUTDIR"
SOF="output_files/${PROJECT}.sof"
test -f "$SOF" || { echo "ERROR: no .sof produced" >&2; exit 1; }
STAMP="$(date -u +%Y%m%d)"
# A diagnostic bitstream must be identifiable once it is a file on an SD card,
# not only in the CI artifact it came from.
DEFTAG=""
if [ -n "${S32_DEFINES:-}" ]; then
  DEFTAG="_$(printf '%s' "$S32_DEFINES" | tr -cd 'A-Za-z0-9' | cut -c1-24)"
fi
RBF="$OUTDIR/SegaSystem32_${STAMP}${S32_SEED:+_seed${S32_SEED}}${DEFTAG}.rbf"
quartus_cpf -c -o bitstream_compression=on "$SOF" "$RBF"
ls -lh "$RBF"
sha256sum "$RBF" 2>/dev/null || shasum -a 256 "$RBF"

if [ -f output_files/"${PROJECT}".sta.summary ]; then
  echo
  echo "== Timing gate (all corners) =="
  # Deliberately AFTER the RBF is written, so a failing bitstream still lands in
  # the artifact and can be examined -- it just must not be flashed, which is
  # what the non-zero exit says.
  # Report the interpreter once per build.  The container's python3 version was
  # inferred from a SyntaxError rather than known, which is a poor way to learn
  # a build dependency.
  echo "-- interpreter: $(python3 --version 2>&1)"
  set +e
  python3 verif/timing/check_timing_gate.py \
    output_files/"${PROJECT}".sta.summary
  TIMING_GATE_RC=$?
  set -e
fi

# The gate's exit codes are distinct on purpose.  The first version of this
# script used f-strings, crashed on the CI container's older python3, and
# build.sh announced "timing gate rejected this bitstream" -- reporting a
# broken check as a failing design.  That is the same defect this gate exists
# to fix, so the two are never conflated again.
case "${TIMING_GATE_RC:-0}" in
  0) : ;;
  3) echo "BUILD FAILED: timing gate REJECTED this bitstream -- do not flash it" >&2
     exit 1 ;;
  2) echo "BUILD FAILED: timing gate could not evaluate the STA summary" >&2
     echo "  (STA did not run, or output_files/${PROJECT}.sta.summary is unreadable)" >&2
     exit 1 ;;
  *) echo "BUILD FAILED: the timing gate itself is broken (exit ${TIMING_GATE_RC})" >&2
     echo "  This is a TOOLING fault, not a verdict on the bitstream." >&2
     exit 1 ;;
esac
