import sys
import tempfile
import unittest
from pathlib import Path
from xml.etree import ElementTree

from tools.gen_mra import BUTTONS, GAMES, IGNORED_PARENTS, gen


class BoardDescriptorTests(unittest.TestCase):
    def test_ignored_parents_are_not_profile_descriptors(self) -> None:
        self.assertTrue(IGNORED_PARENTS.isdisjoint(GAMES))

    def test_holo_and_spidman_are_standard_profile_descriptors(self) -> None:
        self.assertEqual(GAMES["holo"][0] & 0x06, 0x00)
        self.assertEqual(GAMES["holo"][0] & 0x20, 0x00)
        self.assertEqual(GAMES["spidman"][0] & 0x20, 0x20)

    def test_supported_standard_games_keep_their_board_features(self) -> None:
        self.assertEqual(GAMES["darkedge"][:3], bytes.fromhex("200003"))
        self.assertEqual(GAMES["radr"][:3], bytes.fromhex("089080"))
        # Rad Mobile: MSM6253 ADC (b0 bit3) + DRIVING analog profile
        # (b1[5:4]=1), no protection, no gear toggle and no comm link -- MAME's
        # init_radm installs only the cabinet lamp/wiper switch outputs.
        self.assertEqual(GAMES["radm"][:3], bytes.fromhex("081000"))
        # Byte 4 is the semantic player-port layout: Rad Mobile leaves P1_A
        # bit0 unused and puts Light/Wiper on bits 1/2 (DIGITAL_RADM = 1).
        self.assertEqual(GAMES["radm"][4], 0x01)

    def test_every_supported_four_player_parent_selects_the_ppi(self) -> None:
        # b0[5] is the descriptor's i8255-present flag.  Keep this list
        # explicit: Arabian Fight and Golden Axe II use the same 4-player
        # board as the ordinary PPI parents even though they also select V25.
        expected = {"arabfgt", "darkedge", "ga2", "spidman"}
        actual = {name for name, descriptor in GAMES.items()
                  if descriptor[0] & 0x20}
        self.assertEqual(actual, expected)


