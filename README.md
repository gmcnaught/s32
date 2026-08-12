# Sega System 32 for MiSTer FPGA

Sega System 32 arcade core for the MiSTer DE10-Nano. The target is the
standard single-screen System 32 board, using the MiSTer SDRAM expansion and
DDR3 framebuffer path where required.

This repository contains source code, build scripts, verification, and MRA
metadata. Commercial arcade ROMs are not included. Multi 32 and AS-1 are not
supported or emitted by the production profile.

| Item | Value |
| --- | --- |
| Core title | Sega System 32 |
| Target hardware | MiSTer DE10-Nano, Cyclone V, SDRAM expansion |
| Original board | Sega System 32 standard single-screen PCB, 837-7428 / 171-5964E |
| Production RBF | `segas32.rbf` |
| Toolchain | Quartus Prime 17.0.2 Build 602 |

## Profiles

The repository has one universal production profile. Game differences are
selected by the MRA descriptor; no game-specific production macro is used.

| Profile | Production macros | Games | RBF |
| --- | --- | --- | --- |
| `segas32` | `S32_PROFILE_STANDARD=1`, `S32_GAME_ONLY_STD=1`, `S32_UNIVERSAL=1`, `S32_V25_HW=1` | All supported parents; descriptors select the real V25 for `ga2`/`arabfgt` | `segas32.rbf` |

## Features in the OSD

| Option | Choices / function |
| --- | --- |
| Aspect ratio | Original, Full Screen |
| Scandoubler Fx | None, CRT 25%, CRT 50%, CRT 75% |
| Service Mode | Off, On |
| Alien 3 Flicker Blend | Off, On; Alien3: The Gun only |
| V60 Fetch | Fast, PCB (Reset); the setting is latched on reset |
| Scale | Normal, V-Integer, HV-Integer |
| CRT Adjust | Off, On |
| CRT H-Size | `-16` to `+15` |
| CRT H-Position | `-48` to `+48` |
| CRT V-Shift | `-16` to `+15` lines |
| Reset | Resets the running core |

CRT Adjust changes image geometry while keeping the native sync signals
stable. Game controls are remappable through MiSTer input settings; each MRA
declares the button labels and defaults for its game.

## PCB Accuracy

This table is limited to board facts supported by the official System 32
schematic set or silicon reverse-engineering evidence. It documents the
hardware boundary and chip roles, not a universal cycle-accurate claim. The
[PCB evidence ledger](docs/pcb/system32_evidence.json) records the remaining
open timing, analogue, PLD, and protection measurements.

