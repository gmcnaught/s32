# uPD77P25 firmware-execution laboratory

This directory is a standalone, synthesizable laboratory only. It is not in
`files.qip`, is not instantiated by `s32_core`, and does not replace or modify
the production Air Rescue HLE.

`upd7725_lab.vhd` was adapted from `rtl/chip/DSP/DSPn.vhd` and the RAM
interface approach in `rtl/bram.vhd` from MiSTer-devel/SNES_MiSTer, pinned at
commit `ac616cade7df274a491614e95765ba87164798c7` (clean local checkout,
canonical URL https://github.com/MiSTer-devel/SNES_MiSTer.git). Those sources
and this adaptation are GNU GPL version 3; a copy is retained as `COPYING`.

Changes from the donor: fixed SNES firmware multiplexing, save-state/debug
bus, and Altera-specific MIF RAMs were removed; the uPD7725 sizes are fixed at
2K x 24 program and 1K x 16 data; portable text-hex initialization and
runtime load ports were added; P0, P1, DMA, EI, DR/RQM and architectural debug
state are exposed. Decode and state transitions were cross-checked against
MAME `src/devices/cpu/upd7725/upd7725.cpp` (BSD-3-Clause, R. Belmont/byuu):
all OP/RT/JP/LD forms, ALU flags, DP/RP modifiers, source/destination forms,
stack control, multiplier results, and the generic interrupt microsequence are
implemented. The external interrupt input recognizes an EI-qualified rising
edge, clears EI, executes a synthetic NOP, then a synthetic `LCALL $100`, as
MAME specifies.

Known limitation: no System 32 daughterboard latch, DMA, or interrupt wiring is
asserted. Current MAME System 32 source explicitly leaves all three unresolved
and disables the device. Consequently `int_i`, P0/P1 and DMA are generic chip
pins only and have no asserted Air Rescue source or board meaning. Serial data
is exposed as a parallel SI laboratory input; serial clock/shift timing and the
host's physical byte-wide DR bus are outside this firmware-execution boundary
(the laboratory host interface transfers a complete 16-bit DR atomically).
This is a firmware-execution research boundary, not a production core.

`verif/upd7725/gen_vectors.py` is an independent executable model of MAME's
ALU/flag equations. It covers ALU opcodes 1-15 on both accumulators (30 GHDL
differential vectors), plus 34 JP vectors covering both encodings and reset-
state outcomes for C, Z, OV0, OV1, S0, S1, DPL, SIACK, SOACK and RQM. The
focused firmware test separately covers LD, OP, LJMP, RT, runtime ROM loading,
DR/RQM, status pins, and interrupt NOP/LCALL sequencing.
