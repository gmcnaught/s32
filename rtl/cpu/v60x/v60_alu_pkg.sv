//============================================================================
//  v60_alu_pkg -- the integer operations v60_alu implements.
//
//  One value per instruction whose Condition Codes block has been read off the
//  page.  The multiplies and divides are not here because they are not one
//  cycle of combinational logic.
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
    // Not one of the operations implemented here.
    ALU_NONE = 5'd31
} alu_op_e;

endpackage

`endif