| PCB area | Evidence | Core boundary |
| --- | --- | --- |
| Board identity and clock plan | Sega schematic set 171-5964D / 171-5965C, source scan credited to Nemesis1207 and transcribed in [the reference record](docs/references.md) | Standard single-screen 837-7428 / 171-5964E profile; nominal V60, Z80/YM3438, and PCM clock domains |
| Main CPU and system controller | Official schematics, sheet 1, documented in [the reference record](docs/references.md) | 16-bit V60 external data bus, 24-bit address bus, mapped controller, interrupt, and timer interfaces |
| Scroll hardware | Official schematics, sheet 2; chip role identified as 315-5387 | Four tilemap layers and dual-port video RAM in [`s32_tilemap.sv`](rtl/video/s32_tilemap.sv) |
| Object and frame memory | Official schematics, sheets 3–4; object chip identified as 315-5386 and separate double-buffered frame memory | Sprite/object list processing and framebuffer service in [`s32_sprite.sv`](rtl/video/s32_sprite.sv) |
| Color, priority, and video output | Official schematics, sheet 5; 315-5242/OKI M71064 silicon evidence in [SiliconRE](https://github.com/furrtek/SiliconRE/tree/master/Sega/315-5242) | Digital palette, priority, mixing, shadow/highlight, and RGB output boundary |
| I/O, EEPROM, and sound board inventory | Official schematics, sheets 6–8; EEPROM pin wiring and audio parts are transcribed in [the reference record](docs/references.md) | 315-5296 I/O, BR93C46 serial storage, Z80/YM3438 sound board, and RF5C68-family PCM interfaces |

## Supported games

The following table is the complete set exposed by the tracked MRAs in
[`releases/`](releases/). The names in parentheses are the MAME set names.

| Parent | Supported variants | Profile | RBF |
| --- | --- | --- | --- |
| Alien3: The Gun | Japan (`alien3j`), US, Rev A (`alien3u`), World (`alien3`) | Standard | `segas32.rbf` |
| Arabian Fight | Japan (`arabfgtj`), US (`arabfgtu`), World (`arabfgt`) | Universal / real V25 descriptor path | `segas32.rbf` |
| Burning Rival | Japan (`brivalj`), World (`brival`) | Standard | `segas32.rbf` |
| Dark Edge | Japan (`darkedgej`), World (`darkedge`) | Standard | `segas32.rbf` |
| Golden Axe: The Revenge of Death Adder | Japan (`ga2j`), US, Rev A (`ga2u`), World, Rev B (`ga2`) | Universal / real V25 descriptor path | `segas32.rbf` |
| Holosseum | US, Rev A (`holo`) | Standard | `segas32.rbf` |
| Jurassic Park | Japan, Deluxe (`jparkja`), Japan, Rev A, Conversion (`jparkjc`), Japan, Rev A, Deluxe (`jparkj`), World, Rev A (`jpark`) | Standard | `segas32.rbf` |
| Rad Rally | Japan (`radrj`), US (`radru`), World (`radr`) | Standard | `segas32.rbf` |
| SegaSonic The Hedgehog | Japan, rev. C (`sonic`) | Standard | `segas32.rbf` |
| Slip Stream | Brazil 950515 (`slipstrm`), Hispanic 950515 (`slipstrmh`) | Standard | `segas32.rbf` |
| Spider-Man: The Videogame | Japan (`spidmanj`), US, Rev A (`spidmanu`), World (`spidman`) | Standard | `segas32.rbf` |

Hard Dunk, OutRunners, Stadium Cross, Title Fight, AS-1, and other Multi 32
families are outside the production contract and have no production MRA or
RBF here.

## **Hardware emulated**

| Chip or subsystem | Relevant clock / interface | Implementation and evidence |
| --- | --- | --- |
| NEC µPD70616 V60 | Approximately 16.108 MHz PCB clock; 16-bit data bus and 24-bit address bus | [`s32_v60.sv`](rtl/cpu/v60/s32_v60.sv), [`s32_v60_bus.sv`](rtl/cpu/v60/s32_v60_bus.sv); board interface in [the PCB reference](docs/references.md) |
| Sega 315-5385 controller | V60 memory-mapped 8/16-bit register interface; interrupt and timer sources | [`s32_io.sv`](rtl/io/s32_io.sv); chip role and board placement from schematic sheet 1, with behavior cross-checked against [MAME](https://github.com/mamedev/mame) |
| Sega 315-5386 object hardware | System/video clock; object RAM and framebuffer service | [`s32_sprite.sv`](rtl/video/s32_sprite.sv); object role and RAM topology from schematic sheets 3–4, behavior from [MAME](https://github.com/mamedev/mame) |
| Sega 315-5387 scroll hardware | System/video clock; dual-port tilemap VRAM and mapped scroll registers | [`s32_tilemap.sv`](rtl/video/s32_tilemap.sv); scroll role from schematic sheet 2, behavior from [MAME](https://github.com/mamedev/mame) |
| Sega 315-5388 / 315-5242 video boundary | Pixel path; palette, priority, mixer, and digital RGB output | [`s32_mixer.sv`](rtl/video/s32_mixer.sv) and top-level video path; schematic sheet 5 plus [315-5242 SiliconRE evidence](https://github.com/furrtek/SiliconRE/tree/master/Sega/315-5242) |
| Sega 315-5296 I/O | V60-mapped 8-bit I/O ports; JAMMA, DIP, service, coin, and reset control | [`s32_io.sv`](rtl/io/s32_io.sv); schematic sheet 6 and [the EEPROM/I/O reference](docs/references.md) |
| BR93C46 / 93C46 EEPROM | Serial CS, clock, data-in, and data-out lines on the 315-5296 interface | [`s32_io.sv`](rtl/io/s32_io.sv); schematic sheet 6 and MiSTer NVRAM upload/download support |
| MSM6253 ADC, µPD4701 counters, and 8255 PPI | Descriptor-selected V60-mapped ADC, trackball, and parallel-I/O interfaces | [`s32_io.sv`](rtl/io/s32_io.sv); MAME device maps and per-game MRA descriptors in [`gen_mra.py`](tools/gen_mra.py) |
| NEC V25 protection path | Universal profile; descriptor-selected program/cache and dual-port mailbox RAM | [`s32_v25_cpu.sv`](rtl/cpu/v25/s32_v25_cpu.sv), [`s32_v25_rom_cache.sv`](rtl/cpu/v25/s32_v25_rom_cache.sv), and the pinned [s80x86 provenance record](rtl/cpu/v25/s80x86/README.system32.md) |
| Z80 sound CPU | Approximately 8.054 MHz; ROM, shared RAM, and memory/I/O bus | [`s32_soundsys.sv`](rtl/audio/s32_soundsys.sv) and the vendored [`T80`](rtl/audio/T80/) core; schematic sheets 7–8 |
| 2 × YM3438 FM | Z80 I/O register interface on the sound board | [`JT12`](rtl/audio/jt12/) instances; schematic sheet 8 and [JT12](https://github.com/jotego/jt12) |
| RF5C68-family PCM | Approximately 12.5 MHz PCM clock; Z80-mapped registers and wave RAM | [`s32_rf5c68.sv`](rtl/audio/s32_rf5c68.sv); schematic sheet 8, MAME behavior, and the family reference in [`DESIGN.md`](docs/DESIGN.md) |
| MiSTer ROM, SDRAM, and DDR3 services | HPS ROM/download stream; SDRAM program/data traffic and DDR3 video framebuffer | Top-level [`Arcade-SegaSystem32.sv`](Arcade-SegaSystem32.sv), MiSTer [`sys/`](sys/), and the MRA stream generated by [`gen_mra.py`](tools/gen_mra.py) |

## Credits

- **Meathax** — System 32 integration, authored RTL, profile routing, MRA
  generation, verification, and MiSTer packaging.
- **Sega and the System 32 schematic researchers** — original hardware
  documentation. The public schematic scan is credited to Nemesis1207 in
  [the source record](docs/references.md).
- **MAME developers** — the [MAME System 32 driver and device models](https://github.com/mamedev/mame), used as the primary behavioral reference for CPU, video, protection, EEPROM, and sound behavior.
- **Jamie Iles** — [s80x86](https://github.com/jamieiles/80x86), used by the
  V25 compatibility wrapper; the pinned commit and GPL notice are in
  [`README.system32.md`](rtl/cpu/v25/s80x86/README.system32.md).
- **Jose Tejada Gomez / Jotego** — [JT12](https://github.com/jotego/jt12),
  used for the YM3438-compatible FM implementation.
- **Daniel Wallner, MikeJ, Mike Johnson, TobiFlex, Sean Riddle, and Sorgelig**
  — contributors to the vendored [T80 Z80 core](rtl/audio/T80/); source
  headers retain the original BSD-style notices.
- **furrtek / SiliconRE** — [315-5242](https://github.com/furrtek/SiliconRE/tree/master/Sega/315-5242)
  and 315-5385 silicon reverse-engineering references; the retained license
  is [`SiliconRE-LICENSE`](docs/references/siliconre/315-5385/SiliconRE-LICENSE).
- **MiSTer-devel** — [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer),
  the vendored MiSTer framework, [MRA documentation](https://mister-devel.github.io/MkDocs_MiSTer/developer/mra/),
  and [mra-tools-c](https://github.com/MiSTer-devel/mra-tools-c).
- **Reference core authors** — [S32X_MiSTer](https://github.com/MiSTer-devel/S32X_MiSTer),
  [Arcade-IremM92_MiSTer](https://github.com/MiSTer-devel/Arcade-IremM92_MiSTer),
  [WonderSwan_MiSTer](https://github.com/MiSTer-devel/WonderSwan_MiSTer),
  and the MegaCD RF5C164 implementation, as documented in
  [`reference-cores.md`](docs/reference-cores.md) and [`DESIGN.md`](docs/DESIGN.md).
- **Umberto Parisi (rmonic79), with Andrea Bogazzi (@asturur)** — the GPL CRT
  Adjust module used by the geometry controls.
- **Tool authors and maintainers** — [Intel Quartus](https://www.intel.com/content/www/us/en/software/programmable/quartus-prime/overview.html),
  [Verilator](https://www.veripool.org/verilator/), [Icarus Verilog](https://steveicarus.github.io/iverilog/),
  ModelSim, and MAME, used for synthesis, simulation, and verification.

## License

The original System 32 core source is licensed under GNU GPL version 3; see
[`LICENSE`](LICENSE). The repository is an aggregate containing components
that retain their own notices and licenses:

- s80x86: GNU GPL version 3 or later; [`COPYING`](rtl/cpu/v25/s80x86/COPYING).
- JT12: GNU GPL version 3; [`LICENSE`](rtl/audio/jt12/LICENSE).
- T80: BSD-style terms in the source headers under [`rtl/audio/T80/`](rtl/audio/T80/).
- CRT Adjust: GNU GPL version 3 or later, as stated in [`crt_adjust.sv`](rtl/crt_adjust.sv).
- MiSTer framework and Intel/Altera generated IP under [`sys/`](sys/): retain
  their upstream/vendor notices.
- SiliconRE reference material: [`SiliconRE-LICENSE`](docs/references/siliconre/315-5385/SiliconRE-LICENSE).

MAME, MiSTer reference cores, and other linked projects remain under their
respective licenses. Arcade ROMs are not included and remain the property of
their copyright holders.

## How to install

1. Obtain `segas32.rbf` and the MRA files. It is the universal image for all
   supported parents, including Arabian Fight and Golden Axe II.
2. Copy the RBF file to `/media/fat/_Arcade/` on the MiSTer SD card.
3. Copy the MRA files to the same `/media/fat/_Arcade/` directory. Equivalent
   MiSTer release folders are also supported.
4. Put the required MAME ROM ZIPs in `/media/fat/games/mame/`, then launch the
   game from the MiSTer Arcade menu.

For automatic installation, add this entry to
`/media/fat/downloader.ini`:

```ini
[meathax/meatcores]
db_url = https://raw.githubusercontent.com/meathax/meatcores/db/downloader_meathax_meatcores.zip
```

After adding the entry, run **Update All** to download the cores and MRAs.

## Building and verification

Quartus Prime 17.0.2 Build 602 is the pinned hardware toolchain. Set
`QUARTUS_ROOT` to the installation directory and run the profile wrapper from
the repository root:

```powershell
$env:QUARTUS_ROOT = 'D:\Q17'
.\tools\build-segas32.bat
```

Do not edit or share Quartus generated databases between builds. The wrappers
serializes machine-wide Quartus work and stages only qualified release output.
For source/profile validation, use:

```powershell
python -B -m unittest discover -s verif -p 'test_*.py'
python -B verif/check_ga2_release.py
python -B verif/check_arabianfight_release.py
python -B verif/check_holo_release.py
& .\verif\run_regression.ps1
```
