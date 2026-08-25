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
# Not a gate: this revision is recorded as NOT YET TIMING-CLOSED in the QSF
# header, so a non-zero failing-path count is expected and is reported rather
# than fatal.  The STA summary is the artifact that matters.
quartus_sta "$PROJECT" || echo "(STA reported failing paths -- see the summary)"

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
  echo "== STA summary (slack) =="
  grep -iE "slack|Timing Analyzer Summary|^; +(Setup|Hold)" \
    output_files/"${PROJECT}".sta.summary | head -20 || true
fi