class ButtonMetadataTests(unittest.TestCase):
    def test_ga2_magic_is_attack_plus_jump(self) -> None:
        names, defaults = BUTTONS["ga2"]
        self.assertEqual(names.split(","),
                         ["Attack", "Jump", "-", "-", "-", "-",
                          "Start", "Coin", "Test", "Service", "Pause"])
        self.assertEqual(defaults.split(","),
                         ["A", "B", "Start", "Select", "R", "L", "Y"])

    def test_arabian_fight_has_attack_and_jump_buttons(self) -> None:
        names, defaults = BUTTONS["arabfgt"]
        self.assertEqual(names.split(","),
                         ["Attack", "Jump", "-", "-", "-", "-",
                          "Start", "Coin", "Test", "Service", "Pause"])
        self.assertEqual(defaults.split(","),
                         ["A", "B", "Start", "Select", "R", "L", "Y"])

    def test_spiderman_has_two_action_buttons_and_system_controls(self) -> None:
        names, defaults = BUTTONS["spidman"]
        self.assertEqual(names.split(","),
                         ["Attack", "Jump", "-", "-", "-", "-",
                          "Start", "Coin", "Test", "Service"])
        self.assertEqual(defaults.split(","),
                         ["A", "B", "Start", "Select", "R", "L"])

    def test_holosseum_has_only_light_and_heavy_attack(self) -> None:
        names, defaults = BUTTONS["holo"]
        self.assertEqual(names.split(","),
                         ["Light Attack", "Heavy Attack", "-", "-", "-", "-",
                          "Start", "Coin", "Test", "Service"])
        self.assertEqual(defaults.split(","),
                         ["A", "B", "Start", "Select", "R", "L"])

    def test_dark_edge_names_actions_and_assigns_jump_to_last_default_button(self) -> None:
        names, defaults = BUTTONS["darkedge"]
        self.assertEqual(names.split(","),
                         ["Light Punch", "Heavy Punch", "Jump",
                          "Light Kick", "Heavy Kick", "-",
                          "Start", "Coin", "Test", "Service"])
        self.assertEqual(defaults.split(","),
                         ["A", "B", "R", "X", "Y", "Start", "Select", "L"])

    def test_rad_mobile_shares_the_driving_pedals_and_adds_light_and_wiper(self) -> None:
        """Rad Mobile matches Rad Rally's pedal layout.

        B1/B2 are the shared digital Accelerate/Brake fallbacks that drive the
        MSM6253 channels; Rad Mobile's Light and Wiper cabinet switches sit on
        B3/B4 so they cannot collide with them.  Rad Mobile has no gear
        selector, which is the only difference from Rad Rally.
        """
        names, defaults = BUTTONS["radm"]
        self.assertEqual(names.split(","),
                         ["Accelerate", "Brake", "Light", "Wiper", "-", "-",
                          "Start", "Coin", "Test", "Service"])
        self.assertEqual(defaults.split(","),
                         ["A", "B", "X", "Y", "Start", "Select", "R", "L"])

    def test_rad_rally_names_its_pedals_and_puts_the_gear_toggle_on_b3(self) -> None:
        """The gear toggle is joystick_0[6] = B3, matching Slip Stream.

        This previously named B1 "Gear Change", but B1 is the accelerator.
        """
        names, defaults = BUTTONS["radr"]
        self.assertEqual(names.split(","),
                         ["Accelerate", "Brake", "Gear Change", "-", "-", "-",
                          "Start", "Coin", "Test", "Service"])
        self.assertEqual(defaults.split(","),
                         ["A", "B", "X", "Start", "Select", "R", "L"])

    def test_promoted_games_keep_cabinet_button_counts(self) -> None:
        expected = {"darkedge": 5, "holo": 2, "radm": 4, "radr": 3}
        for parent, count in expected.items():
            with self.subTest(parent=parent):
                names, _ = BUTTONS[parent]
                self.assertEqual(sum(name != "-" for name in names.split(",")[:6]),
                                 count)

    def test_slip_stream_maps_pedals_and_gear_to_a_b_x(self) -> None:
        names, defaults = BUTTONS["slipstrm"]
        self.assertEqual(names.split(","),
                         ["Accelerate", "Brake", "Gear Change", "-", "-", "-",
                          "Start", "Coin", "Test", "Service"])
        self.assertEqual(defaults.split(","),
                         ["A", "B", "X", "Start", "Select", "R", "L"])


class EepromArchiveSourceTests(unittest.TestCase):
    def generate_radr(self, setname: str, parent: str) -> ElementTree.Element:
        data = {
            "parent": parent,
            "title": f"EEPROM source fixture {setname}",
            "year": "1991",
            "manu": "Sega",
            "regions": [
                {
                    "region": "maincpu", "size": 1,
                    "loads": [{
                        "macro": "ROM_LOAD", "file": "program.bin",
                        "offset": 0, "size": 1, "crc": "00000000",
                    }],
                },
                {
                    "region": "eeprom", "size": 0x80,
                    "loads": [{
                        "macro": "ROM_LOAD16_WORD",
                        "file": "eeprom-radr.ic76",
                        "offset": 0, "size": 0x80, "crc": "602032c6",
                    }],
                },
            ],
        }
        with tempfile.TemporaryDirectory() as tmp:
            self.assertTrue(gen(setname, data, tmp))
            path = next(Path(tmp).glob("*.mra"))
            return ElementTree.parse(path).getroot()

    def test_parent_and_clone_eeprom_roms_name_their_archives(self) -> None:
        for setname, parent, expected_zip in (
            ("radr", "", "radr.zip"),
            ("radru", "radr", "radr.zip|radru.zip"),
        ):
            with self.subTest(setname=setname):
                root = self.generate_radr(setname, parent)
                eeprom = next(
                    rom for rom in root.findall("rom")
                    if rom.attrib["index"] == "2"
                )
                self.assertEqual(eeprom.attrib.get("zip"), expected_zip)
                self.assertEqual(eeprom.attrib.get("md5"), "none")
                self.assertEqual(
                    eeprom.find("part").attrib,
                    {"name": "eeprom-radr.ic76", "crc": "602032c6"},
                )


