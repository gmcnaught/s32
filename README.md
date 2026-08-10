Built cores are available for free at https://www.patreon.com/cw/Meathax

# Sega System 32 for MiSTer FPGA

This is the Sega System 32 arcade core for MiSTer FPGA.

| Item | Hardware |
| --- | --- |
| Core title | Sega System 32 |
| Original arcade board | Sega System 32 standard single-screen PCB, 837-7428 / 171-5964E |
| FPGA target | MiSTer DE10-Nano (Cyclone V) with SDRAM expansion |
| Production profiles | `segas32.rbf` and `segas32v25.rbf` |

This is an open, source-first FPGA recreation of Sega's System 32 hardware
(1990–1994). It does not distribute commercial arcade ROMs. The project is
still a work in progress.

**System 32 only — Multi 32 is not supported.** The production revisions
compile with `S32_SYSTEM32_ONLY=1`; Hard Dunk, OutRunners, Stadium Cross,
Title Fight and AS-1 are outside the supported target and have no production
MRA or RBF here.

## Features in the OSD

| OSD option | Choices / function |
| --- | --- |
| Aspect ratio | Original, Full Screen |
| Scandoubler Fx | None, CRT 25%, CRT 50%, CRT 75% |
| Service Mode | Off / On |
| Alien 3 Flicker Blend | Off / On; combines its alternating HUD and gun-sight sprite fields; shown for Alien3: The Gun only |
| V60 Fetch | PCB / Fast (Reset); optional reset-latched wide ROM instruction-cache fetch while RAM code, data and I/O retain authentic bus timing |
| Scale | Normal, V-Integer, HV-Integer |
| CRT Adjust | Off / On; enables the CRT geometry controls below |
| CRT H-Size | Horizontal stretch/squeeze from `-16` to `+15` |
| CRT H-Position | Horizontal image position from `-48` to `+48` |
| CRT V-Shift | Vertical image shift from `-16` to `+15` lines |
| Reset | Resets the running core |

The CRT controls change the picture geometry while keeping the native sync
signals stable. The Multi 32 screen selector is not included because this
repository builds System 32 profiles only.

## Compatibility

The following is the current development status. A check mark means the title
is currently working on the target MiSTer setup; it is not a claim of complete
PCB or gameplay certification.

| Game | Status |
| --- | --- |
| Holosseum | ✓ |
| Spider-Man: The Videogame | ✓ |
| Slip Stream | ✗ |
| Alien3: The Gun | ✗ |
| Air Rescue | ✗ |
| Burning Rival | ✗ |
| Dark Edge | ✗ |
| Golden Axe: The Revenge of Death Adder | ✓ |
| Arabian Fight | ✗ |
| Jurassic Park | ✗ |
| Rad Rally | ✗ |
| SegaSonic The Hedgehog | ✗ |

## PCB Accuracy

The following areas are based on the documented System 32 PCB schematics and
board research recorded in `docs/references.md` and `docs/pcb/`.

| PCB area | Evidence-backed implementation |
| --- | --- |
| Board identity and clock plan | Standard single-screen 837-7428 / 171-5964E board; approximately 16.108 MHz V60, 8.054 MHz Z80/YM3438 and 12.5 MHz PCM clock rates |
| Main CPU bus | NEC µPD70616 V60 with a 16-bit external data bus and 24-bit address bus |
| System controller | Sega 315-5385 address mapping, interrupt controller and timer block |
| Object hardware | Sega 315-5386A sprite/object engine with dedicated sprite RAM and framebuffer rendering |
| Scroll hardware | Sega 315-5387 tilemap engine with four scrolling layers and associated dual-port video RAM |
| Color and priority hardware | Sega 315-5388 frame-memory, color, priority and mixing stage with palette SRAM |
| Video output | Sega 315-5242 digital RGB/DAC boundary |
| Input/output board | Sega 315-5296 I/O, four-bit DIP inputs and JAMMA control wiring |
| EEPROM | BR93C46AP/93C46 serial wiring on the documented 315-5296 port bits |
| Sound board | Z80 sound CPU, 8 KB battery-backed RAM, two YM3438 FM chips, RF5C105/RF5C68-family PCM and PCM RAM |

