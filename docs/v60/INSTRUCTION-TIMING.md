# V60 per-instruction timing: verification result

Asked 2026-08-25, after a claim that the V60 Programmer's Reference contains
comprehensive instruction timing. **It does not.** Neither does any other
public NEC V60 or V70 document that could be located. This note records the
evidence, so the question does not have to be re-litigated, and delivers the
closest thing to timing data that *is* extractable.

---

## 1. The claim is false, and the check is cheap to reproduce

**Document checked:** `µPD70616 Programmer's Reference Manual`, NEC Electronics
Inc., November 1986, "Preliminary Information", 308 pages
(archive.org item `NEC_V60pgmRef`).

Method: downloaded the item's OCR text layer (`NEC_V60pgmRef_djvu.txt`,
513 KB, 301 of 308 page footers present — essentially full coverage), then
keyword-swept it and visually confirmed the table layouts against the page
scans.

Whole-document keyword counts:

| term | occurrences |
| --- | --- |
| `clock` (case-insensitive) | **0** |
| `MHz` | **0** |
| `ns` | **0** |
| `Execution Time` | **0** |
| `wait state` | **0** |
| `microsecond` / `nanosecond` | **0** |
| `cycle` | 17 — all "bus cycle" in prose, none numeric |

Zero occurrences of the word "clock" in a 308-page CPU manual settles it.

**Structural confirmation.** The table of contents lists Sections 1–11 plus
Appendix A (Instruction Set Summary), B (Instruction Formats), C (Addressing
Mode Encodings). There is no timing appendix.

**Appendix A columns, confirmed visually on the page scan (leaf n301, page A-6):**

```
Mnemonic | Opcode (76543210 76543210) | Format | Flags (CY OV S Z) | Exceptions
```

No Clocks column exists.

**Per-instruction pages (Section 7) carry:** Syntax, Instruction, Opcode,
Operation, Description, Condition Codes, Exceptions. No timing field.

## 2. Where the "Clocks" column people remember actually lives — and why it is empty

The *databook* (not the programmer's reference) does print a Clocks column:

**Document:** *NEC Microprocessor and Peripherals Data Book, 1986*,
µPD70616 (V60) section, pages 3.295–3.299.

Its instruction summary header reads:

```
Mnemonic | Opcode | Instruction Format | Clocks | Flags (CY OV S Z) | Exceptions
```

Confirmed visually on the page scan (leaf n327 = databook page 3.296): the
**Clocks column is present and every single cell in it is blank**, across all
nine pages of the table. NEC laid out the column for a preliminary datasheet
and never filled it in. This independently reconfirms the finding already
recorded in `claude/V60_V70_source_dossier.md` §6.

The same is true of the V70. `upd70632_v70.pdf` in this project (NEC Advance
Product Information, May 1987, 17 pp.) reproduces the same summary table with
the same Clocks column — also entirely blank — and states outright:

> "A detailed description of the register set, instruction set, the 6-stage
> pipeline, and the MMU are beyond the scope of this advance product data
> sheet. Please refer to the V60 Programmer's Reference Manual or the µPD70616
> data sheet for more information."

Both of which are the documents checked above. The chain of references is a
closed loop with no timing in it.

**Conclusion: there is no public per-instruction cycle count for the V60, in
any document, and the plan in the RTL audit §7 step 6 — measure on hardware —
remains the only honest path to execution timing.**

## 3. What the Programmer's Reference *does* give you, which is not nothing

The manual specifies, for every instruction, the **number, size, and access
type of every operand**. On a 16-bit-bus part at 16 MHz where a minimum data
cycle is 3–4 clocks, operand traffic dominates the cycle count. This is the
memory-traffic half of a timing model, and it is fully documented.

Operand access notation (manual §7, page 7-1):

| symbol | meaning |
| --- | --- |
| `r` | read access |
| `w` | write access |
| `rw` | read and write access |
| `rwi` | **read-modify-write interlocked** access |
| `ex` | execute access |
| `n` | no access (MOVEA) |

Extracted into `v60_operand_access.csv` (delivered alongside): **118
instruction types, 220 typed variants**, each with operand list, per-operand
data size, access type, and a derived count of 16-bit data-bus cycles assuming
every operand is in memory and aligned.

Example rows:

| mnemonic | variant | operands | bus cycles (all-memory) |
| --- | --- | --- | --- |
| ADD | add.b | `src.b(1B).r ; dst.b(1B).rw` | 3 |
| ADD | add.w | `src.w(4B).r ; dst.w(4B).rw` | 6 |
| ADDF | addf.l | `src.l(8B).r ; dst.l(8B).rw` | 12 |
| TASI | tasi | `dst.b(1B).rwi` | 2 |
| XCH | xch.w | `dst1.w(4B).rw ; dst2.w(4B).rw` | 4 |

Caveats, stated plainly: this is machine-extracted from an OCR text layer.
161 of 220 rows parse cleanly and are marked `ok`; 59 are marked `review`,
almost all because the OCR mangled a variant *label* (`clr1`→`clrl`,
`set1`→`setl`, `schcu`→`schcd`) rather than the access data. Spot-check
against the page scans before relying on a `review` row. The counts assume
memory operands; a register operand costs zero bus cycles, and the actual
count also depends on the addressing mode's own operand fetches (displacement,
indirect word) and on alignment, which the addressing-mode chapter specifies.

