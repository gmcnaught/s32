//============================================================================
//  v60_muldiv -- MUL, MULU, DIV, DIVU, REM and REMU.
//
//  Clean-room.  Every rule below is the sentence its instruction's page prints,
//  and the six pages disagree with each other often enough that they are worth
//  quoting rather than summarising:
//
//    MUL   "dst <- dst * src"    "An overflow occurs when the double length
//          intermediate product does [not] fit within the precision of the
//          destination operand."
//          OV: integer overflow.  S: "the result is negative".  Z.  CY unchanged.
//    MULU  "dst <- dst * src (unsigned)"   "An overflow occurs when the product
//          cannot fit within the precision of the destination operand."
//          S: "the MSB of the result is set" -- which is the same bit.
//    DIV   "dst <- dst / src"    "The quotient is computed according to the
//          rules of signed division.  Overflow occurs when the negative maximum
//          integer is divided by -1.  The destination will remain unchanged if
//          an integer overflow or Zero Divide exception occurs."
//          Exceptions: Zero Divide, and nothing else -- the overflow is a flag.
//    DIVU  the same, unsigned, and "OV Cleared": unsigned division cannot
//          overflow.
//    REM   "dst <- dst % src"    "The sign of the remainder is the same as the
//          sign of the dividend."  "OV Cleared."
//    REMU  "All operands are treated as unsigned data, however, the condition
//          code flags are set as if the remainder is a signed value."
//
//  The destination is the dividend and the source the divisor, which the
//  syntax lines fix -- "div.b src.b.r, dst.b.rw" with the operation "dst / src".
//
//  ---------------------------------------------------------------------------
//  Where this disagrees with MAME, and why
//  ---------------------------------------------------------------------------
//  Two places, and the project's own rule decides both: execution semantics
//  come from the Programmer's Reference, with MAME as an oracle where the
//  Reference is silent.  Here it is not silent.
//
//  * A DIVIDE BY ZERO RAISES.  DIV, DIVU, REM and REMU each print an
//    Exceptions block containing "Zero Divide", Table 8-1 gives it code 1500
//    in the Arithmetic Exceptions group, and Figure 8-2 puts the Integer
//    Arithmetic Exception at vector 21.  MAME does not trap: it leaves the
//    destination alone, sets Z and S from it and clears OV, and the Sega
//    System 32 core inherits that (`s32_v60.sv`, "MAME divide-by-zero:
//    destination unchanged and no trap").  Three NEC statements against an
//    emulator's omission.
//
//  * MUL's OVERFLOW IS A SIGNED FIT.  The page's test is whether "the double
//    length intermediate product does [not] fit within the precision of the
//    destination operand", and for a signed multiply into a signed destination
//    that is a signed fit: the discarded half must be the sign extension of
//    the half that is kept.  MAME tests `(product >> width) != 0` on the
//    signed product's bit pattern, which is an UNSIGNED fit test, so it
//    reports overflow for `MUL.W -1, 1` -- a product that fits a signed word
//    exactly.  MULU's page says "cannot fit", the destination is unsigned, and
//    there the two tests are the same one.
//
//  Both are marked here and in docs/v60/MULTIPLY-DIVIDE.md rather than left to
//  be discovered by a diff against the shipping core.
//
//  ---------------------------------------------------------------------------
//  What is NOT here
//  ---------------------------------------------------------------------------
//  MULX, MULUX, DIVX and DIVUX.  Their destination is a doubleword -- "a
//  register pair, low register first" (S3) -- and nothing in this tree
//  addresses one: v60_regfile has `ra_pair` and no caller, and v60_ea warns
//  when asked for an eight-byte register-direct operand.  That is
//  docs/v60/NEXT-STEPS.md's own item, and it is a datapath change rather than
//  an arithmetic one: DIVX in particular writes a quotient into the low word
//  and a remainder into the high word of one destination.
//
//  ---------------------------------------------------------------------------
//  Why it iterates
//  ---------------------------------------------------------------------------
//  A shift-add multiplier and a restoring divider, 32 steps each, over one
//  64-bit accumulator -- the two algorithms have the same shape, which is why
//  they share it.  Not because the databook says so: it says nothing about how
//  long any instruction takes, and every cell of its Clocks column is blank
//  (docs/v60/INSTRUCTION-TIMING.md).  It iterates because `*` and `/` on
//  variable 32-bit operands are not something to hand a fitter, and because
//  the sequencer needs a busy/done handshake either way.
//============================================================================
`timescale 1ns/1ps

module v60_muldiv
    import v60_alu_pkg::*;
    import v60_psw_pkg::*;
(
    input               clk,
    input               rst,

    input               start,      // one pulse, with the operands presented
    input  alu_op_e     op,
    input         [3:0] opbytes,    // the operands' width: 1, 2 or 4
    input        [31:0] x,          // src -- the multiplier, or the divisor
    input        [31:0] y,          // dst -- the multiplicand, or the dividend
    // The X forms' extra half.  For DIVX and DIVUX the dividend is the whole
    // doubleword, so its HIGH word arrives here; for MULX and MULUX only the
    // low word is an input at all -- "The word designated by the destination
    // operand is multiplied by the word contents of the source operand" -- so
    // this is ignored by them.
    input        [31:0] y_hi,
    input         [3:0] flags_in,   // {CY, OV, S, Z}; CY is unchanged by all six

    output logic [31:0] result,
    // The upper word of a doubleword destination: the product's high half for
    // MULX and MULUX, and the REMAINDER for DIVX and DIVUX -- which is not the
    // same quantity as `result` at all.
    output logic [31:0] result_hi,
    output logic  [3:0] flags_out,
    output logic        writes,     // "the destination will remain unchanged"
    output logic        zero_div,   // the Integer Arithmetic Exception
    output logic        busy,
    output logic        done
);

wire is_mulx = (op == ALU_MULX) || (op == ALU_MULUX);
wire is_divx = (op == ALU_DIVX) || (op == ALU_DIVUX);
wire is_dbl  = is_mulx || is_divx;
wire is_mul  = (op == ALU_MUL) || (op == ALU_MULU) || is_mulx;
wire is_rem  = (op == ALU_REM) || (op == ALU_REMU);
wire is_sgn  = (op == ALU_MUL)  || (op == ALU_DIV) || (op == ALU_REM) ||
               (op == ALU_MULX) || (op == ALU_DIVX);

wire [31:0] mask = (opbytes == 4'd1) ? 32'h0000_00FF :
                   (opbytes == 4'd2) ? 32'h0000_FFFF : 32'hFFFF_FFFF;
wire [31:0] msb  = (opbytes == 4'd1) ? 32'h0000_0080 :
                   (opbytes == 4'd2) ? 32'h0000_8000 : 32'h8000_0000;

// The operands at their own width, extended to 32 bits the way the operation
// reads them.  "If the immediate quick addressing mode is specified for the
// source operand, the immediate data is zero extended to the source operand
// length before performing the operation" -- which happens above this, in the
// addressing mode; what happens here is the extension from the OPERAND's
// length to the machine's.
wire [31:0] xz = x & mask;
wire [31:0] yz = y & mask;
wire        xs = |(xz & msb);
wire        ys = |(yz & msb);
wire [31:0] xe = (is_sgn && xs) ? (xz | ~mask) : xz;
wire [31:0] ye = (is_sgn && ys) ? (yz | ~mask) : yz;

// Magnitudes, so one unsigned engine serves both signednesses.
wire [31:0] xm = (is_sgn && xs) ? (~xe + 32'd1) : xe;
wire [31:0] ym = (is_sgn && ys) ? (~ye + 32'd1) : ye;

// And the doubleword dividend, for DIVX and DIVUX.  "the lower numbered
// register contains the least significant word while the higher numbered
// register contains the most significant word" (S2), and in memory the
// doubleword is "identified by the address of the low order byte" -- so the
// machine is consistently little-endian about this and {y_hi, y} is the value.
wire [63:0] yd  = {y_hi, y};
wire        yds = yd[63];
wire [63:0] ydm = (is_sgn && yds) ? (~yd + 64'd1) : yd;

// The X divides overflow on ordinary inputs, which no other divide here does:
// a 64-bit dividend over a 32-bit divisor needs up to 64 quotient bits and has
// 32 to put them in.  The magnitude test is the classic one -- if the high
// word alone is already at least the divisor, the quotient has run off the top
// before the loop starts.
//
// NOT ENUMERATED BY THE PAGE, and this is a decision.  DIVX's Description
// names exactly one overflow case, "the negative maximum integer divided by
// -1", which is the WORD DIV rule copied across; it does not mention the
// quotient-does-not-fit case, which for a doubleword dividend is far commoner.
// Its Condition Codes block says "OV Set if integer overflow occurs", so the
// general condition is plainly intended and the Description simply fails to
// list it.  The plate agrees that OV moves here where DIVU's prints a literal
// 0.  See docs/v60/DOUBLEWORD.md.
wire        divx_ovf = is_divx && (ydm[63:32] >= xm) && (xm != 32'd0);

typedef enum logic [1:0] { S_IDLE, S_RUN, S_FIN } state_e;
state_e      state;
logic  [5:0] cnt;
// SIXTY-FIVE bits, for the multiply, and the extra one is not slack: a
// shift-add multiplier's running high half is the previous high half plus the
// multiplicand, which is 33 bits before the shift brings it back down.  A
// 64-bit accumulator drops that bit and the byte and halfword widths never
// notice -- their operands are too small to reach it.  The word edges do:
// MULU.w 0xFFFFFFFE x 0x7FFFFFFF lost the carry out of bit 63 and reported OV
// clear on a product that needs 63 of them.
//
// The DIVIDER also uses the 33rd bit, and at these widths it cannot reach it.
// A 32-bit dividend gives a running remainder that is a prefix of the dividend
// reduced by the divisor, so after k of the 32 steps it is below 2^k, and it
// can only be at or above 2^31 on the last step -- where there is no further
// shift.  The bit is carried because DIVX and DIVUX divide a DOUBLEWORD, where
// it is reachable on every step.  The assertion at the bottom holds the
// argument rather than leaving it as a comment.
logic [64:0] acc;       // {product} for a multiply; {remainder, quotient} for a divide
logic [31:0] opnd;      // the multiplicand, or the divisor
logic        r_mul, r_rem, r_sgn;
logic        r_qneg, r_rneg;      // the signs the result gets back
logic  [3:0] r_bytes;
logic [31:0] r_mask, r_msb;
logic [31:0] r_ye;                // the dividend, for the DIV overflow test
logic        r_divov;
logic        r_dbl, r_mulx, r_divx;
logic        r_qneg64;            // the doubleword quotient's sign, for the fit test
logic  [3:0] r_flags_in;

assign busy = (state != S_IDLE);

// One step of either algorithm.  The multiply consumes a bit of the multiplier
// out of the bottom of the accumulator and adds the multiplicand into the top;
// the divide shifts the dividend up into the remainder and subtracts.
wire [64:0] mul_add  = acc[0] ? {acc[64:32] + {1'b0, opnd}, acc[31:0]} : acc;
wire [64:0] mul_next = {1'b0, mul_add[64:1]};

wire [64:0] div_sh   = {acc[63:0], 1'b0};
wire        div_fits = (div_sh[64:32] >= {1'b0, opnd});
wire [64:0] div_next = div_fits ? {div_sh[64:32] - {1'b0, opnd},
                                   div_sh[31:1], 1'b1}
                                : div_sh;

// ---------------------------------------------------------------------------
// The answer, once the engine has stopped.
// ---------------------------------------------------------------------------
// A multiply's product is 64 bits and the destination is `opbytes` wide; a
// divide's quotient and remainder are each at most as wide as the operands.
wire [63:0] acc64  = acc[63:0];
wire [63:0] prod   = r_qneg ? (~acc64 + 64'd1) : acc64;
wire [31:0] quo    = r_qneg ? (~acc[31:0] + 32'd1) : acc[31:0];
wire [31:0] rem_v  = r_rneg ? (~acc[63:32] + 32'd1) : acc[63:32];

wire [31:0] raw = r_mul ? prod[31:0] : (r_rem ? rem_v : quo);

// The upper word of a doubleword destination.  For a multiply it is the
// product's high half; for a divide it is the REMAINDER, which the DIVX page
// draws with its own caption -- "Upper Word/Register" over the remainder and
// "Lower Word/Register" over the quotient, one picture covering the register
// pair and the memory operand alike.
wire [31:0] raw_hi = r_mul ? prod[63:32] : rem_v;

// The signed X divide's second overflow test.  divx_ovf above catches a
// quotient that needs more than 32 bits; this catches one that needs all 32
// but the destination is signed, so only 31 of them are available.  -2^31 is
// representable and +2^31 is not, which is why the two bounds differ.
wire        divx_fit_bad = r_divx && r_sgn &&
                           (r_qneg64 ? (acc[31:0] > 32'h8000_0000)
                                     : (acc[31:0] > 32'h7FFF_FFFF));

// "does [not] fit within the precision of the destination operand".  Signed for
// MUL, unsigned for MULU -- see the header for where MAME reads this
// differently.
wire        fit_signed =
    (r_bytes == 4'd1) ? (prod[63:8]  == {56{prod[7]}}) :
    (r_bytes == 4'd2) ? (prod[63:16] == {48{prod[15]}}) :
                        (prod[63:32] == {32{prod[31]}});
wire        fit_unsigned =
    (r_bytes == 4'd1) ? (prod[63:8]  == 56'd0) :
    (r_bytes == 4'd2) ? (prod[63:16] == 48'd0) :
                        (prod[63:32] == 32'd0);

logic f_ov, f_s, f_z;
always_comb begin
    if (r_mulx) begin
        // "OV Cleared", unconditionally, on both X multiply pages -- and it is
        // coherent: a 32x32 product always fits 64 bits, so an X multiply
        // CANNOT overflow.  That is exactly the property distinguishing them
        // from MUL and MULU, whose OV reports a product too wide for the
        // destination.
        //
        // The plate disagrees, printing the same four glyphs on the X rows as
        // on the non-X rows above them, which is what a copied row looks like.
        // DECISION: take the Reference, because its reading is the only one
        // with a mechanism behind it.  docs/v60/DOUBLEWORD.md records it.
        f_ov = 1'b0;
    end else if (r_mul) begin
        f_ov = r_sgn ? !fit_signed : !fit_unsigned;
    end else if (r_rem) begin
        f_ov = 1'b0;                             // "OV Cleared", both pages
    end else if (r_divx) begin
        f_ov = r_divov || divx_fit_bad;
    end else begin
        f_ov = r_divov;                          // min / -1, and only that
    end

    if (r_mulx) begin
        // "The result" is the DOUBLEWORD product, so S is bit 63 and Z tests
        // all sixty-four.  Reading them off the low word instead would report
        // a 64-bit product of 0x1_00000000 as zero.
        f_s = prod[63];
        f_z = (prod == 64'd0);
    end else begin
        // DIVX's S and Z describe the QUOTIENT.  DECISION, marked: its
        // destination holds two different quantities and the page's "the
        // result" does not say which, but the quotient is what the division
        // produced and the remainder is a by-product -- and DIV's own flags
        // are the quotient's.
        f_s = |(raw & r_msb);
        f_z = ((raw & r_mask) == 32'd0);
    end
end

always_ff @(posedge clk) begin
    if (rst) begin
        state      <= S_IDLE;
        cnt        <= 6'd0;
        acc        <= 65'd0;
        opnd       <= 32'd0;
        done       <= 1'b0;
        zero_div   <= 1'b0;
        writes     <= 1'b1;
        result     <= 32'd0;
        flags_out  <= 4'd0;
        r_mul      <= 1'b0;
        r_rem      <= 1'b0;
        r_sgn      <= 1'b0;
        r_qneg     <= 1'b0;
        r_rneg     <= 1'b0;
        r_bytes    <= 4'd4;
        r_mask     <= 32'hFFFF_FFFF;
        r_msb      <= 32'h8000_0000;
        r_ye       <= 32'd0;
        r_divov    <= 1'b0;
        r_dbl      <= 1'b0;
        r_mulx     <= 1'b0;
        r_divx     <= 1'b0;
        r_qneg64   <= 1'b0;
        result_hi  <= 32'd0;
        r_flags_in <= 4'd0;
    end else begin
        done <= 1'b0;

        case (state)
        S_IDLE: if (start) begin
            r_mul      <= is_mul;
            r_rem      <= is_rem;
            r_sgn      <= is_sgn;
            r_bytes    <= opbytes;
            r_mask     <= mask;
            r_msb      <= msb;
            r_ye       <= ye;
            r_flags_in <= flags_in;
            zero_div   <= 1'b0;
            writes     <= 1'b1;
            r_divov    <= 1'b0;
            r_dbl      <= is_dbl;
            r_mulx     <= is_mulx;
            r_divx     <= is_divx;
            r_qneg64   <= is_sgn && (xs ^ yds);

            if (is_mul) begin
                // The multiplier goes in the low half and is consumed a bit at
                // a time; the multiplicand is added into the high half.
                acc    <= {33'd0, ym};
                opnd   <= xm;
                r_qneg <= is_sgn && (xs ^ ys);
                r_rneg <= 1'b0;
                cnt    <= 6'd32;
                state  <= S_RUN;
            end else if (xz == 32'd0) begin
                // "The destination operand remains unchanged when a Zero
                // Divide exception occurs", and the exception is raised.
                zero_div  <= 1'b1;
                writes    <= 1'b0;
                result    <= 32'd0;
                flags_out <= flags_in;      // nothing said; nothing moved
                done      <= 1'b1;
                state     <= S_IDLE;
            end else if (is_divx) begin
                // The dividend is the whole doubleword.  It goes in as
                // {remainder, quotient} with the high word in the remainder
                // half, and thirty-two steps shift it through -- which is the
                // same engine, given a starting value that occupies all of it
                // rather than only the bottom half.
                acc    <= {1'b0, ydm};
                opnd   <= xm;
                r_qneg <= is_sgn && (xs ^ yds);
                r_rneg <= is_sgn && yds;
                r_divov <= divx_ovf;
                cnt     <= 6'd32;
                state   <= S_RUN;
            end else begin
                acc    <= {33'd0, ym};
                opnd   <= xm;
                // A quotient is negative when the operands' signs differ; a
                // remainder takes "the sign of the dividend", which is the
                // destination.
                r_qneg <= is_sgn && (xs ^ ys);
                r_rneg <= is_sgn && ys;
                // "Overflow occurs when the negative maximum integer is
                // divided by -1", and only then.  REM cannot: its result is
                // zero.
                r_divov <= is_sgn && !is_rem && ys && (ym == (msb & mask)) &&
                           xs && (xm == 32'd1);
                cnt     <= 6'd32;
                state   <= S_RUN;
            end
        end

        S_RUN: begin
            acc <= r_mul ? mul_next : div_next;
            cnt <= cnt - 6'd1;
            if (cnt == 6'd1) state <= S_FIN;
        end

        S_FIN: begin
            // A doubleword destination is not masked to the operand width:
            // its width IS eight bytes.  The mask belongs to the source's
            // size field, which the X forms fix at a word anyway.
            result    <= r_dbl ? raw : (raw & r_mask);
            result_hi <= raw_hi;
            // "CY Unchanged" on all six, so it comes back as it went in.
            flags_out <= {r_flags_in[PSW_CY], f_ov, f_s, f_z};
            // "The destination will remain unchanged if an integer overflow
            // ... occurs" -- DIV's page, and DIVUX's says the same.  The flags
            // still move, which is what its Condition Codes block describes.
            // "The destination operand does not change when an overflow or a
            // Zero Divide exception occurs" -- one sentence covering two
            // different things, and for the X divides the overflow half is the
            // common case rather than the exotic one.  So the whole
            // doubleword writeback is gated, both halves together.
            writes <= !(r_divov || divx_fit_bad);
            done   <= 1'b1;
            state  <= S_IDLE;
        end

        default: state <= S_IDLE;
        endcase
    end
end

// synthesis translate_off
// The reachability argument above, as a check.  If a doubleword dividend ever
// reaches this unit, this is what will say the divider needed its 33rd bit.
always_ff @(posedge clk) begin
    // The 33rd bit is UNREACHABLE for a 32-bit dividend and reachable on every
    // step for a doubleword one, which is why the accumulator was built 65 bits
    // wide before there was anything to use it.  So this stays a warning for
    // the word divides and is expected for the X forms.
    if (!rst && (state == S_RUN) && !r_mul && !r_divx && acc[64])
        $display("WARN v60_muldiv: the divider's remainder reached its 33rd bit, which a 32-bit dividend cannot do (t=%0t)",
                 $time);
end

always_ff @(posedge clk) begin
    if (!rst && start &&
        !((opbytes == 4'd1) || (opbytes == 4'd2) || (opbytes == 4'd4)))
        $display("WARN v60_muldiv: %0d byte operand -- the integer data types are byte, halfword and word (t=%0t)",
                 opbytes, $time);
end
// synthesis translate_on

endmodule
