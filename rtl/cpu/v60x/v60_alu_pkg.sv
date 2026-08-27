//============================================================================
//  v60_alu_pkg -- the integer operations v60_alu implements.
//
//  One value per instruction whose Condition Codes block has been read off the
//  page.  The multiplies and divides are not here because they are not one
//  cycle of combinational logic, and the shifts and rotates are not here
//  because their flag rules have not been read yet -- see
//  docs/v60/EXECUTION-STAGE-PLAN.md.
//============================================================================
`ifndef V60_ALU_PKG_SV
`define V60_ALU_PKG_SV

package v60_alu_pkg;

typedef enum logic [3:0] {
    ALU_ADD  = 4'd0,
    ALU_ADDC = 4'd1,
    ALU_SUB  = 4'd2,
    ALU_SUBC = 4'd3,
    ALU_CMP  = 4'd4,    // subtracts and keeps only the flags
    ALU_NEG  = 4'd5,
    ALU_TEST = 4'd6,    // keeps only the flags, and clears CY and OV
    ALU_AND  = 4'd7,
    ALU_OR   = 4'd8,
    ALU_XOR  = 4'd9,
    ALU_NOT  = 4'd10
} alu_op_e;

endpackage

`endif
