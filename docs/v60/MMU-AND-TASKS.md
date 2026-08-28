# The MMU and task switching

The address translation model, the twelve privileged instructions that read,
write and invalidate its state, and an honest account of what implementing
them would cost this tree.

Sources: Programmer's Reference **§4 Address Spaces** (not §6 — §6 is
Instruction Formats), **§5 Task Management**, **§3 Register Set** for the
privileged register layouts, **§8 Interrupts and Exceptions** for the fault
vectors, and the §7 pages for each instruction. Encodings are already
confirmed against p. 3.299 and are not re-derived here.

---

## 1. The translation model

### The virtual address decomposes into four fields

**§1, Address Translation**, which is the compact statement of the whole walk:

> The 32-bit virtual address is split into fields for the purpose of address
> translation. First, **the upper two bits are used to identify the section by
> selecting one of the four area table register pairs.** The area table
> register pair contains the base address and length of the memory resident
> area table to be used in the next step of the translation.
>
> Using the base address from the previous step, **bits 20:29 of the virtual
> address are used as the offset into the area table to select the ATE** (area
> table entry). The selected ATE contains the base address of the page table to
> be used in the second level of translation and the permissions required to
> access this area. If the access permissions are not met, the translation is
> aborted and an exception will occur.
>
> Next, **bits 12:19 of the virtual address are used as an offset in the page
> table to select a PTE** (page table entry). The PTE contains the physical
> base address of the page, whether it is physical present and the page level
> access permissions.
>
> If the page level protections are met, the access can occur and **low order
> 12 bits of the virtual address are concatenated with the page base address
> obtained from the PTE to form the physical memory address**.

```
 31 30 29                20 19        12 11                 0
+-----+--------------------+------------+--------------------+
| SEC |        AREA        |    PAGE    |       OFFSET       |
+-----+--------------------+------------+--------------------+
   2           10               8                12
    |           |                |                 |
    |           |                |                 +--> byte in the 4KB page
    |           |                +--> index into the page table (256 PTEs)
    |           +--> index into the area table (1024 ATEs)
    +--> selects ATBRn/ATLRn, n = 0..3
```

Which is `2 + 10 + 8 + 12 = 32`, and gives the 4 sections × 1024 areas × 256
pages × 4 KB = 4 GB that `docs/v60/REFERENCES.md` records. §1 also gives the
two ends: "maps each 4GB virtual address space into a **16MB** physical address
space", and "Each virtual address space is split into four **1GB** sections. A
section is the first unit of shared virtual \[memory\]".

### Where each level lives

| level | pointed at by | entry | size | alignment |
|---|---|---|---|---|
| section | `ATBRn`/`ATLRn` (privileged register pair, `LDPR`/`STPR` ids 16-23) | — | — | — |
| area | `ATBRn.ATB` → area table in **physical** memory | **ATE**, 8 bytes | up to 1024 entries = 8 KB | doubleword |
| page | `ATE.PTB` → page table in **physical** memory | **PTE**, 4 bytes | up to 256 entries = 1 KB | word |
| page frame | `PTE.RPN` | — | 4 KB | 4 KB |

> Each valid section of a virtual address space has an associated area table.
> Area tables contain up to 1024 entries ... An area table entry is eight bytes
> in size and a complete area table would occupy 8KB of memory. ... Area tables
> exist in the memory address space and must \[be\] aligned on a doubleword
> boundary.

> Page tables contain up to 256 entries ... An page table entry is four bytes
> in size and a complete page table occupies 1KB of memory. ... Page tables
> exist in the memory address space and must \[be\] aligned on a word boundary.

Both tables are addressed **physically** — `ATB` and `PTB` are physical
addresses — so the walk never recurses.

### The two paths, and the page's own labels for them

§4's Figure 4-8 is drawn as two routes to the same answer, and the labels are
worth quoting because they are an architectural statement rather than a
performance note:

```
   Normal Translation          Translation Look-aside Buffer (TLB)
      (firmware)                          (hardware)
   area table register pair
   area table                            TLB contents
   page table
```

So the table walk is **firmware** (microcode) and the TLB hit is **hardware**.
That is the design's own account of why a walk is slow and a hit is free.

---

## 2. The Area Table Entry, field by field

**Figure 4-9**, 64 bits, eight bytes:

```
 63           48 47      40 39   38 37   36 35   34 33 32 31                2  1  0
+---------------+----------+-------+-------+-------+---+--+-------------------+--+--+
|      RFU      |   LOA    |  EXL  |  WRL  |  RDL  |RFU| D|        PTB        | P| V|
+---------------+----------+-------+-------+-------+---+--+-------------------+--+--+
```

