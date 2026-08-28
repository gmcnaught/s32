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