class OptimizedLayoutTests(unittest.TestCase):
    def test_every_mra_commits_descriptor_after_region_downloads(self) -> None:
        mra_dir = Path(__file__).parents[1] / "mra"
        paths = sorted(mra_dir.glob("*.mra"))
        # Air Rescue is intentionally excluded because its second PCB is not
        # part of the production core.
        self.assertEqual(len(paths), 19)
        for path in paths:
            root = ElementTree.parse(path).getroot()
            roms = root.findall("rom")
            indexes = [int(rom.attrib["index"]) for rom in roms]
            self.assertEqual(indexes[-1], 0, path.name)
            self.assertTrue(all(index in {0, 2, 4, 5, 6, 7, 8, 9}
                                for index in indexes), path.name)
            descriptor_rom = roms[-1]
            self.assertNotIn("zip", descriptor_rom.attrib, path.name)
            descriptor = bytes.fromhex(descriptor_rom.findtext("part", ""))
            self.assertEqual(len(descriptor), 64, path.name)
            self.assertTrue(any(index >= 4 for index in indexes), path.name)

    def test_air_rescue_is_not_emitted(self) -> None:
        names = {path.name for path in (Path(__file__).parents[1] / "mra").glob("*.mra")}
        self.assertFalse(any("Air Rescue" in name for name in names))

    def test_rad_mobile_ships_both_regions_with_the_radm_port_layout(self) -> None:
        mra_dir = Path(__file__).parents[1] / "mra"
        paths = sorted(mra_dir.glob("Rad Mobile*.mra"))
        self.assertEqual([path.name for path in paths],
                         ["Rad Mobile (US).mra", "Rad Mobile (World).mra"])
        for path in paths:
            root = ElementTree.parse(path).getroot()
            descriptor = bytes.fromhex(root.findall("rom")[-1].findtext("part", ""))
            self.assertEqual(descriptor[0] & 0x08, 0x08, path.name)   # ADC
            self.assertEqual((descriptor[1] >> 4) & 0x03, 0x01, path.name)
            self.assertEqual(descriptor[2], 0x00, path.name)          # no prot
            self.assertEqual(descriptor[4], 0x01, path.name)          # RADM
            # Both sets ship the factory 93C46 image as the index-2 default.
            eeprom = [rom for rom in root.findall("rom")
                      if rom.attrib["index"] == "2"]
            self.assertEqual(len(eeprom), 1, path.name)
            self.assertEqual(eeprom[0].find("part").attrib["name"],
                             "eeprom-radm.ic76", path.name)

    def test_rad_rally_uses_behavioral_link_without_diagnostic_firmware(self) -> None:
        for path in (Path(__file__).parents[1] / "mra").glob("Rad Rally*.mra"):
            root = ElementTree.parse(path).getroot()
            roms = root.findall("rom")
            indexes = [int(rom.attrib["index"]) for rom in roms]
            self.assertNotIn(13, indexes, path.name)
            self.assertNotIn(14, indexes, path.name)
            self.assertEqual(indexes[-1], 0, path.name)


