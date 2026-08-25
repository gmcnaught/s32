# NEC V60 / V70 — document catalogue

What exists, what does not, and how far each source can actually carry a
cycle-accurate V60. Compiled 2026-08-24 during the audit of this repository's
CPU core; moved into the tree so provenance stops living only in a chat
artifact.

Companion documents, both published Artifacts:

- **V60 Cycle-Accuracy Audit** — the RTL audit this stack is executing
  <https://claude.ai/code/artifact/15803301-746e-4ae5-aebc-f0de73b2b6c5>
- **V60 Source Ledger** — the survey this file is drawn from
  <https://claude.ai/code/artifact/70fbfecf-c257-4221-b8ce-194656dc3775>

**The files themselves are not in this repository.** They are NEC's
copyrighted scans and this repository is public. They belong in
`docs/reference/`, which is gitignored; see that directory's README. Cite by
document and section in code comments, the way `rtl/cpu/v60/s32_v60_bus.sv`
and `s32_v60_timebase.sv` already cite "databook §4".

## The shape of the problem

| | Status |
|---|---|
| **External bus** | **Fully specified.** The 1986 databook gives all seven bus states, both cycle modes, wait, hold, error, freeze and ~30 AC parameters. |
| **Internal timing** | **Not published.** The instruction summary has a "Clocks" column and every cell in it is blank — verified across all nine pages. No public NEC document gives per-instruction cycle counts. |
| **V70 (µPD70632)** | **No public datasheet**, in any language. AC characteristics appear not to be in circulation at all. |

That split is why this project can become bus-cycle-accurate from documents
alone, and cannot become cycle-accurate from documents alone.

## Recovered

### µPD70616 (V60) data sheet & design guide, 1986
`NEC_uPD70616_V60_DataBook_1986.pdf` · 73 pp · databook pp. 3.229–3.301

The one document that matters most, and the only public source for the V60's
external electrical and bus-timing specification. Extracted from the 335 MB
scan of the *NEC Microprocessor and Peripherals Data Book, 1986*.

- **§1 Design Information** — pin-function prose for ST2–ST0, MRQ, R/W, BCY,
  DS, FAS, UBE, DL1–DL0, BLOCK/MSMAT, BMODE, READY, BERR, RT/EP, BFREZ, INT,
  NMI, CPBUSY, HLDRQ, HLDAK; the UBE/A0 byte-lane decode; and the full
  **MRQ + ST2–ST0 bus-status encoding**, including string mode, demand-mode
  fetch, machine-fault acknowledge and halt acknowledge.
- **Electricals** — absolute maximums, DC characteristics (VOH 2.4 V @ −400 µA,
  VOL 0.45 V @ 3.2 mA, IDD 400 mA @ 12 MHz, 100 pF load), capacitance, and ~30
  named AC parameters. *Caveat:* several Min/Max cells read **TBD** in this
  preliminary edition, notably `tCYK` and the clock high/low widths.
- **§2 Pipeline Operation** — the six units, the four-stage occupancy table,
  the 16-byte prefetch queue, the 3-entry decoded-instruction queue, the
  16-entry TLB, and the PFU's lowest-priority bus status.
- **§4 Bus Operation** — seven states with a transition diagram; BMODE sampled
  on the **falling edge of T2** (T3 skipped, READY ignored); READY sampled on
  the **falling edge of T3 and of each TW**; reset held ≥ 20 clocks; **three TI
  states auto-inserted between back-to-back I/O cycles**; HLDRQ sampled on the
  rising edge in T4 or TI, buses tri-stated on the rising edge of TH, HLDAK a
  half-clock later, exit through TI.
- **Timing waveform plates** — clock, reset, async input, read, write, bus
  error, bus hold, bus freeze, FRM/MSMAT.

A grep-able OCR extract ships as `uPD70616_databook_1986_OCR.txt`. **Good
enough to search; not good enough to trust for numbers — read the plates.**

### V60 Programmer's Reference Manual, Nov 1986
`NEC_V60_ProgrammersRef_1986.pdf` · 308 pp · searchable text layer

The full architectural spec: data types, register set, address spaces with
two-level area/page translation and ATE/PTE formats, task management and
context switching, all seven instruction formats and 21 addressing modes,
interrupts and exceptions with the system base table and every stack frame
layout, software debug (trace, breakpoints, address traps), V20/V30 emulation
mode, and the Functional Redundancy Monitor.

