#!/usr/bin/env bash
# Compile far enough to get a real timing netlist, then check s32.sdc's V60
# exceptions against it (verif/timing/sdc_check.tcl).
#
# THIS DOES NOT AND MUST NOT PRODUCE AN RBF.
#
# tools/build.sh is deliberately disabled so that no Linux/CI path can produce
# or qualify a public bitstream -- release builds go through the locked Windows
# pipeline (tools/build-s32.bat) and its gates.  This script honours that: it
# runs quartus_map and quartus_fit to get a fitted netlist, then quartus_sta,
# and NEVER calls quartus_asm.  No .sof and no .rbf is created, so it cannot
# become a way around those gates.
#
# Usage:
#   verif/timing/run_quartus_sdc_check.sh            # Quartus already on PATH
#   docker run --rm -v "$PWD:/build" raetro/quartus:17.0 \
#       bash -c "cd /build && verif/timing/run_quartus_sdc_check.sh"
#
# QUARTUS_ROOT may point at an install whose bin/ is not on PATH.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

PROJECT="Arcade-SegaSystem32"

if [ -n "${QUARTUS_ROOT:-}" ] && [ -x "$QUARTUS_ROOT/bin/quartus_sh" ]; then
  export PATH="$QUARTUS_ROOT/bin:$PATH"
fi
command -v quartus_map >/dev/null 2>&1 || {
  echo "ERROR: quartus_map not on PATH." >&2
  echo "       Set QUARTUS_ROOT, or run this inside raetro/quartus:17.0." >&2
  exit 127
}

echo "== Quartus =="
quartus_sh --version | head -2

# The project is pinned to Quartus 17.0 (the QPF says so, and the supported
# pipeline validates 17.0.2.602).  Newer Quartus is not compatible with this
# design, so say plainly what is being used rather than letting a mismatch
# surface later as a confusing fit error.
ver="$(quartus_sh --version | sed -n 's/.*Version \([0-9.]*\).*/\1/p' | head -1)"
case "$ver" in
  17.0*) : ;;
  *) echo "WARNING: Quartus $ver is not 17.0; this project is pinned to 17.0." >&2 ;;
esac

# The Qsys tools live outside quartus/bin, and the raetro image only puts
# quartus/bin on PATH.
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
# rtl/pll/pll.qip -- which files.qip pulls in -- points at
# rtl/pll/synthesis/pll.qip, and BOTH that directory and rtl/pll/pll.qsys are
# gitignored: they are generated, not committed.  Without this step Analysis &
# Synthesis dies with
#   Error (12006): Node instance "pll" instantiates undefined entity "pll"
# rtl/pll/pll.v is only a simulation placeholder ("cannot produce a valid
# release bitstream", says its own header) and is deliberately NOT in
# files.qip, so it does not stand in for the real IP.
#
# Invocation is exactly the one documented in tools/make_pll.tcl's header,
# which is also what tools/build.bat does before compiling.
QSYS_SCRIPT="$(find_qsys qsys-script)" || {
  echo "ERROR: qsys-script not found; cannot generate the PLL IP." >&2; exit 127; }
QSYS_GENERATE="$(find_qsys qsys-generate)" || {
  echo "ERROR: qsys-generate not found; cannot generate the PLL IP." >&2; exit 127; }
echo "using $QSYS_SCRIPT"
echo "using $QSYS_GENERATE"
"$QSYS_SCRIPT" --script=tools/make_pll.tcl
"$QSYS_GENERATE" rtl/pll/pll.qsys --synthesis=VERILOG --output-directory=rtl/pll
test -f rtl/pll/synthesis/pll.qip || {
  echo "ERROR: rtl/pll/synthesis/pll.qip was not generated." >&2; exit 1; }
echo "PLL IP generated."

echo
echo "== Analysis & Synthesis =="
quartus_map "$PROJECT" --read_settings_files=on

echo
echo "== Fitter (placement is needed before get_registers means anything) =="
quartus_fit "$PROJECT"

echo
echo "== Timing analysis + SDC checks =="
# The script opens the project itself, so do NOT also pass the project name --
# quartus_sta would open it first and the script's project_open would then be a
# double-open error.  quartus_sta returns non-zero when the TCL calls
# `qexit -error`.
quartus_sta -t verif/timing/sdc_check.tcl

echo
echo "== Summary =="
cat output_files/v60_sdc_check.txt

# Deliberately absent: quartus_asm.  See the header.
if ls output_files/*.sof output_files/*.rbf >/dev/null 2>&1; then
  echo "ERROR: a bitstream was produced; this path must not do that." >&2
  exit 1
fi
echo "OK: no bitstream produced, as intended."
