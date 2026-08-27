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
