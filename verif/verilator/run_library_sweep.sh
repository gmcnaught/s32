#!/usr/bin/env bash
# Boot every System 32 set through the full-core romboot harness -- each with
# its OWN board descriptor, read from the image's desc.txt -- and emit one row
# per set.  This is the baseline artifact for per-game triage: it says which
# sets boot, which fault, which render nothing, and whether the SDRAM/DDR paths
# meet their per-scanline deadlines.
#
#   ./verif/verilator/run_library_sweep.sh                 # all 17 sets
#   SETS="radm radr slipstrm" ./verif/verilator/run_library_sweep.sh
#   FRAMES=420 DUMPAT=200 ./verif/verilator/run_library_sweep.sh
#   REPARSE=1 ./verif/verilator/run_library_sweep.sh        # re-tabulate, no sim
#
# Sets run STRICTLY ONE AT A TIME.  Do not parallelise this: the global limit
# is two Verilator processes across all sessions, and the first iteration also
# pays for the build.
#
# This is a smoke sweep, not a correctness gate.  A row marked OK means the set
# booted, took no unexpected exception, kept its PC moving and put pixels on
# the screen.  It says nothing about whether those pixels are RIGHT -- that
# needs the captured frame looked at, which is why every run keeps its PPM.
#
# Column meanings, because two of them are easy to misread:
#   FRAMEPX  non-black pixels in the CAPTURED FRAME, counted from the PPM.
#            This is the authoritative "is anything on screen" number and what
#            the BLACK verdict keys on.  Ground truth, not a counter.
#   NB/F     non-black pixels in the last frame, derived as the delta of the
#            harness's nb_pix between the final two frame lines.
#   NB_CUM   nb_pix itself: a RUNNING TOTAL over the whole run, never reset,
#            despite its comment in the harness saying "per-frame".  Shown only
#            because it appears in logs and is easy to misread -- a set whose
#            screen has gone black still carries whatever it accumulated during
#            boot, so a nonzero NB_CUM proves nothing about the current frame.
#   STUCK    consecutive-identical-PC count at the moment the last frame line
#            printed.  A small value is normal -- a multi-cycle instruction
#            holds the PC.  The harness's own freeze threshold is 500,000, at
#            which it prints [FROZEN]; that marker, not this number, is what
#            FROZEN below keys on.
#   PCUNIQ   distinct PC values across all frame lines.  A very low count over
#            many frames is the scross-style spin-loop signature.  SPIN? is a
#            HEURISTIC flag, not a finding -- confirm it before quoting it.
set -uo pipefail
cd "$(dirname "$0")/../.."

FRAMES="${FRAMES:-150}"
DUMPAT="${DUMPAT:-80}"
DUMPN="${DUMPN:-1}"
REPARSE="${REPARSE:-0}"
OUT="${OUT:-scratch/library-sweep}"
# Every System 32 family with a shipped MRA.  Multi 32 left this repo in
# a7e280f; as1 is out of scope (laserdisc); sonicp/kokoroj have no launcher.
SETS="${SETS:-alien3 arabfgt arescue brival darkedge dbzvrvs f1en f1lap ga2 holo jpark radm radr slipstrm sonic spidman svf}"

mkdir -p "$OUT"
SUMMARY="$OUT/summary.md"
{
  echo "| Set | Descriptor | Frames | Final PC | PCUNIQ | exc | sc | STUCK | FRAMEPX | NB/F | NB_CUM | SPRPX | tile_ovr | fb_undr | Verdict |"
  echo "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"
} > "$SUMMARY"

ROW='%-9s %-9s %-6s %-9s %-6s %-4s %-5s %-6s %-8s %-8s %-10s %-10s %-8s %-7s %s\n'
# shellcheck disable=SC2059
printf "$ROW" SET DESC FRAMES PC PCUNIQ EXC SC STUCK FRAMEPX NB/F NB_CUM SPRPX TILE_OVR FB_UNDR VERDICT

