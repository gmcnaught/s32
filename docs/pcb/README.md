# System 32 PCB evidence boundary

`system32_evidence.json` is the machine-readable ledger for the source-backed
PCB accuracy work. It intentionally separates documented board facts from
inferences and from measurements that cannot be made without a physical PCB.

The current target is the single-screen 837-7428 / 171-5964E System 32 board.
Multi 32 remains outside the production contract. Game and revision differences
must continue to arrive through the 64-byte descriptor and the two global
profiles, rather than through new game-specific RTL macros.

Validate it with:

```powershell
python -B tools/validate_pcb_evidence.py --check-rtl
```

An `implemented` claim must name a repository implementation file. Claims about
custom-ASIC internals, analogue response, PLD contents, or protection timing
remain open until online evidence is sufficient or a physical board capture is
available.
