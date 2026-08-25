#!/usr/bin/env bash
# Stacked-branch helper for the V60 cycle-accuracy work.
#
# The stack follows the remediation sequence in the "V60 Cycle-Accuracy Audit".
# Each branch is based on the one above it in this list, and each PR targets
# its parent, so a reviewer sees only that stage's diff.
#
#   main
#    +- v60/00-restore-verif        verification tree + build tooling back on main
#       +- v60/01-ci-icarus-gate    Icarus runners + GitHub Actions gate
#          +- v60/02-defect-fixes   audit S05: the eight RTL defects
#             +- v60/03-handshake-sva      audit S07.2: SVA for the four
#                                          bus-handshake invariants.  MUST land
#                                          before any cadence change -- today
#                                          every cadence experiment fails
#                                          silently.
#                +- v60/03b-quartus-sdc-ci Quartus CI for the SDC carve-out
#                                          stage 03 added.  Not an audit stage:
#                                          no simulator can check a timing
#                                          constraint, so this is the only way
#                                          that change is verifiable at all.
#                +- v60/04-clock-tree      audit S07.3: BIU onto clk_ram with a
#                                          six-phase T-state counter.  A
#                                          prerequisite, not a step: clk_sys /
#                                          f_V60 = 2.9996, so a T-state machine
#                                          written on clk_sys cannot express the
#                                          databook's falling-edge sampling
#                                          points at all.
#                   +- v60/05-tstate-biu   audit S07.4: real TI/T1/T2/T3/T4/TW/TH
#                                          machine, BMODE, READY, I/O recovery,
#                                          hold, and the pin-level status lines.
#                                          Fixes the continuation-cycle count.
#                      +- v60/06-retire-fast-ifetch
#                                          audit S07.5: fetch visible on the
#                                          modelled bus, 16-byte FIFO PFU at
#                                          lowest priority, plus the prefetch
#                                          address-range guard.
#                         +- v60/07-exec-timing
#                                          audit S07.6: drop the clk_sys/2
#                                          execution overclock.  This one is a
#                                          research project, not documented work.
#
# Regression gate for anything from 05 down: the Golden Axe II / Spider-Man /
# Rad Rally black-screen cases.  Stages 05-06 change what the bus costs, which
# shifts the execute:bus ratio implicitly -- expect to re-tune.
#
# Usage:
#   tools/stack.sh list                 show the stack and what is unpushed
#   tools/stack.sh init                 record each branch's current base
#   tools/stack.sh restack              rebase every branch onto its parent
#   tools/stack.sh push                 force-with-lease push the whole stack
#   tools/stack.sh next <branch>        start the next stage off the current tip
#
# Restacking needs to know where each branch was cut from, because `git rebase
# <parent> <branch>` after the parent has been amended replays the parent's OLD
# commit onto its new one and conflicts.  The cut point is recorded per branch
# in git config as branch.<name>.stackBase and used as the `--onto` cut:
#
#   git rebase --onto <parent> <recorded base> <branch>
#
# `next` records it automatically; `init` backfills it for branches created by
# hand.  Losing the record is recoverable -- restack falls back to the parent's
# reflog and says so -- but it is a guess, so re-run `init` after any manual
# branch surgery.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

STACK=(
  main
  v60/00-restore-verif
  v60/01-ci-icarus-gate
  v60/02-defect-fixes
  v60/03-handshake-sva
  v60/03b-quartus-sdc-ci
  v60/04-clock-tree
  v60/05-tstate-biu
  v60/06-retire-fast-ifetch
  v60/07-exec-timing
)

exists() { git show-ref --verify --quiet "refs/heads/$1"; }

cmd_list() {
  local parent=""
  for b in "${STACK[@]}"; do
    if ! exists "$b"; then printf '  %-28s (not created)\n' "$b"; continue; fi
    local ahead="" upstream_state="untracked"
    if [ -n "$parent" ]; then ahead=$(git rev-list --count "$parent..$b"); fi
    if git rev-parse --verify --quiet "origin/$b" >/dev/null; then
      local d
      d=$(git rev-list --left-right --count "origin/$b...$b" 2>/dev/null)
      upstream_state="origin: -${d%%	*} +${d##*	}"
    fi
    printf '  %-28s %-16s %s\n' "$b" "${ahead:+$ahead commit(s)}" "$upstream_state"
    parent="$b"
  done
}

base_of() {   # recorded cut point for $1, or a reflog guess
  local b=$1 parent=$2 rec
  rec=$(git config --get "branch.$b.stackBase" || true)
  if [ -n "$rec" ] && git rev-parse --verify --quiet "$rec^{commit}" >/dev/null; then
    echo "$rec"; return 0
  fi
  # No record.  The parent's previous reflog position is the usual cut point
  # after an amend or a rebase; anything else needs `init`.
  rec=$(git rev-parse --verify --quiet "$parent@{1}" || true)
  if [ -n "$rec" ]; then
    echo "!! $b has no recorded base; guessing $parent@{1} ($rec)" >&2
    echo "!!   if that is wrong: git config branch.$b.stackBase <sha> && retry" >&2
    echo "$rec"; return 0
  fi
  echo "!! $b has no recorded base and $parent has no reflog -- run: tools/stack.sh init" >&2
  return 1
}

cmd_init() {
  local parent=""
  for b in "${STACK[@]}"; do
    if ! exists "$b"; then parent="$b"; continue; fi
    if [ -n "$parent" ] && [ "$b" != "main" ]; then
      local mb; mb=$(git merge-base "$parent" "$b")
      git config "branch.$b.stackBase" "$mb"
      printf '  %-28s base %s\n' "$b" "$(git rev-parse --short "$mb")"
    fi
    parent="$b"
  done
  echo "bases recorded"
}

cmd_restack() {
  local parent=""
  for b in "${STACK[@]}"; do
    if ! exists "$b"; then parent="$b"; continue; fi
    if [ -n "$parent" ] && [ "$b" != "main" ]; then
      local base
      base=$(base_of "$b" "$parent") || exit 1
      if [ "$base" = "$(git rev-parse "$parent")" ]; then
        echo ">> $b already on $parent"
      else
        echo ">> rebasing $b onto $parent (cut at $(git rev-parse --short "$base"))"
        git rebase --onto "$parent" "$base" "$b" || {
          echo "!! rebase of $b stopped -- resolve, then: git rebase --continue"
          echo "!! afterwards: git config branch.$b.stackBase $(git rev-parse "$parent")"
          exit 1
        }
      fi
      git config "branch.$b.stackBase" "$(git rev-parse "$parent")"
    fi
    parent="$b"
  done
  echo "restack complete"
}

cmd_push() {
  for b in "${STACK[@]}"; do
    [ "$b" = "main" ] && continue
    exists "$b" || continue
    git push --force-with-lease -u origin "$b"
  done
}

cmd_next() {
  local new=$1 tip=""
  for b in "${STACK[@]}"; do exists "$b" && tip="$b"; done
  echo ">> branching $new off $tip"
  git checkout -b "$new" "$tip" || return 1
  git config "branch.$new.stackBase" "$(git rev-parse "$tip")"
}

case "${1:-list}" in
  list)    cmd_list ;;
  init)    cmd_init ;;
  restack) cmd_restack ;;
  push)    cmd_push ;;
  next)    cmd_next "${2:?usage: tools/stack.sh next <branch>}" ;;
  *) echo "usage: tools/stack.sh {list|init|restack|push|next <branch>}"; exit 2 ;;
esac
