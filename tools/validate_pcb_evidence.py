#!/usr/bin/env python3
"""Validate the source-backed System 32 PCB evidence ledger."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[1]
LEDGER = ROOT / "docs" / "pcb" / "system32_evidence.json"


def validate(check_rtl: bool = False) -> list[str]:
    errors: list[str] = []
    try:
        ledger = json.loads(LEDGER.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"cannot read {LEDGER}: {exc}"]

    if ledger.get("schema") != "s32-pcb-evidence-1":
        errors.append("unexpected evidence schema")
    scope = ledger.get("scope", {})
    if scope.get("family") != "Sega System 32":
        errors.append("scope.family must be Sega System 32")
    if scope.get("production_profiles") != ["standard", "v25"]:
        errors.append("production profiles must be exactly standard and v25")
    if "Multi 32" not in scope.get("excluded_from_production", []):
        errors.append("Multi 32 must remain excluded from production")
    if scope.get("physical_pcb_available") is not False:
        errors.append("physical_pcb_available must document the current limitation")

    required_facts = {
        "master_oscillator_hz",
        "v60_hz",
        "z80_ym3438_hz",
        "pcm_hz",
        "v60_external_data_bus_bits",
        "v60_address_bits",
    }
    facts = ledger.get("board_facts", {})
    for key in required_facts:
        if not isinstance(facts.get(key), int) or facts[key] <= 0:
            errors.append(f"board_facts.{key} must be a positive integer")

    sources = ledger.get("sources", {})
    claims = ledger.get("claims", [])
    claim_ids: set[str] = set()
    valid_confidence = {"high", "medium", "low", "unknown"}
    valid_status = {"implemented", "pending_measurement_or_decapsulation",
                    "pending_measurement", "pending_rom_and_trace_evidence"}
    for claim in claims:
        claim_id = claim.get("id")
        if not claim_id or claim_id in claim_ids:
            errors.append(f"duplicate or missing claim id: {claim_id!r}")
        claim_ids.add(claim_id)
        if claim.get("confidence") not in valid_confidence:
            errors.append(f"{claim_id}: invalid confidence")
        if claim.get("status") not in valid_status:
            errors.append(f"{claim_id}: invalid status")
        for source_id in claim.get("sources", []):
            if source_id not in sources:
                errors.append(f"{claim_id}: unknown source {source_id}")
        implementation = claim.get("implementation", [])
        if claim.get("status") == "implemented":
            if not implementation:
                errors.append(f"{claim_id}: implemented claim has no implementation")
            for relative in implementation:
                if not (ROOT / relative).is_file():
                    errors.append(f"{claim_id}: missing implementation {relative}")

    if check_rtl:
        for qsf, profile in ((ROOT / "s32.qsf", "S32_PROFILE_STANDARD=1"),):
            text = qsf.read_text(encoding="utf-8")
            if profile not in text:
                errors.append(f"{qsf.name}: missing {profile}")
            if 'VERILOG_MACRO "S32_PCB_TIMING=1"' not in text:
                errors.append(f"{qsf.name}: missing S32_PCB_TIMING=1")
            if "NUM_PARALLEL_PROCESSORS 8" not in text:
                errors.append(f"{qsf.name}: must use eight Quartus workers")
            if 'VERILOG_MACRO "S32_REAL_V25=1"' not in text:
                errors.append(f"{qsf.name}: missing S32_REAL_V25=1 (merged profile requirement)")
        core_text = (ROOT / "rtl" / "s32_core.sv").read_text(encoding="utf-8")
        if "S32_PCB_TIMING" not in core_text or "FAST_IFETCH_EN" not in core_text:
            errors.append("s32_core.sv: production fetch timing boundary is missing")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check-rtl", action="store_true")
    args = parser.parse_args()
    errors = validate(args.check_rtl)
    if errors:
        for error in errors:
            print(f"PCB EVIDENCE FAIL: {error}", file=sys.stderr)
        return 1
    print("PCB EVIDENCE PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
