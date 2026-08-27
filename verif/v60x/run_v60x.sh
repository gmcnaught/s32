#!/usr/bin/env bash
# Clean-room V60 benches, under BOTH simulators.
#
# Both, every time, on purpose.  A bench in this project passed under Icarus
# and failed under the other with 254 errors because of a blocking/non-blocking
# race the two schedule differently, and Icarus happened to resolve it the way
# the author intended.  One simulator is an opinion.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
export PATH="/opt/homebrew/bin:$PATH"

RTL="rtl/cpu/v60x/v60_bus_pkg.sv rtl/cpu/v60x/v60_biu.sv \
     rtl/cpu/v60x/v60_am_pkg.sv rtl/cpu/v60x/v60_am_decode.sv \
     rtl/cpu/v60x/v60_dxu.sv rtl/cpu/v60x/v60_ea.sv \
     rtl/cpu/v60x/v60_bus_arb.sv rtl/cpu/v60x/v60_pfu.sv \
     rtl/cpu/v60x/v60_fmt_pkg.sv rtl/cpu/v60x/v60_op_pkg.sv \
     rtl/cpu/v60x/v60_fmt_decode.sv rtl/cpu/v60x/v60_idu.sv"
WORK="${WORK:-/tmp/v60x}"
mkdir -p "$WORK"
pass=0; fail=0

# The opcode table is data (tools/v60x/insn_table.py) and v60_op_pkg.sv is
# generated from it.  A table edited without regenerating is a table that says
# one thing and an RTL that does another, so check before running anything.
if ! python3 tools/v60x/insn_table.py > "$WORK/table.log" 2>&1; then
  echo "FAIL  the instruction table does not validate"; sed 's/^/        /' "$WORK/table.log"
  exit 1
fi
( cd tools/v60x && python3 gen_op_pkg.py "$WORK/v60_op_pkg.sv" >/dev/null )
if ! diff -q "$WORK/v60_op_pkg.sv" rtl/cpu/v60x/v60_op_pkg.sv > /dev/null; then
  echo "FAIL  rtl/cpu/v60x/v60_op_pkg.sv is stale -- regenerate it:"
  echo "        (cd tools/v60x && python3 gen_op_pkg.py ../../rtl/cpu/v60x/v60_op_pkg.sv)"
  exit 1
fi

run() {
  local tb=$1 marker=$2 src="$RTL verif/v60x/$1.sv"

  if ! iverilog -g2012 -s "$tb" -o "$WORK/$tb.icarus" $src > "$WORK/$tb.ibuild" 2>&1; then
    echo "BUILDFAIL $tb (icarus)"; grep -v Anachronistic "$WORK/$tb.ibuild" | head -3
    fail=$((fail+1)); return
  fi
  vvp "$WORK/$tb.icarus" > "$WORK/$tb.irun" 2>&1
  if grep -qF "$marker" "$WORK/$tb.irun"; then echo "PASS  $tb (icarus)"; pass=$((pass+1))
  else echo "FAIL  $tb (icarus)"; tail -4 "$WORK/$tb.irun" | sed 's/^/        /'; fail=$((fail+1)); fi

  rm -rf "$WORK/$tb.vl"
  if ! verilator --binary --timing -Wno-fatal -Wno-lint --top-module "$tb" \
        -o "$tb.bin" -Mdir "$WORK/$tb.vl" $src > "$WORK/$tb.vbuild" 2>&1; then
    echo "BUILDFAIL $tb (verilator)"; grep "%Error" "$WORK/$tb.vbuild" | head -3
    fail=$((fail+1)); return
  fi
  "$WORK/$tb.vl/$tb.bin" > "$WORK/$tb.vrun" 2>&1
  if grep -qF "$marker" "$WORK/$tb.vrun"; then echo "PASS  $tb (verilator)"; pass=$((pass+1))
  else echo "FAIL  $tb (verilator)"; tail -4 "$WORK/$tb.vrun" | sed 's/^/        /'; fail=$((fail+1)); fi
}

run tb_v60_biu_tstates "V60 BIU T-STATE PASS"
run tb_v60_biu_pins    "V60 BIU PINS PASS"
run tb_v60_am_decode   "V60 AM DECODE PASS"
run tb_v60_dxu         "V60 DXU PASS"
run tb_v60_ea          "V60 EA PASS"
run tb_v60_pfu         "V60 PFU PASS"
run tb_v60_fmt_decode  "V60 FMT PASS"
run tb_v60_idu         "V60 IDU PASS"

echo "======================================================"
echo "V60X: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "V60X: ALL PASS"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
