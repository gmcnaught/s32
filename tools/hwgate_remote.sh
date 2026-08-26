#!/bin/sh
# Runs ON the MiSTer.  Loads each of the four gate titles in turn and takes two
# screenshots ~45 s apart.
#
# Two shots, always.  Under a WORKING build Dark Edge's first shot is black --
# it is still mid fade-in at 30 s -- so a single sample cannot tell a fade from
# a failure.  And the sizes printed here are a convenience, not the verdict:
# a frozen flat frame compresses to ~1464 bytes while a legitimate dark attract
# frame is ~12 KB of real content, so size alone has already produced a wrong
# call once.  tools/hwgate_score.py is what decides.
set -u
STAMP="${1:-hwgate}"
SHOTS=/media/fat/screenshots

for t in "ga2|Golden Axe The Revenge of Death Adder (World, Rev B).mra" \
         "spidman|Spider-Man The Videogame (World).mra" \
         "radr|Rad Rally (World).mra" \
         "darkedge|Dark Edge (World).mra"; do
  core=${t%%|*}; mra=${t#*|}
  echo "--- $core"
  echo "load_core /media/fat/_Arcade/$mra" > /dev/MiSTer_cmd
  sleep 30
  echo screenshot > /dev/MiSTer_cmd
  sleep 3
  sleep 45
  echo screenshot > /dev/MiSTer_cmd
  sleep 3
  echo "    CORENAME=$(cat /tmp/CORENAME 2>/dev/null)"
  ls -t "$SHOTS/$core"/*.png 2>/dev/null | sed -n '1,2p' | while read f; do
    echo "    SHOT $(stat -c %s "$f") $f"
  done
done
echo "GATE-DONE $STAMP"
