import json
import tempfile
import unittest
from pathlib import Path

from verif.analyze_arescue_census import REQUIRED_PEER_DEVICES, validate_pair


class AirRescueCensusTest(unittest.TestCase):
    def _write(self, path: Path, changed: bool = False) -> None:
        rows = [{"schema": "s32-arescue-census-v1", "event": "header"}]
        for board in ("main", "sub"):
            devices = set(REQUIRED_PEER_DEVICES)
            if board == "main":
                devices.add("dsp")
            for ordinal, device in enumerate(sorted(devices), 1):
                rows.append(
                    {
                        "schema": "s32-arescue-census-v1",
                        "event": "bus_complete",
                        "first": True,
                        "board": board,
                        "device": device,
                        "rw": "R",
                        "lanes": 3,
                        "pc": "00000000",
                        "address": "000000",
                        "canonical_address": "000000",
                        "data": "0001" if changed and board == "sub" and ordinal == 1 else "0000",
                        "mem_mask_raw": "0000ffff",
                    }
                )
        path.write_text("\n".join(json.dumps(row) for row in rows) + "\n", encoding="utf-8")

    def test_matching_pair(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            left = Path(directory) / "a.jsonl"
            right = Path(directory) / "b.jsonl"
            self._write(left)
            self._write(right)
            self.assertEqual(validate_pair(left, right), {"main": 15, "sub": 14})

    def test_mismatch_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            left = Path(directory) / "a.jsonl"
            right = Path(directory) / "b.jsonl"
            self._write(left)
            self._write(right, changed=True)
            with self.assertRaisesRegex(ValueError, "nondeterministic"):
                validate_pair(left, right)


if __name__ == "__main__":
    unittest.main()
