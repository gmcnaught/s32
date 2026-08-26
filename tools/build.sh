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
RBF="$OUTDIR/SegaSystem32_${STAMP}.rbf"
quartus_cpf -c -o bitstream_compression=on "$SOF" "$RBF"
ls -lh "$RBF"
sha256sum "$RBF" 2>/dev/null || shasum -a 256 "$RBF"

if [ -f output_files/"${PROJECT}".sta.summary ]; then
  echo
  echo "== Timing gate (all corners) =="
  # Deliberately AFTER the RBF is written, so a failing bitstream still lands in
  # the artifact and can be examined -- it just must not be flashed, which is
  # what the non-zero exit says.
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
