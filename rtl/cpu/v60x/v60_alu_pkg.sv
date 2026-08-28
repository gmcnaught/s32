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

typedef enum logic [5:0] {
    ALU_ADD  = 6'd0,
    ALU_ADDC = 6'd1,
    ALU_SUB  = 6'd2,
    ALU_SUBC = 6'd3,
    ALU_CMP  = 6'd4,    // subtracts and keeps only the flags
    ALU_NEG  = 6'd5,
    ALU_TEST = 6'd6,    // keeps only the flags, and clears CY and OV
    ALU_AND  = 6'd7,
    ALU_OR   = 6'd8,
    ALU_XOR  = 6'd9,
    ALU_NOT  = 6'd10,
    // MOV: the source, passed through.  Its flags column on p.3.296 is blank
    // -- it leaves the condition codes as it found them.
    ALU_MOV  = 6'd11,
    // The shift group.  All four take a SIGNED byte count in the source
    // operand: positive shifts or rotates left, negative right.  See
    // docs/v60/SHIFTS.md.
    ALU_SHL  = 6'd12,   // logical shift, zeros in from either end
    ALU_SHA  = 6'd13,   // arithmetic: the sign follows a right shift
    ALU_ROT  = 6'd14,   // rotate
    ALU_ROTC = 6'd15,   // rotate the destination and CY together
    // The extending moves, whose two operands are at different widths.  They
    // are the only operations here that need the SOURCE's width as well.
    ALU_MOVS = 6'd16,   // sign extended to the destination's length
    ALU_MOVZ = 6'd17,   // zero extended
    ALU_MOVT = 6'd18,   // truncated, and OV if the bits dropped disagree
    // Three more that write and do not read, and leave all four flags alone.
    ALU_RVBIT = 6'd25,  // the source BYTE's bits, reversed
    ALU_RVBYT = 6'd26,  // the source WORD's bytes, reversed
    ALU_SETF  = 6'd27,  // a condition, materialised as 01H or 00H
    // "The INC instruction is a shorter encoding for the more general
    // instruction `add #1, dst`" -- so they ARE the adder, with the addend
    // fixed at one, and their Condition Codes blocks are ADD's and SUB's term
    // for term.  One operand: Format III.
    ALU_INC   = 6'd28,
    ALU_DEC   = 6'd29,
    // NOP: "no action is taken", and its Operation line is "PC <- PC + 1".
    ALU_NOP   = 6'd30,
    // MOVEA: the source operand's ADDRESS, passed through.  The sequencer is
    // what makes the source an address; here it is a move.
    ALU_MOVEA = 6'd32,
    // The PSW three.  GETPSW's operand is write-only and its value comes from
    // the sequencer, which is what holds the PSW; the UPDPSW pair writes NO
    // operand -- both of theirs are ".r" -- and the sequencer merges into the
    // PSW itself at retirement.
    ALU_GETPSW  = 6'd33,
    ALU_UPDPSWH = 6'd34,
    ALU_UPDPSWW = 6'd35,
    // "The OV flag is tested and if set, an Integer Overflow Exception
    // occurs.  Otherwise, instruction execution continues with the next
    // instruction."  Format V, one byte, no operand -- the sequencer does all
    // of it and nothing reaches the ALU.
    ALU_BRKV    = 6'd36,
    // Unconditional breakpoint trap.  Format V, one byte, nothing reaches the
    // ALU.
    ALU_BRK     = 6'd37,
    // "If the specified condition is satisfied by the integer condition codes,
    // the specified trap handler is entered."  Format III, and its one operand
    // IS read -- but it is read as a condition and a vector, not as an
    // arithmetic value, so nothing here computes with it.  The sequencer takes
    // the two nibbles apart.  See docs/v60/BREAK-AND-TRAP.md.
    ALU_TRAP    = 6'd38,
    // "The bit-wise AND of floating point trap mask field in the TKCW register
    // and the floating point condition codes in the PSW is computed and if the
    // result is non-zero, a floating point operation trap will occur."  Format
    // V, one byte, no operand -- both of its inputs are registers the
    // sequencer reaches, so nothing arrives here either.
    ALU_TRAPFL  = 6'd39,
    // "PrivilegedRegister( regID ) <- src" and "dst <- PrivilegedRegister(
    // regID )".  Both are Format I/II with two operands, and in both the
    // privileged register is named by the VALUE of one of them rather than by
    // a field of the instruction -- so both operands are fetched normally and
    // the register file's privileged port does the rest.  Nothing arithmetic
    // happens, so LDPR produces nothing here; STPR passes the value the
    // sequencer read out of that port straight through, the way GETPSW passes
    // the PSW.
    ALU_LDPR    = 6'd40,
    ALU_STPR    = 6'd41,
    // "The processor halts and waits for an interrupt.  Following the
    // execution of the interrupt handler, program execution will continue with
    // the instruction following the HALT instruction."  Format V, one byte,
    // privileged -- and the sequencer's only stateful instruction: it retires
    // normally and then declines to fetch again.
    ALU_HALT    = 6'd42,
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
    ALU_TEST1   = 6'd43,
    ALU_SET1    = 6'd44,
    ALU_CLR1    = 6'd45,
    ALU_NOT1    = 6'd46,
    // "dst <- port" and "port <- src".  Both are a move; what makes them I/O
    // is that the bus cycle for ONE of their two operands is directed at the
    // I/O address space -- the source's for IN, the destination's for OUT.
    // Both are privileged, and "Rn" is Illegal for the port operand, a
    // register having no address to send.
    ALU_IN      = 6'd47,
    ALU_OUT     = 6'd48,
    // "[-SP] <- src" and "dst <- [SP+]", and each page says outright what it
    // is: "The PUSH instruction is a shorter encoding of the more general
    // instruction mov.w src, [ -sp ]", and POP of "mov.w [ sp+ ], dst".  So
    // whatever [-Rn] and [Rn+] do on R31 with a word operand, these do -- and
    // nothing arithmetic happens.  PUSH's value goes to the stack from the
    // sequencer; POP's comes back the same way and is passed through here.
    ALU_PUSH    = 6'd49,
    ALU_POP     = 6'd50,
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
    ALU_PREPARE = 6'd51,
    ALU_DISPOSE = 6'd52,
    // "dst1 <-> dst2", and the syntax line names NEITHER a source: both are
    // ".rw", both read and both written, which is the page's way of saying the
    // two roles are symmetric.  The ALU produces the half that goes to dst2;
    // the sequencer writes the other half back to dst1, which the page
    // guarantees is a register.
    ALU_XCH     = 6'd53,
    // "[-SP] <- registers" and "registers <- [SP+]", under a 32-bit mask whose
    // bit n selects Rn for n = 0..30 and whose bit 31 selects the PSW.  R31
    // has NO bit -- its column is taken by the PSW, and PUSHM's Description
    // says so in words: "The SP (R31) is not saved".
    //
    // The two scan in opposite directions, which is what makes them
    // round-trip: PUSHM "from the MSB (PSW) to the LSB (R0)" and POPM "from
    // the LSB (R0) to the MSB (PSW)".  Nothing reaches the ALU; the sequencer
    // walks the mask.
    ALU_PUSHM   = 6'd54,
    ALU_POPM    = 6'd55,
    // "lock ; flags <- dst - 0FFH ; dst <- 0FFH ; unlock".  Test-and-set: the
    // comparison is a subtract with the subtrahend fixed at 0FFH, so Z is set
    // exactly when the byte was ALREADY 0FFH -- that is, when the lock was
    // already held.  The four condition codes are a SUBTRACT's, not a test's.
    ALU_TASI    = 6'd56,
    // v60_muldiv's six.  Not combinational, and v60_seq waits on them; see
    // docs/v60/MULTIPLY-DIVIDE.md.
    ALU_MUL  = 6'd19,
    ALU_MULU = 6'd20,
    ALU_DIV  = 6'd21,
    ALU_DIVU = 6'd22,
    ALU_REM  = 6'd23,
    ALU_REMU = 6'd24,
    // Not one of the operations implemented here.
    ALU_NONE = 6'd63
} alu_op_e;

endpackage

`endif
