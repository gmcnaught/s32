#!/usr/bin/env python3
"""Static contract for the current Holosseum hardware release profile.

2026-08-05: the separate s32v25 revision was retired -- real V25 hardware is
now always compiled into the single s32.qsf, descriptor-led (board.has_v25)
like every other per-game config bit (see memory s32-single-profile-roadmap).
Holo's own descriptor sets has_v25=0 (asserted below via the byte-0 feature
field), so the V25 core stays compiled-in but idle for this game -- it is no
longer *absent* from the build the way it was under the two-revision split.
"""

from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
qsf = (ROOT / "s32.qsf").read_text(encoding="utf-8")
assert 'VERILOG_MACRO "S32_SYSTEM32_ONLY=1"' in qsf, "release is not System 32-only"
assert 'VERILOG_MACRO "S32_PROFILE_STANDARD=1"' in qsf
assert 'VERILOG_MACRO "S32_REAL_V25=1"' in qsf, \
    "merged profile must compile the real V25 core (runtime-gated per game)"

# The real NEC V25 is only hardware for Golden Axe: The Revenge of Death
# Adder and Arabian Fight, but the merged profile compiles it unconditionally
# now (files.qip) and gates it at runtime via the board descriptor instead of
# at compile time via a second Quartus revision.
files_qip = (ROOT / "files.qip").read_text(encoding="utf-8")
assert "QIP_FILE rtl/cpu/v25/v25.qip" in files_qip or \
    "QIP_FILE rtl/cpu/v25/v25.qip" in qsf, \
    "merged profile lost the real V25 sources"
assert 'VERILOG_MACRO "S80X86_PSEUDO_286_INT=0"' in qsf, \
    "merged profile lost the s80x86 interrupt-mode parse option"

matches = []
for path in (ROOT / "mra").glob("*.mra"):
    tree = ET.parse(path)
    if tree.findtext("setname") == "holo":
        matches.append((path, tree))

assert len(matches) == 1, f"expected exactly one Holo MRA, found {len(matches)}"
path, tree = matches[0]
root = tree.getroot()
assert root.findtext("rbf") == "s32"
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
