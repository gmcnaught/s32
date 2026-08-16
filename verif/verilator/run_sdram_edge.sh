#!/usr/bin/env bash
# Verilator cross-validation matrix for the sdram.sv request-latch fix.
# {fixed RTL, pre-fix reconstruction} x {edge-aligned PLL, half-offset TB phase}.
set -u
cd "$(dirname "$0")/../.." || exit 1   # repo root
WARN="-Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-INITIALDLY"
VERILATOR_SAFE="${VERILATOR_SAFE:-verilator-safe}"
VERILATOR_SIM_SAFE="${VERILATOR_SIM_SAFE:-verilator-sim-safe}"
command -v "$VERILATOR_SAFE" >/dev/null 2>&1 || { echo "missing $VERILATOR_SAFE" >&2; exit 127; }

source verif/verilator/workspace.sh
s32_verilator_workspace "$VERILATOR_SAFE"
MDIR="$(s32_verilator_mdir vsdram)"
BUILD_LOG="$S32_VERILATOR_WORKSPACE/vbuild.log"
command -v "$VERILATOR_SIM_SAFE" >/dev/null 2>&1 || { echo "missing $VERILATOR_SIM_SAFE" >&2; exit 127; }

run() {
  local tag="$1" dut="$2" phase="$3" vcd="$4"
  local def="+define+SIMULATION"
  [ "$phase" = "half" ] && def="$def +define+HALF_OFFSET"
  "$VERILATOR_SAFE" status
  "$VERILATOR_SAFE" --binary --timing --trace --threads 1 \
     --verilate-jobs 4 --build-jobs 4 $WARN --top-module tb_sdram_edge $def \
     --Mdir "$MDIR" -o tb_sdram_edge verif/verilator/tb_sdram_edge.sv "$dut" >"$BUILD_LOG" 2>&1
  if [ $? -ne 0 ]; then echo "[$tag] BUILD FAILED"; tail -5 "$BUILD_LOG"; return; fi
  # rename the vcd this run produces so runs don't clobber each other
  local out; out="$("$VERILATOR_SIM_SAFE" -- "$MDIR/tb_sdram_edge" 2>&1)"
  [ -n "$vcd" ] && [ -f verif/verilator/tb_sdram_edge.vcd ] && mv verif/verilator/tb_sdram_edge.vcd "$vcd"
  local res; res="$(echo "$out" | grep -E 'RESULT|HUNG|lost' | head -3 | tr '\n' ' ')"
  local cnt; cnt="$(echo "$out" | grep -E 'icache|V25 burst' | tr '\n' ' ')"
  printf '[%-22s] %s || %s\n' "$tag" "$res" "$cnt"
}

echo "=== sdram.sv arbitration cross-validation (Verilator 5.032) ==="
run "FIXED  edge-aligned"  rtl/mem/sdram.sv        edge verif/verilator/tb_sdram_edge_fixed.vcd
run "FIXED  half-offset"   rtl/mem/sdram.sv        half ""
run "PREFIX edge-aligned"  scratch/sdram_prefix.sv edge verif/verilator/tb_sdram_edge_prefix.vcd
run "PREFIX half-offset"   scratch/sdram_prefix.sv half ""
echo "=== VCDs: tb_sdram_edge_fixed.vcd (pass), tb_sdram_edge_prefix.vcd (hang) ==="