for g in $SETS; do
  log="$OUT/$g.log"

  if [[ "$REPARSE" != "1" ]]; then
    if [[ ! -f "roms/sim/$g/desc.txt" ]]; then
      printf '%-9s %-9s %s\n' "$g" "-" "NO-IMAGE (build it with tools/make_sim_images.py)"
      echo "| \`$g\` | - | - | - | - | - | - | - | - | - | - | - | - | - | NO-IMAGE |" >> "$SUMMARY"
      continue
    fi
    rm -rf "$OUT/$g"; mkdir -p "$OUT/$g"
    rm -f scratch/vromboot_out/dump*.ppm
    nice -n 19 ./verif/verilator/run_romboot.sh "$g" "$FRAMES" \
        +DUMPAT="$DUMPAT" +DUMPN="$DUMPN" +OVLOG=1 > "$log" 2>&1
    rc=$?
    # Keep the captured frames beside the log; the next set would overwrite them.
    for p in scratch/vromboot_out/dump*.ppm; do
      [[ -e "$p" ]] && mv "$p" "$OUT/$g/"
    done
  else
    [[ -f "$log" ]] || { printf '%-9s %s\n' "$g" "NO-LOG"; continue; }
    rc=0
  fi

  # Ground truth for "is anything on screen": count the captured frame itself.
  # The harness's nb_pix counter cannot answer this -- see the header note.
  ppm=""
  for p in "$OUT/$g"/dump*.ppm; do [[ -e "$p" ]] && ppm="$p" && break; done
  if [[ -n "$ppm" ]]; then
    framepx=$(awk 'NF==3 && !($1=="0" && $2=="0" && $3=="0") {n++} END {print n+0}' "$ppm")
  else
    framepx="-"
  fi

  read -r desc frames pc pcuniq exc sc stuck nbdelta nb sprpx tovr fundr verdict < <(
    awk -v rc="$rc" '
      function field(s, key,   n, a, i) {
        n = split(s, a, /[ \t]+/)
        for (i = 1; i <= n; i++)
          if (a[i] ~ "^" key "=") { sub("^" key "=", "", a[i]); return a[i] }
        return "?"
      }
      /^\[desc\] .* -> /   { d = $(NF-3) $(NF-2) $(NF-1) $NF }
      /^\[FROZEN\]/        { frozen = 1 }
      /ROMBOOT DONE/       { done = 1 }
      /^\[ov\] /           { ovline = $0 }
      /^frame [0-9]+:/     { prev = last; last = $0; seen_pc[field($0, "pc")] = 1; nframe++ }
      END {
        if (last == "") {
          print (d ? d : "-"), "-","-","-","-","-","-","-","-","-","-","-",
                (rc == 0 ? "NO-OUTPUT" : "RUN-FAILED"); exit
        }
        fr = last; sub(/^frame /, "", fr); sub(/:.*/, "", fr)
        pc    = field(last, "pc");  exc   = field(last, "exc")
        sc    = field(last, "sc");  stuck = field(last, "stuck")
        nb    = field(last, "nb");  sprpx = field(last, "sprpx")
        # Per-frame non-black pixels: nb_pix is a running total, so the last
        # frame is worth exactly the delta over the frame before it.
        nbd = (prev == "") ? "?" : nb - field(prev, "nb")
        uniq = 0; for (k in seen_pc) uniq++
        tovr = "?"; fundr = "?"
        if (ovline != "") {
          # [ov] f=N tile_overrun sticky=b cnt=N  fb_underrun sticky=b cnt=N
          n = split(ovline, a, /[ \t]+/); s = 0
          for (i = 1; i <= n; i++)
            if (a[i] ~ /^cnt=/) { sub(/^cnt=/, "", a[i]); if (s++ == 0) tovr = a[i]; else fundr = a[i] }
        }
        v = "OK"
        if (rc != 0 || !done)                       v = "RUN-FAILED"
        else if (frozen)                            v = "FROZEN"
        else if (exc + 0 != 0)                      v = "EXCEPTION"
        else if (tovr != "?"  && tovr  + 0 != 0)    v = "TILE-OVERRUN"
        else if (fundr != "?" && fundr + 0 != 0)    v = "FB-UNDERRUN"
        else if (uniq <= 2 && nframe >= 20)         v = "SPIN?"
        print (d ? d : "-"), fr, pc, uniq, exc, sc, stuck, nbd, nb, sprpx, tovr, fundr, v
      }' "$log"
  )

  # BLACK is decided here, not in awk: the captured frame outranks any counter,
  # and it only demotes an otherwise-OK row -- a set that faulted or froze keeps
  # the more specific verdict.
  if [[ "$verdict" == "OK" ]]; then
    if [[ "$framepx" != "-" && "$framepx" -eq 0 ]]; then
      verdict="BLACK"
    elif [[ "$framepx" == "-" && "$nbdelta" != "?" && "$nbdelta" -eq 0 ]]; then
      verdict="BLACK"
    fi
  fi

  # shellcheck disable=SC2059
  printf "$ROW" "$g" "$desc" "$frames" "$pc" "$pcuniq" "$exc" "$sc" "$stuck" \
    "$framepx" "$nbdelta" "$nb" "$sprpx" "$tovr" "$fundr" "$verdict"
  echo "| \`$g\` | \`$desc\` | $frames | $pc | $pcuniq | $exc | $sc | $stuck | $framepx | $nbdelta | $nb | $sprpx | $tovr | $fundr | $verdict |" >> "$SUMMARY"
done

echo
echo "logs + captured frames: $OUT/"
echo "markdown rows:          $SUMMARY"
