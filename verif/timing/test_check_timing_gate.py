#!/usr/bin/env python3
"""Unit tests for the timing gate, keyed to the 2026-08-25 hardware results."""
import subprocess, sys, tempfile, unittest
from pathlib import Path

GATE = Path(__file__).resolve().parent / "check_timing_gate.py"


def block(kind, domain, slack, tns=None):
    return (f"Type  : {kind} '{domain}'\n"
            f"Slack : {slack}\nTNS   : {tns if tns is not None else slack}\n\n")


def run(text):
    with tempfile.NamedTemporaryFile("w", suffix=".summary", delete=False) as fh:
        fh.write(text)
        path = fh.name
    r = subprocess.run([sys.executable, str(GATE), path],
                       capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


CORE_RAM = "emu|pll|pll_inst|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk"
CORE_SYS = "emu|pll|pll_inst|altera_pll_i|general[1].gpll~PLL_OUTPUT_COUNTER|divclk"
HDMI = "pll_hdmi|pll_hdmi_inst|altera_pll_i|cyclonev_pll|counter[0].output_counter|divclk"


class TestGate(unittest.TestCase):
    def test_main_shape_passes(self):
        """main (825e2a28) renders on hardware: only the vendored HDMI setup misses."""
        rc, out = run(block("Slow 1100mV -40C Model Setup", HDMI, "-0.132")
                      + block("Slow 1100mV 100C Model Setup", CORE_RAM, "0.224"))
        self.assertEqual(rc, 0, out)
        self.assertIn("TIMING GATE PASS", out)

    def test_pr14_shape_fails(self):
        """PR #14 blacked out every game: hold violations on clk_ram."""
        rc, out = run(block("Slow 1100mV 100C Model Hold", CORE_RAM, "-0.304", "-0.601")
                      + block("Slow 1100mV 100C Model Setup", CORE_RAM, "0.202"))
        self.assertEqual(rc, 3, out)
        self.assertIn("hold violation on a core clock", out)

    def test_pr15_shape_fails(self):
        """PR #15 (functionally null) also blacked out: hold on clk_sys."""
        rc, out = run(block("Slow 1100mV 100C Model Hold", CORE_SYS, "-0.537", "-1.745"))
        self.assertEqual(rc, 3, out)

    def test_core_setup_violation_is_fatal(self):
        rc, out = run(block("Slow 1100mV 100C Model Setup", CORE_RAM, "-0.010"))
        self.assertEqual(rc, 3, out)
        self.assertIn("setup violation on a core clock", out)

    def test_hdmi_setup_beyond_allowance_is_fatal(self):
        rc, _ = run(block("Slow 1100mV 100C Model Setup", HDMI, "-0.400"))
        self.assertEqual(rc, 3)

    def test_recovery_violation_is_fatal(self):
        rc, _ = run(block("Slow 1100mV 100C Model Recovery", CORE_RAM, "-0.050"))
        self.assertEqual(rc, 3)

    def test_no_f_strings(self):
        """The CI container's python3 predates f-strings; the first version of
        this gate crashed there and build.sh called it a rejected bitstream."""
        src = GATE.read_text()
        for line in src.splitlines():
            stripped = line.strip()
            self.assertFalse(stripped.startswith('f"') or ' f"' in line
                             or " f'" in line,
                             "f-string in the gate: " + line)

    def test_empty_summary_is_fatal(self):
        """An STA that did not run must not read as a pass."""
        rc, out = run("nothing useful here\n")
        self.assertEqual(rc, 2, out)


if __name__ == "__main__":
    unittest.main()
