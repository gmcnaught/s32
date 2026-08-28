//============================================================================
//  v60_fpu -- the floating point group's datapath.
//
//  Clean-room.  Separate from v60_alu for one reason that is not style: a long
//  real is SIXTY-FOUR bits and v60_alu's operands are thirty-two.  §2, p.2-6:
//
//    "The short real data type is a 32-bit binary floating point
//     representation conforming to the IEEE single precision format.  The
//     short real format consists of a mantissa sign bit, an 8-bit biased
//     exponent and a 23-bit mantissa"
//
//    "The long real data type Is a 64-bit binary floating point representation
//     conforming to the IEEE double precision format.  The long real format
//     consists of a mantissa sign bit, an 11-bit biased exponent and a 52-bit
//     mantissa"
//
//  §1 says the same from the other end: "The uPD70616 floating point data types
//  and operations conform to the IEEE 754 standard."
//
//  ---------------------------------------------------------------------------
//  What is here, and what is not
//  ---------------------------------------------------------------------------
//  MOVF, NEGF and ABSF.  All three are sign-bit and classification work with no
//  arithmetic in them, so they need none of the rounding, subnormal and NaN
//  behaviour that docs/v60/FLOATING-POINT.md records as UNSETTLED by the pages
//  -- six separate gaps, one of which (SUBF's operand order) changes results
//  and has no plate to check.  The arithmetic four are deliberately not here
//  until those are decided rather than guessed.
//
//  ---------------------------------------------------------------------------
//  Why the shipping core is a weak oracle here
//  ---------------------------------------------------------------------------
//  s32_v60.sv's FP unit states its own contract in its header -- "Behavioral
//  contract is MAME op2.hxx/op5.hxx, which use host `float`" -- and diverges
//  from the pages in five documented ways (docs/v60/FLOATING-POINT.md's
//  cross-check): long real is not implemented AT ALL, MOVF sets no flags,
//  CMPF's CY and OV are hardwired to zero, no floating point condition code is
//  ever written, and no floating point exception is ever raised.  So the usual
//  "MAME as an oracle where the Reference is silent" does not apply: here the
//  Reference speaks and the core does not follow it.
//============================================================================
`timescale 1ns/1ps

module v60_fpu
    import v60_psw_pkg::*;
(
    input  v60_alu_pkg::alu_op_e op,
    // 4 for a short real, 8 for a long one.  It comes from the table's operand
    // widths, not from a decision here.
    input                 [3:0] fbytes,
    input                [63:0] a,          // the source
    input                 [3:0] flags_in,   // {CY, OV, S, Z}
    input                 [4:0] ffl_in,     // {FIV, FZD, FOV, FUD, FPR}

    output logic         [63:0] result,
    output logic          [3:0] flags_out,
    output logic          [4:0] ffl_out,
    // The CONDITION, not a trap request.  §8 states the architecture's shape
    // four separate times and it is the same each time: the FLAG is set
    // unconditionally, a TKCW bit decides whether that becomes a trap, and
    // when it does not, execution continues with a stated result.
    //
    //   "The PSW.FIV flag will be set as a result of an invalid operation.  If
    //    the exception is enabled, the destination operand remains unchanged.
    //    If disabled, a QuietNaN is stored in the destination and execution
    //    continues."
    //
    // So this reports "a NaN or an infinity was used as an operand" and the
    // sequencer, which is where TKCW is reachable, decides what to do with it.
    // The module used to raise on the operand class alone; see
    // docs/v60/FLOATING-POINT-AUDIT.md's D1.
    output logic                resv_operand
);

import v60_alu_pkg::*;

wire is_long = (fbytes == 4'd8);

// The three fields, at whichever width.  Short real is 1/8/23 and long real is
// 1/11/52, both with the sign at the top.
wire        f_sign = is_long ? a[63] : a[31];
wire [10:0] f_exp  = is_long ? a[62:52] : {3'd0, a[30:23]};
wire [51:0] f_man  = is_long ? a[51:0]  : {a[22:0], 29'd0};
// The exponent's all-ones value, which is the width's own: 0xFF short, 0x7FF
// long.
wire [10:0] exp_max = is_long ? 11'h7FF : 11'h0FF;

// IEEE 754's four classes, which every flag sentence below is written in terms
// of.  A biased exponent of zero is a zero or a denormal depending on the
// mantissa; an all-ones exponent is an infinity or a NaN the same way.
wire f_man_zero = (f_man == 52'd0);
wire is_zero    = (f_exp == 11'd0) && f_man_zero;
wire is_denorm  = (f_exp == 11'd0) && !f_man_zero;
wire is_inf     = (f_exp == exp_max) && f_man_zero;
wire is_nan     = (f_exp == exp_max) && !f_man_zero;

// NEGF's and ABSF's results are the source with its sign bit rewritten, which
// is all either of them does -- no arithmetic, so no rounding and no
// normalisation.
wire [63:0] neg_res = is_long ? {~a[63], a[62:0]}
                              : {32'd0, ~a[31], a[30:0]};
wire [63:0] abs_res = is_long ? {1'b0, a[62:0]}
                              : {32'd0, 1'b0, a[30:0]};
wire [63:0] mov_res = is_long ? a : {32'd0, a[31:0]};

// The result's own class, for the flags.  MOVF's Condition Codes block says
// "destination" in every sentence and the other two say "result"; for all
// three the value being described is what is about to be written, and only
// ABSF's differs from the source -- in its sign bit, which no classification
// here depends on.
wire res_sign = (op == ALU_ABSF) ? 1'b0
              : (op == ALU_NEGF) ? ~f_sign : f_sign;

always_comb begin
    result       = mov_res;
    flags_out    = flags_in;
    ffl_out      = ffl_in;
    resv_operand = 1'b0;

    case (op)
    // "The source operand is copied to the destination operand and the flags
    // updated to reflect the state of the destination."
    ALU_MOVF: begin
        result = mov_res;
        // "CY Set if the destination is negative and non-zero" -- the
        // non-zero term matters: negative zero exists in IEEE 754 and this
        // sentence excludes it, where S below does not.
        flags_out[PSW_CY] = res_sign && !is_zero;
        flags_out[PSW_OV] = 1'b0;                     // "OV Cleared"
        // "S Set if the destination MANTISSA SIGN BIT is set" -- the bit, not
        // the value, so negative zero sets S where it does not set CY.
        flags_out[PSW_S]  = res_sign;
        flags_out[PSW_Z]  = is_zero;
        // "FIV Set if the destination is a NaN or infinite, otherwise
        // unchanged."  MOVF is the only instruction in the group whose FIV
        // sentence names NaN and infinity directly rather than saying "an
        // invalid operation is attempted".
        if (is_nan || is_inf) ffl_out[4] = 1'b1;      // FIV
        if (is_denorm)        ffl_out[1] = 1'b1;      // FUD
        resv_operand = is_nan || is_inf;
    end
    // "The negation of the source operand is stored in the destination
    // operand."
    ALU_NEGF: begin
        result = neg_res;
        flags_out[PSW_CY] = res_sign && !is_zero;
        flags_out[PSW_OV] = 1'b0;
        flags_out[PSW_S]  = res_sign;
        flags_out[PSW_Z]  = is_zero;
        if (is_nan || is_inf) ffl_out[4] = 1'b1;
        if (is_denorm)        ffl_out[1] = 1'b1;
        resv_operand = is_nan || is_inf;
    end
    // "The absolute value of the source operand is stored in the destination
    // operand."  Its flag block is the group's one distinctive one: THREE of
    // the four integer flags are unconditionally cleared, because the result
    // cannot be negative.  It is the only row in the whole Floating Point
    // block with a 0 in the CY and S columns.
    ALU_ABSF: begin
        result = abs_res;
        flags_out[PSW_CY] = 1'b0;
        flags_out[PSW_OV] = 1'b0;
        flags_out[PSW_S]  = 1'b0;
        flags_out[PSW_Z]  = is_zero;
        if (is_nan || is_inf) ffl_out[4] = 1'b1;
        if (is_denorm)        ffl_out[1] = 1'b1;
        resv_operand = is_nan || is_inf;
    end
    default: ;
    endcase
end

endmodule
