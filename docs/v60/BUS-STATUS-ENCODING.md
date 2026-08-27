# V60 bus status: the MRQ + ST2–ST0 encoding

**Status: recovered 2026-08-27.** This closes the open item recorded in
`docs/reference/README.md` — *"`st` (ST2-ST0) in rtl/cpu/v60/s32_v60_bus.sv
carries this core's OWN codes, not NEC's, because the MRQ + ST2-ST0 bus-status
table was not available."*

Sources, both now held under `docs/reference/` (gitignored, not redistributed):

- `NEC_uPD70616_V60_DataBook_1986.pdf` §1, **databook p. 3.233** (PDF p. 265) —
  what the CPU emits.
- `NEC_uPD71613_SystemBusController_V60_1986.pdf` **Table 1, p. 6.165** — what
  the companion bus controller decodes. An independent second source.

## The table

`MRQ` is the memory request pin. In this table it is a bit value: **0 selects
the memory address space, 1 selects I/O**.

| MRQ | ST2 | ST1 | ST0 | Bus status | Mode |
|:---:|:---:|:---:|:---:|---|---|
| 0 | 0 | 0 | 0 | Reserved for future use | Single |
| 0 | 0 | 0 | 1 | String Mode Data Access | String |
| 0 | 0 | 1 | 0 | Short Path Data Access | Single |
| 0 | 0 | 1 | 1 | Single Mode Data Access | Single |
| 0 | 1 | 0 | 0 | System Base Table Access | Single |
| 0 | 1 | 0 | 1 | Translation Table Access | Single |
| 0 | 1 | 1 | 0 | Demand Mode Instruction Fetch | |
| 0 | 1 | 1 | 1 | Instruction Prefetch | |
| 1 | 0 | 0 | 0 | Reserved for future use | Single |
| 1 | 0 | 0 | 1 | String Mode I/O Access | String |
| 1 | 0 | 1 | 0 | Reserved for future use | |
| 1 | 0 | 1 | 1 | Single Mode I/O Access | Single |
| 1 | 1 | 0 | 0 | Machine Fault Acknowledge | |
| 1 | 1 | 0 | 1 | Halt Acknowledge | |
| 1 | 1 | 1 | 0 | Interrupt Acknowledge | Single |
| 1 | 1 | 1 | 1 | Reserved for future use | |

Definitions the databook attaches to the non-obvious codes:

- **String mode** — bus cycles for variable-length data types (character string
  and bit string). **Single mode** — all other data access cycles.
- **Short Path** — "a short path memory bus status is substituted for a single
  mode data access when a read access can be satisfied by the write data for
  the current bus cycle." It is a *read served from the write data already on
  the bus*, not a distinct external transaction shape.

ST2–ST0 are three-state outputs and enter high impedance during hold
acknowledge (databook p. 3.233).

## Two traps in the second source

**1. The 71613's column header is printed `ST2 | ST0 | ST1`.** Not ST2/ST1/ST0.
Anyone transcribing Table 1 left to right without reading the header will
silently swap two bits of every code. The table above is in ST2/ST1/ST0 order.

**2. Code 000 disagrees between the two documents.** The CPU databook calls
`MRQ=0, ST=000` *Reserved for Future Use*; the 71613 decodes it as *Coprocessor
Memory Write* (and `MRQ=1, ST=000` as *Coprocessor Write*), emitting `CPRD` /
`CPWR` strobes for it. Both readings are first-hand NEC. The CPU document is
authoritative for what the CPU **emits**, so the table above follows it; the
71613 tells you what a system built around one would **do** with that code.
System 32 has no coprocessor, so nothing here depends on the resolution — but
do not "fix" one against the other.

The four most distinctive codes — `100` System Base Table, `101` Translation
Table, `110` Demand Mode Fetch, `111` Instruction Prefetch — appear identically
in both documents, which is what makes the rest of the transcription
trustworthy.

## What this does not settle

The AC parameters. Several Min/Max cells read **TBD** in this preliminary
edition, `tCYK` and the clock high/low widths among them. That matters for
driving a real V60, not for an FPGA reimplementation of one.
