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
//  The shift group -- SHL, SHA, ROT, ROTC -- is here too, and its four
//  Condition Codes blocks say (SHL's wording; ROT and ROTC print the same
//  with "rotated" for "shifted"):
//
//    "CY  Set if the last shifted bit was set, cleared if the last shifted bit
//         was zero or the shift count was zero
//     OV  Cleared
//     S   Set if the MSB of the result is set, otherwise cleared
//     Z   Set if the result is zero, otherwise cleared"
//
//  SHA differs in two of the four: "OV  Set if integer overflow occurs" with
//  the Description saying "integer overflow occurs if the sign of the result
//  changes at anytime during the execution of this instruction", and "S  Set
//  if the result is negative".  See docs/v60/SHIFTS.md for the rest of what
//  those pages fix -- the signed byte count, what a count past the operand's
//  width does, and where each opcode is.
//
//  RVBIT, RVBYT and SETF are here too, and all three are one line of their own
//  page:
//
//    "The individual bits of the byte data addressed by the source operand are
//     reversed"                                            -- RVBIT, S7
//    "dst <- byte_reversed( src )"                          -- RVBYT, S7
//    "if ( condition ) then dst <- 01H else dst <- 00H"     -- SETF, S7
//
//  Three things about them are easy to get wrong and are marked where they are
//  implemented:
//
//  * RVBIT is a BYTE instruction -- "rvbit src.b.r, dst.b.w".  It reverses
//    eight bits, not thirty-two.  RVBYT is the word one.
//  * SETF's condition is in the LOW nibble of its source ("the condition code
//    field is found in the lower four bits ... the upper four bits are
//    ignored"), where TRAP's is in the high nibble.  Sharing a condition
//    evaluator between the two is right; sharing the nibble is a bug.  See
//    docs/v60/TRANCHE-ONE.md.
//  * All three leave every flag alone.  Both reversals print four "Unchanged"
//    lines and blank flag rows on the plate, so a byte swap does not set Z
//    even when the result is zero.
//
//  Not here: MUL, MULU, DIV and DIVU, which are not one cycle of
//  combinational logic.
//============================================================================
`timescale 1ns/1ps

module v60_alu
    import v60_psw_pkg::*;
(
    // The operation, and the operands in the order the pages name them: the
    // second operand is the destination, so SUB computes y - x, which is
    // CMP's "src2 - src1" with src1 = x.
    input  v60_alu_pkg::alu_op_e op,
    input                 [3:0] opbytes,     // the DESTINATION's: 1, 2 or 4
    // The source's width, which differs from the destination's only in the
    // extending moves -- "the source and destination operand lengths differ in
    // this instruction" (MOVS, MOVZ, MOVT) -- and is ignored by everything
    // else, whose two operands are the same size.
    input                 [3:0] xbytes,
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

// The source's own width, for the extending moves.
wire [31:0] xmask = (xbytes == 4'd1) ? 32'h0000_00FF :
                    (xbytes == 4'd2) ? 32'h0000_FFFF : 32'hFFFF_FFFF;
wire [31:0] xmsb  = (xbytes == 4'd1) ? 32'h0000_0080 :
                    (xbytes == 4'd2) ? 32'h0000_8000 : 32'h8000_0000;
wire        x_sign = |(x & xmsb);

// "The contents of the source operand are sign extended to the destination
// length" / "are zero extended" / "are truncated to the destination operand
// length".  All three are the source read at ITS width and then presented at
// the destination's.
wire [31:0] mov_zx = x & xmask;
wire [31:0] mov_sx = x_sign ? (mov_zx | ~xmask) : mov_zx;

// "If any of the truncated bits do not match the sign of the result, an
// integer overflow has occurred and the OV flag is set."  The bits dropped
// are the source's above the destination's width, and the sign of the result
// is the destination's top bit.
wire [31:0] mov_drop = mov_zx & ~mask;
wire        movt_ov  = sign_of(mov_zx, msb) ? (mov_drop != (xmask & ~mask))
                                            : (mov_drop != 32'd0);

// "B7 B6 B5 B4 B3 B2 B1 B0" above and "B0 B1 B2 B3 B4 B5 B6 B7" below, so
// dst[i] = src[7-i] -- over the source's BYTE, whatever the destination is.
wire [7:0] rvbit_res = {x[0], x[1], x[2], x[3], x[4], x[5], x[6], x[7]};

// "Byte3 Byte2 Byte1 Byte0" above and "Byte0 Byte1 Byte2 Byte3" below.
wire [31:0] rvbyt_res = {x[7:0], x[15:8], x[23:16], x[31:24]};

wire [31:0] xm = x & mask;
wire [31:0] ym = y & mask;
wire        cy_in = flags_in[PSW_CY];

// The addend.  "The INC instruction is a shorter encoding for the more general
// instruction `add #1, dst`" and the DEC page says the same of `sub #1, dst`
// (S7), so INC and DEC ARE the adder with the addend fixed at one, and they
// share every line below -- including the overflow terms, which is what makes
// their Condition Codes blocks identical to ADD's and SUB's without a second
// derivation to keep in step.
wire        addend_one = (op == ALU_INC) || (op == ALU_DEC);
wire [31:0] xa = addend_one ? (32'd1 & mask) : xm;

// Sum and difference one bit wider than the operand, so the carry out and the
// borrow are bits of the result rather than a separate derivation.
wire [32:0] sum  = {1'b0, ym} + {1'b0, xa} +
                   {32'd0, ((op == ALU_ADDC) ? cy_in : 1'b0)};