No bus timing and no electricals — that is what the databook is for. Its value
here is as the reference against which this core's MAME-derived instruction
semantics should be audited.

Use the archive item's `_text.pdf` derivative: same page images but with a real
OCR text layer. **The plain `NEC_V60pgmRef.pdf` is image-only — do not use it.**
A flat dump ships as `V60_ProgrammersRef_1986_text.txt`.

### µPD71611 clock generator · µPD71613 system bus controller
`NEC_uPD71611_ClockGen_V60_1986.pdf` · 11 pp
`NEC_uPD71613_SystemBusController_V60_1986.pdf` · 9 pp

The documented companion logic for a V60 system. Neither sits on the System 32
board, but both specify the V60 bus **from the outside**, which is directly
useful for an electrically correct BIU.

- **71611** — 32 MHz crystal ÷2 → 16 MHz system clock, Schmitt-trigger reset
  synchroniser, and a programmable wait-state generator (WAIT2–0 decoded to a
  wait count, triggered off the CPU's BCY), synchronous and asynchronous
  sources. DC + AC characteristics and four pages of waveforms.
- **71613** — decodes ST2–ST0 + MRQ + R/W qualified by BCY into MEMR/MEMW,
  IOR/IOW, coprocessor R/W and a separate interrupt-acknowledge strobe, plus
  buffer enable/direction. Its **Table 1 is a complete command-output state
  table** covering string-mode memory write, memory write with short bus cycle,
  translation-table write and system base table access — a decode of every bus
  status code the CPU can emit.

### µPD70616 short-form data sheet, 1987
`NEC_uPD70616_ShortForm_PGA_Pinout_1987.pdf` · 4 pp

From *1987 NEC Microcomputer Products Vol. 2* (bitsavers). One advantage over
the 1986 databook: its symbol → PGA-coordinate table OCRs cleanly (GND→F2,
BMODE→K3, A18→L10 …), where the 1986 book renders the same information as a
dot-matrix graphic. Vol. 1 has zero hits for 70616.

## Does not exist publicly

### µPD70632 (V70) data sheet or hardware manual

No public copy located, in any language. The one PDF that used to exist —
`mess.redump.net/_media/datasheets/nec/upd70632_v70.pdf`, reported to hold
signal descriptions and memory-access timing diagrams but no pinout and no AC
specs — is gone; the host is dead.

**A Wayback copy may survive. That check is the single highest-value lead left
and it needs a browser** — `web.archive.org` was blocked from the environment
the survey was run in.

The best living source is a Japanese hobbyist building a V70 board:
「V70 μPD70632 に挑む」, むらたのおと, 2025. He obtained NEC internal documents
(pinout, signal roles, timing scans) privately via X from an account called
"parsec den", and reports that **AC characteristics are unavailable even in
those**, forcing him to clock the part conservatively. Independent confirmation
that V70 timing is not in circulation.

Partial corroboration of the signal set comes from HP's 64758 in-circuit
emulator manuals on archive.org: 132-pin PGA, 20 MHz internal, 8–20 MHz target
clock with no wait states, and independent configuration for /READY, /BERR,
BFREZ, RT/EP, /NMI, INT, /HLDRQ. No AC/DC appendix, no waveforms.

NDL returns zero results for µPD70616. Every datasheet aggregator —
datasheetarchive, datasheetq, datasheetbank, searchdatasheet, ic37 — resolves
to the same one-line entry in NEC's *Semiconductor Selection Guide 1995*.
**Don't chase them.** Since `IS_V70` is already an unused parameter and System
32 is V60-only, the practical call is to leave V70 out of scope until a
datasheet surfaces.

### A usable die shot

`NEC_V60_die.jpg` is 905 × 900 px — about 0.8 megapixels for a 375,000-
transistor, 1.5 µm chip. That resolves floorplan blocks and nothing else.
Gate-level extraction at this die size needs a multi-gigapixel mosaic,
typically 10–50 Gpx at 50–100×, ideally delayered.

"Visual analysis of the die shot" can support floorplan-level reasoning — which
unit sits where, relative microcode-ROM area, datapath width — but **it cannot
yield timing**.

No V60 die-shot analysis or transistor-level RE exists anywhere. furrtek's
SiliconRE covers arcade and console customs only; its single NEC entry is a
Hudson µPD65005 PC-Engine multitap.

## Paywalled — worth buying

- **Kimura, Komoto & Yano, "Implementation of the V60/V70 and its FRM
  function", IEEE Micro 8(2):22–36, Apr 1988.** The design team's own account.
  The single most relevant paper. Xplore 527.
- Yano, Koumoto & Sato, "V60/V70 microprocessor and its systems support
  functions", COMPCON Spring '88, 36–42. Xplore 4824.
- Yamahata et al., 「マイクロプロセッサV60のアーキテクチャ」, IPSJ
  SIG-Microcomputer 43-2, 1987-02-06, and Takahashi & Yano
  「V60/V70アーキテクチャ」, IPSJ SIG, 1988-01-21 — **likely the cheapest route
  to a real pipeline description; IPSJ SIG reports are often free.**
- 可児健二 『Vシリーズマイコン 2』, Maruzen, Apr 1987 — probably the fullest
  Japanese hardware treatment. Print only, second-hand.

**Patents are free and useful.** US5054026A (NEC, Tsubota, priority
1988-08-12) describes FRM master/checker comparison across non-pipelined vs
pipelined bus cycles with ADRS, DATA, DS, BCYST and T1/T2 states. Related:
US5182754A, US5136595, EP0343626A2. A broader NEC 1986–89 sweep for TLB and
bus-unit filings has not been done and would likely yield more.

Note: Nakayama et al., IEEE JSSC 24(5), Oct 1989 is the **µPD72691/72291**, the
V60/V70 FPU — no public datasheet exists for it. The 1986 databook carries the
µPD72191 FPP instead, which is the cancelled V20/V30-family part, **not** the
V60's coprocessor.

## Not obtained

**Sega System 32 schematics, 171-5964D / 171-5965C.** Community scans exist;
the canonical thread is on Arcade-Projects, which returns 403 to automated
fetching and needs a browser and probably a forum account.

For "electrically correct" these are essential and entirely separate from
everything above: they show how Sega actually clocked the V60, generated waits,
and decoded its status lines. This repository's README claims to work from them
across sheets 1–8, but the evidence ledger backing that claim sits in the
unpublished `docs/` tree.

## The gap, stated plainly

With everything above in hand you can build a **bus-cycle-accurate** V60. Full
cycle accuracy is a different problem and the documentation for it does not
exist.

The 1986 databook fully specifies the external interface. That is finite,
well-defined work. But the instruction-set summary in that same databook has a
"Clocks" column and **every cell in it is blank**. The pipeline description is a
page of prose plus a stage-occupancy table, not a hazard and interlock
specification. So internal timing has to come from one of three places:

1. **Measurement on real hardware** — a System 32 board or a bare V60 with a
   logic analyser on the bus. Because the PFU is the lowest-priority bus
   requester and the prefetch queue is 16 bytes, externally-visible bus
   activity is a surprisingly strong observable: **fetch patterns leak pipeline
   state**. This is the most reliable path and the one that would let anyone
   use the phrase "cycle-accurate" honestly.
2. **The IEEE Micro 1988 implementation paper plus the IPSJ Japanese SIG
   reports** — the only written descriptions of the internals by the people who
   built it.
3. **A real die scan**, which does not exist yet at usable resolution.

Note the consequence for this repository's roadmap: audit step §07.6 (dropping
the clk_sys/2 execution overclock) is gated on 1 or 2, and should be named a
research project rather than an implementation step.

## MAME is an architectural oracle, not a temporal one

`src/devices/cpu/v60/v60.cpp` carries the comment
`// Actual cycles / instruction is unknown`. It is an interpreter with guessed
timings and no bus-cycle model.

Good source of instruction semantics. Bad source of instruction timing. That
boundary is exactly where this core sits: its own header declares the
behavioural contract to be MAME's v60 core, which is why it is
instruction-accurate and not cycle-accurate.

## Open items in the RTL that these documents would close

- **`st` (ST2–ST0) in `rtl/cpu/v60/s32_v60_bus.sv` carries this core's own
  codes, not NEC's** — the header says so. Needs databook §1's status encoding
  table. This is the one blocking gap in the T-state work.
- Normal-vs-short cycle selection is implemented from the audit's prose. Needs
  the §4 read/write waveform plates to confirm the sampling instants and T4's
  contents.
- The three-TI I/O recovery is implemented and dormant. Needs §4's statement of
  whether it applies to I/O cycles only or to any back-to-back cycle.
- The ~30 AC parameters, several of them TBD in the preliminary edition, are
  needed before any claim that the BIU is "electrically describable" against a
  µPD71613 decode table.
