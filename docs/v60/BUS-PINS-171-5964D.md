# What System 32 actually connects to the V60's bus pins

Source: **Sega System 32 schematics, 171-5964D / 837-7428, sheet 1 of 9
("MAIN CPU"), dated 1990/7/12**, rev stamp 91.1.-8. The CPU is `IC34`,
labelled on the drawing as **µPD70616 (V60™), 68 Pin PGA**.

The audit's §04 recorded that this core has *no pin-level interface at all* —
zero occurrences of ST2-ST0, MRQ, R/W, BCY, DS, FAS, UBE, DL1-DL0, BLOCK,
BMODE, READY, BERR, RT/EP, BFREZ, CPBUSY, HLDRQ or HLDAK anywhere under
`rtl/cpu/v60/` — and §07.4 asks for them to be exposed "even where System 32
ties them off". This note records *which* are tied off, to what, and which are
live, so that work does not have to guess.

## The table

| pin | on this board | goes to |
| --- | --- | --- |
| `CLK` | driven | `16MA` from sheet 9/9 |
| `RESET` | driven | `RES` from sheet 7/9 |
| `/NMI` | driven | `NMI` from sheet 7/9 |
| `INT` | driven | `VINT` |
| `READY` | driven | `/VWAT` |
| `BMODE` | driven | `BMOD` |
| **`/BLOCK`** | **NOT CONNECTED** | — drawn as an open pin, no net |
| **`DL0`** | **NOT CONNECTED** | — open pin |
| **`DL1`** | **NOT CONNECTED** | — open pin |
| `/HLDRQ` | pulled up 4.7 k; **input from expansion connector C.N. I** | via sheet 9/9, C.N. I pin 4-b |
| `/HLDAK` | driven out, pulled up 4.7 k | `IC38` / `IC51`; also leaves as `/SHLDAK` to C.N. I pin 3-a |
| `/CPBUSY` | **pulled up 4.7 k, inactive** | no driver |
| `/BERR` | **pulled up 4.7 k, inactive** | no driver |
| `RT/EP` | **pulled up 4.7 k, inactive** | no driver |
| `BFREZ` | **pulled DOWN**, `R40` 4.7 k to GND, via 2-pin jumper `JP1` | jumper-selectable |
| `BCY` `/DS` `R/W` `/UBE` `/FAS` `/MRQ` `ST0` `ST1` `ST2` | **all driven out**, pulled up through `RA18`/`RA19` (4.7 k ×2) | `IC38` (315-5325, 128-pin flat) and `IC51` (315-5441, GAL 16V8) |

Pull-up networks on the address and data buses: `RA20`-`RA22` on A0-A23,
`RA24`/`RA25` on D0-D15, all 4.7 k.

## The three things that change what we do

**1. `BLOCK` is a no-connect.** `5e8a244` asserted that "System 32 has no
external arbiter to honour it" and exposed the pin anyway on the grounds that
it makes the core electrically describable. That reasoning now has a source:
the pin is physically unterminated on the board. Exposing it is still correct
and still costs nothing, and no amount of driving it can affect this hardware.
The TASI hazard the interlock was written for is entirely internal, which is
what made the interlock an *internal* hold-off rather than a bus signal.

**2. The status group is real and is consumed.** `ST0`-`ST2`, `MRQ`, `R/W`,
`BCY`, `DS`, `UBE` and `FAS` are not decorative — they leave the CPU and land
on the 315-5325 system controller and the 315-5441 GAL, which is where this
board's chip selects, `VWAT` wait generation and refresh interlock come from.
So §07.4's "expose them even where they are tied off" understates it: on this
board they are the bus decode. Anything claiming to be electrically correct has
to drive them with the right values at the right T-states, not merely export
them.

**3. `HLDRQ` is an expansion input, and on a standard board nothing drives
it.** Sheet 9/9 puts `/HLDRQ` on **C.N. I**, a 48-pin DIN plug connector, pin
4-b, flowing *into* the main board, with the acknowledge leaving as `/SHLDAK`
on pin 3-a. `/VWAT`, `BMOD` and `/UBE` are routed to the same connector. So bus
hold on System 32 is there for a board plugged into C.N. I to take the bus —
and with nothing plugged in, the 4.7 k pull-up on sheet 1/9 holds it inactive
for the life of the machine.

That is a **scope reduction**, not an extra requirement. This core supports the
standard single-screen board only (README: Multi 32 and AS-1 are out of scope),
so a correct model can hold `HLDRQ` deasserted and never enter TH. The pins
should still be exposed, for the same describability reason as `BLOCK`, but
§07.4's TH state has no way to be entered on the hardware this core targets and
does not need to be exercised to claim correctness on it.

`BERR`, `CPBUSY` and `RT/EP` are the ones genuinely tied off inactive, and
`BFREZ` is pulled low through a jumper — so a *correct* model can hold those
three at their inactive levels and treat `BFREZ` as strapped. With `HLDRQ`
added to that list on a bare board, the only V60 inputs that actually move on
this hardware are `CLK`, `RESET`, `/NMI`, `INT`, `READY` (`/VWAT`) and
`BMODE`.

## Caveats

**Corrected 2026-08-25.** The first version of this note said `/HLDRQ` was
driven from sheet 7/9 (SOUND CPU) and that bus hold was therefore live
hardware. That was wrong: the sheet reference beside the pin is smudged on the
scan, and sheet 7/9 carries no such signal — what it has is `ZBRQ`/`ZBAK` into
the *Z80's* `BUSRQ`/`BUSAK`, which is a different bus. Sheet 9/9 has the real
answer, above.

Pin designators (`E11`, `B2`, `D11`, …) are read off a hand-lettered 1990 scan
at high magnification and are the least reliable thing here; the *signal*
facts — connected / pulled up / pulled down / open — are legible and are what
the table is for. Verify a pin number against the scan before wiring anything
to it.

This is the single-screen board only. The ADC referenced by `sel_adc` in
`s32_core.sv` is **not on these sheets** — sheet 6/9 ("INPUT/OUTPUT") carries
`IC6` = 315-5296 with its own separate `/RD`, `/WR` and `/CS` pins, the 93C46
(`BR93C46AP`), the JAMMA edge and the player wiring, and no converter. The ADC
lives on an I/O extension board, consistent with `cfg_has_adc` gating it. So
the open question about whether the ADC's chip select should assert on reads is
**not answered by this document** and needs the extension-board drawing.

## Provenance

Retrieved 2026-08-25 from
`https://jammarcade.net/images/2026/02/System-32-Schematics.pdf`
— 11 pages, 7.26 MB, scanned images with no text layer, every page `/Rotate 270`.

Sheet index:

| page | drawing | sheet |
| --- | --- | --- |
| 1-2 | 171-5965C / 837-7429 | ROM BOARD 1, ROM BOARD 2 |
| 3 | 171-5964D / 837-7428 | MAIN CPU 1/9 |
| 4 | | SCROLL 2/9 |
| 5 | | OBJECT 3/9 |
| 6 | | FRAME MEMORY 4/9 |
| 7 | | COLOR/PRIORITY 5/9 |
| 8 | | INPUT/OUTPUT 6/9 |
| 9 | | SOUND CPU 7/9 |
| 10 | | PCM SOUND 8/9 |
| 11 | | CONNECTOR 9/9 |

These are the exact drawing numbers the README's PCB Accuracy table cites, and
the ones `mem:v60-cycle-accuracy-audit` records as essential but unfetchable
(Arcade-Projects 403s automated requests). The PDF itself is **not** vendored
into this repository — that is a redistribution decision, not a technical one.
