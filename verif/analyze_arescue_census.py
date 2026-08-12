"""Validate deterministic Air Rescue dual-PCB first-access censuses.

The MAME scheduler may interleave the two V60s differently around simultaneous
shared-RAM accesses.  This validator therefore compares normalized first-event
tables independently per board and never promotes the diagnostic scheduler_seq
to an acceptance ordering.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


FIRST_FIELDS = (
    "board",
    "device",
    "rw",
    "lanes",
    "pc",
    "address",
    "canonical_address",
    "data",
    "mem_mask_raw",
)

REQUIRED_PEER_DEVICES = {
    "rom_alias",
    "rom",
    "irq",
    "work",
    "io",
    "mixer",
    "palette",
    "sprite_ctrl",
    "sprite_ram",
    "vram",
    "sound_shared",
    "dual_bridge",
    "dual_id",
    "adc",
}


def load(path: Path) -> list[dict[str, Any]]:
    events = [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]
    if not events or events[0].get("schema") != "s32-arescue-census-v1":
        raise ValueError(f"{path}: missing s32-arescue-census-v1 header")
    return events


def first_table(events: list[dict[str, Any]], board: str) -> list[tuple[Any, ...]]:
    return [
        tuple(event.get(field) for field in FIRST_FIELDS)
        for event in events
        if event.get("event") == "bus_complete"
        and event.get("board") == board
        and event.get("first") is True
    ]


def validate_pair(left: Path, right: Path) -> dict[str, int]:
    a = load(left)
    b = load(right)
    counts: dict[str, int] = {}
    for board in ("main", "sub"):
        first_a = first_table(a, board)
        first_b = first_table(b, board)
        if first_a != first_b:
            limit = min(len(first_a), len(first_b))
            mismatch = next((i for i in range(limit) if first_a[i] != first_b[i]), limit)
            raise ValueError(
                f"{board}: nondeterministic first-event table at index {mismatch}; "
                f"counts {len(first_a)} vs {len(first_b)}"
            )
        counts[board] = len(first_a)

    sub_devices = {row[1] for row in first_table(a, "sub")}
    missing = sorted(REQUIRED_PEER_DEVICES - sub_devices)
    if missing:
        raise ValueError(f"sub: census ended before required private devices: {', '.join(missing)}")

    # DSP exists only on the main PCB. Its absence on the peer is topology,
    # while every other required private digital block must be observed.
    main_devices = {row[1] for row in first_table(a, "main")}
    if "dsp" not in main_devices or "dsp" in sub_devices:
        raise ValueError("DSP topology mismatch: expected main-only DSP accesses")
    return counts


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("left", type=Path)
    parser.add_argument("right", type=Path)
    args = parser.parse_args()
    counts = validate_pair(args.left, args.right)
    print(
        "AIR RESCUE CENSUS PASS "
        f"main_first={counts['main']} sub_first={counts['sub']} ordering=per-board"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
