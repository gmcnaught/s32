#!/usr/bin/env bash
# Sweep the p5 arbitration-parity phase across {fixed,prefix}x{edge,half} to
# map which parities trigger the request-drop.  Builds once per (dut,phase).
set -u
cd "$(dirname "$0")/../.." || exit 1
MDIR=/tmp/vsweep
WARN="-Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDPARAM -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-INITIALDLY"
VERILATOR_SAFE="${VERILATOR_SAFE:-verilator-safe}"
VERILATOR_SIM_SAFE="${VERILATOR_SIM_SAFE:-verilator-sim-safe}"
if ! command -v "$VERILATOR_SAFE" >/dev/null 2>&1 &&
   [[ -x /mnt/c/Users/meath/bin/verilator-safe.exe ]]; then
  VERILATOR_SAFE=/mnt/c/Users/meath/bin/verilator-safe.exe
fi
if ! command -v "$VERILATOR_SIM_SAFE" >/dev/null 2>&1 &&
   [[ -x /mnt/c/Users/meath/bin/verilator-sim-safe.exe ]]; then
  VERILATOR_SIM_SAFE=/mnt/c/Users/meath/bin/verilator-sim-safe.exe
fi

build() {  # $1=dut $2=phase(edge|half) -> binary at $MDIR/sim
  local def="+define+SIMULATION"; [ "$2" = half ] && def="$def +define+HALF_OFFSET"
  "$VERILATOR_SAFE" status
  "$VERILATOR_SAFE" --binary --timing --threads 1 --verilate-jobs 4 --build-jobs 4 $WARN --top-module tb_sdram_edge $def \
     --Mdir "$MDIR" -o sim verif/verilator/tb_sdram_edge.sv "$1" >/tmp/vb.log 2>&1 \
     || { echo "BUILD FAIL"; tail -4 /tmp/vb.log; return 1; }
}

sweep() {  # $1=label $2=dut $3=phase
  build "$2" "$3" || return
  local line="$1:"
  for d in $(seq 0 15); do
    local o; o="$("$VERILATOR_SIM_SAFE" -- "$MDIR/sim" +p5delay=$d 2>&1)"
    if echo "$o" | grep -q 'RESULT: PASS'; then line="$line  d$d=PASS"
    else line="$line  d$d=HANG"; fi
  done
  echo "$line"
}

echo "=== p5-phase sweep (d0..d15 = p5 delayed N clk_sys cycles) ==="
sweep "FIXED  edge " rtl/mem/sdram.sv        edge
sweep "FIXED  half " rtl/mem/sdram.sv        half
sweep "PREFIX edge " scratch/sdram_prefix.sv edge
sweep "PREFIX half " scratch/sdram_prefix.sv half
