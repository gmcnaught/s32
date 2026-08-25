# The V70 needs its own bus unit

`s32_v60_bus` is a **V60** bus unit. It is not, and should not become, a
parameterised V60/V70 one. This note records why, so the `IS_V70` parameter
that used to sit in it does not come back.

## What was wrong

`s32_v60_bus` declared `parameter IS_V70` and **never referenced it**. Its
header claimed "V70 (IS_V70=1) uses 1..2 aligned 32-bit cycles"; the body
issued 16-bit cycles unconditionally. Setting the parameter to 1 promised a
32-bit bus and silently delivered a V60 one — worse than not offering it,
because it reads as support.

The parameter is removed. `s32_v60.sv` keeps its own `IS_V70`, which does one
real thing: select the Processor ID Register value (`0x7000` vs `0x6000`).
That is an *architectural* difference and belongs in the core.

## Why one module cannot serve both

The two parts share an architecture — µPD70632 Advance Product Information
p.7: *"The µPD70632 has the same architecture as the µPD70616 (V60)"* — and
share the ST2–ST0 + MRQ + DL1–DL0 status pin set. They do **not** share a bus.

| | V60 (µPD70616) | V70 (µPD70632) |
|---|---|---|
| Data bus | 16-bit | **32-bit** |
| Byte enables | UBE + A0 | **B3E–B0E** |
| Minimum bus cycle | 3 clocks short / 4 normal | **2 clocks** |
| Bus states | TI, T1, T2, T3, T4, TW, TH (7) | T1, T2, TW, TI, **TIO1, TIO2, TIO3**, TH (8) |
| Cycle-mode select | **BMODE** pin | none — dynamic bus sizing |
| I/O cycles | memory-mapped on System 32 | separate, **5-clock minimum**, three TIO states |
| I/O sizing | n/a | **IOSZEN, IO8/IO16**, sampled at TIO3 |
| Start strobes | BCY | **BCYST** (memory) and **IOBCY** (I/O) |
| Package / clock | 68-pin PGA, 16 MHz | 132-pin PGA, 20 MHz |

Sources: µPD70632 Advance Product Information, May 1987, pp. 2–6; the 1987
short-form µPD70616 data sheet's PGA table (1987 NEC Microcomputer Products
Vol. 2, pp. 266–269) for the V60 pin set and package; and databook §4 via the
cycle-accuracy audit for the V60 bus states. See `REFERENCES.md`.

The T-state machines are not the same machine with a width parameter. The V70
has no T3 or T4 at all — its data phase ends at T2 — and it has three I/O
states the V60 does not have. A shared module would be a union of two automata
with almost no overlap, and every existing V60 assertion would have to grow a
"unless V70" clause. That is how the invariants this stack just added stop
meaning anything.

## The rule for using V70 documents on V60 work

The V70 document is the most detailed NEC bus description we hold, which makes
it tempting to reach for. **Architecture and encodings may cross. Timing may
not.**

| may cross | may not |
|---|---|
| the ST2-ST0 + MRQ bus-status encoding | any T-state name, count or ordering |
| which instructions are indivisible (TASI, CAXI) | "asserted during T1", "trailing edge of T2" |
| that BLOCK spans the whole indivisible operation | the two-clock bus cycle |
| register set, MMU, exception model, SBT layout | READY/BERR/BFREZ sampling instants |
| that string instructions are interruptible | the three TIO states and dynamic bus sizing |

The V70 has **eight** bus states and a **two-clock** minimum cycle with no T3
or T4. The V60 has **seven** and a three-clock short / four-clock normal cycle
with BMODE. A V70 timing statement transplanted into a V60 T-state machine is
not an approximation of the right answer -- it describes a different machine,
and it would be invisible in simulation because our own benches would simply
encode it too.

Concretely, for the bus-lock work: take from the V70 document that TASI and
CAXI are the indivisible pair and that the lock covers the whole operation
including any interrupt-acknowledge cycle. Derive **when** it asserts and
releases from the V60's own T-states in `s32_v60_bus.sv`, not from the V70's
T1/T2. Where a statement's V60 form is genuinely unknown, say so rather than
substituting the V70's.

## What a V70 BIU would need

Not scheduled — Multi 32 is out of production scope — but recorded so the size
of the job is not underestimated:

- A `s32_v70_bus.sv` with the 8-state machine, `B3E–B0E`, `BCYST`/`IOBCY`, and
  the TIO1–TIO3 I/O sizing sequence.
- A timebase that can produce 20 MHz with a representable half-clock. **This is
  the hard part.** `clk_ram` (96.634615 MHz) has no integer divisor near
  20 MHz: `/5` gives 19.327 MHz (−3.4%) *and* is odd, so it has no half-period
  tick — which defeats the reason the V60's BIU moved to `clk_ram` in the first
  place. A V70 BIU needs either a different PLL output or a different approach.
  See `rtl/cpu/v60/s32_v60_timebase.sv`.
- Dynamic bus sizing, which System 32 has no equivalent of.

## Current state of Multi 32

`s32_core` forces `is_multi32` low whenever `SYSTEM32_ONLY` is set, which the
QSF sets, so **the production bitstream contains no Multi 32 support at all**.

In a non-`SYSTEM32_ONLY` build, Multi 32 today runs the **V60** bus unit at the
V70's rate, via the NCO fallback in `s32_core`'s timebase wiring. That is a
16-bit V60 BIU pretending to be a 20 MHz V70 — it is not V70 support and should
not be mistaken for a starting point. The fallback exists so that build does
not silently get *re-rated* by the `clk_ram` timebase; it does not make the bus
correct.
