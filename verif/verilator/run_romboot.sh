#!/usr/bin/env bash
# Full-core MiSTer S32 functional sim under Verilator (fast, no hardware).
# Boots real ROMs through s32_core (HLE protection), renders RGB video, dumps
# frames as PPM.  Requires WSL verilator 5.x.  Run from repo root.
#   ./run_romboot.sh <game> [FRAMES] [extra +plusargs...]
# e.g. ./run_romboot.sh ga2 135 +COINAT=64 +COINLEN=6 +STARTAT=84 +DUMPAT=104 +DUMPN=16
set -u
cd "$(dirname "$0")/../.."
GAME="${1:-ga2}"; FRAMES="${2:-90}"; shift 2 2>/dev/null || shift $# 
MDIR=/tmp/vromboot
WARN="-Wno-fatal -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-UNOPTFLAT -Wno-BLKANDNBLK -Wno-CASEINCOMPLETE -Wno-MULTIDRIVEN -Wno-INITIALDLY -Wno-DECLFILENAME"
# The board descriptor comes from the image's own desc.txt, which
# make_sim_images.py copies verbatim out of the MRA's ioctl index-0 stream.
# It is deliberately NOT hardcoded here: the previous per-game case defaulted to
# B0=20 (has_ppi) for anything unlisted, so most of the 17 sets simulated a
# machine the core does not ship -- missing ADC, phantom 8255, no protection
# selector, wrong sprite bank mask.  Override individual fields on the command
# line (+B0/+B1/+B2/+SBM) when a test needs to vary one.
DESC="$PWD/roms/sim/$GAME/desc.txt"
if [[ ! -f "$DESC" ]]; then
  echo "run_romboot: no descriptor at $DESC" >&2
  echo "  build the image first: python tools/make_sim_images.py <mra> roms/$GAME.zip roms/sim/$GAME" >&2
  exit 1
fi
# -j/--build-jobs capped at 6, matching the Quartus NUM_PARALLEL_PROCESSORS
# limit.  This was -j 0, which forks one compiler per core: 32 on this machine
# at up to ~1 GB each, and two concurrent builds exhaust the 64 GB.
verilator --binary --timing -j 6 --build-jobs 6 --threads 1 $WARN \
  +define+SIMULATION +define+S32_REAL_FB_SIM \
  --top-module tb_core_romboot --Mdir "$MDIR" -o romboot -f scratch/romboot.f 2>&1 | grep -E "%Error" && exit 1
mkdir -p scratch/vromboot_out && cd scratch/vromboot_out
nice -n 19 "$MDIR/romboot" +IMG="$(cd ../.. && pwd)/roms/sim/$GAME" \
  +DESC="$DESC" +FRAMES=$FRAMES "$@"
