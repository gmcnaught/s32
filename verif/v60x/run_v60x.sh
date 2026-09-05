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

# The generated package is checked against the table below by regenerating it.
# That check is defeated by Python's bytecode cache: an edit to
# tools/v60x/insn_table.py that lands in the same second as the last one and
# leaves the file the same length -- which is what reverting a one-character
# mutation does -- keeps the cached .pyc valid, so the generator and the check
# both read the OLD table and agree with each other about a stale file.  Found
# exactly that way.
export PYTHONDONTWRITEBYTECODE=1

# Which simulators to run.  Default both, on purpose (see the header).  CI has
# no Verilator, so it sets V60X_SIMS=icarus; a bench that passes there and
# fails locally under Verilator is still a failure.
SIMS="${V60X_SIMS:-icarus verilator}"

RTL="rtl/cpu/v60x/v60_bus_pkg.sv rtl/cpu/v60x/v60_biu.sv \
     rtl/cpu/v60x/v60_am_pkg.sv rtl/cpu/v60x/v60_am_decode.sv \
     rtl/cpu/v60x/v60_dxu.sv rtl/cpu/v60x/v60_dmux.sv \
     rtl/cpu/v60x/v60_ea.sv \
     rtl/cpu/v60x/v60_bus_arb.sv rtl/cpu/v60x/v60_pfu.sv \
     rtl/cpu/v60x/v60_psw_pkg.sv rtl/cpu/v60x/v60_regfile.sv \
     rtl/cpu/v60x/v60_alu_pkg.sv rtl/cpu/v60x/v60_alu.sv rtl/cpu/v60x/v60_fpu.sv \
     rtl/cpu/v60x/v60_muldiv.sv \
     rtl/cpu/v60x/v60_fmt_pkg.sv rtl/cpu/v60x/v60_op_pkg.sv \
     rtl/cpu/v60x/v60_fmt_decode.sv rtl/cpu/v60x/v60_idu.sv \
     rtl/cpu/v60x/v60_exc.sv rtl/cpu/v60x/v60_seq.sv"
WORK="${WORK:-$(mktemp -d)}"
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
  local tb=$1 marker=$2 extra="${3:-}" src="$RTL verif/v60x/$1.sv"

  if [[ " $SIMS " == *" icarus "* ]]; then
    if ! iverilog -g2012 -s "$tb" -o "$WORK/$tb.icarus" $src > "$WORK/$tb.ibuild" 2>&1; then
      echo "BUILDFAIL $tb (icarus)"; grep -v Anachronistic "$WORK/$tb.ibuild" | head -3
      fail=$((fail+1))
    else
      vvp "$WORK/$tb.icarus" $extra > "$WORK/$tb.irun" 2>&1
      if grep -qF "$marker" "$WORK/$tb.irun"; then echo "PASS  $tb (icarus)"; pass=$((pass+1))
      else echo "FAIL  $tb (icarus)"; tail -4 "$WORK/$tb.irun" | sed 's/^/        /'; fail=$((fail+1)); fi
    fi
  fi

  if [[ " $SIMS " == *" verilator "* ]]; then
    rm -rf "$WORK/$tb.vl"
    if ! verilator --binary --timing -Wno-fatal -Wno-lint --top-module "$tb" \
          -o "$tb.bin" -Mdir "$WORK/$tb.vl" $src > "$WORK/$tb.vbuild" 2>&1; then
      echo "BUILDFAIL $tb (verilator)"; grep "%Error" "$WORK/$tb.vbuild" | head -3
      fail=$((fail+1))
    else
      "$WORK/$tb.vl/$tb.bin" $extra > "$WORK/$tb.vrun" 2>&1
      if grep -qF "$marker" "$WORK/$tb.vrun"; then echo "PASS  $tb (verilator)"; pass=$((pass+1))
      else echo "FAIL  $tb (verilator)"; tail -4 "$WORK/$tb.vrun" | sed 's/^/        /'; fail=$((fail+1)); fi
    fi
  fi
}

run tb_v60_biu_tstates "V60 BIU T-STATE PASS"
run tb_v60_biu_pins    "V60 BIU PINS PASS"
run tb_v60_am_decode   "V60 AM DECODE PASS"
run tb_v60_dxu         "V60 DXU PASS"
run tb_v60_ea          "V60 EA PASS"
run tb_v60_dmux       "V60 DMUX PASS"
run tb_v60_pfu         "V60 PFU PASS"
run tb_v60_fmt_decode  "V60 FMT PASS"
run tb_v60_idu         "V60 IDU PASS"
run tb_v60_front       "V60 FRONT PASS"
run tb_v60_psw         "V60 PSW PASS"
run tb_v60_regfile     "V60 REGFILE PASS"
run tb_v60_alu         "V60 ALU PASS"
run tb_v60_muldiv      "V60 MULDIV PASS"
run tb_v60_exc         "V60 EXC PASS"
run tb_v60_seq         "V60 SEQ PASS"

# The co-simulation oracle needs the SHIPPING core beside the clean-room one,
# so it compiles a different file list.  Everything else about it is the same:
# both simulators, one marker.
COSIM_RTL="rtl/s32_pkg.sv \
     rtl/cpu/v60/s32_v60.sv rtl/cpu/v60/s32_v60_bus.sv \
     rtl/cpu/v60/s32_v60_timebase.sv \
     rtl/cpu/v60x/v60_bus_pkg.sv rtl/cpu/v60x/v60_biu.sv \
     rtl/cpu/v60x/v60_am_pkg.sv rtl/cpu/v60x/v60_am_decode.sv \
     rtl/cpu/v60x/v60_bus_arb.sv rtl/cpu/v60x/v60_pfu.sv \
     rtl/cpu/v60x/v60_psw_pkg.sv rtl/cpu/v60x/v60_alu_pkg.sv \
     rtl/cpu/v60x/v60_fmt_pkg.sv rtl/cpu/v60x/v60_op_pkg.sv \
     rtl/cpu/v60x/v60_fmt_decode.sv rtl/cpu/v60x/v60_idu.sv"
RTL="$COSIM_RTL" run tb_v60_cosim "V60 COSIM PASS"

echo "======================================================"
echo "V60X: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "V60X: ALL PASS"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
