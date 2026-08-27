# What one operand costs: logical access → bus cycles

**Written 2026-08-27**, with `v60_dxu` and `v60_ea`. This is the piece that
makes `docs/v60/v60_operand_access.csv` measurable: that file counts *data bus
cycles*, and until now nothing in this tree turned an operand into any.

Sources, all first-hand: `NEC_uPD70616_V60_DataBook_1986.pdf` §1 and §4, and
the Programmer's Reference (`NEC_V60pgmRef_djvu.txt`) §3 and §8. Both under
`docs/reference/`, gitignored.

## The bus can only do three things

> "Both memory and I/O address spaces are organized into a pair of byte-wide
> banks and are addressed by A23-A1. The even addressed bank is selected
> whenever A0 is driven low during an I/O or memory bus cycle. Selection of the
> odd addressed bank is controlled by the UBE* signal." — p. 3.235

> "The sixteen bit bidirectional data bus is organized into a pair of byte-wide
> data buses, supporting both 8- and 16-bit bus cycles. Eight bit bus cycles
> and sixteen bit bus cycles are distinguished by A0 and UBE*." — p. 3.235

| UBE* | A0 | Access type |
|:---:|:---:|---|
| 0 | 0 | Halfword access |
| 0 | 1 | Upper byte access |
| 1 | 0 | Lower byte access |
| 1 | 1 | **Reserved** |
— p. 3.236

Three legal shapes, and a halfword is only one of them when A0 is low. No rule
about splitting has to be quoted, because the encoding leaves nothing else:

    address even and two or more bytes left  ->  halfword cycle
    otherwise                                ->  byte cycle, upper lane if A0
                                                 is 1, lower lane if A0 is 0

This has to work for unaligned operands, because they are legal:

> "In some special cases, instructions and data must be aligned. However,
> generally there are no alignment requirements and only the performance is
> affected by not aligning data on its boundary." — Programmer's Reference §3

## The cost table

| operand | aligned | at an odd address |
|---|---:|---:|
| byte | 1 | 1 |
| halfword | 1 | 2 |
| word | 2 | 3 |
| doubleword | 4 | 5 |

`v60_dxu` reports it as `cycles`, and `v60_ea` adds the pointer read an
indirect mode makes — a 32-bit pointer, so two more cycles when it is aligned —
into `bus_cycles`. A word operand reached through `[disp[Rn]]` at an odd
address is 2 + 3 = 5, which `tb_v60_ea` asserts against real memory.

Two pins already say which cycle of an access you are looking at, which is
independent evidence that a logical access was expected to take several:

- **DL1-DL0** is the access's *logical* length and does not change across its
  cycles (p. 3.235).
- **FAS\*** is "0: First bus cycle / 1: Subsequent bus cycles" (p. 3.235).

## Two decisions in `v60_dxu`, neither from a page

**A doubleword has no DL code.** DL1-DL0 encodes byte, halfword, word and
reserved — that is the whole table (p. 3.235). An eight-byte operand is driven
as `word`, and treated as *two* logical word accesses for FAS\*, so the pin
asserts again on the fifth byte. Any other choice contradicts either DL or
FAS\*; this one at least keeps both self-consistent.

**Which cycle goes first.** The split above walks upward from the operand's
address. The databook does not say the CPU works up rather than down, and
nothing observable in this core depends on it — but a bus analyser would see
it, so it is written down rather than assumed.

## The scaling table prints 3 for Word

`v60_ea` scales an index register by the operand's size. The databook has two
statements about that and they do not agree.

> "The scaled index addressing modes automatically scale the contents of an
> index register by the size of the operand (byte / halfword / word /
> doubleword) before performing the access." — p. 3.257

The table on p. 3.261:

| Data type | Increment/decrement | Scaled index |
|---|---:|---:|
| Byte | 1 | 1 |
| Halfword | 2 | 2 |
| **Word** | **4** | **3** |
| Doubleword | 8 | 8 |
| Packed decimal | 1 | 1 |
| Unpacked decimal | 2 | 2 |
| Byte character | 1 | 1 |
| Halfword character | 2 | 2 |
| Bit | 4 | 4 |
| Bit field | 4 | — |
| Bit string | 1 | — |

Every other row's scaled index equals the type's size in bytes. Word's is
printed 3, against its own increment of 4 and against the sentence on p. 3.257.
Nothing on this machine is scaled by 3. `v60_ea` scales a word index by **4**
and `tb_v60_ea` names the cell in the check that covers it.

That is the fourth cell in these two figures that does not survive being read
against the rest of the document; the other three are in
`docs/v60/ADDRESSING-MODES.md`.

## Boundaries

- **Which PC** a PC-relative displacement is relative to is not decided here.
  `v60_ea` takes `pc_val` as given; that question belongs to instruction fetch.
- **The address is 32 bits, the bus is 24** (A23-A0, p. 3.235). `v60_ea`
  reports all 32 and the top eight are dropped at the pins.
- **A doubleword register-direct operand** needs a register *pair*. `v60_ea` is
  handed one register value and warns in simulation if asked for eight bytes of
  it.
- **I/O accesses** are not an addressing mode. `v60_dxu` can drive I/O status,
  and `v60_ea` ties it low, because a mode names memory; IN/OUT will drive the
  data unit directly.