## 4. Two corrections to the existing project docs, found while checking

**4.1 — `rwi` gives you the bus-lock list the audit asked for.**
Audit §4.2 records that no bus lock is modelled. The manual identifies exactly
which instructions require it: the ones carrying an `rwi` operand. In the whole
instruction set that is exactly two: `TASI` (`dst.b.rwi`) and `CAXI`
(`Rn.w.rw, dst.w.rwi`) — the same pair the V70 datasheet names explicitly. The V70 document
confirms the external contract: *"BLOCK\* is an active low output that is
asserted throughout the execution of an indivisible instruction (TASI, CAXI)
… asserted during T1 of the first bus cycle of the indivisible operation, and
deasserted on the trailing edge of the last clock period of the last bus cycle
of the operation. BLOCK\* is also asserted for the duration of an interrupt
acknowledge bus cycle."* That is a complete, implementable spec for the lock
signal the core is missing.

**4.2 — String instructions are architecturally interruptible and resumable,
and the RTL's non-interruptible string execution is a real divergence, not
MAME parity.**
Audit §6 lists this as a scope decision. The manual is explicit, in 13
instruction entries (`ANDBS`, `ANDNBS`, `CMPC`, `CMPCF`, `CMPCS`, `MOVBS`,
`NOTBS`, `ORBS`, `ORNBS`, `SCH0BS`, `SCH1BS`, `XORBS`, `XORNBS` — the `NOTBS`
page names `ANDBS` in its own prose, an NEC copy-paste error worth knowing
about if you grep the manual):

> "To minimize the interrupt latency time, the *xxx* instruction allows the
> service of interrupts and faults following the completion of a bus cycle.
> After servicing the interrupt or correction of the fault condition,
> instruction execution continues from the point of interruption."

and it names the architectural state that makes resumption possible — **R28
and R27 hold the live source and destination addresses during execution**, not
after it. So the interrupt-latency bound is one bus cycle, not one whole
string operation, and the resume state is in the general-purpose register file
where a handler can see it. Any interrupt-timing work on this core has to fix
this before the numbers mean anything.

The register roles, from the CMPCS page (§5 below carries the full quote):

| register | role during a string operation |
| --- | --- |
| **R28** | live **source** address |
| **R27** | live **destination** address |
| **R26** | **stop character** — an input the instruction tests against, not a pointer |

Note the direction: source is the higher-numbered register. That is an easy
transposition to make, and it would silently swap the two pointers on resume.

**4.3 — the V70 datasheet is no longer missing.**
Dossier §3 records that no public µPD70632 datasheet could be found. The copy
now in this project supplies the V70's external bus model: 385K transistors,
1.5 µm CMOS, 6-stage pipeline, 32-bit data bus, **two-clock bus cycle**
(40 MB/s at 20 MHz), eight bus states `T1 T2 TW TI TIO1 TIO2 TIO3 TH`,
`READY*`/`BERR*`/`RT/EP*`/`BFREZ` all sampled on the **trailing edge of T2 and
of every TW**, three leading TIO states on I/O cycles for dynamic bus sizing
(`IOSZEN*`, `IO8/IO16*`), and 16-entry fully-associative TLB with LRU
replacement whose miss handling runs in microcode without stalling the
prefetch/decode/bus units. It still carries **no AC characteristics and no
pinout**, consistent with the Japanese hobbyist report cited in the dossier.

## Sources