## Full list of supported games

These are the 12 parent titles emitted by the production MRA generator. Regional
and revision variants are included where the MRA set provides them.

| Game | Production profile | RBF |
| --- | --- | --- |
| Air Rescue | Standard | `segas32.rbf` |
| Alien3: The Gun | Standard | `segas32.rbf` |
| Arabian Fight | Real V25 | `segas32v25.rbf` |
| Burning Rival | Standard | `segas32.rbf` |
| Dark Edge | Standard | `segas32.rbf` |
| Golden Axe: The Revenge of Death Adder | Real V25 | `segas32v25.rbf` |
| Holosseum | Standard | `segas32.rbf` |
| Jurassic Park | Standard | `segas32.rbf` |
| Rad Rally | Standard | `segas32.rbf` |
| SegaSonic The Hedgehog | Standard | `segas32.rbf` |
| Slip Stream | Standard | `segas32.rbf` |
| Spider-Man: The Videogame | Standard | `segas32.rbf` |

Rad Mobile, Multi 32 titles and AS-1 are not part of the current production
profiles, even though related historical research or simulation material may
remain in the repository.

## What the core implements

- System 32 video: four scrolling/zooming tilemap layers, text and bitmap
  layers, a hardware-style sprite list with zoom, priority, blending, fades,
  and 320/416-pixel display modes.
- Audio: Z80 sound CPU, two YM3438-compatible FM channels, and RF5C68-family
  PCM.
- Board devices: 315-5296 I/O, 93C46 EEPROM save/load, MSM6253 gun/analogue
  ADC, µPD4701 trackball counters, 8255 PPI, timers/interrupt controller, and
  the V25 protection path used by Golden Axe II and Arabian Fight.
- MiSTer integration: MRA-based ROM loading, 16-bit HPS transfers, Cyclone V
  SDRAM for ROM regions, and the DE10-Nano DDR3 framebuffer for sprites.

## **Hardware emulated**

| Hardware | Core implementation |
| --- | --- |
| NEC µPD70616 V60 | Synthesizable 32-bit CISC CPU with a 16-bit external bus, interrupts, traps and System 32 instruction coverage |
| NEC V25 protection CPU | Real V25-compatible execution path and program/cache memories in `segas32v25` |
| Sega 315-5385 | System controller, address mapping, interrupt sources and timers |
| Sega 315-5386A | Object/sprite list processing, zoom and sprite framebuffer rendering |
| Sega 315-5387 | Four tilemap layers, scrolling, zoom, row effects, text and bitmap paths |
| Sega 315-5388 / 315-5242 boundary | Palette, priority mixing, shadows, fades, blending and RGB video output |
| Sega 315-5296 | Per-game I/O, cabinet controls, service/test inputs and sound reset control |
| Z80 sound board | Z80 CPU, ROM banking, shared RAM, interrupts and sound command path |
| 2 × YM3438 | FM synthesis channels using the GPL JT12 implementation |
| RF5C68-family PCM | Eight-channel PCM playback, wave RAM, panning, looping and sample-rate timing |
| BR93C46 / 93C46 EEPROM | Serial read, write and erase behavior with MiSTer save/load support |
| MSM6253 ADC | Descriptor-selected gun and analogue controls |
| µPD4701 counters | Descriptor-selected three-channel trackball input for SegaSonic |
| 8255 PPI | Descriptor-selected four-player input hardware |
| Per-game boards | V25 dual-port RAM, dual-PCB communication, Air Rescue DSP responder and descriptor-selected protection responders |

## Credits and source acknowledgements

- **Meathax** — core integration, original System 32 RTL, MRA generator,
  verification and MiSTer packaging.
