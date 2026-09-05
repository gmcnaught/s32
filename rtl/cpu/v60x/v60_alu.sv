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
    // The bit field group's two extra inputs: where the field starts within
    // the word the sequencer read, and how long it is.  `bf_len` is six bits
    // because a length of 32 is legal and 32 does not fit in five.
    input                 [2:0] bf_resid,
    input                 [5:0] bf_len,
    // The decimal group's third operand: Format VII's extension byte again,
    // carrying a MASK PATTERN here rather than a length.  §6 admits the reuse
    // in one clause -- "This field is also used to store the mask pattern for
    // the ADDDC, SUBDC, SUBRDC, and CVTD instructions."
    input                 [7:0] dec_pat,
    input                 [3:0] flags_in,  // {CY, OV, S, Z} as the PSW holds them

    // The Decimal Format exception, which every one of the five can raise and
    // which the sequencer turns into vector 23.
    output logic                dec_bad,
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

// The four bit instructions.  "An Illegal Data Field exception occurs if the
// bit offset is outside the range 0 to 31" -- the sequencer raises that, so by
// the time the offset reaches here it is known to fit in five bits.
wire  [4:0] bit_sel  = x[4:0];
wire [31:0] bit_one  = 32'd1 << bit_sel;
// "The CY and Z flags reflect the state of the bit PRIOR to the execution of
// the instruction", which every one of the four pages says twice -- once as
// the two Operation lines and once in prose.  So SET1 on a bit that was
// already 1 leaves CY = 1 and Z = 0, having changed nothing, and SET1 on a
// clear bit leaves CY = 0 and Z = 1 having set it.  CY and Z are always
// complements here; there is no input for which they agree.
wire        bit_old  = |(y & bit_one);

