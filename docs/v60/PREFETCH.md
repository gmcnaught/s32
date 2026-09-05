# The prefetch unit, and who gets the bus

**Written 2026-08-27**, with `v60_pfu` and `v60_bus_arb`.

Sources, both under `docs/reference/` and both saying the same thing:

> "The PFU (prefetch unit) performs prefetching of instructions for the
> instruction decoding logic. As the lowest priority bus requester, the PFU
> uses otherwise idle bus cycles to keep the 16 byte instruction prefetch queue
> filled. Prefetching of instructions attempts to minimize instruction
> execution time by making available without delay the next instruction for the
> instruction decode unit. In the event of a control transfer, interrupt or
> exception, the instruction queue contents are flushed and a demand mode
> instruction fetch is made." — databook p. 3.246

> "The pre-fetch unit is designed to load the 16 byte instruction queue from
> external memory during idle bus periods." — Programmer's Reference §2

And the two bus status codes carry the same distinction (p. 3.233-4):

| MRQ ST2 ST1 ST0 | | |
|---|---|---|
| `0 1 1 0` | Demand Mode Instruction Fetch | "The instruction prefetch queue has been flushed by a control transfer and a demand mode instruction fetch is taking place." |
| `0 1 1 1` | Instruction Prefetch | filling the queue from idle bus cycles |

So five things are specified, not chosen:

1. the queue is **16 bytes**;
2. a fetch is the **lowest priority** bus request;
3. a control transfer, interrupt or exception **flushes** it;
4. the fetch after a flush is a **demand** fetch, the rest are **prefetches**;
5. the first fetch out of reset is from **0FFFFF0H** (p. 3.282), which is where
   `v60_pfu` starts and why it starts in demand mode.

## Arbitration

`v60_bus_arb` implements "lowest priority bus requester" as: a grant is taken
when the bus is free, the data unit wins whenever it is asking, and **the grant
is held until the ack**.

Holding it is not a style choice. `v60_biu` latches its pins at the rising edge
of T1 and acknowledges at the falling edge of T4 (p. 3.283); there is no way to
abort a cycle in between. A master that lost the mux mid-cycle would have its
cycle finished under another master's name and would never see its own ack —
which in this tree is not hypothetical: an earlier version released the grant
when a requester dropped its request, and a data read at `0x800` was delivered
into the instruction queue. `tb_v60_pfu` now asserts, on every cycle, that the
owner does not change between BCY* asserting and the ack, and that an ack
reaches exactly one master.

The other half of the rule: a request withdrawn **before** its cycle starts does
release the grant, or the bus is held for a cycle that will never run.

Because re-arbitration happens at every ack, "otherwise idle" is fine grained:
`v60_dxu` holds its request across all the bus cycles of one logical access and
drops it on the last, so a prefetch takes the first cycle *after* an access
finishes, never one in the middle of it.

## Two decisions in `v60_pfu`, neither from a page

**What DL1-DL0 says during a fetch.** The databook says FAS* is undefined
during an instruction fetch (p. 3.235) and says nothing at all about DL. A
fetch moves a halfword, so this drives `halfword`.

**An odd target.** The bus can only fetch an aligned halfword — `{UBE*, A0}`
has no other encoding for two bytes — so a control transfer to an odd address
fetches at `pc & ~1` and the byte *before* the target is dropped. The documents
do not settle whether that can happen: "in some special cases, instructions and
data must be aligned" (Programmer's Reference §3) without saying which cases,
and the one alignment rule that is stated is about exception handlers, which
"must be aligned on a word boundary" (§8). Dropping the byte is cheap and
correct if instruction alignment is not guaranteed; assuming alignment would be
silently wrong if it is not.

That decision has a visible consequence, and `tb_v60_pfu` asserts it rather than
leaving it to be discovered: an **odd instruction stream rests at fifteen queued
bytes**, because the sixteenth slot cannot take a whole halfword.

## Boundary

The queue is byte-at-a-time on purpose: a mod field is 1 to 9 bytes and only
decoding it says how long it is, so `v60_am_decode` takes exactly this
interface. What it does *not* have yet is a consumer — instruction formats and
opcode decode are the next stage, and `byte_pc` is there for them, because a
PC-relative displacement needs to know which PC (`v60_ea` deliberately does not
decide that).
