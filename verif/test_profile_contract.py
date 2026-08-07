"""Prevent future chats from routing games into ad-hoc RBF profiles."""

from pathlib import Path
from xml.etree import ElementTree
import unittest

from tools.gen_mra import GAMES, RBF_BY_PARENT


ROOT = Path(__file__).parents[1]
MRA_DIR = ROOT / "mra"


class GlobalProfileContractTests(unittest.TestCase):
    def test_declined_games_are_not_routed_or_emitted(self) -> None:
        removed = {
            "arescue", "alien3", "kokoroj", "kokoroj2", "sonicp",
            "brival", "darkedge", "dbzvrvs", "f1en", "f1lap",
            "slipstrm", "svf", "jleague",
        }
        self.assertTrue(removed.isdisjoint(GAMES))
        for path in MRA_DIR.glob("*.mra"):
            root = ElementTree.parse(path).getroot()
            setname = root.findtext("setname", "")
            parent = root.findtext("parent", setname)
            self.assertNotIn(setname, removed, path.name)
            self.assertNotIn(parent, removed, path.name)

    def test_exactly_two_quartus_profiles_exist(self) -> None:
        """2026-08-06: split back into two dedicated profiles -- segas32v25
        (ga2/arabfgt, real V25) and segas32 (Sonic and future non-V25 games,
        HLE only). See PROFILE_CONTRACT.md for the routing rules this
        protects."""
        for name in ("segas32v25.qpf", "segas32v25.qsf", "segas32.qpf", "segas32.qsf"):
            self.assertTrue((ROOT / name).is_file(), name)
        for obsolete in ("s32", "s32v25", "Arcade-SegaSystem32", "s32GoldenAxe", "s32ArabianFight"):
            self.assertFalse((ROOT / f"{obsolete}.qpf").exists(), obsolete)
            self.assertFalse((ROOT / f"{obsolete}.qsf").exists(), obsolete)

    def test_profile_qsfs_carry_the_right_v25_shape(self) -> None:
        v25 = (ROOT / "segas32v25.qsf").read_text(encoding="utf-8")
        self.assertIn('VERILOG_MACRO "S32_PROFILE_STANDARD=1"', v25)
        self.assertIn('VERILOG_MACRO "S32_REAL_V25=1"', v25)
        self.assertIn('VERILOG_MACRO "S32_GAME_ONLY=1"', v25)
        self.assertNotIn('VERILOG_MACRO "S32_PROFILE_V25=1"', v25)
        self.assertNotIn('VERILOG_MACRO "S32_GAME_ONLY_STD=1"', v25)

        std = (ROOT / "segas32.qsf").read_text(encoding="utf-8")
        self.assertIn('VERILOG_MACRO "S32_PROFILE_STANDARD=1"', std)
        self.assertIn('VERILOG_MACRO "S32_GAME_ONLY_STD=1"', std)
        self.assertNotIn('VERILOG_MACRO "S32_REAL_V25=1"', std)
        self.assertNotIn('VERILOG_MACRO "S32_PROFILE_V25=1"', std)
        self.assertNotIn('VERILOG_MACRO "S32_GAME_ONLY=1"', std)

        for standard in (v25, std):
            for legacy in ("S32_GA2_ONLY", "S32_GOLDENAXE_ONLY", "S32_ARABFIGHT_ONLY",
                            "S32_V25_GAME_ONLY", "S32_SONIC_ONLY"):
                self.assertNotIn(f'VERILOG_MACRO "{legacy}=1"', standard)

    def test_every_emitted_mra_routes_to_a_known_profile(self) -> None:
        self.assertEqual(RBF_BY_PARENT, {"ga2": "segas32v25", "arabfgt": "segas32v25"})
        seen = set()
        for path in MRA_DIR.glob("*.mra"):
            root = ElementTree.parse(path).getroot()
            parent = root.findtext("parent") or root.findtext("setname")
            if parent not in GAMES:
                continue
            seen.add(parent)
            expected_rbf = RBF_BY_PARENT.get(parent, "segas32")
            self.assertEqual(root.findtext("rbf"), expected_rbf, path.name)
        self.assertTrue(seen)
        self.assertTrue(seen <= set(GAMES))

    def test_romboot_ga2_qualification_uses_descriptor_boundary(self) -> None:
        """A protection selector must not classify standard games as GA2."""
        text = (ROOT / "verif/common/tb_core_romboot.sv").read_text(
            encoding="utf-8")
        self.assertIn("ga2_qualification", text)
        self.assertIn("((b0 & 8'h06) == 8'h02)", text)
        self.assertIn(
            "board.v25_table,\n             ga2_qualification, board.has_adc, board.has_track",
            text,
        )
        self.assertNotIn("b2 != 1 && frames >= 70 && spr_px == 0", text)

    def test_romboot_attract_gate_requires_verilator_screenshot(self) -> None:
        """Promotion must be backed by a non-black frame from this run."""
        text = (ROOT / "verif/common/tb_core_romboot.sv").read_text(
            encoding="utf-8")
        self.assertIn("REQUIRE_VERILATOR_SCREENSHOT", text)
        self.assertIn("dump_nonblack_seen", text)
        self.assertIn("VERILATOR SCREENSHOT FAIL", text)

    def test_standard_fighting_inputs_are_descriptor_selected(self) -> None:
        """Brival/Dark Edge upper buttons must not use GA2's P3/P4 wiring."""
        text = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        self.assertIn(
            "active_board.prot_sel == PROT_DARKEDGE) ? darkedge_p1a",
            text,
        )
        self.assertIn("wire [7:0] brival_ppi_pb", text)
        self.assertIn("wire [7:0] darkedge_ppi_pb", text)
        self.assertIn("wire brival_inputs = active_board.prot_sel == PROT_BRIVAL", text)
        self.assertIn(
            "wire darkedge_inputs = active_board.prot_sel == PROT_DARKEDGE",
            text,
        )
        self.assertIn(
            ".ppi_pa(core_ppi_pa), .ppi_pb(core_ppi_pb), .ppi_pc(core_ppi_pc)",
            text,
        )

    def test_rad_rally_gear_is_a_descriptor_selected_toggle(self) -> None:
        text = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        self.assertIn("if (joystick_0[4] && !radr_gear_btn_d)", text)
        self.assertIn("radr_gear <= ~radr_gear", text)
        self.assertIn("active_board.gear_toggle ? gear_toggle_p1a", text)

    def test_rad_mobile_light_wiper_layout_is_descriptor_selected(self) -> None:
        text = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        self.assertIn("wire [7:0] radm_p1a", text)
        self.assertIn(
            "active_board.digital_profile == DIGITAL_RADM) ? radm_p1a",
            text,
        )

    def test_attract_sweep_preserves_gate_and_capture_tail(self) -> None:
        """The matrix runner must request and finish every attract capture."""
        text = (ROOT / "verif/verilator/run_library_sweep.sh").read_text(
            encoding="utf-8")
        self.assertIn("run_args+=(+REQUIRE_VERILATOR_SCREENSHOT)", text)
        self.assertNotIn("slipstrm", text)
        self.assertNotIn("dbzvrvs", text)
        self.assertIn("jpark|sonic|spidman)", text)
        self.assertIn("radm)                  echo 660", text)


if __name__ == "__main__":
    unittest.main()
