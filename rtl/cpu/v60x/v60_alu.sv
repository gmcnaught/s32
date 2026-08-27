//============================================================================
//  v60_alu -- the integer operations, and the four flags they leave.
//
//  Clean-room.  Every flag rule below is the sentence the Programmer's
//  Reference prints in that instruction's Condition Codes block, cross-checked
//  against the databook's Flags column on p.3.296, which marks the same set:
//
//    ADD  ADDC  SUB  SUBC  NEG  CMP   * * * *   all four
//    TEST                             0 0 * *   CY and OV cleared
//    AND  OR  XOR  NOT                - 0 * *   CY unchanged, OV cleared
//
//    "CY  Set if a carry is generated, otherwise cleared"        -- ADD
//    "CY  Set if a borrow is generated, otherwise cleared"       -- SUB
//    "OV  Set if integer overflow occurs, otherwise cleared"
//    "S   Set if the result is negative, otherwise cleared"
//    "Z   Set if the result is zero, otherwise cleared"
//    "CY  Cleared / OV  Cleared"                                 -- TEST
//    "CY  Unchanged / OV  Cleared /
//     S   Set if the MSB of the result is set"                   -- AND
//    "src2 - src1"                                               -- CMP
//
//  ---------------------------------------------------------------------------
//  DECISION, not from a page: the flags are evaluated at the OPERAND's width.
//  ---------------------------------------------------------------------------
//  Nothing states it.  Every instruction has .b / .h / .w variants and the
//  sentences say "the result", which for a byte operation can only mean the
//  byte; AND's "the MSB of the result" is the same word for all three widths
//  and can only mean bit 7, 15 or 31 respectively.  So a byte ADD of 0x7F and
//  1 sets S and OV here, and a 32-bit machine that evaluated at 32 bits would
//  set neither.  Marked because it is a reading, and tb_v60_alu makes it
//  visible by checking the boundaries at every width.
//
//  Not here: MUL, MULU, DIV, DIVU and the shifts and rotates.  The first four
//  are not one cycle of combinational logic, and the shift group's condition
//  code blocks have not been read off the page yet -- see
//  docs/v60/EXECUTION-STAGE-PLAN.md.
//============================================================================
`timescale 1ns/1ps

module v60_alu
    import v60_psw_pkg::*;
(
    // The operation, and the operands in the order the pages name them: the
    // second operand is the destination, so SUB computes y - x, which is
    // CMP's "src2 - src1" with src1 = x.
    input  v60_alu_pkg::alu_op_e op,
    input                 [3:0] opbytes,     // 1, 2 or 4
    input                [31:0] x,         // src1 / the source
    input                [31:0] y,         // src2 / the destination
    input                 [3:0] flags_in,  // {CY, OV, S, Z} as the PSW holds them

    output logic         [31:0] result,
    output logic          [3:0] flags_out,
    output logic                writes      // CMP and TEST leave no result
);

import v60_alu_pkg::*;

// The operand's width in bits, and a mask for it.
wire  [5:0] nbits = {opbytes, 3'b000};          // 8, 16 or 32
wire [31:0] mask  = (opbytes == 4'd1) ? 32'h0000_00FF :
                    (opbytes == 4'd2) ? 32'h0000_FFFF : 32'hFFFF_FFFF;
wire [31:0] msb   = (opbytes == 4'd1) ? 32'h0000_0080 :
                    (opbytes == 4'd2) ? 32'h0000_8000 : 32'h8000_0000;

wire [31:0] xm = x & mask;
wire [31:0] ym = y & mask;
wire        cy_in = flags_in[PSW_CY];

// Sum and difference one bit wider than the operand, so the carry out and the
// borrow are bits of the result rather than a separate derivation.
wire [32:0] sum  = {1'b0, ym} + {1'b0, xm} +
                   {32'd0, ((op == ALU_ADDC) ? cy_in : 1'b0)};
wire [32:0] diff = {1'b0, ym} - {1'b0, xm} -
                   {32'd0, ((op == ALU_SUBC) ? cy_in : 1'b0)};
wire [32:0] negd = {1'b0, 32'd0} - {1'b0, xm};

// The carry or borrow out of the operand's top bit.
function automatic logic carry_of(input logic [32:0] v, input logic [3:0] w);
    case (w)
        4'd1:    carry_of = v[8];
        4'd2:    carry_of = v[16];
        default: carry_of = v[32];
    endcase
endfunction

// Signed overflow: the two operands agreed about their sign and the result
// does not (addition), or they disagreed and the result follows the
// subtrahend (subtraction).
function automatic logic sign_of(input logic [31:0] v, input logic [31:0] m);
    sign_of = |(v & m);
endfunction

logic [31:0] raw;
logic        f_cy, f_ov, f_s, f_z;

always_comb begin
    raw    = 32'd0;
    f_cy   = flags_in[PSW_CY];
    f_ov   = 1'b0;
    writes = 1'b1;

    case (op)
        ALU_ADD, ALU_ADDC: begin
            raw  = sum[31:0];
            f_cy = carry_of(sum, opbytes);
            f_ov = (sign_of(xm, msb) == sign_of(ym, msb)) &&
                   (sign_of(raw, msb) != sign_of(ym, msb));
        end
        ALU_SUB, ALU_SUBC, ALU_CMP: begin
            raw  = diff[31:0];
            f_cy = carry_of(diff, opbytes);          // a borrow
            f_ov = (sign_of(xm, msb) != sign_of(ym, msb)) &&
                   (sign_of(raw, msb) != sign_of(ym, msb));
            if (op == ALU_CMP) writes = 1'b0;
        end
        ALU_NEG: begin
            raw  = negd[31:0];
            f_cy = carry_of(negd, opbytes);
            // Negating the most negative value is the one overflow.
            f_ov = (sign_of(xm, msb) && sign_of(raw, msb));
        end
        ALU_TEST: begin
            raw    = xm;
            f_cy   = 1'b0;                          // "CY Cleared"
            f_ov   = 1'b0;                          // "OV Cleared"
            writes = 1'b0;
        end
        ALU_AND: raw = ym & xm;
        ALU_OR:  raw = ym | xm;
        ALU_XOR: raw = ym ^ xm;
        ALU_NOT: raw = ~xm;
        ALU_MOV: raw = xm;
        default: ;
    endcase
end

// S and Z are read at the operand's width, which is the decision above.
// MOV is the exception: its flags column on p.3.296 is blank, so it leaves all
// four as it found them.
assign result    = raw & mask;
assign f_s       = sign_of(raw, msb);
assign f_z       = ((raw & mask) == 32'd0);
assign flags_out = (op == ALU_MOV) ? flags_in : {f_cy, f_ov, f_s, f_z};

// synthesis translate_off
always_comb begin
    // Only when the width is a real value: before the first instruction is
    // decoded it is still unknown, and an unknown is not a complaint.
    if ((^opbytes !== 1'bx) &&
        !((opbytes == 4'd1) || (opbytes == 4'd2) || (opbytes == 4'd4)))
        $display("WARN v60_alu: %0d byte operand -- the integer data types are byte, halfword and word (p.3.295)",
                 opbytes);
end
// synthesis translate_on

endmodule
