# Sega System 32 for MiSTer FPGA

MiSTer FPGA core for Sega's standard single-screen System 32 arcade board
(837-7428 / 171-5964E). It targets the DE10-Nano with SDRAM and uses one
universal `Arcade-SegaSystem32.rbf`; each MRA selects the required game
hardware, including the real NEC V25 path for Arabian Fight and Golden Axe II.

Commercial ROMs are not included. Multi 32 and AS-1 hardware are not supported.

## Features in the OSD

- Original 4:3 or full-screen aspect ratio
- Normal, vertical-integer, or full-integer scaling
- Optional CRT 25%, 50%, and 75% scandoubler effects
- CRT horizontal size/position and vertical-shift controls for 15 kHz output
- Persistent 128-byte 93C46 high-score/settings storage
- Service mode and reset
- Per-game remappable controls defined by each MRA

## PCB Accuracy

This table lists only areas supported by schematics or silicon evidence. It
defines the implemented hardware boundary, not a blanket cycle-accuracy claim.
Open timing, analogue, PLD, and protection questions are tracked in the
[PCB evidence ledger](docs/pcb/system32_evidence.json).

| Area | Evidence | Core implementation |
| --- | --- | --- |
| Board and clocks | Sega schematics 171-5964D / 171-5965C | Standard single-screen board; V60, Z80/YM3438, and PCM domains |
| Main CPU/controller | Schematics, sheet 1 | 16-bit V60 bus, interrupts, timers, and system control |
| Scroll hardware | Schematics, sheet 2; Sega 315-5387 | Four tilemap layers and dual-port VRAM |
| Objects/frame memory | Schematics, sheets 3-4; Sega 315-5386 | Object processing and double-buffered framebuffer |
| Colour/video output | Schematics, sheet 5; [315-5242 silicon evidence](https://github.com/furrtek/SiliconRE/tree/master/Sega/315-5242) | Palette, priority, shadow/highlight, and RGB output |
| I/O, EEPROM, and sound | Schematics, sheets 6-8 | 315-5296 I/O, 93C46 storage, Z80, dual YM3438, and PCM |

See [hardware references](docs/references.md) for the schematic provenance and
detailed source record.

## Supported games

The 24 tracked MRA variants use the same universal RBF:

- **Arabian Fight:** World, US, Japan
- **Dark Edge:** World, Japan
- **Golden Axe: The Revenge of Death Adder:** World Rev B, US Rev A, Japan
- **Holosseum:** US Rev A
- **Rad Mobile:** World, US
- **Rad Rally:** World, US, Japan
- **Slip Stream:** Brazil, Hispanic
- **Spider-Man: The Videogame:** World, US Rev A, Japan
- **Super Visual Football / Soccer:** European, European Rev A, US Rev A
- **The J.League 1994:** Japan, Japan Rev A

Alien3: The Gun, Burning Rival, Jurassic Park, SegaSonic The Hedgehog, Hard
Dunk, OutRunners, Stadium Cross, Title Fight, AS-1, and other Multi 32 games
remain outside the production profile.

## **Hardware emulated**

| Chip or subsystem | Interface | Implementation / reference |
| --- | --- | --- |
| NEC µPD70616 V60 | ~16.108 MHz, 16-bit data / 24-bit address bus | [`s32_v60.sv`](rtl/cpu/v60/s32_v60.sv), [`s32_v60_bus.sv`](rtl/cpu/v60/s32_v60_bus.sv) |
| Sega 315-5385 controller | V60 registers, IRQs, timers | [`s32_io.sv`](rtl/io/s32_io.sv); schematics and MAME behaviour |
| Sega 315-5386 objects | Object RAM and framebuffer | [`s32_sprite.sv`](rtl/video/s32_sprite.sv); schematic sheets 3-4 |
| Sega 315-5387 scroll | Tilemap VRAM and registers | [`s32_tilemap.sv`](rtl/video/s32_tilemap.sv); schematic sheet 2 |
| Sega 315-5388 / 315-5242 video | Palette, priority, RGB | [`s32_mixer.sv`](rtl/video/s32_mixer.sv); schematic and silicon evidence |
| Sega 315-5296 I/O | JAMMA, DIP, service, coin | [`s32_io.sv`](rtl/io/s32_io.sv); schematic sheet 6 |
| BR93C46 EEPROM | Serial NVRAM | `s32_io.sv`; MiSTer NVRAM upload/download |
| MSM6253 ADC / 8255 PPI | Driving and parallel I/O | Descriptor-selected interfaces in `s32_io.sv` |
| NEC V25 protection | Program/cache and mailbox RAM | [`s32_v25_cpu.sv`](rtl/cpu/v25/s32_v25_cpu.sv); [s80x86 provenance](rtl/cpu/v25/s80x86/README.system32.md) |
| Z80 sound CPU | ~8.054 MHz | [`s32_soundsys.sv`](rtl/audio/s32_soundsys.sv); vendored [`T80`](rtl/audio/T80/) |
| 2 × YM3438 | Z80 register bus | [`JT12`](rtl/audio/jt12/) |
| RF5C68-family PCM | ~12.5 MHz, wave RAM | [`s32_rf5c68.sv`](rtl/audio/s32_rf5c68.sv) |
| MiSTer memory services | HPS download, SDRAM, DDR3 | [`Arcade-SegaSystem32.sv`](Arcade-SegaSystem32.sv), [`sys/`](sys/) |

## Credits

- **Meathax** - System 32 RTL, integration, MRA generation, verification, and packaging.
- **Sega, Nemesis1207, and System 32 researchers** - original hardware and
  public schematic material recorded in [the source ledger](docs/references.md).
- **MAME developers** - [System 32 behavioural reference](https://github.com/mamedev/mame).
- **Jamie Iles** - [s80x86](https://github.com/jamieiles/80x86), used by the
  V25 wrapper; pin and licence details are retained with the source.
- **Jose Tejada Gomez / Jotego** - [JT12](https://github.com/jotego/jt12),
  [JT8255](https://github.com/jotego/jt8255/tree/3bb5f7ea461fc7d72b847ec55ce997e5d5bc1754),
  and audited [JTCORES](https://github.com/jotego/jtcores/tree/1268a90e365c2520b412f224ae30d20c61aa0031)
  reference work.
- **Daniel Wallner, MikeJ, Mike Johnson, TobiFlex, Sean Riddle, and Sorgelig**
  - the vendored T80 Z80 core.
- **furrtek / SiliconRE** - Sega 315-5242 and 315-5385 silicon research.
- **Umberto Parisi (rmonic79) and Andrea Bogazzi (@asturur)** -
  [MiSTer-CRT-Adjust](https://github.com/rmonic79/MiSTer-CRT-Adjust/tree/c682de9f4acc61d8f4c7779efb48149d3baa3a8e).
- **MiSTer-devel and reference-core authors** - MiSTer framework, MRA tooling,
  and the audited S32X, Irem M92, WonderSwan, and MegaCD integration references
  listed in [reference-cores.md](docs/reference-cores.md).
- Intel Quartus, Verilator, Icarus Verilog, ModelSim, and MAME tool authors.

## License

Original core source is licensed under [GNU GPLv3](LICENSE). Vendored
components retain their own terms and notices:

- s80x86: GPLv3 or later ([COPYING](rtl/cpu/v25/s80x86/COPYING))
- JT12: GPLv3 ([LICENSE](rtl/audio/jt12/LICENSE))
- JT8255 conformance reference: MIT ([LICENSE](verif/donors/LICENSE.jt8255))
- T80: BSD-style terms in [`rtl/audio/T80/`](rtl/audio/T80/)
- CRT Adjust: GPLv3 or later; provenance in [`verif/donors/README.md`](verif/donors/README.md)
- SiliconRE material: [SiliconRE licence](docs/references/siliconre/315-5385/SiliconRE-LICENSE)
- MiSTer framework and Intel/Altera IP: retained upstream/vendor notices

Linked reference projects and arcade ROMs remain under their respective terms.

## How to install

Copy `Arcade-SegaSystem32.rbf` and the MRA files to `/media/fat/_Arcade/`.
Place the required MAME ROM ZIPs in `/media/fat/games/mame/`, then launch a
game from the MiSTer Arcade menu.

For automatic installation, add this to `/media/fat/downloader.ini` and run
**Update All**:

```ini
[meathax/meatcores]
db_url = https://raw.githubusercontent.com/meathax/meatcores/db/downloader_meathax_meatcores.zip
```

## Development

Quartus Prime 17.0.2 Build 602 is the pinned toolchain. Build the universal
profile with `tools/build-segas32.bat`. See [PROFILE_CONTRACT.md](PROFILE_CONTRACT.md)
for profile rules and verification commands.