// ---------------------------------------------------------------------------
// The bit field group.
// ---------------------------------------------------------------------------
// One shift and one mask over the word the sequencer read, which is all the
// "must not exceed thirty-two" constraint permits it to be.
//
// The mask is built in 33 bits so that a length of 32 -- legal, and the
// maximum -- does not shift a 32-bit one off its own top.  `bf_len` is
// likewise six bits wide for the same reason.
wire [32:0] bf_mask33 = (33'd1 << bf_len) - 33'd1;
wire [31:0] bf_mask   = bf_mask33[31:0];

// WHICH operand carries the bit-addressed word differs across the group, and
// it is the syntax lines that say so rather than a convention:
//
//   extbfs bsrc.w.r, blen.b.r, dst.w.w    -- the field is operand ONE
//   cmpbfs bsrc.w.r, blen.b.r, src.w.r    -- the field is operand ONE
//   insbfr src.w.r,  bdst.w.rw, blen.b.r  -- the field is operand TWO
//
// INSBF is the odd one because its bit-addressed operand is the DESTINATION,
// and a destination is operand two everywhere in this sequencer.
wire        bf_is_ins = (op == ALU_INSBFR) || (op == ALU_INSBFL);
wire [31:0] bf_word   = bf_is_ins ? y : x;

// The field, right justified, as it sits in memory.
wire [31:0] bf_field  = (bf_word >> bf_resid) & bf_mask;
// Its sign bit is the field's own top bit, which moves with the length.
wire        bf_sign   = (bf_len == 6'd0) ? 1'b0 : bf_field[bf_len - 6'd1];
// "Extract Sign Extended": everything above the field takes that bit.
wire [31:0] bf_sx     = bf_sign ? (bf_field | ~bf_mask) : bf_field;
// "Left Justified": the field is moved to the TOP of the word.  A length of
// zero would shift by 32, so it is special-cased rather than left to the
// simulator -- and zero is a legal length that both pages discuss.
wire [31:0] bf_left   = (bf_len == 6'd0) ? 32'd0 : (bf_field << (6'd32 - bf_len));

// INSBF takes its source from opposite ends for its two variants: "Insert
// Right Justified" uses the source's low `len` bits and "Insert Left
// Justified" its high ones.
wire [31:0] bf_ins_r  = x & bf_mask;
wire [31:0] bf_ins_l  = (bf_len == 6'd0) ? 32'd0 : ((x >> (6'd32 - bf_len)) & bf_mask);

// ---------------------------------------------------------------------------
// The decimal group.
// ---------------------------------------------------------------------------
// A packed byte is TWO digits, high nibble the more significant, and both must
// be 0-9: "When a nibble is expected to contain a digit, only the valid BCD
// values [0..9] can be specified."  A zoned byte is ONE digit in the low
// nibble with an unrestricted zone above it.
//
// Neither is signed.  §3 gives the decimal data type no sign nibble, no sign
// byte and no convention at all, which is why S never moves on any of the five
// and why OV never moves either: there is no sign to report and no range to
// overflow beyond the byte, whose overflow IS the carry.
wire  [3:0] dec_x_hi = x[7:4];
wire  [3:0] dec_x_lo = x[3:0];
wire  [3:0] dec_y_hi = y[7:4];
wire  [3:0] dec_y_lo = y[3:0];
wire  [7:0] dec_xv   = dec_x_hi * 4'd10 + dec_x_lo;   // 0..99
wire  [7:0] dec_yv   = dec_y_hi * 4'd10 + dec_y_lo;
wire        dec_cy_in = flags_in[PSW_CY];

// "The CY flag and the decimal source operand are added to the decimal
// destination operand."  CY is an INPUT, and the carry out is DECIMAL -- out of
// the top digit at 100, not bit 8 of a binary sum.  0x59 + 0x59 is 0xB2 in
// binary with no carry; as decimal it is 118, which is 0x18 with CY set.
wire  [8:0] dec_add  = {1'b0, dec_yv} + {1'b0, dec_xv} + {8'd0, dec_cy_in};
wire signed [8:0] dec_sub  = $signed({1'b0, dec_yv}) - $signed({1'b0, dec_xv})
                             - $signed({8'd0, dec_cy_in});
wire signed [8:0] dec_subr = $signed({1'b0, dec_xv}) - $signed({1'b0, dec_yv})
                             - $signed({8'd0, dec_cy_in});

wire        dec_is_add  = (op == ALU_ADDDC);
wire        dec_is_sub  = (op == ALU_SUBDC);
wire        dec_is_subr = (op == ALU_SUBRDC);
wire        dec_is_arith = dec_is_add || dec_is_sub || dec_is_subr;

wire signed [8:0] dec_raw = dec_is_add  ? $signed(dec_add)
                          : dec_is_sub  ? dec_sub : dec_subr;
// "The CY flag will be set if there is a carry out" / "if there is a borrow".
wire        dec_cy_out = dec_is_add ? (dec_add >= 9'd100) : (dec_raw < 0);
// Brought back into 0..99 the way a decimal adder does.
wire  [7:0] dec_val    = dec_cy_out ? (dec_is_add ? (dec_add[7:0] - 8'd100)
                                                  : (dec_raw[7:0] + 8'd100))
                                    : dec_raw[7:0];
// And back to packed BCD.  The two halves are named rather than concatenated
// inline: `{dec_val / 10, dec_val % 10}` concatenates two EIGHT-bit results and
// an eight-bit target keeps only the low half of that, which is the remainder
// alone -- 118 came out as 0x08 rather than 0x18.
wire  [3:0] dec_res_hi = dec_val / 8'd10;
wire  [3:0] dec_res_lo = dec_val % 8'd10;
wire  [7:0] dec_res    = {dec_res_hi, dec_res_lo};

// The conversions.  "The byte length source operand is unpacked by performing
// a bit-wise OR of the digits with the pattern operand" -- and the digit order
// CROSSES, which is the thing a summary would lose: the packed byte's HIGH
// nibble becomes the digit of the zoned halfword's LOW byte.
// `pat` is OR'd in as a WHOLE BYTE into both halves, so its low nibble lands on
// top of the digit -- a pattern with pat[3:0] non-zero corrupts the digit it is
// meant to decorate.  No page forbids it and no page says what the result is;
// this does what the Operation block prints.
wire  [7:0] dec_pz_lo = {4'd0, dec_x_hi} | dec_pat;
wire  [7:0] dec_pz_hi = {4'd0, dec_x_lo} | dec_pat;
wire [15:0] dec_pz    = {dec_pz_hi, dec_pz_lo};
// The exact inverse: dst[7:4] <- src[3:0], dst[3:0] <- src[11:8].
wire  [7:0] dec_zp = {x[3:0], x[11:8]};

// "Following the addition operation, the result is checked to verify that a
// valid BCD representation exists" -- the ARITHMETIC three check the RESULT and
// not their operands, which the page is explicit about and which is worth
// stating because it is the reverse of the conversions.
// The OPERAND rule, which §3 states as a property of the DATA and not of any
// instruction -- so it applies to all five, and the two conversions below
// already follow it:
//
//   "When a nibble is expected to contain a digit, only the valid BCD values
//    [0..9] can be specified.  ANY OTHER VALUE WILL CAUSE AN ILLEGAL DECIMAL
//    FORMAT EXCEPTION TO OCCUR.  There is no restriction on the contents of
//    the zone field."
//
// CORRECTION.  This check was absent and the commit that added the group
// claimed the result check below was "unreachable by construction", on the
// reasoning that a value-based adder always produces valid BCD.  THAT WAS
// FALSE, and docs/v60/DECIMAL-AUDIT.md's D1 disproves it by construction:
// dec_xv reaches 165 for an input of 0xFF, not 99, so dec_val is not bounded
// by 99 either, and dec_res_hi -- a FOUR-bit wire taking dec_val/10 -- keeps a
// non-digit for dec_val in 100..159 and folds one back to 0..9 above that.
// ADDDC 0xA0 + 0xA0 raises today; ADDDC 0xF0 + 0xF0 does not and is silently
// wrong.  Over all 131,072 (x, y, CY) triples the result check fires on 22.5%
// of them and misses 81,600 cases with an invalid input nibble.
//
// So the same class of illegal input was caught about a quarter of the time,
// by magnitude rather than by anything architectural.  The operand check is
// TOTAL where the result check is partial.
wire        dec_op_bad  = (dec_x_hi > 4'd9) || (dec_x_lo > 4'd9) ||
                          (dec_y_hi > 4'd9) || (dec_y_lo > 4'd9);
// And the page's own extra rule on the way out, kept because it is a rule and
// because it constrains an adder built nibble-wise, which can produce a
// non-digit from two digits: "Following the addition operation, the result is
// checked to verify that a valid BCD representation exists in the unmasked
// portion of the result."  With the operands rejected on the way in this IS
// now unreachable -- which is what makes the claim true rather than assumed.
wire        dec_res_bad = dec_op_bad ||
                          (dec_res[7:4] > 4'd9) || (dec_res[3:0] > 4'd9);
// CVTD.PZ checks its SOURCE, prior to the conversion.
wire        dec_pz_bad  = (dec_x_hi > 4'd9) || (dec_x_lo > 4'd9);
// CVTD.ZP checks two different things, and the zone check is the only place in
// the group where a well-formed digit position still raises: "The upper
// nibbles are then compared to the upper nibble of the mask pattern."  §3 says
// "There is no restriction on the contents of the zone field", so this
// restriction comes from the INSTRUCTION and not from the data type.
wire        dec_zp_bad  = (x[7:4]   != dec_pat[7:4]) ||
                          (x[15:12] != dec_pat[7:4]) ||
                          (x[3:0]   > 4'd9) || (x[11:8] > 4'd9);

// CMPBF's subtraction runs the OTHER WAY from CMP's.  Its Operation block is
// "flags <- src - bitfield" and its Description says the same in words -- "The
// comparison is made by subtracting the bit field data from the word length
// source operand" -- where CMP's is dst - src.  The ALU's own `diff` is
// ym - xa, so this cannot reuse it: the source here is x and the field is not
// an operand at all.
//
// "If the bit field length is zero, zero will be subtracted from the source
// operand", which falls out of a zero-length mask.
wire [31:0] bf_cmp_val = (op == ALU_CMPBFS) ? bf_sx   :
                         (op == ALU_CMPBFL) ? bf_left : bf_field;
// The source is operand TWO here -- "cmpbfs bsrc.w.r, blen.b.r, src.w.r" --
// because the field is operand one.
wire [32:0] bf_cmp     = {1'b0, y} - {1'b0, bf_cmp_val};
wire        bf_cmp_ov  = (y[31] != bf_cmp_val[31]) && (bf_cmp[31] != y[31]);

wire        cy_in = flags_in[PSW_CY];

// The addend.  "The INC instruction is a shorter encoding for the more general
// instruction `add #1, dst`" and the DEC page says the same of `sub #1, dst`
// (S7), so INC and DEC ARE the adder with the addend fixed at one, and they
// share every line below -- including the overflow terms, which is what makes
// their Condition Codes blocks identical to ADD's and SUB's without a second
// derivation to keep in step.
wire        addend_one = (op == ALU_INC) || (op == ALU_DEC);
// TASI is the same idea with a different constant: its Operation is
// "flags <- dst - 0FFH", so it IS the subtractor with the subtrahend fixed at
// 0FFH, exactly as INC and DEC are the adder with the addend fixed at one.
// Taking it from here rather than having the sequencer fake an operand keeps
// the constant on the page it came from.
wire [31:0] xa = addend_one       ? (32'd1 & mask)          :
                 (op == ALU_TASI) ? (32'h0000_00FF & mask)  : xm;

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
        // Both are "dst <- port" / "port <- src": a move, and all four flags
        // Unchanged.  Which side is the port is the sequencer's business.
        ALU_IN, ALU_OUT: raw = x;
        // PUSH's operand never reaches the ALU: the sequencer writes it to
        // the stack itself.
        ALU_PUSH: writes = 1'b0;
        // POP's destination takes what the sequencer read off the stack,
        // presented as x -- the same shape as GETPSW and STPR.
        ALU_POP: raw = x;
        // Both do all their work on R30 and R31, in the sequencer.
        ALU_PREPARE, ALU_DISPOSE: writes = 1'b0;
        // Half of the exchange: dst2 takes what dst1 held, presented as x.
        // The other half is the sequencer's, because it needs a second write
        // port's worth of work and the page constrains it to a register.
        ALU_XCH: raw = x;
        // The mask walk is entirely the sequencer's.
        ALU_PUSHM, ALU_POPM: writes = 1'b0;
        // Both operands ".b.r"; the effect is entirely an exception.
        ALU_CHLVL: writes = 1'b0;
        // "flags <- dst - Rn", which is CMP with x = Rn and y = dst.  Nothing
        // is produced here: on a match the destination takes R28 and on a
        // mismatch Rn takes the destination, and neither value is the
        // subtraction.
        ALU_CAXI: begin
            raw    = diff[31:0];
            f_cy   = carry_of(diff, opbytes);
            f_ov   = (sign_of(xa, msb) != sign_of(ym, msb)) &&
                     (sign_of(raw, msb) != sign_of(ym, msb));
            writes = 1'b0;
        end
        // "dst <- 0FFH" -- unconditionally, whatever the comparison said.
        // The flags are the comparison's and the result is the constant, which
        // is why this cannot be CMP with a different writeback.
        // "The designated bit field is extracted using the specified mode and
        // stored in the destination operand."  All four flags Unchanged --
        // p.3.297's row is blank for both EXTBF and INSBF.
        //
        // "If the bit field length is zero, zero will be stored in the
        // destination operand", which falls out: a zero-length mask is zero.
        // "Three reads, no write -- the result is the flags."
        ALU_CMPBFS, ALU_CMPBFZ, ALU_CMPBFL: writes = 1'b0;
        // "The decimal addition operation occurs only for the unmasked portion
        // of the operands, as determined by the mask pattern."
        //
        // NOT IMPLEMENTED, and it cannot be from what is held: no page in
        // either book defines what a mask pattern looks like, which bit or
        // nibble masks what, or what "unmasked portion" means at nibble
        // granularity.  The two CVTD instructions give bit-level Operation
        // blocks for THEIR use of the same byte -- OR'd in on .PZ, compared
        // against pat[7:4] on .ZP -- but that is a zone value, a different use
        // of the field.  Same byte, two meanings, and only one of them printed.
        //
        // s32_v60.sv decodes the pattern and then never reads it on these
        // three, so there is no oracle for it either.  The operation here is
        // over the whole byte, which is what an all-unmasked pattern means, and
        // the gap is recorded in docs/v60/DECIMAL.md rather than guessed.
        ALU_ADDDC, ALU_SUBDC, ALU_SUBRDC: raw = {24'd0, dec_res};
        ALU_CVTDPZ: raw = {16'd0, dec_pz};
        ALU_CVTDZP: raw = {24'd0, dec_zp};
        ALU_EXTBFS: raw = bf_sx;
        ALU_EXTBFZ: raw = bf_field;
        ALU_EXTBFL: raw = bf_left;
        // "The source operand is converted to a bit field of specified length
        // and stored in the destination operand" -- so the word read is
        // rewritten with the field replaced, and everything outside it kept.
        //
        // "No transfer will occur if the bit field length is zero", which is a
        // DIFFERENT rule from EXTBF's at zero length: there the destination
        // takes zero, here it is untouched.  A zero-length mask makes the
        // merge below the identity, so that falls out too.
        ALU_INSBFR: raw = (bf_word & ~(bf_mask << bf_resid)) | (bf_ins_r << bf_resid);
        ALU_INSBFL: raw = (bf_word & ~(bf_mask << bf_resid)) | (bf_ins_l << bf_resid);
        ALU_TASI: begin
            raw  = 32'h0000_00FF;
            f_cy = carry_of(diff, opbytes);          // "Set if a borrow"
            f_ov = (sign_of(xa, msb) != sign_of(ym, msb)) &&
                   (sign_of(diff[31:0], msb) != sign_of(ym, msb));
        end
        // "test1 offset.w.r, base.w.r" -- both operands read, nothing written.
        ALU_TEST1: begin writes = 1'b0; f_cy = bit_old; end
        ALU_SET1:  begin raw = y |  bit_one; f_cy = bit_old; end
        ALU_CLR1:  begin raw = y & ~bit_one; f_cy = bit_old; end
        ALU_NOT1:  begin raw = y ^  bit_one; f_cy = bit_old; end
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
                (op == ALU_HALT)   || (op == ALU_IN)    || (op == ALU_OUT) ||
                (op == ALU_EXTBFS) || (op == ALU_EXTBFZ) || (op == ALU_EXTBFL) ||
                (op == ALU_INSBFR) || (op == ALU_INSBFL) ||
                (op == ALU_PUSH)   || (op == ALU_POP)   ||
                (op == ALU_PREPARE) || (op == ALU_DISPOSE) ||
                (op == ALU_XCH)    || (op == ALU_PUSHM) || (op == ALU_POPM) ||
                (op == ALU_CHLVL);
wire keep_but_ov = (op == ALU_MOVT);
// "CY Set if the designated bit is 1, otherwise cleared / OV Unchanged /
// S Unchanged / Z Set if the designated bit is 0, otherwise cleared" -- the
// same four lines on all four pages.  Z is NOT the usual "is the result zero":
// SET1 on a clear bit produces a non-zero result and still leaves Z set,
// because Z describes the bit that was read and not the word that was written.
wire bit_op = (op == ALU_TEST1) || (op == ALU_SET1) ||
              (op == ALU_CLR1)  || (op == ALU_NOT1);
// TASI's S and Z describe the COMPARISON and not the value written.  "S Set if
// the comparison results are negative" and "Z Set if the comparison results
// are zero", where the result written is always 0FFH -- so the ordinary path,
// which takes both from `raw`, would report S = 1 and Z = 0 every time.
wire tasi_op = (op == ALU_TASI);

// CMPBF's four flags are an ordinary subtract's -- "Set if a BORROW is
// generated", which is CMP's convention and not ADD's -- but over its own
// subtraction rather than the ALU's, so it takes its own branch.
wire cmpbf_op = (op == ALU_CMPBFS) || (op == ALU_CMPBFZ) || (op == ALU_CMPBFL);

// The decimal five, whose flag rule is unlike anything else here.
//
// Z IS STICKY: "Unchanged if the result is zero, otherwise cleared."  It is
// never SET by any of the five.  A program presets it and it survives to the
// end of a multi-byte chain only if every byte produced zero -- an accumulated
// "the whole number was zero" rather than a per-byte result.
//
// The Condition Codes block and the Description DISAGREE on one clause.  The
// block says Z is cleared when the result is non-zero; the Description says
// "If the result is non-zero OR A CARRY IS GENERATED, the Z flag will be
// cleared".  The Description is the more specific statement and the one that
// makes the chained use correct -- a byte that produces 00 with a carry out is
// not a zero result of the whole number -- so it is the reading taken here.
// Same page, same book, and nothing reconciles them; recorded in
// docs/v60/DECIMAL.md.
wire dec_op = dec_is_arith || (op == ALU_CVTDPZ) || (op == ALU_CVTDZP);
// Which quantity Z tests differs across the group and is transcribed as
// printed: the arithmetic three test their RESULT, CVTD.PZ tests its SOURCE
// and CVTD.ZP tests its DESTINATION.  For an exact conversion the last two are
// the same test, so nothing observable turns on it -- but they are printed
// differently.
wire dec_z_clear = dec_is_arith        ? ((dec_res != 8'd0) || dec_cy_out)
                 : (op == ALU_CVTDPZ)  ? (x[7:0] != 8'd0)
                                       : (dec_zp != 8'd0);

// "a Decimal Format exception will occur and the destination will remain
// unchanged", on all five pages.  WHEN each checks differs and is transcribed
// as printed: the arithmetic three check the RESULT following the operation,
// and the two conversions check their SOURCE prior to it.
assign dec_bad = dec_is_arith        ? dec_res_bad
               : (op == ALU_CVTDPZ)  ? dec_pz_bad
               : (op == ALU_CVTDZP)  ? dec_zp_bad
                                     : 1'b0;

assign result    = raw & mask;
assign f_s       = sign_of(raw, msb);
assign f_z       = ((raw & mask) == 32'd0);
always_comb begin
    if (keep_all)          flags_out = flags_in;
    else if (keep_but_ov)  begin
        flags_out           = flags_in;
        flags_out[PSW_OV]   = f_ov;
    end else if (dec_op) begin
        // "OV Unchanged / S Unchanged" on all five, and CY moves only on the
        // arithmetic three -- the plate's `- - - .` against `. - - .`.
        flags_out          = flags_in;
        if (dec_is_arith) flags_out[PSW_CY] = dec_cy_out;
        if (dec_z_clear)  flags_out[PSW_Z]  = 1'b0;
    end else if (cmpbf_op) begin
        flags_out = {bf_cmp[32], bf_cmp_ov, bf_cmp[31], (bf_cmp[31:0] == 32'd0)};
    end else if (tasi_op)  begin
        flags_out = {f_cy, f_ov, sign_of(diff[31:0], msb),
                     ((diff[31:0] & mask) == 32'd0)};
    end else if (bit_op)   begin
        flags_out           = flags_in;
        flags_out[PSW_CY]   = bit_old;
        flags_out[PSW_Z]    = ~bit_old;
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
