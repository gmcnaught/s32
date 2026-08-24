#!/usr/bin/env bash
# Full-core Icarus gate: the subset of verif/run_regression.sh that needs
# nothing but iverilog and this checkout.  Used by CI and by anyone without
# ModelSim or the verilator-safe wrappers.
#
# Deliberately NOT included:
#   tb_core_v25int  - does not build against this tree (connects .clk_v25,
#                     which is an internal wire, not a port of s32_core).
#                     Pre-existing; fails identically on a pristine checkout.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

CORE_SRC="rtl/s32_pkg.sv rtl/cpu/v60/s32_v60.sv rtl/cpu/v60/s32_v60_bus.sv
     rtl/video/*.sv rtl/crt_adjust.sv
     rtl/audio/s32_rf5c68.sv rtl/audio/s32_multipcm.sv
     rtl/audio/s32_audio_mix.sv rtl/audio/s32_soundsys.sv
     rtl/io/s32_io.sv rtl/prot/s32_prot.sv
     verif/common/jt12_stub.v rtl/s32_core.sv"

S32_ONLY="-DS32_SYSTEM32_ONLY -DS32_PROFILE_STANDARD -DS32_PCB_TIMING"
# The cadence bench elaborates s32_core's production preprocessing choice, so
# it needs the full universal define set rather than the profile flags above.
CADENCE_DEFS="-DS32_SYSTEM32_ONLY -DS32_PROFILE_STANDARD -DS32_UNIVERSAL -DS32_V25_HW -DS32_GAME_ONLY_STD -DS32_PCB_TIMING"

WORK="${WORK:-/tmp/s32_core_gate}"
mkdir -p "$WORK"
pass=0; fail=0; failed=""

# run <name> <defines> <sources> <top-or-empty> <marker>
#
# vvp output is captured to a file and grepped afterwards rather than piped
# straight into `grep -q`: grep exits on the first match, and with pipefail set
# the SIGPIPE that kills a still-writing vvp would be reported as a failure of
# a run that actually passed.
run() {
  local name=$1 defs=$2 srcs=$3 top=$4 marker=$5
  local topflag=""
  [ -n "$top" ] && topflag="-s $top"
  rm -f "$WORK/$name"
  if ! eval iverilog -g2012 -DSIMULATION "$defs" $topflag -o "$WORK/$name" $srcs \
        > "$WORK/$name.build.log" 2>&1; then
    echo "BUILDFAIL $name  (see $WORK/$name.build.log)"
    grep -v Anachronistic "$WORK/$name.build.log" | head -5
    fail=$((fail+1)); failed="$failed $name"; return
  fi
  timeout 1800 vvp "$WORK/$name" > "$WORK/$name.run.log" 2>&1
  if grep -qF "$marker" "$WORK/$name.run.log"; then
    echo "PASS  $name"; pass=$((pass+1))
  else
    echo "FAIL  $name   (expected '$marker')"
    tail -4 "$WORK/$name.run.log" | sed 's/^/        /'
    fail=$((fail+1)); failed="$failed $name"
  fi
}

run lint_universal "" "$CORE_SRC verif/common/tb_core_lint.sv"    "" "CORE UNIVERSAL LINT PASS"
run lint_s32 "$S32_ONLY" "$CORE_SRC verif/common/tb_core_lint.sv" "" "CORE STANDARD PROFILE LINT PASS"
run boot_universal "" "$CORE_SRC verif/common/tb_core_boot.sv"    "" "CORE BOOT PASS"
run boot_s32 "$S32_ONLY" "$CORE_SRC verif/common/tb_core_boot.sv" "" "CORE BOOT PASS"
run soak "" "$CORE_SRC verif/common/tb_core_soak.sv"              "" "CORE SOAK PASS"
run ga2path "" "$CORE_SRC verif/common/tb_core_ga2path.sv"        "" "GA2 PATH PASS"

# The V60 execution/bus cadence.  This bench already proves the invariant
# s32.sdc's two-cycle V60 register-to-register exception rests on -- the
# execution enable never fires on adjacent clk_sys edges -- over a 65536-edge
# window.  It was in verif/run_regression.sh but in none of the runners, so
# nothing was checking it outside a full ModelSim regression.
run exec_cadence "$CADENCE_DEFS" \
    "rtl/s32_pkg.sv rtl/s32_core.sv verif/common/tb_v60_exec_cadence.sv" \
    tb_v60_exec_cadence "V60 EXEC CADENCE PASS"
run exec_retire "" \
    "rtl/cpu/v60/s32_v60.sv rtl/cpu/v60/s32_v60_bus.sv verif/common/tb_v60_exec_retire.sv" \
    tb_v60_exec_retire "V60 EXEC RETIRE PASS"

echo "======================================================"
echo "CORE ICARUS GATE: $pass passed, $fail failed${failed:+ -> FAILED:$failed}"
[ "$fail" -eq 0 ] && echo "CORE ICARUS GATE: ALL PASS"
exit $fail