- **MAME developers** — the `segas32` driver, video, protection, EEPROM, V60,
  RF5C68 and MultiPCM implementations used as the primary behavioral reference:
  [MAME](https://github.com/mamedev/mame).
- **Jamie Iles** — [s80x86](https://github.com/jamieiles/80x86), used as the
  synthesizable CPU engine behind the NEC V25 wrapper. The pinned upstream
  commit and corresponding source are documented in
  `rtl/cpu/v25/s80x86/README.system32.md`.
- **Jose Tejada Gomez / Jotego** — [JT12](https://github.com/jotego/jt12),
  used for the YM3438-compatible FM cores.
- **Daniel Wallner, MikeJ, Mike Johnson, TobiFlex, Sean Riddle and Sorgelig**
  — contributors to the [T80 Z80 core](http://www.opencores.org/cvsweb.shtml/t80/)
  used by the sound board.
- **MiSTer-devel** — [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer),
  MiSTer framework conventions, HPS I/O and MRA integration.
- **Jotego / jtcores**, MiSTer S32X, MiSTer Irem M92 and WonderSwan MiSTer
  contributors — architecture, CPU and memory-arbitration references
  documented in `docs/reference-cores.md` and
  `docs/v25-core-evaluation.md`; their RTL is not copied into this core.
- **MegaCD RF5C164 contributors** — family-compatible PCM implementation
  references for the RF5C68 model, as documented in `docs/DESIGN.md`.
- **mister-devel/mra-tools-c** and MiSTer documentation contributors — MRA
  format and downloader/framework conventions.
- **furrtek / SiliconRE** — silicon reverse-engineering references for the
  Sega 315-5242 and 315-5385 devices:
  [SiliconRE](https://github.com/furrtek/SiliconRE).
- **Sega System 32 schematic researchers**, including the schematics scan
  credited to Nemesis1207, for board-level device and signal references.
- **Umberto Parisi (rmonic79)**, with help from **Andrea Bogazzi (@asturur)**,
  for the GPL CRT Adjust module used by the OSD geometry controls.

## License

The original project source is released under the GNU General Public License
version 3 or later; see [LICENSE](LICENSE). Third-party components retain their
own notices and licenses:

- s80x86: GPL v3 or later, `rtl/cpu/v25/s80x86/COPYING`;
- JT12: GPL v3, `rtl/audio/jt12/LICENSE`;
- T80: permissive BSD-style terms in the source headers under `rtl/audio/T80`;
- CRT Adjust: GPL v3 or later, as stated in `rtl/crt_adjust.sv`;
- SiliconRE material: its accompanying license in
  `docs/references/siliconre/315-5385/SiliconRE-LICENSE`.

MAME and other linked reference projects remain under their respective
licenses. Arcade ROMs are not included and remain the property of their
respective copyright holders.

## How to install

### Manual installation

1. Obtain the matching RBF and the MRA files.
2. Put `segas32.rbf` and `segas32v25.rbf` in `_Arcade/cores/` on the MiSTer
   SD card.
3. Put the MRA files in `_Arcade/`.
4. Install the required matching MAME ROM ZIPs, then launch the title from the
   MiSTer arcade menu.

### Automatic installation with Downloader

Add this entry to `/media/fat/downloader.ini`:

```ini
[meathax/meatcores]
db_url = https://raw.githubusercontent.com/meathax/meatcores/db/downloader_meathax_meatcores.zip
```

Then run **Update All** in Downloader to retrieve the cores and MRAs
automatically.

## Building from source

Quartus Prime Lite 17.0.2 Build 602 is the pinned toolchain. On Windows, point
`QUARTUS_ROOT` at the installation and run the audited build drivers:

```bat
set QUARTUS_ROOT=D:\Q17
tools\build-s32.bat
tools\build-s32v25.bat
```

The build wrapper serializes all Quartus/RBF work on the machine, including
builds from separate worktrees. Keep each queued build in its own project copy
so Quartus databases, generated IP, reports and release staging never overlap.
When a seed becomes a timing best, the build also records per-corner full-path
reports for the game, HDMI pixel and audio clocks.

Useful checks that do not build an RBF are:

```sh
bash verif/run_regression.sh
python -m unittest discover -s verif -p "test_*.py"
```