class RegenerationFidelityTests(unittest.TestCase):
    """The tracked MRAs must be exactly what gen_mra.py emits today.

    Drift here is silent and lossy: a regeneration overwrites hand-carried
    metadata with whatever the generator tables happen to say.  That is how the
    ga2 Pause mapping was lost -- BUTTONS["ga2"] omitted it while the three
    tracked MRAs shipped it, so any regeneration would have dropped a working
    control with no error.  Skipped when the MAME source is absent (it is
    reference material, not tracked).
    """

    MAME_SRC = (Path(__file__).parents[1] / "reference" / "ga2-cycle-accuracy" /
                "07_emulator_sources" / "mame_current" / "src" / "mame" /
                "sega" / "segas32.cpp")

    def test_ga2_mras_keep_the_pause_mapping(self) -> None:
        names, defaults = BUTTONS["ga2"]
        self.assertEqual(names.split(",")[-1], "Pause")
        self.assertEqual(defaults.split(",")[-1], "Y")
        mra_dir = Path(__file__).parents[1] / "mra"
        paths = sorted(mra_dir.glob("Golden Axe*.mra"))
        self.assertEqual(len(paths), 3)
        for path in paths:
            buttons = ElementTree.parse(path).getroot().find("buttons")
            self.assertIsNotNone(buttons, path.name)
            self.assertEqual(buttons.attrib["names"], names, path.name)
            self.assertEqual(buttons.attrib["default"], defaults, path.name)

    def test_generator_reproduces_every_tracked_mra(self) -> None:
        if not self.MAME_SRC.is_file():
            self.skipTest(f"MAME reference source not present: {self.MAME_SRC}")
        import subprocess, tempfile
        repo = Path(__file__).parents[1]
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(
                [sys.executable, str(repo / "tools" / "gen_mra.py"),
                 str(self.MAME_SRC), tmp],
                 check=True, capture_output=True)
            generated = sorted(Path(tmp).glob("*.mra"))
            for mra_dir in (repo / "mra", repo / "releases"):
                tracked = sorted(mra_dir.glob("*.mra"))
                self.assertEqual([p.name for p in generated],
                                 [p.name for p in tracked],
                                 str(mra_dir))
                for want, got in zip(tracked, generated):
                    # Compare text, not bytes: the tracked files carry CRLF
                    # from git's autocrlf checkout while the generator emits
                    # LF.
                    self.assertEqual(
                        want.read_text(encoding="utf-8").splitlines(),
                        got.read_text(encoding="utf-8").splitlines(),
                        want.name,
                    )


class Multi32ExclusionTests(unittest.TestCase):
    """This repository is System 32 only.

    Every shipped Quartus revision sets S32_SYSTEM32_ONLY=1, which folds
    is_multi32 to a constant and removes the second palette, the second mixer,
    the MultiPCM path and half of work RAM.  A Multi 32 MRA therefore
    advertises a game no RBF built here can run.  These tests fail if one is
    reintroduced by either surface: the generator table or the tracked MRAs.
    """

    MULTI32_PARENTS = ("harddunk", "orunners", "scross", "titlef")

    def test_generator_defines_no_multi32_set(self) -> None:
        for parent in self.MULTI32_PARENTS:
            self.assertNotIn(parent, GAMES)

    def test_no_game_descriptor_sets_the_multi32_bit(self) -> None:
        # b0 bit0 is the multi32 flag the RTL parses out of the index-0
        # descriptor.  No emitted set may assert it.
        for name, descriptor in GAMES.items():
            self.assertEqual(descriptor[0] & 0x01, 0x00, name)

    def test_no_tracked_mra_carries_a_multi32_descriptor(self) -> None:
        mra_dir = Path(__file__).parents[1] / "mra"
        paths = sorted(mra_dir.glob("*.mra"))
        self.assertTrue(paths)
        for path in paths:
            root = ElementTree.parse(path).getroot()
            setname = root.findtext("setname", "")
            self.assertNotIn(setname, self.MULTI32_PARENTS, path.name)
            descriptor = bytes.fromhex(root.findall("rom")[-1].findtext("part", ""))
            self.assertEqual(descriptor[0] & 0x01, 0x00, path.name)

    def test_no_mra_targets_a_multi32_rbf(self) -> None:
        mra_dir = Path(__file__).parents[1] / "mra"
        for path in sorted(mra_dir.glob("*.mra")):
            rbf = ElementTree.parse(path).getroot().findtext("rbf", "")
            self.assertNotIn("Multi32", rbf, path.name)
            self.assertNotIn("OutRunners", rbf, path.name)


if __name__ == "__main__":
    unittest.main()
