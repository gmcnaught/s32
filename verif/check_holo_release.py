#!/usr/bin/env python3
"""Static contract for the current Holosseum hardware release profile."""

from pathlib import Path
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
qsf = (ROOT / "s32.qsf").read_text(encoding="utf-8")
assert 'VERILOG_MACRO "S32_SYSTEM32_ONLY=1"' in qsf, "release is not System 32-only"
# Per-game revisions own their feature macros. The shared QSF must not force
# Golden Axe/V25 hardware into future Holo, Spider-Man, or other game builds.
assert 'VERILOG_MACRO "S32_REAL_V25=1"' not in qsf, \
    "shared QSF unexpectedly forces the V25 into every game core"
assert 'VERILOG_MACRO "S32_PROFILE_STANDARD=1"' in qsf

# The real NEC V25 is hardware for Golden Axe: The Revenge of Death Adder and
# Arabian Fight only, so the standard revision does not merely leave it
# switched off -- it does not compile it.  The sources are listed by
# s32v25.qsf, not by the shared files.qip, and S80X86_PSEUDO_286_INT (a
# required parse option for the upstream s80x86 Flags module) is therefore
# meaningless here.  Assert both halves: gone from the standard revision, and
# still present for the two games that need the CPU.
files_qip = (ROOT / "files.qip").read_text(encoding="utf-8")
v25_qsf = (ROOT / "s32v25.qsf").read_text(encoding="utf-8")
assert "QIP_FILE rtl/cpu/v25/v25.qip" not in files_qip, \
    "shared file list still compiles the real V25 into every game core"
assert 'VERILOG_MACRO "S80X86_PSEUDO_286_INT' not in qsf, \
    "standard revision defines an s80x86 parse option but has no s80x86 sources"
assert "QIP_FILE rtl/cpu/v25/v25.qip" in v25_qsf, \
    "the V25 revision lost the real V25 sources"
assert 'VERILOG_MACRO "S80X86_PSEUDO_286_INT=0"' in v25_qsf, \
    "the V25 revision lost the s80x86 interrupt-mode parse option"

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
