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

    def test_only_one_quartus_profile_exists(self) -> None:
        """2026-08-05: s32v25 was retired -- one merged profile serves every
        System 32 game (see memory s32-single-profile-roadmap)."""
        for name in ("s32.qpf", "s32.qsf"):
            self.assertTrue((ROOT / name).is_file(), name)
        for obsolete in ("s32v25", "Arcade-SegaSystem32", "s32GoldenAxe", "s32ArabianFight"):
            self.assertFalse((ROOT / f"{obsolete}.qpf").exists(), obsolete)
            self.assertFalse((ROOT / f"{obsolete}.qsf").exists(), obsolete)

    def test_profile_qsf_carries_standard_and_real_v25(self) -> None:
        standard = (ROOT / "s32.qsf").read_text(encoding="utf-8")
        self.assertIn('VERILOG_MACRO "S32_PROFILE_STANDARD=1"', standard)
        self.assertIn('VERILOG_MACRO "S32_REAL_V25=1"', standard)
        self.assertNotIn('VERILOG_MACRO "S32_PROFILE_V25=1"', standard)
        for legacy in ("S32_GA2_ONLY", "S32_GOLDENAXE_ONLY", "S32_ARABFIGHT_ONLY", "S32_V25_GAME_ONLY"):
            self.assertNotIn(f'VERILOG_MACRO "{legacy}=1"', standard)

    def test_every_emitted_mra_routes_to_the_single_global_profile(self) -> None:
        self.assertEqual(RBF_BY_PARENT, {})
        seen = set()
        for path in MRA_DIR.glob("*.mra"):
            root = ElementTree.parse(path).getroot()
            parent = root.findtext("parent") or root.findtext("setname")
            if parent not in GAMES:
                continue
            seen.add(parent)
            self.assertEqual(root.findtext("rbf"), "s32", path.name)
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
