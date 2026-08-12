import hashlib, subprocess, sys, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import convert_upd77p25_rom as conv

class ConverterTest(unittest.TestCase):
    def test_layout_and_endianness(self):
        blob = bytearray(conv.SIZE)
        blob[0:8] = bytes.fromhex("00123456FFABCDEF")
        blob[0x2000:0x2004] = bytes.fromhex("13572468")
        p, d = conv.convert(bytes(blob))
        self.assertEqual((len(p), len(d)), (2048, 1024))
        self.assertEqual(p[:2], ["123456", "ABCDEF"])
        self.assertEqual(d[:2], ["1357", "2468"])

    def test_reproducible_and_opt_in_hash_gate(self):
        blob = bytes(conv.SIZE)
        with tempfile.TemporaryDirectory() as td:
            rom, a, b = Path(td)/"d7725.01", Path(td)/"a", Path(td)/"b"
            rom.write_bytes(blob)
            cmd = [sys.executable, str(ROOT/"tools"/"convert_upd77p25_rom.py"), str(rom), "--out-dir"]
            subprocess.run(cmd+[str(a)], check=True); subprocess.run(cmd+[str(b)], check=True)
            for name in ("upd7725_program.hex", "upd7725_data.hex", "upd7725_hashes.txt"):
                self.assertEqual((a/name).read_bytes(), (b/name).read_bytes())
            bad = subprocess.run(cmd+[str(a), "--verify-known"], capture_output=True)
            self.assertNotEqual(bad.returncode, 0)
