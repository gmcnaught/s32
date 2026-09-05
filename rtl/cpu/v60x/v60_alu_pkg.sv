//============================================================================
//  v60_alu_pkg -- the integer operations v60_alu implements.
//
//  One value per instruction whose Condition Codes block has been read off the
//  page.  Most of them are v60_alu's, which is combinational; the six at the
//  bottom are v60_muldiv's, which is not -- they are in the same enum because
//  the generated table has one column for "what does this opcode do", and
//  splitting it would put the same question in two places.
//============================================================================
`ifndef V60_ALU_PKG_SV
`define V60_ALU_PKG_SV

package v60_alu_pkg;

// SEVEN bits.  Six was exactly full -- 0 through 62 with ALU_NONE at 63 -- and
// the bit field group needs eight more.  The width is stated here and nowhere
// else; v60_seq's `aop` and v60_muldiv's `op` take their width from this type.
typedef enum logic [6:0] {
    ALU_ADD  = 7'd0,
    ALU_ADDC = 7'd1,
    ALU_SUB  = 7'd2,
    ALU_SUBC = 7'd3,
    ALU_CMP  = 7'd4,    // subtracts and keeps only the flags
    ALU_NEG  = 7'd5,
    ALU_TEST = 7'd6,    // keeps only the flags, and clears CY and OV
    ALU_AND  = 7'd7,
    ALU_OR   = 7'd8,
    ALU_XOR  = 7'd9,
    ALU_NOT  = 7'd10,
    // MOV: the source, passed through.  Its flags column on p.3.296 is blank
    // -- it leaves the condition codes as it found them.
    ALU_MOV  = 7'd11,
    // The shift group.  All four take a SIGNED byte count in the source
    // operand: positive shifts or rotates left, negative right.  See
    // docs/v60/SHIFTS.md.
    ALU_SHL  = 7'd12,   // logical shift, zeros in from either end
    ALU_SHA  = 7'd13,   // arithmetic: the sign follows a right shift
    ALU_ROT  = 7'd14,   // rotate
    ALU_ROTC = 7'd15,   // rotate the destination and CY together
    // The extending moves, whose two operands are at different widths.  They
    // are the only operations here that need the SOURCE's width as well.
    ALU_MOVS = 7'd16,   // sign extended to the destination's length
    ALU_MOVZ = 7'd17,   // zero extended
    ALU_MOVT = 7'd18,   // truncated, and OV if the bits dropped disagree
    // Three more that write and do not read, and leave all four flags alone.
    ALU_RVBIT = 7'd25,  // the source BYTE's bits, reversed
    ALU_RVBYT = 7'd26,  // the source WORD's bytes, reversed
    ALU_SETF  = 7'd27,  // a condition, materialised as 01H or 00H
    // "The INC instruction is a shorter encoding for the more general
    // instruction `add #1, dst`" -- so they ARE the adder, with the addend
    // fixed at one, and their Condition Codes blocks are ADD's and SUB's term
    // for term.  One operand: Format III.
    ALU_INC   = 7'd28,
    ALU_DEC   = 7'd29,
    // NOP: "no action is taken", and its Operation line is "PC <- PC + 1".
    ALU_NOP   = 7'd30,
    // MOVEA: the source operand's ADDRESS, passed through.  The sequencer is
    // what makes the source an address; here it is a move.
    ALU_MOVEA = 7'd32,
    // The PSW three.  GETPSW's operand is write-only and its value comes from
    // the sequencer, which is what holds the PSW; the UPDPSW pair writes NO
    // operand -- both of theirs are ".r" -- and the sequencer merges into the
    // PSW itself at retirement.
    ALU_GETPSW  = 7'd33,
    ALU_UPDPSWH = 7'd34,
    ALU_UPDPSWW = 7'd35,
    // "The OV flag is tested and if set, an Integer Overflow Exception
    // occurs.  Otherwise, instruction execution continues with the next
    // instruction."  Format V, one byte, no operand -- the sequencer does all
    // of it and nothing reaches the ALU.
    ALU_BRKV    = 7'd36,
    // Unconditional breakpoint trap.  Format V, one byte, nothing reaches the
    // ALU.
    ALU_BRK     = 7'd37,
    // "If the specified condition is satisfied by the integer condition codes,
    // the specified trap handler is entered."  Format III, and its one operand
    // IS read -- but it is read as a condition and a vector, not as an
    // arithmetic value, so nothing here computes with it.  The sequencer takes
    // the two nibbles apart.  See docs/v60/BREAK-AND-TRAP.md.
    ALU_TRAP    = 7'd38,
    // "The bit-wise AND of floating point trap mask field in the TKCW register
    // and the floating point condition codes in the PSW is computed and if the
    // result is non-zero, a floating point operation trap will occur."  Format
    // V, one byte, no operand -- both of its inputs are registers the
    // sequencer reaches, so nothing arrives here either.
    ALU_TRAPFL  = 7'd39,
    // "PrivilegedRegister( regID ) <- src" and "dst <- PrivilegedRegister(
    // regID )".  Both are Format I/II with two operands, and in both the
    // privileged register is named by the VALUE of one of them rather than by
    // a field of the instruction -- so both operands are fetched normally and
    // the register file's privileged port does the rest.  Nothing arithmetic
    // happens, so LDPR produces nothing here; STPR passes the value the
    // sequencer read out of that port straight through, the way GETPSW passes
    // the PSW.
    ALU_LDPR    = 7'd40,
    ALU_STPR    = 7'd41,
    // "The processor halts and waits for an interrupt.  Following the
    // execution of the interrupt handler, program execution will continue with
    // the instruction following the HALT instruction."  Format V, one byte,
    // privileged -- and the sequencer's only stateful instruction: it retires
    // normally and then declines to fetch again.
    ALU_HALT    = 7'd42,
    // The four bit instructions -- "test1 offset.w.r, base.w.r" and its three
    // read-modify-write siblings.  All four have the SAME two flag lines and
    // differ only in what they leave behind:
    //
    //     CY <- bit( base, offset )        (all four)
    //     Z  <- ~bit( base, offset )       (all four)
    //     bit(...) <- 1 / 0 / ~bit(...)    (SET1 / CLR1 / NOT1)
    //
    // The offset is the source and the base is the destination, which is the
    // pairing the shift group already reads as x and y.
    ALU_TEST1   = 7'd43,
    ALU_SET1    = 7'd44,
    ALU_CLR1    = 7'd45,
    ALU_NOT1    = 7'd46,
    // "dst <- port" and "port <- src".  Both are a move; what makes them I/O
    // is that the bus cycle for ONE of their two operands is directed at the
    // I/O address space -- the source's for IN, the destination's for OUT.
    // Both are privileged, and "Rn" is Illegal for the port operand, a
    // register having no address to send.
    ALU_IN      = 7'd47,
    ALU_OUT     = 7'd48,
    // "[-SP] <- src" and "dst <- [SP+]", and each page says outright what it
    // is: "The PUSH instruction is a shorter encoding of the more general
    // instruction mov.w src, [ -sp ]", and POP of "mov.w [ sp+ ], dst".  So
    // whatever [-Rn] and [Rn+] do on R31 with a word operand, these do -- and
    // nothing arithmetic happens.  PUSH's value goes to the stack from the
    // sequencer; POP's comes back the same way and is passed through here.
    ALU_PUSH    = 7'd49,
    ALU_POP     = 7'd50,
    // The frame pair, and between them they touch exactly two registers --
    // R30 (FP) and R31 (SP).  NOT R29: S3 gives the argument pointer to CALL
    // and RET, so the frame pointer is this pair's alone.
    //
    //   PREPARE:  tmp <- num ; [-SP] <- FP ; FP <- SP ; SP <- SP - tmp
    //   DISPOSE:  SP <- FP ; FP <- [SP+]
    //
    // DISPOSE needs no operand because "SP <- FP" discards the local-variable
    // area whatever size it was -- which is why PREPARE's `num` never has to
    // be remembered anywhere.
    ALU_PREPARE = 7'd51,
    ALU_DISPOSE = 7'd52,
    // "dst1 <-> dst2", and the syntax line names NEITHER a source: both are
    // ".rw", both read and both written, which is the page's way of saying the
    // two roles are symmetric.  The ALU produces the half that goes to dst2;
    // the sequencer writes the other half back to dst1, which the page
    // guarantees is a register.
    ALU_XCH     = 7'd53,
    // "[-SP] <- registers" and "registers <- [SP+]", under a 32-bit mask whose
    // bit n selects Rn for n = 0..30 and whose bit 31 selects the PSW.  R31
    // has NO bit -- its column is taken by the PSW, and PUSHM's Description
    // says so in words: "The SP (R31) is not saved".
    //
    // The two scan in opposite directions, which is what makes them
    // round-trip: PUSHM "from the MSB (PSW) to the LSB (R0)" and POPM "from
    // the LSB (R0) to the MSB (PSW)".  Nothing reaches the ALU; the sequencer
    // walks the mask.
    ALU_PUSHM   = 7'd54,
    ALU_POPM    = 7'd55,
    // "lock ; flags <- dst - 0FFH ; dst <- 0FFH ; unlock".  Test-and-set: the
    // comparison is a subtract with the subtrahend fixed at 0FFH, so Z is set
    // exactly when the byte was ALREADY 0FFH -- that is, when the lock was
    // already held.  The four condition codes are a SUBTRACT's, not a test's.
    ALU_TASI    = 7'd56,
    // "This instruction provides a protected method of accessing more
    // privileged execution levels."  Both operands are read and neither is
    // written; the whole effect is an exception, and the ONLY one in the set
    // whose handler does not run at execution level 0.
    ALU_CHLVL   = 7'd57,
    // "lock ; flags <- dst - Rn ; if (Z=1) then dst <- R28 else Rn <- dst ;
    // unlock" -- compare and swap, and "a more general form of the TASI
    // instruction".  R28 is an IMPLICIT third operand: the new value comes
    // from it and it appears nowhere in the syntax line.  The comparison is
    // CMP's exactly, so that is all this does; which of the two writes happens
    // is the sequencer's.
    ALU_CAXI    = 7'd58,
    // The X forms, whose destination is a DOUBLEWORD -- "a register pair, low
    // register first" (S3), or eight contiguous bytes "identified by the
    // address of the low order byte" (S2).
    //
    //   MULX/MULUX  dst.d <- dst.LOW_WORD * src.w      (a 64-bit product)
    //   DIVX/DIVUX  dst.d <- dst.d / src.w, and the two halves of the
    //               destination take DIFFERENT quantities: "The resulting
    //               32-bit quotient is stored in the lower word of the
    //               destination and the 32-bit remainder is stored in the
    //               upper word."
    //
    // So DIVX is not a 64-bit result; it is two independent 32-bit results
    // sharing one operand, which is why v60_muldiv gained a second result
    // port rather than a wider one.
    ALU_MULX    = 7'd59,
    ALU_MULUX   = 7'd60,
    ALU_DIVX    = 7'd61,
    ALU_DIVUX   = 7'd62,
    // The bit field group.  Three instructions, each in variants the sub-op
    // byte's two-bit `ext` field selects -- 00 signed, 01 unsigned, 10 right
    // justified (p.3.295).  NOTE that `ext` there is a two-bit field IN THE
    // SUB-OP BYTE and is a different thing from Format VII's `ext` BYTE in the
    // operand stream, which carries the field's length; the two are named the
    // same on facing pages.
    //
    // All three take a bit field that "must not span a length of greater than
    // four bytes" (§3), which with the pages' "the sum of the bit offset and
    // the bit field length must not exceed thirty-two" is what makes a field
    // always reachable in ONE 32-bit access.  So the datapath is a shift and a
    // mask over one word, not a multi-word extract.
    ALU_EXTBFS  = 7'd63,   // sign extended
    ALU_EXTBFZ  = 7'd64,   // zero extended
    ALU_EXTBFL  = 7'd65,   // left justified
    ALU_CMPBFS  = 7'd66,
    ALU_CMPBFZ  = 7'd67,
    ALU_CMPBFL  = 7'd68,
    ALU_INSBFR  = 7'd69,   // right justified
    ALU_INSBFL  = 7'd70,   // left justified
    // The decimal group -- one primitive each, not string operations: both data
    // operands of the arithmetic three are BYTES, two packed digits.
    //
    //   ADDDC   dst <- dst + src + CY
    //   SUBDC   dst <- dst - src - CY
    //   SUBRDC  dst <- src - dst - CY     (the operands reverse, not the home)
    //
    // CY is an INPUT here, which nothing else on the read side of an
    // arithmetic instruction in this set is -- these five are the inner step of
    // a multi-byte decimal loop and the carry threads the digits together.
    // That is why all three mnemonics say "with Carry" and why there is no
    // plain ADDD.
    ALU_ADDDC   = 7'd71,
    ALU_SUBDC   = 7'd72,
    ALU_SUBRDC  = 7'd73,
    // "Convert Packed to Zoned" and back.  The digit order CROSSES: the high
    // nibble of the packed byte becomes the digit of the LOW half of the zoned
    // halfword, which is what makes a zoned string run most-significant-digit
    // at the lowest address.
    ALU_CVTDPZ  = 7'd74,
    ALU_CVTDZP  = 7'd75,
    // The floating point group's three that contain no arithmetic: they move a
    // value, flip its sign bit, or clear it.  So they need none of the
    // rounding, subnormal and NaN behaviour docs/v60/FLOATING-POINT.md records
    // as unsettled, and they are implementable from the pages alone.
    //
    // Both widths run through the same operations -- "movf.s src.s.r, dst.s.w"
    // and "movf.l src.l.r, dst.l.w" -- with the width coming from the operand
    // sizes, so one ALU op serves each.
    ALU_MOVF    = 7'd76,
    ALU_NEGF    = 7'd77,
    ALU_ABSF    = 7'd78,
    // v60_muldiv's six.  Not combinational, and v60_seq waits on them; see
    // docs/v60/MULTIPLY-DIVIDE.md.
    ALU_MUL  = 7'd19,
    ALU_MULU = 7'd20,
    ALU_DIV  = 7'd21,
    ALU_DIVU = 7'd22,
    ALU_REM  = 7'd23,
    ALU_REMU = 7'd24,
    // Not one of the operations implemented here.
    ALU_NONE = 7'd127
} alu_op_e;

endpackage

`endif
