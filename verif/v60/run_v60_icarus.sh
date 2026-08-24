#!/usr/bin/env bash
# Icarus-only V60 unit runner (local substitute for run_v60_verilator.sh, whose
# verilator-safe/verilator-sim-safe wrappers are not present on this machine).
# Same TB list, same PASS markers.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
PKG="rtl/s32_pkg.sv"
CPU="rtl/cpu/v60/s32_v60.sv rtl/cpu/v60/s32_v60_bus.sv"
declare -A TB=(
  [tb_v60_smoke]="SMOKE PASS"
  [tb_v60_directed]="DIRECTED PASS"
  [tb_v60_fetch]="FETCH PERF PASS"
  [tb_v60_smc]="V60 SMC PASS"
  [tb_v60_long_ea]="LONG EA PASS"
  [tb_v60_bus_lanes]="V60 BUS LANES PASS"
  [tb_v60_divx]="DIVX PASS"
  [tb_v60_divxmem]="V60 DIVXMEM PASS"
  [tb_v60_flags]="V60 FLAGS PASS"
  [tb_v60_ga2_bossbar]="V60 GA2 BOSSBAR PASS"
  [tb_v60_incdecmem]="V60 INCDECMEM PASS"
  [tb_v60_rotate]="V60 ROTATE PASS"
  [tb_v60_shaov]="V60 SHAOV PASS"
  [tb_v60_xch]="V60 XCH PASS"
  [tb_v60_audit]="AUDIT PASS"
  [tb_v60_bits]="BITS PASS"
  [tb_v60_decimal]="DECIMAL PASS"
  [tb_v60_search]="V60 SEARCH PASS"
  [tb_v60_cmpc]="V60 CMPC PASS"
  [tb_v60_movcd]="V60 MOVCD PASS"
  [tb_v60_schd]="V60 SCHD PASS"
  [tb_v60_strfs]="V60 STRFS PASS"
  [tb_v60_fp]="V60 FP PASS"
  [tb_v60_fpdecode]="V60 FPDECODE PASS"
  [tb_v60_spidman_xchh]="SPIDMAN XCH.H PASS"
  [tb_v60_spidman_window]="SPIDMAN WINDOW PASS"
  [tb_v60_spidman_gate]="SPIDMAN GATE PASS"
  [tb_v60_ea_overlap_disp]="V60 EA_OVERLAP DISP PASS"
)
ORDER="tb_v60_smoke tb_v60_directed tb_v60_fetch tb_v60_smc tb_v60_long_ea tb_v60_bus_lanes tb_v60_divx tb_v60_divxmem tb_v60_flags tb_v60_ga2_bossbar tb_v60_incdecmem tb_v60_rotate tb_v60_shaov tb_v60_xch tb_v60_audit tb_v60_bits tb_v60_decimal tb_v60_search tb_v60_cmpc tb_v60_movcd tb_v60_schd tb_v60_strfs tb_v60_fp tb_v60_fpdecode tb_v60_spidman_xchh tb_v60_spidman_window tb_v60_spidman_gate tb_v60_ea_overlap_disp"
WORK="${WORK:-/tmp/s32_v60_ut}"
mkdir -p "$WORK"
pass=0; fail=0; failed=""
for tb in ${TBLIST:-$ORDER}; do
  src="verif/v60/${tb}.sv"
  [ -f "$src" ] || { echo "SKIP  $tb (no file)"; continue; }
  if ! iverilog -g2012 -Wno-timescale -DSIMULATION -o "$WORK/$tb.vvp" -s "$tb" $PKG $CPU "$src" > "$WORK/$tb.log" 2>&1; then
    echo "BUILDFAIL $tb  (see $WORK/$tb.log)"; fail=$((fail+1)); failed="$failed $tb"; continue
  fi
  out="$(cd "$WORK" && timeout 600 vvp "$tb.vvp" 2>&1)"
  if echo "$out" | grep -qF "${TB[$tb]}"; then
    extra="$(echo "$out" | grep -E 'FETCH PERF:|LANES|cycles=' | head -1)"
    echo "PASS  $tb   ${extra}"; pass=$((pass+1))
  else
    echo "FAIL  $tb   (expected '${TB[$tb]}')"
    echo "$out" | tail -4 | sed 's/^/        /'
    fail=$((fail+1)); failed="$failed $tb"
  fi
done
if [ -f "$WORK/tb_v60_smc.vvp" ]; then
  if (cd "$WORK" && timeout 600 vvp tb_v60_smc.vvp +CEDIV=3 2>&1) | grep -qF "V60 SMC PASS"; then
    echo "PASS  tb_v60_smc(ce=/3)"; pass=$((pass+1))
  else
    echo "FAIL  tb_v60_smc(ce=/3)"; fail=$((fail+1)); failed="$failed tb_v60_smc(ce/3)"
  fi
fi
echo "======================================================"
echo "V60 ICARUS UNIT: $pass passed, $fail failed${failed:+ -> FAILED:$failed}"
[ "$fail" -eq 0 ] && echo "V60 ICARUS UNIT: ALL PASS"
exit $fail
