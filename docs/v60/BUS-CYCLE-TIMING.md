# V60 §4 bus operation: the exact sampling instants

**Status: recovered 2026-08-27.** This closes two more open items from
`docs/reference/README.md`:

- *"Normal-vs-short cycle selection is implemented from the audit's prose
  (BMODE sampled on the falling edge of T2). Needed: the S4 read/write waveform
  plates to confirm the sampling instants and T4's contents."*
- *"The three-TI I/O recovery between back-to-back cycles is implemented and
  dormant. Needed: the S4 statement of when it applies — I/O only, or any
  back-to-back cycle."*

Source: `NEC_uPD70616_V60_DataBook_1986.pdf` §4, **databook pp. 3.283–3.292**
(PDF pp. 315–324), held under `docs/reference/`.

## The unit of time

> "Bus states are defined and measured from the rising edge of the clock to the
> rising edge of the next." — p. 3.233

So a bus state is a full clock period, rising edge to rising edge, and every
"falling edge of Tn" below is the **midpoint** of that state. This is exactly
why the adapter had to move to `clk_ram`: on `clk_sys` there is no tick at the
half period, so none of the sampling instants below is representable. See
`mem:v60-clock-tree`.

## Memory read cycle — T1, T2, T3, T4 (p. 3.283)

| instant | what happens |
|---|---|
| **rising T1** | `A23-A0`, `DL1-DL0`, `ST2-ST0`, `FAS*`, `MRQ*`, `R/W*`, `UBE*` asserted, valid until end of cycle. `BCY*` asserted, marking cycle start. |
| **falling T1** | `DS*` asserted — external data bus transceivers may be enabled. |
| **falling T2** | `BMODE` sampled. **High = normal** (T2 → T3). **Low = short** (T3 skipped, `READY*` ignored, T4 next). |
| **falling T3** | `READY*` sampled. Low → T4 next. Negated → TW states inserted after T3. |
| **falling each TW** | `READY*` re-sampled until low, then T4 is next. |
| **rising T4** | `BCY*` negated. (`RT/EP*` is sampled here on a cycle with an error, p. 3.233.) |
| **falling T4** | **Read data on `D15-D0` latched internally**, and `DS*` negated simultaneously. Cycle complete. |

That last row is the "T4 contents" the README listed as unknown: the data latch
is at the **falling** edge of T4, not the rising edge that ends the state.

## Memory write cycle (p. 3.283–3.284)

Distinguished by `MRQ*` asserted and `R/W*` **low**. Same skeleton; the
difference recorded in the prose is that write data is driven a half period
later, at the **falling edge of T1**, and **remains valid until the end of T4**.

## Back-to-back I/O — the three-TI rule (p. 3.291)

> "I/O bus cycle timing is automatically modified during the execution of
> back-to-back I/O bus cycles. In order to meet the read and write recovery
> times of peripheral devices without the need for external logic, three TI
> states are inserted between any consecutive pair of I/O bus cycles."

**I/O only.** Not any back-to-back cycle. The question the README asked is
answered: the rule is scoped to consecutive *I/O* cycles, and its stated purpose
is peripheral recovery time.

## Bus hold — TH (p. 3.292)

| instant | what happens |
|---|---|
| **rising edge of T4 or TI** | `HLDRQ*` sampled. Asserted (low) → next state is TH. |
| **rising edge of TH** | `A23-A0`, `D15-D0`, `DL1-DL0`, `ST2-ST0`, `BCY*`, `DS*`, `FAS*`, `MRQ*`, `R/W*`, `UBE*` enter high impedance. |

`HLDAK*` follows a half clock later, and the exit is through TI.

**Not reachable on this board.** `docs/v60/BUS-PINS-171-5964D.md` records that
`HLDRQ` is an expansion-connector input (C.N. I pin 4-b) held inactive by a
4.7 kΩ pull-up on a bare System 32 board, so TH cannot be entered on the
hardware this core targets. Implement it for correctness; do not expect to
exercise it from a game.

## Bus freeze — BFREZ (p. 3.233)

`BFREZ` causes bus activity to cease **after the falling edge of T4**, with TI
states inserted.

## The seven states and the two cycle modes (p. 3.280)

> "Each bus cycle consists of a combination of the seven bus states, each state
> being defined as the interval from the rising edge of one clock to the rising
> edge of the next clock."

| state | role |
|---|---|
| TI | bus idle |
| T1 | bus cycle start |
| T2 | bus cycle state 2 |
| T3 | bus cycle state 3 |
| T4 | bus cycle ending |
| TW | wait |
| TH | bus hold |

Two modes, and the distinction matters for the wait-state logic:

- **Standard, four clocks** — T1 T2 T3 T4. External hardware can force TW states
  **between T3 and T4** by negating `READY*`.
- **High speed, three clocks** — "eliminates the T3 bus state by passing from
  bus state T2 directly to T4 **without the opportunity of inserting wait
  states**."

That last clause is the specification for why `READY*` is ignored in short mode:
it is not that the CPU chooses not to look, it is that there is no state in
which a wait could be inserted.

## RESET (pp. 3.281–3.282)

`RESET` is **active high**. It "must be held asserted for a minimum of **20
clock cycles** before returning to a low level."

> "Following the release from the reset state, the µPD70616 will exit the idle
> state and begin execution by performing a memory read (instruction fetch) bus
> cycle from address **0FFFFF0H**."

**This confirms the shipping core's reset vector from primary source.**
`rtl/s32_core.sv:400` instantiates the V60 with `START_PC = 32'hFFFFFFF0`,
attributed in a comment to MAME. It is NEC's, and the physical bus address of
that first fetch is the 24-bit `0FFFFF0H`.

Reset register values, for whenever the sequencer is built:

| register | reset value |
|---|---|
| PSW | `10000000H` |
| PC | `FFFFFFF0H` |
| SBR | `00000000H` |
| SYCW | `00000070H` |
| TKCW | `0000E000H` |
| PSW2 | `0000F002H` |
| ATBR | invalid |
| TLB | cleared |
| others | undefined |

Output pin states while reset is asserted (p. 3.282) — "the bus interface unit
is idle":

| state | outputs |
|---|---|
| High | `R/W*`, `DS*`, `BCY*`, `HLDAK*`, `BLOCK*` (MSMAT) |
| High-Z | `D15-D0` |
| Undefined | `A23-A0`, `DL1-DL0`, `FAS*`, `MRQ*`, `UBE*`, `ST2-ST0` |

`v60_biu` drives the "undefined" group to zero rather than X. Undefined permits
it, and a defined value keeps simulation free of X-propagation noise that would
obscure real faults.

## Open verification item: the 20-clock reset minimum

`RESET` must be held for at least 20 clocks (p. 3.281). Nothing in this tree
checks it, deliberately.

The obvious place — a counter in `v60_biu` — cannot work. That module's only
clock reference is `ce_rise`, and `ce_rise` is gated on `!rst` both in the
benches and in `s32_v60_timebase`, so a counter driven by it is dead for
precisely the interval it would be measuring. An assertion written that way was
tried, and reported a pass on a bench that released reset after four fast
clocks.

The check belongs where the raw clock is visible and the V60 period is known:
at the board level, beside the reset synchroniser. Until it lives there, the
requirement is documented and unenforced, which is at least honest.
