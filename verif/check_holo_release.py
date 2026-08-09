#!/usr/bin/env python3
"""Static contract for the current Holosseum hardware release profile.

2026-08-07: split back into two dedicated profiles -- segas32v25.qsf (ga2,
arabfgt: real V25) and segas32.qsf (Sonic, Holo, and Spider-Man: HLE only).
Holo has no V25 protection hardware, so it belongs to segas32's scope.
"""

from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
qsf = (ROOT / "segas32.qsf").read_text(encoding="utf-8")
assert 'VERILOG_MACRO "S32_SYSTEM32_ONLY=1"' in qsf, "release is not System 32-only"
assert 'VERILOG_MACRO "S32_PROFILE_STANDARD=1"' in qsf
assert 'VERILOG_MACRO "S32_REAL_V25=1"' not in qsf, \
    "segas32.qsf must not compile the real V25 core -- none of its games have V25 hardware"

matches = []
for path in (ROOT / "mra").glob("*.mra"):
    tree = ET.parse(path)
    if tree.findtext("setname") == "holo":
        matches.append((path, tree))

assert len(matches) == 1, f"expected exactly one Holo MRA, found {len(matches)}"
path, tree = matches[0]
root = tree.getroot()
assert root.findtext("rbf") == "segas32"
assert root.findtext("name") == "Holosseum (US, Rev A)"
rom = root.find("rom[@index='0']")
assert rom is not None and rom.get("zip") is None

descriptor_part = rom.find("part")
assert descriptor_part is not None and descriptor_part.text is not None
descriptor = bytes.fromhex(descriptor_part.text.strip())
assert len(descriptor) == 64
assert descriptor[0] == 0x00, "Holo unexpectedly enables optional board hardware"
assert descriptor[1] == 0x02, "Holo cabinet vertical orientation is missing"
assert descriptor[2] == 0x00, "Holo unexpectedly selects protection HLE"
assert descriptor[3] == 0x81, "Holo must expose two physical 4 MiB sprite banks"
assert descriptor[4:] == bytes(60), "unexpected Holo descriptor options"
assert root.find("rom[@index='8']") is None, \
    "Holo release unexpectedly carries a V25 program"

print(f"HOLO RELEASE MRA PASS: {path.name}")
