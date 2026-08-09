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
            "kokoroj", "kokoroj2", "sonicp",
            "dbzvrvs", "f1en", "f1lap",
            "svf", "jleague",
        }
        self.assertTrue(removed.isdisjoint(GAMES))
        self.assertIn("holo", GAMES)
        self.assertIn("spidman", GAMES)
        self.assertIn("slipstrm", GAMES)
        for promoted in ("alien3", "arescue", "brival", "darkedge", "jpark", "radr"):
            self.assertIn(promoted, GAMES)
        for path in MRA_DIR.glob("*.mra"):
            root = ElementTree.parse(path).getroot()
            setname = root.findtext("setname", "")
            parent = root.findtext("parent", setname)
            self.assertNotIn(setname, removed, path.name)
            self.assertNotIn(parent, removed, path.name)

    def test_exactly_two_quartus_profiles_exist(self) -> None:
        """2026-08-06: split back into two dedicated profiles -- segas32v25
        (ga2/arabfgt, real V25) and segas32 (standard non-V25 games,
        including Sonic and Slip Stream, HLE only). See PROFILE_CONTRACT.md for the routing rules this
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
        self.assertIn('VERILOG_MACRO "S32_V25_MLAB_EEPROM=1"', v25)
        self.assertNotIn('VERILOG_MACRO "S32_V25_MLAB_EEPROM=1"', std)

        for standard in (v25, std):
            self.assertIn('VERILOG_MACRO "MISTER_DISABLE_SHADOWMASK=1"', standard)
            for legacy in ("S32_GA2_ONLY", "S32_GOLDENAXE_ONLY", "S32_ARABFIGHT_ONLY",
                            "S32_V25_GAME_ONLY", "S32_SONIC_ONLY"):
                self.assertNotIn(f'VERILOG_MACRO "{legacy}=1"', standard)

    def test_standard_profile_is_hle_only_and_has_no_real_v25_qip(self) -> None:
        """segas32 may retain the mailbox HLE, but never the real V25 CPU."""
        top = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        core = (ROOT / "rtl/s32_core.sv").read_text(encoding="utf-8")
        qsf = (ROOT / "segas32.qsf").read_text(encoding="utf-8")
        self.assertIn("active_board.has_v25          = board_desc.has_v25;", top)
        self.assertIn("s32_v25 v25 (", core)
        self.assertNotIn("QIP_FILE rtl/cpu/v25/v25.qip", qsf)
        self.assertNotIn('VERILOG_MACRO "S32_REAL_V25=1"', qsf)

    def test_profile_only_sources_are_mutually_exclusive(self) -> None:
        v25 = (ROOT / "segas32v25.qsf").read_text(encoding="utf-8")
        std = (ROOT / "segas32.qsf").read_text(encoding="utf-8")
        shared = (ROOT / "files.qip").read_text(encoding="utf-8")
        self.assertIn("QIP_FILE rtl/cpu/v25/v25.qip", v25)
        self.assertNotIn("SYSTEMVERILOG_FILE rtl/prot/s32_prot.sv", v25)
        self.assertIn("SYSTEMVERILOG_FILE rtl/prot/s32_prot.sv", std)
        self.assertNotIn("QIP_FILE rtl/cpu/v25/v25.qip", std)
        self.assertNotIn("SYSTEMVERILOG_FILE rtl/prot/s32_prot.sv", shared)
        self.assertNotIn("QIP_FILE rtl/cpu/v25/v25.qip", shared)

    def test_production_osd_has_no_debug_pause_or_aim_override(self) -> None:
        top = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        self.assertNotIn("O[12],Pause", top)
        self.assertNotIn("Analog Aim Invert", top)
        self.assertNotIn("wire pause = status[12]", top)
        self.assertIn(".pause(1'b0)", top)

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

    def test_sonic_has_three_lightweight_trackball_controls(self) -> None:
        """Sonic uses three left sticks and exact active-low cabinet buttons."""
        text = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        self.assertIn(
            "joystick_l_analog_0, joystick_l_analog_1, joystick_l_analog_2",
            text,
        )
        self.assertEqual(text.count("s32_trackball_stick trk_stick"), 3)
        self.assertIn("wire trk_tick = core_vs & ~core_vs_d", text)
        self.assertNotIn("trk_div", text)
        self.assertIn("wire sonic_controls = active_board.has_track", text)
        self.assertIn(
            "sonic_p1a = {5'b11111, ~joystick_2[4], 1'b1, ~joystick_0[4]}",
            text,
        )
        self.assertIn(
            "sonic_p2a = {7'b1111111, ~joystick_1[4]}",
            text,
        )
        self.assertIn("sonic_controls ? joystick_2[10]", text)
        self.assertIn("sonic_controls ? joystick_2[11]", text)

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

    def test_alien3_uses_its_cabinet_coin_start_service_wiring(self) -> None:
        """Alien 3 must not fall through to generic SERVICE12 assignments."""
        text = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        self.assertIn(
            "wire alien3_controls = active_board.gun_aim && active_board.coin_swap",
            text,
        )
        # Alien 3 starts each side with its trigger; the MiSTer Start button is
        # an alias for that trigger rather than generic SERVICE12 Start 1/2.
        self.assertIn(
            "wire [7:0] alien3_p1a = p1a_dig & {7'h7f, ~joystick_0[10]}",
            text,
        )
        self.assertIn(
            "wire [7:0] alien3_p2a = p2a_dig & {7'h7f, ~joystick_1[10]}",
            text,
        )
        # MAME alien3: SERVICE12 bit3=Coin 1, bit2=Coin 2, bit4=Service 2,
        # bit5 unused.  Bits 5/4 stay released here so Start cannot issue a
        # service credit; Test and Service retain generic bits 1/0.
        self.assertIn(
            "wire [7:0] svc12_alien3 = ~{2'b00, 2'b00, joystick_0[11],\n"
            "                             joystick_1[11], test_btn, svc_btn}",
            text,
        )
        self.assertIn(
            "wire [7:0] svc12 = alien3_controls ? svc12_alien3 : svc12_generic",
            text,
        )

    def test_alien3_hud_blend_osd_is_hidden_for_every_other_game(self) -> None:
        text = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        core = (ROOT / "rtl/s32_core.sv").read_text(encoding="utf-8")
        fb_if = (ROOT / "rtl/mem/s32_fb_if.sv").read_text(encoding="utf-8")
        self.assertIn('"h0O[8],Alien 3 HUD Blend,Off,On;"', text)
        self.assertIn(
            ".status_menumask({15'd0, active_board.gun_aim && "
            "active_board.coin_swap})",
            text,
        )
        self.assertIn(
            ".alien3_hud_blend(alien3_controls && status[8])",
            text,
        )
        self.assertIn(
            "fb_rd_blend_r <= alien3_hud_blend && "
            "fb_next_is_alien3_hud",
            core,
        )
        self.assertIn(
            "fb_next_y >= 8'd184 && fb_next_y <= 8'd201",
            core,
        )
        self.assertIn("dburst <= 8'd32", fb_if)
        self.assertIn(
            "pix_addr(rd_blend_buf_latched, rd_y, 7'd4)", fb_if
        )
        self.assertIn(
            "pix_addr(rd_blend_buf_latched, rd_y, 7'd44)", fb_if
        )
        self.assertIn("s32_fb_line_ram line_ram0", fb_if)
        self.assertIn("s32_fb_line_ram line_ram1", fb_if)

    def test_rad_rally_gear_is_a_descriptor_selected_toggle(self) -> None:
        text = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        self.assertIn("if (joystick_0[6] && !radr_gear_btn_d)", text)
        self.assertIn("radr_gear <= ~radr_gear", text)
        self.assertIn("active_board.gear_toggle ? gear_toggle_p1a", text)

    def test_driving_pedals_use_right_stick_with_a_b_fallbacks(self) -> None:
        text = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        controls = (ROOT / "rtl/io/s32_driving_controls.sv").read_text(
            encoding="utf-8")
        self.assertIn(".joystick_r_analog_0(joystick_r_analog_0)", text)
        self.assertIn(".right_analog(joystick_r_analog_0)", text)
        self.assertIn("stick_y < 0", controls)
        self.assertIn("stick_y > 0", controls)
        self.assertIn("digital_accel ? 8'hff", controls)
        self.assertIn("digital_brake ? 8'hff", controls)
        self.assertIn("driving_analog ? driving_accel", text)
        self.assertIn("driving_analog ? driving_brake", text)

    def test_rad_mobile_light_wiper_layout_is_descriptor_selected(self) -> None:
        text = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        self.assertIn("wire [7:0] radm_p1a", text)
        self.assertIn(
            "active_board.digital_profile == DIGITAL_RADM) ? radm_p1a",
            text,
        )

    def test_standard_shape_retains_descriptor_gated_adc(self) -> None:
        text = (ROOT / "rtl/s32_core.sv").read_text(encoding="utf-8")
        self.assertIn("if (GAME_ONLY && !GAME_ONLY_STD) begin : g_no_adc", text)
        self.assertIn("s32_msm6253 adc (", text)
        self.assertIn(
            "wire sel_adc   = sel_ioex && (A[5:3] == 3'b010) && cfg_has_adc",
            text,
        )

    def test_standard_shape_retains_promoted_game_hardware(self) -> None:
        core = (ROOT / "rtl/s32_core.sv").read_text(encoding="utf-8")
        top = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        self.assertIn("s32_arescue_dsp dsp (", core)
        self.assertIn("if (GAME_ONLY && !GAME_ONLY_STD) begin : g_game_no_brival", core)
        self.assertIn("if (GAME_ONLY && !GAME_ONLY_STD) begin : g_no_dualpcb", core)
        self.assertIn("wire gun_aim_active = active_board.gun_aim", top)
        self.assertIn("wire alien3_controls = active_board.gun_aim && active_board.coin_swap", top)

    def test_alien3_and_jpark_share_one_analog_aim_path(self) -> None:
        top = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        self.assertIn("wire gun_aim_active = active_board.gun_aim", top)
        self.assertIn(".enable(gun_aim_active)", top)
        self.assertIn(".p1_raw_x(joystick_l_analog_0[7:0])", top)
        self.assertIn(".p1_raw_y(joystick_l_analog_0[15:8])", top)
        self.assertIn(".p2_raw_x(joystick_l_analog_1[7:0])", top)
        self.assertIn(".p2_raw_y(joystick_l_analog_1[15:8])", top)
        self.assertIn("wire aim_inv_x = 1'b0", top)
        self.assertIn("wire aim_inv_y = 1'b0", top)
        self.assertIn("gun_aim_active ? gun_aim_x[0]", top)
        self.assertIn("gun_aim_active ? gun_aim_y[0]", top)
        self.assertIn("gun_aim_active ? gun_aim_x[1]", top)
        self.assertIn("gun_aim_active ? gun_aim_y[1]", top)

    def test_attract_sweep_preserves_gate_and_capture_tail(self) -> None:
        """The matrix runner must request and finish every attract capture."""
        text = (ROOT / "verif/verilator/run_library_sweep.sh").read_text(
            encoding="utf-8")
        self.assertIn("run_args+=(+REQUIRE_VERILATOR_SCREENSHOT)", text)
        self.assertIn("slipstrm", text)
        self.assertNotIn("dbzvrvs", text)
        self.assertIn("jpark|sonic|spidman)", text)
        self.assertIn("radm)                  echo 660", text)


if __name__ == "__main__":
    unittest.main()