| bits | field | meaning, quoted |
|---|---|---|
| 0 | **V** (valid) | "indicates whether the ATE contents are valid. V = \[0\] ATE contents are undefined / V = 1 ATE contents are valid. In the case where the V bit is cleared, **the remainder of the ATE is undefined and available.** The following definitions only apply when the V bit is set." |
| 1 | **P** (present) | "indicates whether the page table specified by the ATE currently exists in memory. ... **An Area Not Present Exception will occur if an ATE is referenced during an address translation with the P bit cleared.**" |
| 2:31 | **PTB** (page table base) | "contains the physical address of a word aligned page table. In the µPD70616 microprocessor, **the high order bits of the PTB (bits 24:31) must be zero.**" |
| 32 | **D** (direction) | "specifies the growth direction of the area defined by this ATE. D = \[0\] positive area growth direction (increasing addresses) / D = 1 negative area growth direction (decreasing addresses)" |
| 33 | RFU | Reserved for future use |
| 34:35 | **RDL** (read execution level) | "contains the execution level required for read access." `00` → level 0; `01` → levels 0,1; `10` → levels 0,1,2; `11` → levels 0,1,2,3 |
| 36:37 | **WRL** (write execution level) | same encoding, for write |
| 38:39 | **EXL** (execute execution level) | same encoding, for execute (the page's prose says "required for read access" — a copy-paste in the book; the field name and position are unambiguous) |
| 40:47 | **LOA** (limit of area) | "specifies the range of valid pages for the area defined by this ATE. **If the D bit is cleared, pages in the range \[0\] ≤ N ≤ LOA are defined. If the D is set, pages in the range 255 ≥ N ≥ LOA are defined.**" |
| 48:63 | RFU | Reserved for future use |

The `PTB` field is bits 2:31 — thirty bits holding a word-aligned address whose
low two bits are implicit. `LOA` bounds the page table so that an area smaller
than 1 MB does not need a full 1 KB page table.

---

## 3. The Page Table Entry, field by field

**Figure 4-10**, 32 bits, four bytes:

```
 31                      12 11 10  9  8  7  6  5  4  3  2  1  0
+---------------------------+--+--+--+--+--+--+-----+--+--+--+--+
|            RPN            | E| W| R| M| A| U| RFU | L| P| I| V|
+---------------------------+--+--+--+--+--+--+-----+--+--+--+--+
```

| bits | field | meaning, quoted |
|---|---|---|
| 0 | **V** (valid) | "indicates whether the PTE contents are valid. ... In the case where the V bit is cleared, the remainder of the PTE is undefined and available. ... **If an address translation using an invalid PTE is attempted, an Invalid Page exception will occur.**" |
| 1 | **I** (I/O mapped) | "determines if the page specified by this PTE is mapped into the memory or I/O address space. I = \[0\] page is not I/O mapped / I = 1 page is I/O mapped" |
| 2 | **P** (present) | "indicates whether or not the page specified by this PTE is in memory. **A Page Not Present Exception will occur if an address translation is attempted using a PTE with the P bit cleared.** ... If the I bit is set in this PTE, the P bit is undefined and disregarded." |
| 3 | **L** (lock) | "used to specify when the page is involved in an I/O operation such as a DMA transfer. **All CPU accesses to a page marked as locked are prohibited and an Invalid Page Exception will occur** if an address translation is attempted using a PTE with the L bit set. ... This field is undefined if the page is I/O mapped." |
| 4:5 | RFU | Reserved for future use |
| 6 | **U** (user) | "is user definable by the operating system and is **ignored during address translation**." |
| 7 | **A** (accessed) | "indicates whether the page associated with this PTE has been referenced. ... This field is undefined if the page is I/O mapped." |
| 8 | **M** (modified) | "indicates whether a Write access has occurred to the page associated with this PTE. ... This field is undefined if the page is I/O mapped." |
| 9 | **R** (readable) | "determines if a Read access can be made ... R = \[0\] no Read access / R = 1 Read access permitted" |
| 10 | **W** (writable) | "determines if a Write access can be made" |
| 11 | **E** (executable) | "determines if a Execute access can be made ... **No Execute access is permitted if the page is I/O mapped.**" |
| 12:31 | **RPN** (real page number) | "has the base address (physical address) of the page associated with this PTE. Pages are aligned on a 4KB page boundary and the lower twelve bits of the physical address are zero. In the µPD70616 microprocessor, **the higher order eight bits must be zero**. The **RPN is a physical address in the memory address space if the I field is cleared, otherwise it is a physical address in the I/O address space.**" |

**`A` and `M` are hardware-written.** Nothing else in this instruction set has
that property: a page table entry is state the *processor* mutates as a side
effect of ordinary loads and stores. That is a write port into memory that
exists for no other reason, and it is easy to miss when reading the
instruction pages alone.

**`I` is where the I/O address space re-enters.** `docs/v60/TRANCHE-ONE.md`
records §4's "Two different methods are provided to generate I/O space
accesses"; `PTE.I` is the second one. A page with `I = 1` makes every ordinary
memory-referencing instruction issue an **I/O** bus cycle, at any execution
level — which is exactly what §4 says the mechanism is for.

---

## 4. The registers that anchor it

### ATBR0-ATBR3 (`LDPR`/`STPR` ids 16, 18, 20, 22)

```
 31        24 23                              3  2  1  0
+------------+---------------------------------+--+--+--+
|  00000000  |               ATB               |RFU| D| V|
+------------+---------------------------------+--+--+--+
```

- **bit 0 `V`** — "determines if the contents of the area table registers are
  valid. **An exception will occur if an address translation is attempted
  using an invalid ATBR/ATLR pair.**"
- **bit 1 `D`** — growth direction for the section, same encoding as the ATE's.
- **bits 3:31 `ATB`** — "a 29-bit **physical address** of the first area table
  entry for the associated section. The lower order three address bits (bits
  0:2) are zero and the area table must be aligned on a doubleword boundary.
  The high order eight bits (bits 24:31) are ignored ... but must be zero for
  compatibility."

### ATLR0-ATLR3 (ids 17, 19, 21, 23)

```
 31                   13 12          3  2   0
+-----------------------+-------------+------+
|          RFU          |     LOS     | RFU  |
+-----------------------+-------------+------+
```

- **bits 3:12 `LOS`** (limit of section) — "used by the hardware to determine
  the number of valid area table entries in an area table. **If the D bit is
  cleared (positive growth direction), area table entries from \[0\] ≤ n ≤ LOS
  are considered valid. If the D bit is set (negative growth direction), area
  table entries in the range LOS ≤ n ≤ 1023 are valid.**"

Ten bits, one per area-table index, exactly as `LOA` is eight bits, one per
page index.

### SYCW (id 7) — and bit 0 is the master switch

```
 31           16 15    12 11     8 7  6    4 3    1 0
+---------------+--------+--------+--+------+------+--+
|      RFU      | ATRSI  |  SPSI  |? | AST  | RFU  |VM|
+---------------+--------+--------+--+------+------+--+
```

- **bit 0 `VM`** (virtual mode) — "**controls the operating mode of the
  processor. VM = \[0\] physical address mode / VM = 1 virtual address
  mode.**" This one bit is the whole difference between a machine that needs
  the MMU and one that does not, and it is written by `LDPR`.
- bits 4:6 `AST` — asynchronous system trap level.
- **bits 8:11 `SPSI`** (stack pointer switching inhibited) — "controls the
  change of the stack pointers during context switching", one bit per level:
  `SPSI[8]` level 0, `[9]` level 1, `[10]` level 2, `[11]` level 3, with
  `0` = "level *n* stack pointer is fixed" and `1` = "switched".
- **bits 12:15 `ATRSI`** (area table register switching inhibited) — same
  shape, one bit per section: `0` = "the section *nn* area table registers are
  fixed", `1` = "switched".

`SPSI` and `ATRSI` are what §5 means by "the inclusion of the area table
registers and stack pointers is controlled by information programmed in the
System Control Word".

### SBR (id 5) and TR (id 6)

- **`SBR.SBA`** — "the **physical address** of the system base table. The
  system base table is aligned on a page boundary and the twelve low order
  bits (bits 0:11) must be zero, otherwise the results are UNPREDICTABLE."
  Every exception vector in this document is reached through it, as a **System
  Base Table Access** bus cycle (`MRQ*,ST2-ST0 = 0100`, p. 3.233).
- **`TR.TCBB`** — "the **virtual address** of the TCB for the current context.
  A task control block must be aligned on a word boundary, thus TCBB field
  (bits 0:1) must be zero, otherwise the results are UNPREDICTABLE." And:
  "**The Task Register is a 32-bit read-only register and is loaded
  automatically by the load task context instruction.**"

That last sentence explains the asymmetry `docs/v60/TRANCHE-ONE.md` found in
the `LDPR`/`STPR` id tables from the other side: **`TR` is id 6, present in
`STPR`'s table and absent from `LDPR`'s, because it is architecturally
read-only and only `LDTASK` writes it.** Two pages, in two sections, agreeing.

---

## 5. The TLB: what the pages actually require

### What they say it is

> Address translation and the associated table lookups are an inherently slow
> process and a hardware assist is required. ... The µPD70616 can take
> advantage of this and **cache the last 16 address translations on-chip in a
> high speed TLB** (translation look-aside buffer). **If the section, area and
> page ID fields match an entry in the TLB and the permissions are satisfied,
> the address translation will occur immediately and without any performance
> penalty.**

So the pages do commit to **16 entries** and to the **match key** — section,
area and page ID, i.e. `VA[31:12]` — and to permissions being checked on a
hit. They say nothing about associativity or replacement policy; the IPSJ
paper's "fully associative, pseudo-LRU" is microarchitecture the manual does
not require. **Nothing observable to software depends on the replacement
policy**, because every entry is a cached copy of a table the software owns.

### When invalidation is *required* — the only part an implementation must honour

The pages state five places where **hardware** invalidates, scattered across
four instruction pages:

| trigger | what is invalidated | page |
|---|---|---|
| `LDPR` to an area table base or length register | "Loading to area table base and length registers **clears TLB entries with corresponding section numbers**." | `LDPR` §7 |
| `LDPR` changing virtual mode to physical in `SYCW` | "**The TLB is cleared** if the virtual mode is changed to physical mode in the \[SYCW\] register." | `LDPR` §7 |
| `UPDATE` | "if the referenced ATE is cached in the TLB, **the entry is invalidated**" | `UPDATE` §7 |
| `UPDPTE` | "and if present in the TLB, **the entry is invalidated**" | `UPDPTE` §7 |
| `LDTASK` | "the area table base and length registers ... are restored as specified by the \[SYCW\] register if virtual mode is enabled and **any TLB entries associated with the updated sections are marked as invalid**" | `LDTASK` §7 |

And two places where **software** invalidates:

- **`CLRTLBA`** — "All TLB Entries ← Invalid". No operand, Format V.
- **`CLRTLB va.p.r`** — "TLBEntry(va) ← Invalid", and the page adds the
  precise scope: "**The CLRTLB instruction only clears a TLB entry that has a
  matching virtual to physical address translation.**"

**The residue is the requirement, and no page states it in one sentence.**
Every hardware invalidation above is triggered by the processor *itself*
changing translation state. `CLRTLB`/`CLRTLBA` exist for the case the hardware
cannot see: **software writing an ATE or PTE directly in memory with an
ordinary store, rather than through `UPDATE`/`UPDPTE`.** That is an inference
from the set of stated triggers, not a quoted rule — but it is the only reason
the two instructions would need to exist, and it is what an implementation
must honour: *the TLB may hold a stale copy of any table entry that was
modified by anything other than the five triggers above, until software clears
it.*

An implementation with **no TLB at all is trivially conformant**: it never
holds a stale entry, so both instructions are correct no-ops and all five
hardware triggers are vacuous. Correctness costs nothing here; only
performance does.

---

## 6. The five accessor instructions

All five are Format I,II, all privileged, and all share one unusual
convention.

### R28 selects between "walk the current space" and "address the table directly"

Every one of the five prints the same pair of paragraphs:

> If the contents of **R28 are 0FFFFFFFFH**, the virtual address operand is
> **translated using the current virtual address space**. Following the
> execution of the instruction, the \[CY and\] Z flags are updated to reflect
> the result of the translation operation.
>
> Otherwise, **R28 is assumed to contain a pointer to an area table** and a
> lookup of the specified \[ATE/PTE\] is performed. **No validity checks are
> performed on the contents of the \[ATE/PTE\].**

So the answer to "do they walk the tables or address them directly" is
**both**, selected by a sentinel value in a general-purpose register:

- `R28 == 0xFFFFFFFF` → a real walk through the live `ATBR`/`ATLR` pair for the
  virtual address's section, with validity and presence checks reported in the
  flags.
- anything else → `R28` is an area table base, and the walk proceeds from
  there **with no checks at all**. This is how an operating system inspects or
  edits the tables of a space that is *not* currently installed.

Each also says: "**This instruction can be executed in either the real or
virtual address mode.**" They work with `SYCW.VM = 0`.

`CLRTLB` uses the same convention with one extra wrinkle: "Otherwise, R28 is
assumed to contain an area table base address and the virtual address is
translated by **ignoring the lower 3 bits of the area table base register and
performing no area table length checking**."

### The five

| | opcode | syntax | Operation | result width |
|---|---|---|---|---|
| `GETATE` | `05` | `getate va.ptr.r, dst.d.w` | `dst ← ATE( va )` | **doubleword** (8 bytes) |
| `UPDATE` | `15` | `update va.p.r, newATE.d.r` | `ATE( va ) ← newATE` | doubleword source |
| `GETPTE` | `04` | `getpte va.ptr.r, dst.w.w` | `dst ← PTE( va )` | word |
| `UPDPTE` | `14` | `updpte va.p.r, newPTE.w.r` | `PTE( va ) ← newPTE` | word source |
| `GETRA` | `03` | `getra va.ptr.r, dst.w.w` | `dst ← real_address( va )` | word |

**`GETATE`/`UPDATE` are doubleword instructions** — an ATE is eight bytes —
so they need everything in `docs/v60/DOUBLEWORD.md`, including the register
pair. That is a dependency worth noting: this group cannot be finished before
tranche three.

**Flags.**

`GETATE`'s block is the simplest, because an ATE fetch has only one way to
fail:

> The Z flag is **cleared if the translation is successful and set if the
> referenced ATBR/ATLR is invalid**.

`GETPTE` and `UPDPTE` share one block:

```
CY  Set if the area is not present, otherwise cleared
OV  Unchanged
S   Unchanged
Z   Set if the address translation is invalid, otherwise cleared
```

> If either the Z or CY flags are set, **the destination remains unchanged**.

`GETRA` has the same shape with a wider set of causes:

> The CY flag will be set if **the area or page** is not present (i.e. swapped
> out to a disk) while the Z flag is set if the address translation fails
> (i.e. an invalid area table **or the page is I/O mapped**). If either the Z
> or CY flags are set, the destination operand remains unchanged.

and

> No validity checks are performed on the contents of the PTE and **no data
> reference is made**.

So `GETRA` is a translation with the data access suppressed — the one way to
ask the MMU a question without touching the page. It reports "not present" in
`CY` rather than faulting, which is what makes it usable *inside* a page-fault
handler.

Note the pattern across all five: **a failure is reported in a flag and leaves
the destination alone; it does not raise.** These instructions are the
operating system's tools for handling faults, so they must not themselves
fault on the conditions they exist to report.

`UPDATE` and `UPDPTE` additionally invalidate the TLB entry they overwrite
(§5 above).

---

## 7. CHKAR / CHKAW / CHKAE

The Reference prints all three on one page headed `CHKA`, "Check Access
Permission".

```
chkar va.p.r, level.b.r    Check Read Access Permission      4D
chkaw va.p.r, level.b.r    Check Write Access Permission     4E
chkae va.p.r, level.b.r    Check Execute Access Permission   4F
```

Operation: `check memory access permissions`

> **A check is made if the byte data addressed by the virtual address can be
> accessed at the specified execution level.** The Z flag will be set if the
> specified access is permitted. The CY flag indicates whether the virtual
> address is mapped into the I/O address space. The S flag will be set if the
> MMU was unable to complete the address translation.

So they check **one byte** at a **virtual address** for a **named access type**
at a **named execution level**, against the `RDL`/`WRL`/`EXL` fields of the ATE
and the `R`/`W`/`E` bits of the PTE.

### The three flags, each meaning something different

| flag | meaning | plate |
|---|---|---|
| **Z** | "set if the specified access **is permitted**" | `•` |
| **CY** | "indicates whether the virtual address is **mapped into the I/O address space**" — i.e. `PTE.I` | `•` |
| **S** | "set if the **MMU was unable to complete the address translation**" | `•` |
| **OV** | unchanged | `—` |

That matches p. 3.299's `• — • •` exactly. Note **`Z` is inverted from its
usual sense** — here `Z = 1` is the *good* outcome, not the zero-result one —
and that `CY` reports a property of the mapping rather than a success or
failure. Three flags carrying three independent facts is unusual in this
instruction set and is the whole point of the instruction: one probe answers
"may I", "where does it live", and "is it even mapped".

### The exception, and the privilege rule inside it

> **An Illegal Data Field exception will occur** if the execution level operand
> is not in the range \[0\] ≤ level ≤ 3 **or the current execution level is
> less privileged than the level operand**, `level < PSW.EL`.

Two conditions in one sentence, and the second is the interesting one: a
program may ask about its own level or a *less* privileged one, never a more
privileged one. The vector is **#20 Illegal Data Field**
(`docs/v60/TRANCHE-ONE.md`).

> The absence of the area or page tables will cause a **memory management fault
> just as in a normal data access**, however, **the page need not be physical
> present for access rights to be checked.**

So a missing *table* faults, but a missing *page* does not — permissions live
in the tables, and the whole purpose is to check them without touching the
page.

### The real-mode sentence, which is the one that matters here

> **When executed in the real mode, the Z flag will be set and the CY and S
> flags cleared.**

That is a complete, unambiguous specification of all three instructions for a
machine with `SYCW.VM = 0`: always permitted, never I/O, never a translation
failure. **A tree with no MMU implements `CHKAR`/`CHKAW`/`CHKAE` exactly and
conformantly by writing three constants**, and it is the pages that say so, not
a convenience.

---

## 8. LDTASK, STTASK and the Task Control Block

### What a context is

**§5:**

> Each task has a context which completely describes the state of the task. A
> context switch saves the current context and loads the context of the next
> task. ... The task's context is completely defined by a **task control block
> (TCB)** and any associated memory management tables.

> • **Program Register Set** — R0-R30, L0SP-L3SP
> • **Memory Management (virtual mode only)** — ATBR0-ATBR3, ATBL0-ATBL3
>   \[ATLR0-ATLR3\]
> • **Task Information** — TR, TKCW

R31 is absent from the list because it is not a register in its own right —
§3: "Load and store operations to R31 only affect the stack pointer for the
current execution level", so it is an alias for one of the four `LnSP`.

### The TCB, and the two things that size it

Figure 5-1 lists, with two brace annotations:

```
   TCB Base Address
     ATLR3  ATBR3  ATLR2  ATBR2                 } "Specified by the
     ATLR1  ATBR1  ATLR0  ATBR0                 }  SYCW register"

     R30 (FP)  R29 (AP)  R28  R27 ... R1  R0    } "Specified by the
                                                }  LDTASK/STTASK instructions"

     L3SP  L2SP  L1SP  L0SP                     } "Specified by the
     TKCW                                       }  SYCW register"
```

> Since not all applications require the use of the full task context, the
> µPD70616 architecture provides for the **elimination of registers from the
> TCB on a task by task basis**. ... **The inclusion of the area table
> registers and stack pointers is controlled by information programmed in the
> System Control Word (SYCW). Control of the size of the general purpose
> register set is done by specifying a register list operand for the context
> switch instructions.**

So a TCB is **variable length**, and its layout depends on `SYCW.ATRSI`,
`SYCW.SPSI` and the instruction's register-list operand together. Figure 5-2
shows a reduced one for "a single virtual address space and only execution
levels \[0\] and 3", with the area table block absent entirely.

### LDTASK

```
ldtask list.w.r, TCBptr.w.r             Opcode 01        Format I, II
```

Operation: `TaskContext ← [TCB]`

Four things restored, in the page's own order:

- **General purpose registers (R30-R0)** — "controlled by the list operand.
  The register list is **scanned sequentially from the LSB to the MSB**. The
  bits set in the list operand identify which general purpose registers are
  restored. **Bit 31 of the register list is Reserved for Future Use and must
  be zero.**" (The page's bit diagram labels the 32 bits `R0`…`R30` and `RFU`.)
- **Area table register pairs** — "restored as specified by the \[SYCW\]
  register **if virtual mode is enabled** and any TLB entries associated with
  the updated sections are marked as invalid. **In real mode, area table
  registers are not stored in the task context.**"
- **Stack pointers (L0SP-L3SP)** — "The stack pointers enabled for switching
  in the \[SYCW\] are restored. **If the current context is using the interrupt
  stack, L0SP will become the new stack pointer.**"
- **Task Control Word (TKCW)** — "updated with the Task Control Word for the
  new context."

And, from §3, the fifth: **`TR` is loaded with the TCB pointer**, since "the
task register is read only and is updated with a new TCB address by the
privileged LDTASK instruction".

### STTASK

```
sttask list.w.r                         Opcode FC/D      Format III
```

Operation: `TCB ← TaskContext`

> The current task context is copied to the Task Control Block (TCB)
> **designated by the Task Register.**

**One operand, not two** — Format III — because the destination address comes
from `TR`. That asymmetry is the pair's defining feature: `LDTASK` is told
where to go and records it in `TR`; `STTASK` writes back to wherever `TR`
already points.

The same four items are saved, with the same `SYCW` gating, plus one rule with
no counterpart on `LDTASK`:

> **Because no valid context exists between the STTASK instruction and a
> subsequent LDTASK instruction, the ISP becomes the current stack pointer
> during the execution of the STTASK instruction.**

That is `PSW.IS` (bit 28, "indicates whether the current processor context is
in the \[interrupt stack\]") being set for the duration — the machine parks on
the interrupt stack while it has no task.

---

## 9. The exceptions this group can raise

§8's Memory Management Exceptions, with vectors:

| vector | name | causes |
|---|---|---|
| **#8** | Area Not Present Exception | `ATE.P = 0` |
| **#9** | Page Not Present Exception | `PTE.P = 0` |
| **#10** | Memory Management Exceptions | I/O Access Violation, Read Access Violation, Write Access Violation (and, from the prose, Read/Write and Execute Access Violation) |
| **#11** | Address Translation Exceptions | Invalid Section, Section Length Violation, Invalid Area, Area Length Violation, Invalid Page |

The access-violation rule, quoted, is the one an implementation checks:

> Access violations occur when the faulted instruction does not have the proper
> permissions to complete the access. Read, write and execute permissions are
> checked at **both the area and page levels** and an access violation will
> occur if:
>
> ♦ The present execution level is less than the specified ATE access level for
>   the access. **`PSW.EL > { RDL, WRL, EXL }`**
> ♦ **The page level permission for the access type is disabled.**
>
> An **I/O access violation** will occur if an access crosses a page boundary
> and the pages are mapped in different address spaces.

And the restart contract, which is why `PSW.IP` exists:

> Memory management exception handlers have the option of **restarting the
> faulted instruction** or terminating the task if the fault cannot be
> corrected.

> The exception handler must read in the area or the page from secondary
> storage and **restart the instruction by executing the RETIS instruction.**

That is the same resumability machinery `docs/v60/CHARACTER-STRING.md` found
from the instruction side — `PSW` bit 26 `IP`, "indicates whether or not an
instruction has been interrupted and should be resumed". The MMU is the
principal generator of the condition.

One more, from §9: **"The address trap logic is disabled during address
translation and system base table accesses. The internal µPD70616 microprogram
will ignore these accesses even if address traps are programmed."** Table-walk
accesses are invisible to the debug hardware.

---

## 10. The honest bottom line

### Can the MMU be implemented without changing `v60_biu` and `v60_dxu`?

**No, and the reason is structural rather than incidental.** Three separate
things break, and each one on its own is sufficient.

**1. The translator is itself a bus master.** A miss walks memory: an 8-byte
ATE fetch and a 4-byte PTE fetch, both at *physical* addresses, both issued as
**Translation Table Access** cycles (`MRQ*,ST2-ST0 = 0101` — already
`BST_TRANS_TABLE` in `v60_bus_pkg.sv`, and already given its own bus-error
codes `0305`/`0315` in `v60_seq.sv`), and both completing **before** the data
access they were asked to translate can be issued. `v60_dxu` today receives a
physical address and issues it; there is no point in that flow at which it can
suspend the access it was given, run two accesses of its own, and resume. That
is a new state machine, not a new field.

**2. The address that leaves is not the address that arrived.** The physical
address is `PTE.RPN[31:12] ‖ VA[11:0]`, and `PTE.I` selects which **address
space** the cycle goes to — so the bus *status* changes as well as the
address, and `v60_biu` is what drives status. A doubleword or unaligned access
can also straddle a page boundary, at which point the second half of one
logical access needs a *different* translation, and §8 names the failure mode
for it ("an I/O access violation will occur if an access crosses a page
boundary and the pages are mapped in different address spaces"). Splitting is
`v60_dxu`'s job today and it splits on address arithmetic alone.

**3. The fault arrives late and must be restartable.** An operand address that
has already been computed can raise #8, #9, #10 or #11 before any data moves,
and the handler is expected to fix the condition and re-run the instruction
via `RETIS`. So the data-access unit needs a fault return path to the
sequencer, and the sequencer needs the restart machinery (`PSW.IP`) that
`docs/v60/CHARACTER-STRING.md` already identified as absent — this tree
recognises exceptions only between instructions.

On top of those, `PTE.A` and `PTE.M` mean the translator **writes to memory as
a side effect of an ordinary load**, which is a write port nothing in the
current design has a reason to own.

### But that is not the same question as "implement this instruction group"

**Twelve of the fourteen have a fully-specified behaviour in physical mode,
and most of it is nothing.** `SYCW.VM = 0` is the reset-consistent state, and
with it:

- **`CHKAR`/`CHKAW`/`CHKAE`** are three constants, and the page says so
  outright: "When executed in the real mode, the Z flag will be set and the CY
  and S flags cleared."
- **`CLRTLBA`** invalidates a TLB that does not exist — a conformant no-op.
- **`CLRTLB`** likewise, after decoding its operand (which it must, to advance
  the PC correctly).
- **`LDTASK`/`STTASK`** are fully implementable **now**: "In real mode, area
  table registers are not stored in the task context", so the only part that
  needs the MMU drops out, and what remains is a register-list-driven block
  move plus `SYCW.SPSI` gating plus the `TKCW`/`TR`/`IS` bookkeeping. This is
  the piece that makes `v60_regfile`'s stack switching and PSW handling matter,
  exactly as expected.
- **`LDPR`/`STPR`** on ids 16-23 are already correct as *storage*; they become
  meaningful only when something reads them.

**The two that are not:** `GETATE`, `UPDATE`, `GETPTE`, `UPDPTE` and `GETRA`
have no degenerate physical-mode behaviour. Their pages say "This instruction
can be executed in either the real or virtual address mode" — they are
*supposed* to work with `VM = 0`, walking tables the software has built in
physical memory — so a real-mode implementation still needs the table walk,
just not the address substitution. That is a smaller job than the MMU (no
`v60_biu`/`v60_dxu` change, because the walk's addresses are already physical
and the *result* is a value in a register rather than an address on the bus)
but it is not nothing: it is a multi-access microsequence with a doubleword
result for two of the five.

**Suggested order, and the honest cost:**

| step | needs | cost |
|---|---|---|
| `CHKAR`/`CHKAW`/`CHKAE`, `CLRTLBA`, `CLRTLB` | nothing | trivial, and conformant |
| `LDTASK`/`STTASK` | register-list sequencer, `SYCW` decode, `IS`/`ISP` | moderate, no datapath change |
| `GETATE`/`UPDATE`/`GETPTE`/`UPDPTE`/`GETRA` | a table-walk microsequence; doubleword operands for two of them | moderate, no `biu`/`dxu` change |
| translation itself | new `biu`/`dxu` structure, restartable faults, `PSW.IP`, `A`/`M` writeback | large, and it is the only item that touches the bus units |

---

## 11. Cross-check: `rtl/cpu/v60/s32_v60.sv`

Read only. "Implemented" and "decoded without trapping" really are different
here, and so is a third category the core occupies more than either.

### Genuinely implemented (2 of 14)

**`LDTASK` (`8'h01`) and `STTASK` (`8'hfc/fd`)**, with real transfer
machinery: `S_TASK_LD_NEXT`/`_ACK` and `S_TASK_ST_NEXT`/`_ACK`, a 36-phase
sequence — "Phase 0 is TKCW, phases 1..4 are enabled L0SP..L3SP fields, and
phases 5..35 are R0..R30". Three details match the pages precisely:

- The stack-pointer phases are gated by **`sycw[7 + task_phase]`**, i.e.
  `sycw[8:11]` — which is exactly `SYCW.SPSI`, one bit per level, in the right
  bit positions.
- The register phases are gated by the **list mask**, one bit per register,
  scanned from `R0` upward — the page's "scanned sequentially from the LSB to
  the MSB".
- `STTASK` sets `PSW` bit 28 (`write_psw(psw | 32'h1000_0000)`) and captures
  `isp <= r[31]`, with the comment "v60SaveStack() after setting IS"; `LDTASK`
  clears the same bit. That is `PSW.IS` and the page's "the ISP becomes the
  current stack pointer during the execution of the STTASK instruction",
  independently arrived at.
- `LDTASK` sets `trr <= task_pointer`, which is §3's read-only `TR` loaded by
  `LDTASK`.

**What is missing:** there are **no ATBR/ATLR phases**. `SYCW.ATRSI` is never
consulted. That is *correct for real mode* — "In real mode, area table
registers are not stored in the task context" — and incomplete for virtual
mode. The TCB layout it implements is `TKCW, L0SP..L3SP, R0..R30` ascending
from the pointer.

### Correct by degeneracy (4 of 14)

**`CHKAR`/`CHKAW`/`CHKAE` (`8'h4d/4e/4f`)**: fully decoded through the F12
operand path, then

```
8'h4d, 8'h4e, 8'h4f: begin // CHKA*: no MMU -> return address valid
    f_z <= 1; f_cy <= 0; f_s <= 0; st <= S_NEXT;
end
```

That is not a stub — it is **verbatim the page's real-mode sentence**: "the Z
flag will be set and the CY and S flags cleared". With `SYCW.VM = 0` this core
is architecturally correct on all three.

**`CLRTLBA` (`8'h10`)**: "no MMU -> one-byte NOP". The page's Operation is
"All TLB Entries ← Invalid"; with no TLB that is a no-op, and Format V makes
it one byte. Correct.

### Decoded and discarded (1 of 14)

**`CLRTLB` (`8'hfe/ff`)**: "consume the complete AM operand; no MMU state" —
the operand is fully decoded so the PC advances correctly, and nothing else
happens. Same reasoning as `CLRTLBA`, so also correct on a TLB-free machine;
listed separately only because it is the one place the core has to do work
(operand decode) to do nothing.

### Not decoded at all (5 of 14)

**`GETRA` (`03`), `GETPTE` (`04`), `GETATE` (`05`), `UPDPTE` (`14`) and
`UPDATE` (`15`) have no case in the primary dispatch.** They fall through to

```
default: begin
    // reserved instruction
    $display("V60: reserved opcode %02x at %08x", opcode, pc);
    exc_vector <= 8'd8; exc_pushval <= psw; st <= S_EXC_PUSH1;
end
```

and take an exception. This is the category that matters for the oracle: for
these five the shipping core does not merely produce a different answer, it
**produces an exception where a conformant core produces a value**.

### `LDPR`/`STPR` on the MMU ids

`atbr0`-`atbr3`, `atlr0`-`atlr3`, `sycw`, `sbr`, `trr`, `tkcw` all exist as
plain 32-bit registers and are read and written by `STPR`/`LDPR` by id. That
is correct **as storage** and inert **as control**: nothing consumes `SYCW.VM`,
nothing consumes `ATBR.ATB`, and neither of `LDPR`'s two documented TLB side
effects exists because there is no TLB. `SYCW` is consumed in exactly one
place — `sycw[8:11]` for the `LDTASK`/`STTASK` stack-pointer gating — which is
the one MMU-adjacent register field the core actually uses.

### One observation outside this group, because it lands in its vector space

The core dispatches reserved opcodes to **`exc_vector <= 8'd8`**. §8 places
**Area Not Present at vector #8** and **Reserved Opcode at #16**. The core's
numbering agrees with the Reference elsewhere (`BRKV` → 21, and
`docs/v60/TRANCHE-ONE.md` checked `BRK` → 13), so this looks like a genuine
mismatch rather than a different table — but it is MAME-derived and I have not
checked MAME's own SBT layout, so it is reported as something to verify, not
as a defect.

### What the co-simulation oracle can and cannot compare

- **Can compare:** `LDTASK`/`STTASK` transfer order, phase gating and register
  effects; the `CHKA*` real-mode flag results; `CLRTLB`/`CLRTLBA` as no-ops
  with correct instruction lengths.
- **Cannot compare anything about translation**, and worse, **must not be fed
  the five accessors at all**: a clean-room core that implements them
  correctly would diverge from the oracle on the first instruction, and the
  divergence would be the oracle's, not the clean-room's. Those five need a
  different check — a reference model or a directed bench with hand-built
  tables — before they can be trusted.
- The `sycw[8:11]` gating is the only place the two cores would even exercise
  the same MMU-register bits.

---

## 12. What the pages do not settle

1. **The TCB's layout direction.** Figure 5-1 lists `ATLR3 … ATBR0`, then
   `R30 … R0`, then `L3SP … L0SP`, then `TKCW`, with "TCB Base Address"
   labelling one end. The OCR cannot tell whether addresses increase down the
   figure or up it, so **which end the base address names is unresolved**, and
   with it the byte offset of every field. `s32_v60.sv` puts `TKCW` at the
   base and ascends through `L0SP..L3SP` then `R0..R30`, which is the reverse
   of the figure's printed order — consistent if the figure is drawn
   high-address-at-top, and wrong if it is not. **This needs the plate, and
   the Programmer's Reference PDF is not held.** It is the single most
   consequential gap in this document: a wrong direction produces a TCB that
   is self-consistent and incompatible with everything else.

2. **Where `TR` sits in the TCB, or whether it does.** §5's context list names
   `TR` under "Task Information" alongside `TKCW`, but Figure 5-1 shows only
   `TKCW`. Since `TR` holds the address *of* the TCB, storing it inside the
   TCB would be redundant — but the list says it is part of the context.

3. **The exact ATE/PTE fetch sizes and orders on a walk.** An ATE is eight
   bytes and a PTE four; nothing says whether the ATE is fetched whole or
   whether the hardware reads only the halves it needs, nor in what order.
   Observable on the bus and nowhere else.

4. **When `A` and `M` are written.** The bits are defined ("has been
   referenced", "a Write access has occurred") but no page says whether the
   write happens before or after the access completes, whether a faulted
   access still sets `A`, or whether `M` is set on the first write or every
   write. This matters for a demand-paging OS and is not stated.

5. **What `V = 0` in an `ATBR` raises.** The register description says "An
   exception will occur if an address translation is attempted using an
   invalid ATBR/ATLR pair" without naming it. §8's #11 group lists "Invalid
   Section", which is the obvious candidate, but the two pages are not joined
   up.

6. **The `EXL` prose.** The ATE's `EXL` field description reads "contains the
   execution level required for **read** access" — a copy of `RDL`'s sentence.
   The field's name and position are unambiguous and §8 names `EXL` in the
   access-violation rule, so this is a book typo rather than a real question;
   recorded so no one re-reads it as a discovery.

7. **TLB coherence for direct table writes.** The five hardware invalidation
   triggers are stated; the requirement that software use `CLRTLB`/`CLRTLBA`
   after writing a table entry by ordinary store is the residue and is stated
   nowhere in one sentence. Marked as an inference in §5.

8. **Whether a page-straddling operand is translated once or twice.** §8
   implies twice (it names a failure mode for the two halves being in
   different address spaces), but no page describes the mechanism, and nothing
   says what happens if the second half faults after the first half has
   already been written.

9. **`CLRTLB`'s flags.** Its Condition Codes block prints `— — — —` and the
   four `Unchanged` lines, so the instruction reports nothing at all — not
   even whether it found an entry. That is stated; what is not stated is
   whether that is deliberate or whether the "only clears a TLB entry that has
   a matching virtual to physical address translation" qualifier was meant to
   be observable.

10. **Timing**, as everywhere: p. 3.299's Clocks column is blank on all
    fourteen rows.