- [µPD70616 Programmer's Reference Manual, Nov 1986 (archive.org, `NEC_V60pgmRef`)](https://archive.org/details/NEC_V60pgmRef)
- [NEC Microprocessor and Peripherals Data Book 1986 (archive.org)](https://archive.org/details/nec-micropocessor-and-peripherals-data-book-1986) — V60 at pages 3.229–3.301
- `upd70632_v70.pdf` — NEC Advance Product Information, µPD70632 (V70), May 1987 (in this project)
- [MAME `v60.cpp`](https://github.com/mamedev/mame/blob/master/src/devices/cpu/v60/v60.cpp) — carries `// Actual cycles / instruction is unknown`


---

## Notes added on landing this into the repository (2026-08-25)

**§3's framing needs one qualification.** "On a 16-bit-bus part at 16 MHz where
a minimum data cycle is 3-4 clocks, operand traffic dominates the cycle count"
is true for the all-memory worst case and not for typical code. The CSV's
all-memory column has mean 3.6 / median 3.0 bus cycles, which at three clocks
per cycle is ~9-11 clocks per instruction of bus traffic alone; `ADD.w` with
both operands in memory is 18. The IPSJ SIG paper (Yamahata et al., 1987-02-06,
also in this directory's catalogue) records the real part at 3.5 MIPS at
16 MHz -- **~4.6 clocks per instruction**. Both cannot describe the same code,
so typical code must be overwhelmingly register-operand. Treat the column as a
worst-case bound.

This matters for the roadmap: it means this core's 22.7 clocks/instruction
(`verif/v60/BASELINE.md`) is an execution-overhead problem, not a bus-traffic
one.

**§4.1 is directly actionable and is now the next work item.** `TASI` and
`CAXI` are the only two instructions carrying an `rwi` operand, and the V70
document supplies the complete external contract for `BLOCK*`. The audit
measured the hazard this leaves open: every read-modify-write is two
independently arbitrated transactions with the request dropped between them,
gap >= 7 execute cycles ~ 290 ns, during which the protection MCU writes work
RAM on port B of a true dual-port BRAM with zero arbitration. `TASI` on work
RAM is not atomic against the protection MCU today.

**§4.2 contradicts the audit, and the audit is probably wrong.** Audit §6 lists
non-interruptible, non-resumable string instructions as a scope decision at
"MAME parity". The manual says the opposite in 13 instruction entries, and
names the architectural state that makes resumption possible. The R27/R28-vs-R26-R28
discrepancy is **resolved** in §5. Both statements were partly right: R28/R27
are the resume pointers and R26 is the stop-character register. Neither
document said which register was which, and that is the part an implementation
actually needs.

**§4.3 is already reflected** in `REFERENCES.md`: the V70 document is held and
catalogued, with the caveat that its bus is a different machine and only its
architecture and status encoding carry across.


---

## 5. R26, R27, R28: resolved from the manual page (2026-08-25)

The open question in §4.2 — whether the string-resume state is R27/R28 or
R26-R28 — is answered by the CMPCS entry in the Programmer's Reference. Both
earlier statements were partly right, and neither was precise enough to build
from. Quoted:

> "The character string designated by the source operand is compared to the
> character string designated by the destination operand. The comparison
> operation continues until a disagreement between the string contents is
> detected, a string is exhausted, or **the stop character in R26** is detected
> in either string.
>
> […]
>
> During the comparison operation, **registers R28 and R27 are used to maintain
> the source and destination addresses respectively**. Following the execution
> of the CMPCS instruction, these registers contain the addresses of the
> characters immediately following the strings if the end of either string was
> reached. Otherwise, R28 and R27 will contain the addresses of the characters
> in disagreement.
>
> To minimize the interrupt latency time, the CMPCS instruction allows the
> service of interrupts and faults following the completion of a bus cycle.
> After servicing the interrupt or correction of the fault condition,
> instruction execution continues from the point of interruption."

Three things follow, in decreasing order of how much they change the RTL.

**R26 is not a pointer.** It holds the stop character — an architectural
*input*, tested during execution. The audit's "R26-R28" names the right
*range* of registers an S-variant string instruction touches and the wrong
role for R26. Treating it as a third pointer would be a real defect.

**R28 is source, R27 is destination.** Source is the higher-numbered register.
Neither project document recorded the direction, and transposing them would
swap the pointers on every resume — a fault that appears only when an
interrupt actually lands mid-string, which is exactly the case nothing in this
project currently exercises.

**Interruptibility is confirmed verbatim, and its granularity is one bus
cycle.** "Following the completion of a bus cycle" — not per element, not per
instruction. This core executes string instructions to completion, so its
interrupt latency for this class is bounded by the whole operation instead.
That is a genuine architectural divergence, not the "MAME parity" scope
decision audit §6 records it as.

The post-execution values are specified too, and they are testable with no
timing model at all: on a normal termination R28/R27 point one past the
strings; on a disagreement they point at the differing characters. The flag
semantics are equally checkable — Z set iff identical length and content, CY
**cleared** if the stop character was detected and set otherwise, S reflecting
lexical order, or the shorter string when one is exhausted.

**Not claimed here, and still to check on the page scans:** which of the other
twelve interruptible string instructions read R26. CMPCS is the entry quoted,
and the `S` suffix suggests stop-character behaviour belongs to the S-variants
rather than to the whole class — but "suggests" is not evidence, and the
per-instruction pages settle it.
