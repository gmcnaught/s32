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
        for promoted in ("alien3", "brival", "darkedge", "jpark", "radr"):
            self.assertIn(promoted, GAMES)
        for path in MRA_DIR.glob("*.mra"):
            root = ElementTree.parse(path).getroot()
            setname = root.findtext("setname", "")
            parent = root.findtext("parent", setname)
            self.assertNotIn(setname, removed, path.name)
            self.assertNotIn(parent, removed, path.name)

    def test_exactly_one_universal_quartus_profile_exists(self) -> None:
        """Every supported parent is routed through the universal revision."""
        for name in ("segas32.qpf", "segas32.qsf"):
            self.assertTrue((ROOT / name).is_file(), name)
        for name in ("segas32v25.qpf", "segas32v25.qsf"):
            self.assertFalse((ROOT / name).exists(), name)
        for obsolete in ("s32", "s32v25", "Arcade-SegaSystem32", "s32GoldenAxe", "s32ArabianFight"):
            self.assertFalse((ROOT / f"{obsolete}.qpf").exists(), obsolete)
            self.assertFalse((ROOT / f"{obsolete}.qsf").exists(), obsolete)

    def test_universal_qsf_carries_both_hardware_shapes(self) -> None:
        qsf = (ROOT / "segas32.qsf").read_text(encoding="utf-8")
        for macro in ("S32_PROFILE_STANDARD=1", "S32_GAME_ONLY_STD=1",
                      "S32_UNIVERSAL=1", "S32_V25_HW=1"):
            self.assertIn(f'VERILOG_MACRO "{macro}"', qsf)
        for macro in ("S32_JT12_MLAB_SHIFTS=1", "S32_V25_MLAB_FIFO=1",
                      "S32_V25_MLAB_EEPROM=1"):
            self.assertNotIn(f'VERILOG_MACRO "{macro}"', qsf)
        self.assertNotIn('VERILOG_MACRO "S32_REAL_V25=1"', qsf)
        self.assertNotIn('VERILOG_MACRO "S32_PROFILE_V25=1"', qsf)
        self.assertIn("QIP_FILE rtl/cpu/v25/v25.qip", qsf)
        self.assertIn('VERILOG_MACRO "MISTER_DISABLE_SHADOWMASK=1"', qsf)
        for legacy in ("S32_GA2_ONLY", "S32_GOLDENAXE_ONLY", "S32_ARABFIGHT_ONLY",
                       "S32_V25_GAME_ONLY", "S32_SONIC_ONLY"):
            self.assertNotIn(f'VERILOG_MACRO "{legacy}=1"', qsf)

    def test_universal_profile_contains_real_v25_and_hle_fallback(self) -> None:
        """The descriptor selects real V25 or HLE behavior at runtime."""
        top = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        core = (ROOT / "rtl/s32_core.sv").read_text(encoding="utf-8")
        qsf = (ROOT / "segas32.qsf").read_text(encoding="utf-8")
        self.assertIn("active_board.has_v25          = board_desc.has_v25;", top)
        self.assertIn("s32_v25 v25 (", core)
        self.assertIn("QIP_FILE rtl/cpu/v25/v25.qip", qsf)
        self.assertIn('VERILOG_MACRO "S32_UNIVERSAL=1"', qsf)

    def test_profile_only_sources_are_mutually_exclusive(self) -> None:
        std = (ROOT / "segas32.qsf").read_text(encoding="utf-8")
        shared = (ROOT / "files.qip").read_text(encoding="utf-8")
        self.assertIn("SYSTEMVERILOG_FILE rtl/prot/s32_prot.sv", std)
        self.assertIn("QIP_FILE rtl/cpu/v25/v25.qip", std)
        self.assertNotIn("SYSTEMVERILOG_FILE rtl/prot/s32_prot.sv", shared)
        self.assertNotIn("QIP_FILE rtl/cpu/v25/v25.qip", shared)

    def test_v60_cadence_fix_is_shared_by_both_profiles(self) -> None:
        """The Sonic timing fix must not become a profile-specific bypass."""
        core = (ROOT / "rtl/s32_core.sv").read_text(encoding="utf-8")
        files_qip = (ROOT / "files.qip").read_text(encoding="utf-8")
        self.assertIn("module s32_v60_exec_cadence", core)
        self.assertIn("s32_v60_exec_cadence v60_cadence", core)
        self.assertIn(".ce(v60_exec_ce)", core)
        self.assertIn("s32_v60_bus vbus", core)
        self.assertIn(".clk(clk_sys), .ce(ce_cpu), .rst(rst)", core)
        self.assertIn("SYSTEMVERILOG_FILE rtl/s32_core.sv", files_qip)
        for profile in (ROOT / "segas32.qsf",):
            text = profile.read_text(encoding="utf-8")
            self.assertIn('VERILOG_MACRO "S32_PROFILE_STANDARD=1"', text)
            self.assertIn('VERILOG_MACRO "S32_SYSTEM32_ONLY=1"', text)

    def test_optional_v60_fetch_keeps_the_physical_bus_fixed(self) -> None:
        """Fast fetch is reset-latched and must never multiply ce_cpu."""
        top = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        core = (ROOT / "rtl/s32_core.sv").read_text(encoding="utf-8")
        cpu = (ROOT / "rtl/cpu/v60/s32_v60.sv").read_text(encoding="utf-8")
        self.assertIn('"O[29],V60 Fetch,Fast,PCB (Reset);"', top)
        self.assertIn("if (reset) fast_v60_fetch <= ~status[29];", top)
        self.assertIn(".fast_v60(fast_v60_fetch)", top)
        self.assertIn(".fast_ifetch(fast_v60)", core)
        self.assertIn(".clk(clk_sys), .ce(ce_cpu), .rst(rst)", core)
        self.assertIn("FAST_IFETCH && fast_ifetch && fetch_is_rom", cpu)
        self.assertIn("reg        seq_pd_valid;", cpu)
        self.assertIn("function automatic [4:0] exact_need_at", cpu)
        self.assertIn("wire [4:0] pf_high = pf_loop_hint ? 5'd24 : 5'd20", cpu)
        self.assertIn("task automatic complete_ea_now", cpu)
        self.assertIn("pf_fast      <= use_fast_ifetch;", cpu)
        self.assertIn("wire        fetch_ack = pf_fast ? if_ack_i : pf_ack;", cpu)
        self.assertNotIn("cpu_turbo", top)

    def test_sprite_throughput_and_publication_are_shared_by_both_profiles(self) -> None:
        """Busy lists keep two-stage pixels and never expose an in-flight FB."""
        core = (ROOT / "rtl/s32_core.sv").read_text(encoding="utf-8")
        sprite = (ROOT / "rtl/video/s32_sprite.sv").read_text(encoding="utf-8")
        self.assertIn(".present(vbl_start), .vblank(vbl_end)", core)
        self.assertIn("fb_rd_buf_r <= spr_scan_buf", core)
        self.assertIn("function automatic [1:0] choose_work_buf", sprite)
        self.assertIn("ready_buf <= work_buf", sprite)
        self.assertIn("scan_buf <= ready_buf", sprite)
        self.assertIn("fb_wr_buf <= is_multi32", sprite)
        self.assertNotIn("R_PIXEL_DATA, R_DONE", sprite)
        self.assertIn("pixel_pen8     <= pixrow", sprite)
        self.assertIn("rs <= R_EMIT", sprite)
        for profile in (ROOT / "segas32.qsf",):
            text = profile.read_text(encoding="utf-8")
            self.assertIn('VERILOG_MACRO "S32_PROFILE_STANDARD=1"', text)

    def test_production_osd_has_no_debug_pause_or_aim_override(self) -> None:
        top = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        self.assertNotIn("O[12],Pause", top)
        self.assertNotIn("Analog Aim Invert", top)
        self.assertNotIn("wire pause = status[12]", top)
        self.assertIn(".pause(1'b0)", top)

    def test_every_emitted_mra_routes_to_a_known_profile(self) -> None:
        self.assertEqual(RBF_BY_PARENT, {parent: "segas32" for parent in GAMES})
        seen = set()
        for path in MRA_DIR.glob("*.mra"):
            root = ElementTree.parse(path).getroot()
            parent = root.findtext("parent") or root.findtext("setname")
            if parent not in GAMES:
                continue
            seen.add(parent)
            expected_rbf = RBF_BY_PARENT[parent]
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
        self.assertIn('"h0O[8],Alien 3 Flicker Blend,Off,On;"', text)
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
            "fb_rd_blend_r <= alien3_hud_blend",
            core,
        )
        self.assertIn("dburst <= 8'd128", fb_if)
        self.assertIn(
            "pix_addr(rd_blend_buf_latched, rd_y, 7'd0)", fb_if
        )
        self.assertIn("s32_fb_line_ram line_ram0", fb_if)
        self.assertIn("s32_fb_line_ram line_ram1", fb_if)

    def test_production_video_path_excludes_optional_geometry(self) -> None:
        text = (ROOT / "Arcade-SegaSystem32.sv").read_text(encoding="utf-8")
        files_qip = (ROOT / "files.qip").read_text(encoding="utf-8")
        for removed in (
            '"O[9],CRT Adjust,Off,On;"',
            '"H1O[14:10],CRT H-Size,',
            '"H1O[21:15],CRT H-Position,',
            '"H1O[26:22],CRT V-Shift,',
            "crt_adjust #(",
        ):
            self.assertNotIn(removed, text)
        self.assertIn('"O[28:27],Scale,Normal,V-Integer,HV-Integer;"', text)
        self.assertIn("video_freak s32_video_freak", text)
        self.assertIn("status[28:27]", text)
        self.assertNotIn("SYSTEMVERILOG_FILE rtl/crt_adjust.sv", files_qip)
        for direct in (
            ".VIDEO_ARX (VIDEO_ARX)",
            ".VIDEO_ARY (VIDEO_ARY)",
            "assign CE_PIXEL = ce_pix_core;",
            "assign VGA_HS = core_hs;",
            "assign VGA_VS = core_vs;",
            "assign VGA_DE = ~(core_hb | core_vb);",
        ):
            self.assertIn(direct, text)

    def test_universal_memory_storage_targets_m10k(self) -> None:
        core = (ROOT / "rtl/s32_core.sv").read_text(encoding="utf-8")
        v25 = (ROOT / "rtl/cpu/v25/s32_v25_cpu.sv").read_text(
            encoding="utf-8")
        self.assertIn(
            '(* ramstyle = "M10K, no_rw_check" *) reg [CACHE_WIDTH-1:0] cache_mem',
            core,
        )
        self.assertEqual(v25.count('ram_block_type = "M10K"'), 2)

    def test_default_regressions_do_not_force_retired_mlab_branches(self) -> None:
        for relative in ("verif/run_regression.ps1", "verif/run_regression.sh"):
            runner = (ROOT / relative).read_text(encoding="utf-8")
            for macro in ("S32_JT12_MLAB_SHIFTS", "S32_V25_MLAB_FIFO",
                          "S32_V25_MLAB_EEPROM"):
                self.assertNotIn(macro, runner, relative)

    def test_modelsim_isolates_incompatible_v25_donor_without_losing_gates(self) -> None:
        runner = (ROOT / "verif/run_regression.ps1").read_text(
            encoding="utf-8")
        self.assertIn("function Assert-V25SourceClosure", runner)
        self.assertIn("V25 UNIVERSAL SOURCE CLOSURE: PASS", runner)
        self.assertNotIn("$V25Sources", runner)
        self.assertNotIn('"-mfcu"', runner)
        self.assertIn("ModelSim full-core lint (compatible HLE shape)", runner)
        self.assertIn("-ModelSimBin $ModelSimDirectory", runner)
        for gate in (
            "verif/v25/run_v25_firmware.ps1",
            "verif/v25/run_v25_integration.ps1",
            "verif/v25/run_v25_sdram.ps1",
        ):
            self.assertIn(gate, runner)

    def test_sound_benches_use_the_external_wave_ram_contract(self) -> None:
        runner = (ROOT / "verif/run_regression.ps1").read_text(
            encoding="utf-8")
        self.assertGreaterEqual(
            runner.count("verif/common/s32_wave_ram_model.sv"), 2)
        for name in ("tb_soundsys_z80.sv", "tb_soundsys_shared.sv"):
            bench = (ROOT / "verif/common" / name).read_text(encoding="utf-8")
            self.assertIn("s32_wave_ram_model wave_mem", bench, name)
            self.assertIn(".wave_rd_req(wave_rd_req)", bench, name)
            self.assertIn(".wave_wr_req(wave_wr_req)", bench, name)
            self.assertNotIn("dut.rf5c68.wave_ram", bench, name)

    def test_real_v25_runners_use_native_safe_build_run_handoff(self) -> None:
        for stem, marker in (
            ("integration", "V25_INTEGRATION"),
            ("sdram", "V25_SDRAM"),
        ):
            ps1 = (ROOT / "verif/v25" / f"run_v25_{stem}.ps1").read_text(
                encoding="utf-8")
            shell = (ROOT / "verif/v25" / f"run_v25_{stem}.sh").read_text(
                encoding="utf-8")
            self.assertIn(r"C:\msys64\usr\bin\bash.exe", ps1)
            self.assertNotIn("& wsl", ps1)
            self.assertIn("$env:S32_V25_BUILD_ONLY = '1'", ps1)
            self.assertIn("& $safeSimulator -- $firmwareExe", ps1)
            self.assertIn("-CFLAGS -D_GLIBCXX_USE_CXX11_ABI=0", shell)
            self.assertIn(f"{marker} EXE:", shell)
            self.assertIn(f"{marker} BUILD DIR:", shell)

    def test_sprite_srom_verification_uses_real_v25_descriptor_scope(self) -> None:
        core = (ROOT / "rtl/s32_core.sv").read_text(encoding="utf-8")
        self.assertIn(".VERIFY_SROM(1'b1)", core)
        self.assertIn(
            ".verify_srom(cfg_has_v25 && !cfg_v25_table)", core)
        self.assertNotIn(".verify_srom(!cfg_v25_table)", core)
        selected = {
            parent for parent, descriptor in GAMES.items()
            if (descriptor[0] & 0x02) and not (descriptor[0] & 0x04)
        }
        self.assertEqual(selected, {"ga2"})

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
        self.assertIn("if (GAME_ONLY && !GAME_ONLY_STD) begin : g_game_no_brival", core)
        self.assertNotIn("s32_arescue_dsp dsp (", core)
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
