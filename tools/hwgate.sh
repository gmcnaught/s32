#!/usr/bin/env bash
# The four-title hardware gate, end to end.
#
#   tools/hwgate.sh <host> <label> [outdir]
#   tools/hwgate.sh 192.168.20.81 seed3-guard
#
# Installs the on-device script, loads Golden Axe II / Spider-Man / Rad Rally /
# Dark Edge in turn, takes two screenshots of each ~45 s apart, pulls them back
# and scores them.
#
# It does NOT flash anything.  Put the bitstream on the device first, and put
# the known-good one back afterwards -- this only measures what is already
# loaded.  Sim green does not predict hardware, so this belongs in the gate for
# an RTL change, not after the merge.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

HOST="${1:?usage: hwgate.sh <host> <label> [outdir]}"
LABEL="${2:?usage: hwgate.sh <host> <label> [outdir]}"
OUT="${3:-_hwgate/$LABEL}"
SSH="ssh -o ConnectTimeout=8 -o StrictHostKeyChecking=no root@$HOST"

echo "== installing the on-device script"
scp -q -o ConnectTimeout=8 tools/hwgate_remote.sh "root@$HOST:/tmp/hwgate_remote.sh"
$SSH "chmod +x /tmp/hwgate_remote.sh"

# ~6 minutes: four titles x (30 s load + 45 s between shots + overhead).
echo "== running the gate on $HOST (about 6 minutes)"
$SSH "/tmp/hwgate_remote.sh '$LABEL'" | tee "/tmp/hwgate_$LABEL.log"
grep -q "GATE-DONE" "/tmp/hwgate_$LABEL.log" || {
  echo "ERROR: the device run did not finish" >&2; exit 1; }

echo
echo "== pulling the screenshots"
mkdir -p "$OUT"
# The two named in the log, per title -- not "the newest two in the directory",
# which would pick up whatever else has been captured since.
for title in ga2 spidman radr darkedge; do
  mkdir -p "$OUT/$title"
  grep -A3 -- "--- $title\$" "/tmp/hwgate_$LABEL.log" \
    | sed -n 's/.*SHOT [0-9]* //p' \
    | while read -r remote; do
        [ -n "$remote" ] || continue
        scp -q -o ConnectTimeout=8 "root@$HOST:$remote" "$OUT/$title/" || true
      done
done

echo
python3 tools/hwgate_score.py "$OUT"
