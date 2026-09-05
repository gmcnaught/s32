#!/usr/bin/env bash
# The two V60 cores on one generated program, N seeds, compared after every
# instruction (tb_v60_lockstep.sv).  Prints every divergence class seen --
# opcode and field -- with the number of seeds it appeared in, then the known
# list check: a class is expected if verif/v60x/lockstep_known.txt names it,
# and the run fails on any class that file does not.
#
#   bash verif/v60x/run_lockstep.sh [N]        default 20
#
# Icarus only: the shipping core's own Icarus runner is the CI mirror, and this
# bench carries both cores.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/../.."
N="${1:-20}"
WORK="${WORK:-$(mktemp -d)}"
mkdir -p "$WORK"
export PYTHONDONTWRITEBYTECODE=1

SRC="rtl/s32_pkg.sv rtl/cpu/v60/s32_v60.sv rtl/cpu/v60/s32_v60_bus.sv rtl/cpu/v60/s32_v60_timebase.sv \
     rtl/cpu/v60x/v60_bus_pkg.sv rtl/cpu/v60x/v60_biu.sv \
     rtl/cpu/v60x/v60_am_pkg.sv rtl/cpu/v60x/v60_am_decode.sv \
     rtl/cpu/v60x/v60_dxu.sv rtl/cpu/v60x/v60_dmux.sv rtl/cpu/v60x/v60_ea.sv \
     rtl/cpu/v60x/v60_bus_arb.sv rtl/cpu/v60x/v60_pfu.sv \
     rtl/cpu/v60x/v60_psw_pkg.sv rtl/cpu/v60x/v60_regfile.sv \
     rtl/cpu/v60x/v60_alu_pkg.sv rtl/cpu/v60x/v60_alu.sv rtl/cpu/v60x/v60_fpu.sv \
     rtl/cpu/v60x/v60_muldiv.sv \
     rtl/cpu/v60x/v60_fmt_pkg.sv rtl/cpu/v60x/v60_op_pkg.sv \
     rtl/cpu/v60x/v60_fmt_decode.sv rtl/cpu/v60x/v60_idu.sv \
     rtl/cpu/v60x/v60_exc.sv rtl/cpu/v60x/v60_seq.sv rtl/cpu/v60x/v60_top.sv \
     verif/v60x/tb_v60_lockstep.sv"

if ! iverilog -g2012 -s tb_v60_lockstep -o "$WORK/lockstep" $SRC > "$WORK/build.log" 2>&1; then
  echo "BUILDFAIL tb_v60_lockstep"; grep -v Anachronistic "$WORK/build.log" | head -5; exit 1
fi

: > "$WORK/all.log"
stops=0
for s in $(seq 1 "$N"); do
  python3 verif/v60x/gen_lockstep_program.py "$s" "$WORK/p$s" > /dev/null
  vvp "$WORK/lockstep" +hex="$WORK/p$s.hex" > "$WORK/r$s.log" 2>&1
  if ! grep -q "V60 LOCKSTEP DONE" "$WORK/r$s.log"; then
    echo "SEED $s: bench did not finish"; tail -3 "$WORK/r$s.log"; exit 1
  fi
  grep -q '^STOP' "$WORK/r$s.log" && stops=$((stops+1))
  sed "s/^/seed=$s /" "$WORK/r$s.log" >> "$WORK/all.log"
done

# One line per (opcode, field) class, with the seeds it appeared in.
grep ' DIVERGE ' "$WORK/all.log" | sed -E 's/^seed=([0-9]+) .* op=([0-9a-f]+) field=([A-Za-z0-9.]+).*/\2 \3 \1/' \
  | sort -u | awk '{k=$1" "$2; n[k]++} END {for (k in n) print k, n[k]}' | sort > "$WORK/classes.txt"

fail=0
while read -r op field seeds; do
  mnem=$(python3 - "$op" <<'EOF'
import sys, importlib.util, io, contextlib
spec = importlib.util.spec_from_file_location('t', 'tools/v60x/insn_table.py'); t = importlib.util.module_from_spec(spec)
with contextlib.redirect_stdout(io.StringIO()): spec.loader.exec_module(t)
op = int(sys.argv[1], 16)
names = sorted({m for m, o, so, f, p in t.TABLE for b in t.expand(o) if b == op})
print('/'.join(names) if names else '?')
EOF
)
  if grep -q -E "^$op[[:space:]]+$field([[:space:]]|$)" verif/v60x/lockstep_known.txt 2>/dev/null; then
    echo "KNOWN    op=$op $mnem field=$field seeds=$seeds"
  else
    echo "NEW      op=$op $mnem field=$field seeds=$seeds"; fail=$((fail+1))
  fi
done < "$WORK/classes.txt"

mem=$(grep -c ' MEMDIVERGE ' "$WORK/all.log")
echo "======================================================"
echo "V60 LOCKSTEP: $N seeds, $(wc -l < "$WORK/classes.txt") divergence classes, $fail new, $stops stops, $mem memory bytes differ"
grep ' LOCKSTEP instructions' "$WORK/all.log" | awk '{for(i=1;i<=NF;i++) if($i ~ /^instructions=/) {split($i,a,"="); s+=a[2]}} END {print "instructions compared:", s}'
[ "$fail" -eq 0 ] && echo "V60 LOCKSTEP: NO NEW DIVERGENCE"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
