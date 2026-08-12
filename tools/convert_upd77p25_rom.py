#!/usr/bin/env python3
"""Convert a legal user-supplied d7725.01 dump into portable hex init files."""
from __future__ import annotations
import argparse, hashlib
from pathlib import Path

SIZE = 0x2800
KNOWN_SHA1 = "e9b05c70b639ee289e557dfd9a6c724b36338e2b"
KNOWN_SHA256 = "1fbe99e8e25e4388b584b76df70d765a8ff9d789930ab428f3d1580c7ab1102d"

def convert(blob: bytes) -> tuple[list[str], list[str]]:
    if len(blob) != SIZE:
        raise ValueError(f"expected 0x{SIZE:x} bytes, got 0x{len(blob):x}")
    # MAME copies 0x2000 bytes into ROM_REGION32_BE: each 24-bit opcode is
    # held in the low 24 bits of one big-endian 32-bit slot.
    program = [f"{int.from_bytes(blob[i:i+4], 'big') & 0xffffff:06X}"
               for i in range(0, 0x2000, 4)]
    data = [f"{int.from_bytes(blob[i:i+2], 'big'):04X}"
            for i in range(0x2000, 0x2800, 2)]
    return program, data

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("rom", type=Path, help="user-supplied d7725.01 (not redistributed)")
    ap.add_argument("--out-dir", type=Path, required=True)
    ap.add_argument("--verify-known", action="store_true",
                    help="require the known Air Rescue dump hashes")
    ns = ap.parse_args()
    blob = ns.rom.read_bytes()
    sha1, sha256 = hashlib.sha1(blob).hexdigest(), hashlib.sha256(blob).hexdigest()
    if ns.verify_known and (sha1 != KNOWN_SHA1 or sha256 != KNOWN_SHA256):
        raise SystemExit(f"hash mismatch: SHA1={sha1} SHA256={sha256}")
    try: program, data = convert(blob)
    except ValueError as exc: raise SystemExit(str(exc)) from exc
    ns.out_dir.mkdir(parents=True, exist_ok=True)
    (ns.out_dir / "upd7725_program.hex").write_text("\n".join(program)+"\n", encoding="ascii", newline="\n")
    (ns.out_dir / "upd7725_data.hex").write_text("\n".join(data)+"\n", encoding="ascii", newline="\n")
    (ns.out_dir / "upd7725_hashes.txt").write_text(f"SHA1 {sha1}\nSHA256 {sha256}\n", encoding="ascii", newline="\n")
    return 0

if __name__ == "__main__": raise SystemExit(main())
