import sys
import unittest
from pathlib import Path
from xml.etree import ElementTree

from tools.gen_mra import BUTTONS, GAMES, IGNORED_PARENTS


class BoardDescriptorTests(unittest.TestCase):
    # 2026-08-05: holo/jpark/radm/radr/spidman moved to IGNORED_PARENTS (see
    # memory s32-single-profile-roadmap) -- descriptor tests specific to those
    # games (ADC/gun/digital-profile/gear-toggle/comm-link-HLE encoding) were
    # removed here, not adapted, since the games themselves are out of scope
    # for this RBF. Restore alongside whichever game returns first.
    def test_ignored_parents_are_not_profile_descriptors(self) -> None:
        self.assertTrue(IGNORED_PARENTS.isdisjoint(GAMES))


class ButtonMetadataTests(unittest.TestCase):
    # 2026-08-05: radm/spidman/sonic button-metadata tests removed alongside
    # the games themselves (see BoardDescriptorTests note above).
    pass


class OptimizedLayoutTests(unittest.TestCase):
    def test_every_mra_commits_descriptor_after_region_downloads(self) -> None:
        mra_dir = Path(__file__).parents[1] / "mra"
        paths = sorted(mra_dir.glob("*.mra"))
        self.assertEqual(len(paths), 6)
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
        tracked = sorted((repo / "mra").glob("*.mra"))
        with tempfile.TemporaryDirectory() as tmp:
            subprocess.run(
                [sys.executable, str(repo / "tools" / "gen_mra.py"),
                 str(self.MAME_SRC), tmp],
                check=True, capture_output=True)
            generated = sorted(Path(tmp).glob("*.mra"))
            self.assertEqual([p.name for p in generated],
                             [p.name for p in tracked])
            for want, got in zip(tracked, generated):
                # Compare text, not bytes: the tracked files carry CRLF from
                # git's autocrlf checkout while the generator emits LF.
                self.assertEqual(want.read_text(encoding="utf-8").splitlines(),
                                 got.read_text(encoding="utf-8").splitlines(),
                                 want.name)


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
