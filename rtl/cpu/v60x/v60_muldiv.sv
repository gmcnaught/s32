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
    input         [3:0] flags_in,   // {CY, OV, S, Z}; CY is unchanged by all six

    output logic [31:0] result,
    output logic  [3:0] flags_out,
    output logic        writes,     // "the destination will remain unchanged"
    output logic        zero_div,   // the Integer Arithmetic Exception
    output logic        busy,
    output logic        done
);

wire is_mul = (op == ALU_MUL) || (op == ALU_MULU);
wire is_rem = (op == ALU_REM) || (op == ALU_REMU);
wire is_sgn = (op == ALU_MUL) || (op == ALU_DIV) || (op == ALU_REM);

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
    if (r_mul)      f_ov = r_sgn ? !fit_signed : !fit_unsigned;
    else if (r_rem) f_ov = 1'b0;                 // "OV Cleared", both pages
    else            f_ov = r_divov;              // min / -1, and only that
    f_s = |(raw & r_msb);
    f_z = ((raw & r_mask) == 32'd0);
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
            result <= raw & r_mask;
            // "CY Unchanged" on all six, so it comes back as it went in.
            flags_out <= {r_flags_in[PSW_CY], f_ov, f_s, f_z};
            // "The destination will remain unchanged if an integer overflow
            // ... occurs" -- DIV's page, and DIVUX's says the same.  The flags
            // still move, which is what its Condition Codes block describes.
            writes <= !(r_divov);
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
    if (!rst && (state == S_RUN) && !r_mul && acc[64])
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