wire [32:0] diff = {1'b0, ym} - {1'b0, xa} -
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

// ---------------------------------------------------------------------------
// The shift group.
//
// "The shift count is specified as signed byte data in a range from -128 to
// +127.  When the shift count is positive, the destination is shifted left
// ... When the shift count is negative, the destination is shifted right."
// So the count is x's low byte read as a sign-magnitude pair, and every
// operation below is expressed as a left one or a right one.
// ---------------------------------------------------------------------------
wire        sh_left = !x[7];
wire  [7:0] sh_amt  = x[7] ? (8'd0 - x[7:0]) : x[7:0];   // 0 to 128
wire        sh_zero = (sh_amt == 8'd0);
wire        v_sign  = sign_of(ym, msb);

// The value sign extended to 32 bits, for the arithmetic right shift and for
// the overflow test.
wire [31:0] v_sext = v_sign ? (ym | ~mask) : ym;

// A shift by the operand's own width already moves every bit out; more than
// that changes nothing further, so the amount is capped for the RESULT.  It
// is not capped for CY, because "the last shifted bit" is a zero (or the
// sign) once the operand's own bits have all gone.
wire  [5:0] sh_cap  = (sh_amt > {2'd0, nbits}) ? nbits : sh_amt[5:0];

// Left: the operand in the low half, so what crosses bit `nbits` is the last
// bit to leave.  Right: the operand in the HIGH half, so what crosses bit 31
// is the last bit to leave.
wire [63:0] sh_l    = {32'd0, ym}     << sh_cap;
wire [63:0] sh_r    = {ym, 32'd0}     >> sh_cap;
wire [63:0] sh_ra   = $signed({v_sext, 32'd0}) >>> sh_cap;

// "If the absolute value of the shift count exceeds the destination operand
// length, zero (positive shift counts) or data consisting of the sign of the
// destination (negative shift counts) is stored" -- which is what capping at
// the width already produces.
wire [31:0] shl_res = sh_left ? sh_l[31:0] : sh_r[63:32];
wire [31:0] sha_res = sh_left ? sh_l[31:0] : sh_ra[63:32];

// The last bit to leave.  Past the operand's width it is a zero for a logical
// shift and the sign for an arithmetic right shift, because those are what is
// being shifted out by then.
wire        sh_past = (sh_amt > {2'd0, nbits});
wire        shl_cy  = sh_zero ? 1'b0
                    : sh_past ? 1'b0
                    : sh_left ? sh_l[nbits]
                              : sh_r[31];
wire        sha_cy  = sh_zero ? 1'b0
                    : sh_past ? (sh_left ? 1'b0 : v_sign)
                    : sh_left ? sh_l[nbits]
                              : sh_ra[31];

// SHA's overflow: "the sign of the result changes at anytime during the
// execution".  The value shifted left is the mathematical one, so the sign is
// unchanged exactly when every bit at and above the operand's sign position
// still agrees with the original sign.  A right shift cannot change it.
wire [63:0] sh_sext64 = {{32{v_sign}}, v_sext};
wire [63:0] sh_ovsh   = sh_sext64 << sh_cap;
wire [63:0] sh_keep   = ~((64'd1 << (nbits - 6'd1)) - 64'd1);
wire        sha_ov    = sh_left &&
                        ((sh_ovsh & sh_keep) != (v_sign ? sh_keep : 64'd0));

// The rotates.  The count is taken modulo the number of bits being rotated,
// which is the operand for ROT and the operand plus CY for ROTC -- "the
// concatentation of the destination operand and CY flag is rotated".
wire  [5:0] rot_e  = {1'b0, sh_amt[4:0]} & (nbits - 6'd1);   // nbits is 8/16/32
wire  [5:0] rot_l  = sh_left ? rot_e : ((nbits - rot_e) & (nbits - 6'd1));
wire [63:0] rot_du = ({32'd0, ym} << nbits) | {32'd0, ym};
wire [31:0] rot_res = (rot_du >> (nbits - rot_l)) & {32{1'b1}};

// ROTC rotates one more bit than the operand has, so the modulo is not a
// power of two and is done by subtraction.
wire  [6:0] rc_m = {1'b0, nbits} + 7'd1;              // 9, 17 or 33
logic [7:0] rc_e_raw;
always_comb begin
    integer k;
    rc_e_raw = sh_amt;
    for (k = 0; k < 15; k = k + 1)
        if (rc_e_raw >= {1'b0, rc_m}) rc_e_raw = rc_e_raw - {1'b0, rc_m};
end
// A right rotate by e is a left rotate by m - e, and by m - 0 = m, which is
// none at all rather than a whole turn.
wire  [6:0] rc_e = sh_left           ? rc_e_raw[6:0]
                 : (rc_e_raw == 8'd0) ? 7'd0
                                      : (rc_m - rc_e_raw[6:0]);
// CY sits immediately above the operand -- at bit `nbits`, which is where the
// concatenation puts it for a byte as much as for a word.
wire [65:0] rc_w  = (({65'd0, cy_in} << nbits) | {34'd0, ym}) &
                    ((66'd1 << rc_m) - 66'd1);
wire [65:0] rc_du = (rc_w << rc_m) | rc_w;
wire [65:0] rc_ro = (rc_du >> (rc_m - rc_e));
wire [31:0] rotc_res = rc_ro[31:0];
// The bit sitting in the carry position IS the last one rotated through it.
wire        rotc_cy  = sh_zero ? 1'b0 : rc_ro[nbits];

// ROT's carry is the same idea: a left rotate leaves the last bit to cross
// the MSB in bit 0, and a right rotate leaves it in the MSB.
wire        rot_cy = sh_zero ? 1'b0
                   : sh_left ? rot_res[0]
                             : |(rot_res & msb);

logic [31:0] raw;
logic        f_cy, f_ov, f_s, f_z;

always_comb begin
    raw    = 32'd0;
    f_cy   = flags_in[PSW_CY];
    f_ov   = 1'b0;
    writes = 1'b1;

    case (op)
        ALU_ADD, ALU_ADDC, ALU_INC: begin
            raw  = sum[31:0];
            f_cy = carry_of(sum, opbytes);
            f_ov = (sign_of(xa, msb) == sign_of(ym, msb)) &&
                   (sign_of(raw, msb) != sign_of(ym, msb));
        end
        ALU_SUB, ALU_SUBC, ALU_CMP, ALU_DEC: begin
            raw  = diff[31:0];
            f_cy = carry_of(diff, opbytes);          // a borrow
            f_ov = (sign_of(xa, msb) != sign_of(ym, msb)) &&
                   (sign_of(raw, msb) != sign_of(ym, msb));
            if (op == ALU_CMP) writes = 1'b0;
        end
        ALU_NEG: begin
            raw  = negd[31:0];
            f_cy = carry_of(negd, opbytes);
            // Negating the most negative value is the one overflow.
            f_ov = (sign_of(xm, msb) && sign_of(raw, msb));
        end
        // "The source operand is unaffected by this instruction", and the
        // destination is written and not read: dst.b.w / dst.w.w.
        // "No action is taken."  Nothing is written and no flag moves.
        ALU_NOP: writes = 1'b0;
        // "dst <- effective_address( src )".  The sequencer computes the
        // address and presents it as x; this passes it through, and the
        // destination is a word whatever the source's size field said.
        ALU_MOVEA: raw = x;
        // "The contents of the Program Status Word (PSW) are copied to the
        // destination operand."  The sequencer presents it as x.
        ALU_GETPSW: raw = x;
        // "PSW <- ( PSW & ~mask ) | ( newPSW & mask )".  Neither operand is
        // written -- both syntax lines are ".r" -- so the merge is the
        // sequencer's, at retirement, and nothing is produced here.
        ALU_UPDPSWH, ALU_UPDPSWW: writes = 1'b0;
        ALU_BRKV, ALU_BRK: writes = 1'b0;
        // Its operand is a condition nibble and a vector nibble, both of
        // which the sequencer reads; nothing is written back to it.
        ALU_TRAP: writes = 1'b0;
        // No operand at all, and it clears none of the flags it reads:
        // its page prints a NINE-line Condition Codes block, the four
        // integer flags and the five floating point ones, all Unchanged.
        ALU_TRAPFL: writes = 1'b0;
        // Its destination is the privileged register the second operand
        // names, which is not an operand at all -- so nothing is written
        // here.
        ALU_LDPR: writes = 1'b0;
        // No operand, and all four flags Unchanged.
        ALU_HALT: writes = 1'b0;
        // "dst <- PrivilegedRegister( regID )".  The sequencer has already
        // read the privileged register and presents it as x.
        ALU_STPR: raw = x;
        ALU_RVBIT: raw = {24'd0, rvbit_res};
        ALU_RVBYT: raw = rvbyt_res;
        // "If the specified condition is satisfied by the integer PSW
        // condition codes, the value 01H (true) is stored in the destination.
        // Otherwise, the value 00H (false) is stored" -- exactly 01H and 00H,
        // not "non-zero" and "zero".  The condition is the source's LOW
        // nibble.
        ALU_SETF: raw = cond_true(x[3:0], flags_in) ? 32'd1 : 32'd0;
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
        ALU_MOV:  raw = xm;
        ALU_MOVS: raw = mov_sx;
        ALU_MOVZ: raw = mov_zx;
        ALU_MOVT: begin
            raw  = mov_zx;                          // masked to the width below
            f_ov = movt_ov;
        end
        ALU_SHL: begin
            raw  = shl_res;
            f_cy = shl_cy;
            f_ov = 1'b0;                            // "OV  Cleared"
        end
        ALU_SHA: begin
            raw  = sha_res;
            f_cy = sha_cy;
            f_ov = sha_ov;
        end
        ALU_ROT: begin
            raw  = rot_res;
            f_cy = rot_cy;
            f_ov = 1'b0;
        end
        ALU_ROTC: begin
            raw  = rotc_res;
            f_cy = rotc_cy;
            f_ov = 1'b0;
        end
        default: ;
    endcase
end

// S and Z are read at the operand's width, which is the decision above.
//
// The moves are the exceptions.  MOV's flags column on p.3.296 is blank and
// MOVS and MOVZ print "CY Unchanged / OV Unchanged / S Unchanged / Z
// Unchanged" outright, so all three leave the four as they found them.  MOVT
// is the odd one: the databook marks one flag for it and the Description says
// which -- "an integer overflow has occurred and the OV flag is set" -- so OV
// moves and the other three do not.
//
// DECISION, not from a page: MOVT CLEARS OV when nothing was truncated away.
// Its Condition Codes block's legend lines did not survive the scan (the
// block OCRs as the two column headings and nothing else), and the sentence
// in the Description says only when OV is set.  Every other block in S7 that
// touches OV says "otherwise cleared", and a flag that could only ever be set
// would be unlike anything else in this instruction set.
// "CY Unchanged / OV Unchanged / S Unchanged / Z Unchanged" on all three of
// the new pages as well, so a reversal that produces zero does not set Z.
wire keep_all = (op == ALU_MOV)   || (op == ALU_MOVS)  || (op == ALU_MOVZ) ||
                (op == ALU_RVBIT) || (op == ALU_RVBYT) || (op == ALU_SETF) ||
                (op == ALU_NOP)   || (op == ALU_MOVEA) || (op == ALU_GETPSW) ||
                (op == ALU_BRKV)  || (op == ALU_BRK)    || (op == ALU_TRAP) ||
                (op == ALU_TRAPFL) || (op == ALU_LDPR)  || (op == ALU_STPR) ||
                (op == ALU_HALT);
wire keep_but_ov = (op == ALU_MOVT);

assign result    = raw & mask;
assign f_s       = sign_of(raw, msb);
assign f_z       = ((raw & mask) == 32'd0);
always_comb begin
    if (keep_all)          flags_out = flags_in;
    else if (keep_but_ov)  begin
        flags_out           = flags_in;
        flags_out[PSW_OV]   = f_ov;
    end else               flags_out = {f_cy, f_ov, f_s, f_z};
end

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
