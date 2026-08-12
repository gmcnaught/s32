import json
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class V60StateInventoryTest(unittest.TestCase):
    def test_generated_inventory_is_current_and_complete(self):
        run = subprocess.run(
            [sys.executable, "-B", "tools/v60_state_inventory.py"],
            cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("100% classified", run.stdout)

    def test_accessor_enumeration_matches_manifest(self):
        manifest = json.loads((ROOT / "verif/v60/state_inventory.json").read_text())
        persistent = [s["name"] for s in manifest["symbols"] if s["class"] == "persistent"]
        accessor = (ROOT / "verif/v60/v60_state_accessors.svh").read_text()
        enumerated = [line.strip().split("(", 1)[1].split(")", 1)[0]
                      for line in accessor.splitlines() if line.strip().startswith("X(")]
        self.assertEqual(enumerated, persistent)
        self.assertEqual(manifest["persistent_count"], len(persistent))
        # Existing benches depend on these flat hierarchical names.  Keeping
        # them in the generated list is the CONTEXTS=1 compatibility gate.
        for name in ("r", "pc", "psw_rest", "st", "cls", "dbus_req", "if_req", "irq_ack"):
            self.assertIn(name, persistent)


if __name__ == "__main__":
    unittest.main()
