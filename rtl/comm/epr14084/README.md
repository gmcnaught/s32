# EPR-14084 firmware-execution lab

This isolated, non-production lab instantiates the vendored T80 and exposes the
inferred EPR-14084 map: ROM `0000-7fff`, private RAM `8000-9fff`, and 2 KiB
dual-port host RAM `c000-c7ff`. JP013A is represented by `reset`; T80 reset
fetch begins at `0000`. Firmware ROM is loaded through the explicit write port.

The MB89237A (`00-0f`), MB89374 (`20-2f`), and observed but unidentified ports
`17`, `40`, and `60` are classifications, not implementations. Every CPU I/O
cycle is exposed on `io_*` and holds `WAIT_n` low until external `io_ack`;
interrupt acknowledge likewise consumes externally supplied `io_rdata` as its
IM0 opcode. CN, FG, and ZFG are unmodified boundary inputs; their board logic
is not guessed. No unknown register value or device timing is fabricated.

Evidence: MAME 0.289 `src/mame/sega/s32comm.{cpp,h}` (BSD-3-Clause) documents
PCB population, 2 KiB shared RAM, and CN/FG/ZFG HLE-facing semantics. Memory
and port maps above remain inferred pending schematics or bus capture. The
Python oracle separately reproduces only MAME's `comm_tick_14084` packet/shared
memory semantics and is not a native-cycle model.

The legal ROM is never committed. Convert it with
`python tools/convert_epr14084_rom.py epr-14084.17 <ignored-output>.hex`; the
converter requires size 32768 and SHA1
`e1bb23eac85e3236046527c5c7688f6f23d43aef`.

With that verified image supplied through `EPR14084_HEX`, the real T80 reaches
its first peripheral transaction deterministically at 705 ns: `OUT (60h),00h`.
The opt-in firmware test asserts that exact barrier and stops there. Port 60h
is still unidentified, so production integration remains deliberately blocked
at this transaction rather than inventing the latch response or side effects.
