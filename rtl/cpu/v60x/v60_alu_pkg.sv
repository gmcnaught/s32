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

typedef enum logic [4:0] {
    ALU_ADD  = 5'd0,
    ALU_ADDC = 5'd1,
    ALU_SUB  = 5'd2,
    ALU_SUBC = 5'd3,
    ALU_CMP  = 5'd4,    // subtracts and keeps only the flags
    ALU_NEG  = 5'd5,
    ALU_TEST = 5'd6,    // keeps only the flags, and clears CY and OV
    ALU_AND  = 5'd7,
    ALU_OR   = 5'd8,
    ALU_XOR  = 5'd9,
    ALU_NOT  = 5'd10,
    // MOV: the source, passed through.  Its flags column on p.3.296 is blank
    // -- it leaves the condition codes as it found them.
    ALU_MOV  = 5'd11,
    // The shift group.  All four take a SIGNED byte count in the source
    // operand: positive shifts or rotates left, negative right.  See
    // docs/v60/SHIFTS.md.
    ALU_SHL  = 5'd12,   // logical shift, zeros in from either end
    ALU_SHA  = 5'd13,   // arithmetic: the sign follows a right shift
    ALU_ROT  = 5'd14,   // rotate
    ALU_ROTC = 5'd15,   // rotate the destination and CY together
    // The extending moves, whose two operands are at different widths.  They
    // are the only operations here that need the SOURCE's width as well.
    ALU_MOVS = 5'd16,   // sign extended to the destination's length
    ALU_MOVZ = 5'd17,   // zero extended
    ALU_MOVT = 5'd18,   // truncated, and OV if the bits dropped disagree
    // v60_muldiv's six.  Not combinational, and v60_seq waits on them; see
    // docs/v60/MULTIPLY-DIVIDE.md.
    ALU_MUL  = 5'd19,
    ALU_MULU = 5'd20,
    ALU_DIV  = 5'd21,
    ALU_DIVU = 5'd22,
    ALU_REM  = 5'd23,
    ALU_REMU = 5'd24,
    // Not one of the operations implemented here.
    ALU_NONE = 5'd31
} alu_op_e;

endpackage

`endif
