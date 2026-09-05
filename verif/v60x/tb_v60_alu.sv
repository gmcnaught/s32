//============================================================================
//  tb_v60_alu -- the four flags, against their definitions rather than against
//  the same bit twiddling.
//
//  The reference below computes the flags from what they MEAN: a carry is an
//  unsigned sum that does not fit, an overflow is a signed result outside the
//  operand's range, S is the top bit of the result and Z is the result being
//  zero.  Restating v60_alu's own expressions would check nothing, so this
//  uses integer arithmetic and range comparisons instead.
//
//  Byte width is checked EXHAUSTIVELY -- all 65536 operand pairs for ADD and
//  for SUB -- because the interesting cases are all at the boundaries and
//  there is no reason to guess which ones to pick.  Halfword and word are
//  checked at their boundaries and across a sweep.
//
//  The sentences being checked, from the Programmer's Reference S7:
//    ADD   "CY Set if a carry is generated"
//    SUB   "CY Set if a borrow is generated"
//    both  "OV Set if integer overflow occurs / S ... negative / Z ... zero"
//    TEST  "CY Cleared / OV Cleared"
//    AND   "CY Unchanged / OV Cleared / S ... MSB of the result is set"
//    CMP   "src2 - src1"
//============================================================================
`timescale 1ns/1ps

module tb_v60_alu;
    import v60_psw_pkg::*;
    import v60_alu_pkg::*;

alu_op_e     op;
reg   [3:0]  opbytes, xbytes;
reg  [31:0]  x, y;
reg   [3:0]  flags_in;
wire [31:0]  result;
wire  [3:0]  flags_out;
wire         writes;

reg  [2:0] bf_resid = 3'd0;
reg  [5:0] bf_len   = 6'd0;
reg  [7:0] dec_pat  = 8'd0;
wire       dec_bad;

// The floating point unit, checked here beside the ALU because it is the same
// kind of thing: one cycle of combinational logic over presented operands.
reg   [3:0] f_bytes = 4'd4;
reg  [63:0] f_a     = 64'd0;
reg   [4:0] f_ffl   = 5'd0;
wire [63:0] f_res;
wire  [3:0] f_flags;
wire  [4:0] f_ffl_out;
wire        f_resv;

v60_fpu fpu (
    .op(op), .fbytes(f_bytes), .a(f_a),
    .flags_in(flags_in), .ffl_in(f_ffl),
    .result(f_res), .flags_out(f_flags), .ffl_out(f_ffl_out),
    .resv_operand(f_resv)
);

v60_alu dut (.op(op), .opbytes(opbytes), .xbytes(xbytes), .x(x), .y(y),
             .bf_resid(bf_resid), .bf_len(bf_len), .dec_pat(dec_pat), .dec_bad(dec_bad),
             .flags_in(flags_in),
             .result(result), .flags_out(flags_out), .writes(writes));

// ---------------------------------------------------------------------------
// The shift group's reference: the Description sentences, one step at a time.
// ---------------------------------------------------------------------------
reg [31:0] m_res;
reg        m_cy, m_ov, m_s, m_z;
integer    wi, oi, ci, vi, fi;
reg  [3:0] w;

function [31:0] wmask(input [3:0] bytes);
    wmask = (bytes == 4'd1) ? 32'h0000_00FF :
            (bytes == 4'd2) ? 32'h0000_FFFF : 32'hFFFF_FFFF;
endfunction

// Values chosen for their edges: zero, one, the sign bit, all ones, and a few
// patterns whose bits are not symmetric so a reversed rotate is visible.
function [31:0] sh_value(input integer i, input [3:0] bytes);
    integer nb;
    begin
        nb = bytes * 8;
        case (i)
            0: sh_value = 32'h0000_0000;
            1: sh_value = 32'h0000_0001;
            2: sh_value = 32'h0000_0003;
            3: sh_value = 32'h0000_0002;
            4: sh_value = 32'hFFFF_FFFF;
            5: sh_value = 32'h0000_0080 << (nb - 8);          // the sign bit
            6: sh_value = 32'h0000_0081 << (nb - 8);
            7: sh_value = 32'h0000_0055;
            8: sh_value = 32'h0000_00AA;
            9: sh_value = 32'h1234_5678;
            10: sh_value = 32'h0000_0040 << (nb - 8);
            default: sh_value = 32'h8000_0001;
        endcase
        sh_value = sh_value & wmask(bytes);
    end
endfunction

task sh_model(input alu_op_e o, input [3:0] bytes,
              input [31:0] v, input [7:0] count, input cy0);
    integer nb, n, k;
    reg [31:0] a;
    reg        cy, out, top_before, sign0, left;
    begin
        nb    = bytes * 8;
        left  = !count[7];
        n     = left ? count : (256 - count);      // the magnitude, 0 to 128
        a     = v & wmask(bytes);
        cy    = cy0;
        out   = 1'b0;
        m_ov  = 1'b0;
        sign0 = a[nb-1];

        for (k = 0; k < n; k = k + 1) begin
            top_before = a[nb-1];
            if (left) begin
                out = top_before;
                a   = (a << 1) & wmask(bytes);
                // Left: a zero comes in for both shifts; a rotate brings the
                // bit that just left, and a rotate through carry brings CY.
                if (o == ALU_ROT)  a[0] = out;
                if (o == ALU_ROTC) begin a[0] = cy; cy = out; end
            end else begin
                out = a[0];
                a   = (a >> 1) & wmask(bytes);
                // Right: "the MSB being shifted into itself" for SHA, the bit
                // that just left for ROT, and CY for ROTC.
                if (o == ALU_SHA)  a[nb-1] = top_before;
                if (o == ALU_ROT)  a[nb-1] = out;
                if (o == ALU_ROTC) begin a[nb-1] = cy; cy = out; end
            end
            // "Integer overflow occurs if the sign of the result changes at
            // anytime during the execution of this instruction."
            if ((o == ALU_SHA) && (a[nb-1] !== sign0)) m_ov = 1'b1;
        end

        m_res = a & wmask(bytes);
        m_cy  = (n == 0) ? 1'b0 : out;
        m_s   = a[nb-1];
        m_z   = ((a & wmask(bytes)) == 32'd0);
        if (o != ALU_SHA) m_ov = 1'b0;
    end
endtask

integer errors = 0;
integer checked_q = 0;

// A check inside a sweep: silent while it passes, and when it fails it says
// which case it was, because "the shift group's result" alone would not.
task chk_q(input cond, input [8*48:1] what, input integer count,
           input integer value_index);
begin
    checked_q = checked_q + 1;
    if (!cond) begin
        errors = errors + 1;
        if (errors < 20)
            $display("FAIL  %0s: op=%0d width=%0d count=%0d value=%h -> %h/%b, model %h/%b",
                     what, op, opbytes, count, y, result, flags_out,
                     m_res & wmask(opbytes), {m_cy, m_ov, m_s, m_z});
    end
end
endtask
integer checked = 0;
task chk(input cond, input [8*72:1] what);
begin
    checked = checked + 1;
    if (!cond) begin
        errors = errors + 1;
        if (errors < 12)
            $display("FAIL  %0s (op=%0d opbytes=%0d x=%h y=%h got=%h flags=%b)",
                     what, op, opbytes, x, y, result, flags_out);
    end
end
endtask

// ---------------------------------------------------------------------------
// The reference: definitions, not expressions copied from the DUT.
//
// In 64 bits, because a Verilog `integer` is 32 bits and signed, so a word
// width modulus does not fit in one -- which this bench got wrong first time
// and the word sweep caught.
// ---------------------------------------------------------------------------
reg  [63:0] u_x, u_y, u_sum, u_r, mod64, umask;
reg signed [63:0] s_x, s_y, s_r, lo64, hi64;
reg   [3:0] want;
reg  [31:0] want_r;

task set_range(input [3:0] w_in);
begin
    case (w_in)
        4'd1: begin mod64 = 64'd256;        lo64 = -64'sd128;   hi64 = 64'sd127;   end
        4'd2: begin mod64 = 64'd65536;      lo64 = -64'sd32768; hi64 = 64'sd32767; end
        default: begin mod64 = 64'd4294967296;
                       lo64 = -64'sd2147483648; hi64 = 64'sd2147483647; end
    endcase
    umask = mod64 - 64'd1;
end
endtask

// The operands, read at the operand's width: unsigned, and sign extended.
function [63:0] uval(input [31:0] v, input [3:0] w_in);
    case (w_in)
        4'd1:    uval = {56'd0, v[7:0]};
        4'd2:    uval = {48'd0, v[15:0]};
        default: uval = {32'd0, v};
    endcase
endfunction

function signed [63:0] sval(input [31:0] v, input [3:0] w_in);
    case (w_in)
        4'd1:    sval = {{56{v[7]}},  v[7:0]};
        4'd2:    sval = {{48{v[15]}}, v[15:0]};
        default: sval = {{32{v[31]}}, v};
    endcase
endfunction

task expect_add(input [3:0] w_in);
begin
    set_range(w_in);
    u_x = uval(x, w_in);  u_y = uval(y, w_in);
    s_x = sval(x, w_in);  s_y = sval(y, w_in);
    u_sum = u_y + u_x;
    u_r   = u_sum & umask;
    s_r   = s_y + s_x;
    want[PSW_CY] = (u_sum >= mod64);                 // it did not fit
    want[PSW_OV] = ((s_r > hi64) || (s_r < lo64));   // outside the range
    want[PSW_S]  = (u_r >= (mod64 >> 1));            // top bit set
    want[PSW_Z]  = (u_r == 64'd0);
    want_r = u_r[31:0];
end
endtask

task expect_sub(input [3:0] w_in);
begin
    set_range(w_in);
    u_x = uval(x, w_in);  u_y = uval(y, w_in);
    s_x = sval(x, w_in);  s_y = sval(y, w_in);
    u_r = (u_y - u_x) & umask;
    s_r = s_y - s_x;
    want[PSW_CY] = (u_y < u_x);                      // a borrow
    want[PSW_OV] = ((s_r > hi64) || (s_r < lo64));
    want[PSW_S]  = (u_r >= (mod64 >> 1));
    want[PSW_Z]  = (u_r == 64'd0);
    want_r = u_r[31:0];
end
endtask

integer i, j;

initial begin
    // Everything but the extending moves has its two operands at one width,
    // so the source's width follows the destination's unless a case says
    // otherwise.
    xbytes = 4'd4;
    flags_in = 4'b0000;

    // =======================================================================
    // Byte width, exhaustively, for ADD and SUB.
    // =======================================================================
    // Let the width settle before the first sample.  Without this the two
    // simulators disagree: Icarus reads the DUT after the loop's own #1, while
    // the other samples the first evaluation before the combinational block has
    // run with the width just assigned, and every byte-width result comes back
    // as though the operand were a word.  One simulator is an opinion.
    //
    // (And the comment above says "the other" on purpose: a line of a comment
    // that begins with that simulator's name is read as a pragma by it.)
    opbytes = 4'd1;
    #1;
    for (i = 0; i < 256; i = i + 1) begin
        for (j = 0; j < 256; j = j + 1) begin
            x = i[31:0]; y = j[31:0];

            op = ALU_ADD; #1;
            expect_add(4'd1);
            chk(result === want_r && flags_out === want, "byte ADD");

            op = ALU_SUB; #1;
            expect_sub(4'd1);
            chk(result === want_r && flags_out === want, "byte SUB");
        end
    end

    // The two the plan names, spelled out.
    opbytes = 4'd1; op = ALU_ADD; x = 32'h01; y = 32'h7F; #1;
    chk(flags_out[PSW_OV] === 1'b1 && flags_out[PSW_S] === 1'b1 &&
        flags_out[PSW_CY] === 1'b0 && flags_out[PSW_Z] === 1'b0,
        "0x7F + 1 at byte width overflows into a negative result");
    x = 32'h01; y = 32'hFF; #1;
    chk(flags_out[PSW_CY] === 1'b1 && flags_out[PSW_Z] === 1'b1 &&
        flags_out[PSW_OV] === 1'b0 && flags_out[PSW_S] === 1'b0,
        "0xFF + 1 at byte width carries out and leaves zero");

    // The same values at word width do neither: the width is the point.
    opbytes = 4'd4; x = 32'h01; y = 32'h7F; #1;
    chk(flags_out === 4'b0000, "0x7F + 1 at word width is unremarkable");

    // =======================================================================
    // Halfword and word: the boundaries, and a sweep.
    // =======================================================================
    opbytes = 4'd2; op = ALU_ADD; x = 32'h0001; y = 32'h7FFF; #1;
    expect_add(4'd2);
    chk(result === want_r && flags_out === want, "0x7FFF + 1 at halfword width");
    x = 32'h0001; y = 32'hFFFF; #1;
    expect_add(4'd2);
    chk(result === want_r && flags_out === want, "0xFFFF + 1 at halfword width");

    opbytes = 4'd4; op = ALU_ADD; x = 32'h00000001; y = 32'h7FFFFFFF; #1;
    chk(flags_out[PSW_OV] === 1'b1 && flags_out[PSW_S] === 1'b1,
        "0x7FFFFFFF + 1 at word width overflows");
    x = 32'h00000001; y = 32'hFFFFFFFF; #1;
    chk(flags_out[PSW_CY] === 1'b1 && flags_out[PSW_Z] === 1'b1,
        "0xFFFFFFFF + 1 at word width carries out and leaves zero");

    for (i = 0; i < 512; i = i + 1) begin
        x = {i[7:0], i[7:0], ~i[7:0], i[7:0]};
        y = {~i[7:0], i[7:0], i[7:0], ~i[7:0]};
        opbytes = (i[8]) ? 4'd2 : 4'd4;
        op = ALU_ADD; #1; expect_add(opbytes);
        chk(result === want_r && flags_out === want, "ADD across a sweep");
        op = ALU_SUB; #1; expect_sub(opbytes);
        chk(result === want_r && flags_out === want, "SUB across a sweep");
    end

    // =======================================================================
    // The operations that are not a plain add or subtract.
    // =======================================================================
    // CMP subtracts and keeps nothing: "src2 - src1".
    opbytes = 4'd1; op = ALU_CMP; x = 32'h05; y = 32'h03; #1;
    chk(writes === 1'b0,             "CMP writes no result");
    chk(flags_out[PSW_CY] === 1'b1,  "CMP of 3 against 5 borrows");
    x = 32'h03; y = 32'h05; #1;
    chk(flags_out[PSW_CY] === 1'b0,  "and the other way round does not");
    x = 32'h05; y = 32'h05; #1;
    chk(flags_out[PSW_Z] === 1'b1,   "equal operands compare zero");

    // TEST clears CY and OV whatever they were.
    flags_in = 4'b1100;                       // CY and OV set
    op = ALU_TEST; x = 32'h80; #1;
    chk(writes === 1'b0,             "TEST writes no result");
    chk(flags_out[PSW_CY] === 1'b0 && flags_out[PSW_OV] === 1'b0,
                                     "TEST clears CY and OV");
    chk(flags_out[PSW_S] === 1'b1,   "and reads S from the operand's top bit");
    x = 32'h00; #1;
    chk(flags_out[PSW_Z] === 1'b1,   "and Z from it being zero");

    // The logical operations leave CY alone and clear OV.
    flags_in = 4'b1100;                       // CY and OV set
    op = ALU_AND; opbytes = 4'd1; x = 32'hF0; y = 32'h3C; #1;
    chk(result === 32'h30,           "AND is an and");
    chk(flags_out[PSW_CY] === 1'b1,  "AND leaves CY unchanged");
    chk(flags_out[PSW_OV] === 1'b0,  "and clears OV");
    op = ALU_OR;  #1; chk(result === 32'hFC, "OR is an or");
    op = ALU_XOR; #1; chk(result === 32'hCC, "XOR is an exclusive or");
    op = ALU_NOT; #1; chk(result === 32'h0F, "NOT complements the source");
    chk(flags_out[PSW_CY] === 1'b1 && flags_out[PSW_OV] === 1'b0,
        "and the logical group all treat CY and OV the same way");

    // NEG, and the one value that cannot be negated.
    flags_in = 4'b0000;
    op = ALU_NEG; opbytes = 4'd1; x = 32'h01; #1;
    chk(result === 32'hFF,           "NEG of 1 is -1 at byte width");
    chk(flags_out[PSW_S] === 1'b1,   "which is negative");
    x = 32'h80; #1;
    chk(flags_out[PSW_OV] === 1'b1,  "NEG of the most negative byte overflows");
    x = 32'h00; #1;
    chk(flags_out[PSW_Z] === 1'b1,   "NEG of zero is zero");

    // Carry in.
    flags_in = 4'b1000;                       // CY set
    op = ALU_ADDC; opbytes = 4'd1; x = 32'h01; y = 32'h01; #1;
    chk(result === 32'h03,           "ADDC adds the carry in");
    op = ALU_SUBC; x = 32'h01; y = 32'h05; #1;
    chk(result === 32'h03,           "SUBC subtracts it");

    // =======================================================================
    // The shift group, against a reference that shifts ONE BIT AT A TIME.
    //
    // v60_alu computes these with barrel shifts and modulo arithmetic; the
    // model below does what the Description sentences literally say, one step
    // per iteration, keeping the last bit to leave and watching the sign after
    // every step.  Two different formulations, which is the point.
    // =======================================================================
    for (wi = 0; wi < 3; wi = wi + 1) begin
        w = (wi == 0) ? 4'd1 : (wi == 1) ? 4'd2 : 4'd4;
        for (oi = 0; oi < 4; oi = oi + 1) begin
            for (ci = -34; ci <= 34; ci = ci + 1) begin
                for (vi = 0; vi < 12; vi = vi + 1) begin
                    for (fi = 0; fi < 2; fi = fi + 1) begin
                        opbytes  = w;
                        y        = sh_value(vi, w);
                        x        = {24'd0, ci[7:0]};
                        flags_in = fi ? 4'b1000 : 4'b0000;
                        case (oi)
                            0: op = ALU_SHL;
                            1: op = ALU_SHA;
                            2: op = ALU_ROT;
                            default: op = ALU_ROTC;
                        endcase
                        #1;
                        sh_model(op, w, y, ci[7:0], flags_in[PSW_CY]);
                        chk_q(result === (m_res & wmask(w)),
                              "the shift group's result", ci, vi);
                        chk_q(flags_out[PSW_CY] === m_cy,
                              "the last bit shifted or rotated out", ci, vi);
                        chk_q(flags_out[PSW_OV] === m_ov,
                              "the shift group's overflow", ci, vi);
                        chk_q(flags_out[PSW_S] === m_s,
                              "the MSB of a shifted result", ci, vi);
                        chk_q(flags_out[PSW_Z] === m_z,
                              "a shifted result being zero", ci, vi);
                    end
                end
            end
        end
    end

    // The sentences that a sweep cannot say out loud, spelled out once each.
    opbytes = 4'd1; flags_in = 4'b0000;
    op = ALU_SHL; y = 32'h81; x = 32'd0; #1;
    chk(result === 32'h81,          "a shift count of zero leaves the value");
    chk(flags_out[PSW_CY] === 1'b0, "and clears CY, which the block says");
    chk(flags_out[PSW_S] === 1'b1,  "and still updates the other flags");
    x = 32'd100; #1;
    chk(result === 32'h00,
        "a count past the operand's length shifts everything out");
    op = ALU_SHA; y = 32'h81; x = 32'hFF & (-32'sd100); #1;
    chk(result === 32'hFF,
        "an arithmetic shift right past it leaves the sign, not zero");
    op = ALU_SHL; #1;
    chk(result === 32'h00, "where a logical one leaves zero");
    op = ALU_SHA; y = 32'h40; x = 32'd1; #1;
    chk(flags_out[PSW_OV] === 1'b1,
        "an arithmetic shift that changes the sign overflows");
    op = ALU_SHL; #1;
    chk(flags_out[PSW_OV] === 1'b0, "where a logical one never does");
    op = ALU_ROT; y = 32'h81; x = 32'd1; #1;
    chk(result === 32'h03,     "a rotate brings the MSB round to the LSB");
    op = ALU_ROTC; y = 32'h81; x = 32'd1; flags_in = 4'b0000; #1;
    chk(result === 32'h02,     "and a rotate through carry brings CY instead");
    chk(flags_out[PSW_CY] === 1'b1, "leaving the MSB in the carry");

    // =======================================================================
    // The extending moves.  "The contents of the source operand are sign
    // extended to the destination length and copied" (MOVS), "are zero
    // extended" (MOVZ), "are truncated to the destination operand length"
    // (MOVT).  All three print, or the databook marks, a flags column that
    // leaves the condition codes alone -- except MOVT's OV.
    // =======================================================================
    flags_in = 4'b1111;                    // all four set, to see them survive
    op = ALU_MOVS; xbytes = 4'd1; opbytes = 4'd2; x = 32'h0000_0080; #1;
    chk(result === 32'h0000_FF80,   "MOVS.BH sign extends a negative byte");
    chk(flags_out === 4'b1111,      "and leaves all four flags alone");
    x = 32'h0000_007F; #1;
    chk(result === 32'h0000_007F,   "and leaves a positive one alone");
    xbytes = 4'd1; opbytes = 4'd4; x = 32'h0000_00FF; #1;
    chk(result === 32'hFFFF_FFFF,   "MOVS.BW reaches the whole word");
    xbytes = 4'd2; opbytes = 4'd4; x = 32'h0000_8001; #1;
    chk(result === 32'hFFFF_8001,   "MOVS.HW from the halfword's own sign bit");

    op = ALU_MOVZ; xbytes = 4'd1; opbytes = 4'd4; x = 32'h0000_0080; #1;
    chk(result === 32'h0000_0080,   "MOVZ does not sign extend");
    chk(flags_out === 4'b1111,      "and leaves the flags alone too");
    x = 32'hFFFF_FFFF; #1;
    chk(result === 32'h0000_00FF,
        "and reads its source at the SOURCE's width, not the destination's");

    // MOVT: "If any of the truncated bits do not match the sign of the result,
    // an integer overflow has occurred and the OV flag is set.  In the event
    // of an overflow, the destination operand is replaced with the low order
    // bits of the true result."
    flags_in = 4'b1010;                    // CY and S set, OV and Z clear
    op = ALU_MOVT; xbytes = 4'd4; opbytes = 4'd1; x = 32'h0000_007F; #1;
    chk(result === 32'h0000_007F,       "MOVT.WB keeps a value that fits");
    chk(flags_out[PSW_OV] === 1'b0,     "with no overflow");
    chk(flags_out[PSW_CY] === 1'b1 && flags_out[PSW_S] === 1'b1 &&
        flags_out[PSW_Z] === 1'b0,      "and the other three untouched");
    x = 32'hFFFF_FFFF; #1;
    chk(result === 32'h0000_00FF,       "-1 truncates to -1");
    chk(flags_out[PSW_OV] === 1'b0,
        "and the bits dropped all matched the sign, so no overflow");
    x = 32'h0000_0080; #1;
    chk(result === 32'h0000_0080,
        "the low order bits are kept even when the value does not fit");
    chk(flags_out[PSW_OV] === 1'b1,
        "and dropping zeros off a result whose sign is set is an overflow");
    x = 32'h0000_0100; #1;
    chk(flags_out[PSW_OV] === 1'b1,      "as is dropping a set bit");
    xbytes = 4'd4; opbytes = 4'd2; x = 32'hFFFF_8000; #1;
    chk(result === 32'h0000_8000,        "MOVT.WH keeps the low halfword");
    chk(flags_out[PSW_OV] === 1'b0,      "whose sign the dropped bits match");
    x = 32'h0001_8000; #1;
    chk(flags_out[PSW_OV] === 1'b1,      "and here they do not");

    $display("V60 ALU: %0d checks", checked);
    // =======================================================================
    // RVBIT, RVBYT and SETF.  Three one-line pages, and the three things that
    // are easy to get wrong: which width each reverses, which nibble SETF's
    // condition is in, and that none of them touches a flag.
    // =======================================================================
    flags_in = 4'b1111;                 // every flag set on the way in

    // "dst[i] = src[7-i]", over a BYTE.  0x01 -> 0x80 is the case the page's
    // own zero-extension sentence points at: "rvbit #1" reverses 0000_0001.
    op = ALU_RVBIT; opbytes = 4'd1; xbytes = 4'd1; y = 32'hFFFF_FFFF;
    x = 32'h0000_0001;
    #1 chk(result === 32'h0000_0080, "RVBIT reverses a byte: 01 -> 80");
    x = 32'h0000_0080;
    #1 chk(result === 32'h0000_0001, "and back again: 80 -> 01");
    x = 32'h0000_00A5;
    #1 chk(result === 32'h0000_00A5, "A5 is a palindrome in eight bits");
    x = 32'h0000_0055;
    #1 chk(result === 32'h0000_00AA, "55 -> AA");
    // The bits ABOVE the byte are not the operand and must not appear.
    x = 32'hFFFF_FF01;
    #1 chk(result === 32'h0000_0080,
           "RVBIT reverses EIGHT bits, not thirty-two: the upper bytes are ignored");
    #1 chk(flags_out === 4'b1111, "and it leaves all four flags alone");
    #1 chk(writes === 1'b1,       "and it writes its destination");

    // The full 32-bit endian swap.
    op = ALU_RVBYT; opbytes = 4'd4; xbytes = 4'd4;
    x = 32'h1122_3344;
    #1 chk(result === 32'h4433_2211, "RVBYT swaps all four bytes");
    x = 32'h0000_0000;
    #1 chk(result === 32'h0000_0000, "a zero swaps to zero");
    #1 chk(flags_out === 4'b1111,
           "and Z is NOT set: both reversals print four Unchanged lines");

    // SETF: the condition is the LOW nibble, and the stored values are exactly
    // 01H and 00H.  Codes A and B are p.3.295's "True/Always" and
    // "False/Never", which makes them checkable without setting up flags.
    op = ALU_SETF; opbytes = 4'd1; xbytes = 4'd1; y = 32'hFFFF_FFFF;
    x = 32'h0000_000A;
    #1 chk(result === 32'h0000_0001, "SETF on the Always condition stores 01H");
    x = 32'h0000_000B;
    #1 chk(result === 32'h0000_0000, "and on the Never condition stores 00H");
    // The high nibble "is ignored and has no effect", which is where TRAP puts
    // ITS condition -- so an implementation that shared the nibble would read
    // B here and store 0.
    x = 32'h0000_00BA;
    #1 chk(result === 32'h0000_0001,
           "SETF reads the LOW nibble: BA is Always, not Never");
    x = 32'h0000_00AB;
    #1 chk(result === 32'h0000_0000, "and AB is Never, not Always");
    #1 chk(flags_out === 4'b1111, "SETF sets a BYTE, not a flag");

    // And it does read the flags it is asked about.
    flags_in = 4'b0000;
    x = 32'h0000_0004;                  // Zero / Equal
    #1 chk(result === 32'h0000_0000, "SETF on Z with Z clear stores 00H");
    flags_in = 4'b0001;                 // Z set
    #1 chk(result === 32'h0000_0001, "and with Z set stores 01H");
    #1 chk(flags_out === 4'b0001,      "still without disturbing them");
    flags_in = 4'd0;

    // =======================================================================
    // INC and DEC at every width, and the seven operations that had no
    // ALU-level case at all.  Their pages define them as "add #1, dst" and
    // "sub #1, dst", so the model here is ADD's and SUB's -- computed from the
    // definition rather than copied from the DUT.
    // =======================================================================
    begin : incdec
        integer wi2, vi2;
        reg [3:0]  bw;
        reg [31:0] v, want, msk;
        reg        want_cy, want_ov, want_s, want_z;
        reg [32:0] wide;
        for (wi2 = 0; wi2 < 3; wi2 = wi2 + 1) begin
            bw  = (wi2 == 0) ? 4'd1 : (wi2 == 1) ? 4'd2 : 4'd4;
            msk = wmask(bw);
            for (vi2 = 0; vi2 < 6; vi2 = vi2 + 1) begin
                // 0, 1, the signed maximum, the signed minimum, -1, and a
                // middling value -- the four boundaries the carry and overflow
                // terms turn on, plus two ordinary ones.
                case (vi2)
                    0: v = 32'd0;
                    1: v = 32'd1;
                    2: v = msk >> 1;                 // signed maximum
                    3: v = (msk >> 1) + 32'd1;       // signed minimum
                    4: v = msk;                      // -1
                    default: v = 32'h5A;
                endcase

                // INC
                op = ALU_INC; opbytes = bw; xbytes = bw;
                x = 32'hDEAD_BEEF;                   // must be ignored
                y = v; flags_in = 4'b0000;
                wide    = {1'b0, v & msk} + 33'd1;
                want    = wide[31:0] & msk;
                want_cy = (bw == 4'd1) ? wide[8] : (bw == 4'd2) ? wide[16] : wide[32];
                want_ov = (((v & msk) & (msk - (msk >> 1))) == 32'd0) &&
                          ((want & (msk - (msk >> 1))) != 32'd0);
                want_s  = ((want & (msk - (msk >> 1))) != 32'd0);
                want_z  = (want == 32'd0);
                #1;
                chk(result === want,               "INC result at width");
                chk(flags_out[PSW_CY] === want_cy, "INC carry at width");
                chk(flags_out[PSW_OV] === want_ov, "INC overflow at width");
                chk(flags_out[PSW_S]  === want_s,  "INC sign at width");
                chk(flags_out[PSW_Z]  === want_z,  "INC zero at width");
                chk(writes === 1'b1,               "INC writes");

                // DEC
                op = ALU_DEC;
                wide    = {1'b0, v & msk} - 33'd1;
                want    = wide[31:0] & msk;
                want_cy = (bw == 4'd1) ? wide[8] : (bw == 4'd2) ? wide[16] : wide[32];
                // SUB's rule with an addend of one: the operands disagree
                // about sign (1 is positive) and the result follows the
                // subtrahend.
                want_ov = (((v & msk) & (msk - (msk >> 1))) != 32'd0) &&
                          ((want & (msk - (msk >> 1))) == 32'd0);
                want_s  = ((want & (msk - (msk >> 1))) != 32'd0);
                want_z  = (want == 32'd0);
                #1;
                chk(result === want,               "DEC result at width");
                chk(flags_out[PSW_CY] === want_cy, "DEC borrow at width");
                chk(flags_out[PSW_OV] === want_ov, "DEC overflow at width");
                chk(flags_out[PSW_S]  === want_s,  "DEC sign at width");
                chk(flags_out[PSW_Z]  === want_z,  "DEC zero at width");
            end
        end
    end

    // The signed minimum decremented is the DEC overflow case the sequencer
    // bench never reached, named explicitly so a failure says which it was.
    op = ALU_DEC; opbytes = 4'd1; xbytes = 4'd1; y = 32'h80; flags_in = 4'd0;
    #1 chk(result === 32'h7F,          "DEC.b 0x80 gives 0x7F");
    #1 chk(flags_out[PSW_OV] === 1'b1, "which overflows a signed byte");
    #1 chk(flags_out[PSW_CY] === 1'b0, "without borrowing");
    #1 chk(flags_out[PSW_S]  === 1'b0, "and the result is positive");

    // The four with no ALU-level assertion at all.  What matters about each is
    // its `writes` and that it disturbs no flag -- for the UPDPSW pair,
    // `writes` is the only thing stopping their flags_out from mattering.
    flags_in = 4'b1010;
    op = ALU_NOP; opbytes = 4'd4; x = 32'h1234_5678; y = 32'h8765_4321;
    #1 chk(writes === 1'b0,       "NOP writes nothing");
    #1 chk(flags_out === 4'b1010, "and disturbs no flag");
    op = ALU_MOVEA;
    #1 chk(result === 32'h1234_5678, "MOVEA passes the address through");
    #1 chk(writes === 1'b1,          "and writes it");
    #1 chk(flags_out === 4'b1010,    "without disturbing a flag");
    op = ALU_GETPSW;
    #1 chk(result === 32'h1234_5678, "GETPSW passes the PSW through");
    #1 chk(writes === 1'b1,          "and writes it");
    #1 chk(flags_out === 4'b1010,    "without disturbing a flag");
    op = ALU_UPDPSWH;
    #1 chk(writes === 1'b0, "UPDPSW.H writes no OPERAND: the PSW is the sequencer's");
    op = ALU_UPDPSWW;
    #1 chk(writes === 1'b0, "and neither does UPDPSW.W");
    op = ALU_BRKV;
    #1 chk(writes === 1'b0, "and BRKV writes nothing at all");
    flags_in = 4'd0;

    // =======================================================================
    // The four bit instructions.  All four share two Operation lines --
    // "CY <- bit( base, offset )" and "Z <- ~bit( base, offset )" -- and every
    // page states the rule a second time in prose: "The CY and Z flags reflect
    // the state of the bit PRIOR to the execution of the instruction."
    // =======================================================================
    op = ALU_TEST1; opbytes = 4'd4; xbytes = 4'd4;
    flags_in = 4'b0000;

    // The bit is 1: CY set, Z clear, and nothing written.
    y = 32'h0000_0100; x = 32'h0000_0008;
    #1 chk(flags_out[PSW_CY] === 1'b1 && flags_out[PSW_Z] === 1'b0,
           "TEST1 of a bit that is 1 sets CY and clears Z");
    #1 chk(writes === 1'b0, "and writes nothing -- both its operands are .r");

    // The bit is 0.
    x = 32'h0000_0009;
    #1 chk(flags_out[PSW_CY] === 1'b0 && flags_out[PSW_Z] === 1'b1,
           "and of a bit that is 0 clears CY and sets Z -- they are always complements");

    // OV and S are Unchanged on all four pages, which is not what the ordinary
    // flag path would produce.
    flags_in = 4'b1111;
    y = 32'h0000_0100; x = 32'h0000_0008;
    #1 chk(flags_out[PSW_OV] === 1'b1 && flags_out[PSW_S] === 1'b1,
           "TEST1 leaves OV and S alone");
    flags_in = 4'b0000;

    // The top bit, which is the range's edge.
    y = 32'h8000_0000; x = 32'h0000_001F;
    #1 chk(flags_out[PSW_CY] === 1'b1, "bit 31 is reachable");
    y = 32'h0000_0001; x = 32'h0000_0000;
    #1 chk(flags_out[PSW_CY] === 1'b1, "and so is bit 0");

    // SET1 on a bit that was ALREADY set: the flags describe the bit BEFORE,
    // so CY is set and Z clear even though nothing changed.
    op = ALU_SET1;
    y = 32'h0000_0100; x = 32'h0000_0008;
    #1 chk(result === 32'h0000_0100, "SET1 on a bit already 1 changes nothing");
    #1 chk(flags_out[PSW_CY] === 1'b1 && flags_out[PSW_Z] === 1'b0,
           "and reports the bit as it was: CY set, Z clear");

    // SET1 on a clear bit.  Z is set even though the RESULT is non-zero --
    // Z describes the bit that was read, not the word that was written.
    y = 32'h0000_0000; x = 32'h0000_0008;
    #1 chk(result === 32'h0000_0100, "SET1 on a clear bit sets it");
    #1 chk(flags_out[PSW_CY] === 1'b0 && flags_out[PSW_Z] === 1'b1,
           "and still sets Z: Z is the bit that was READ, not whether the result is zero");
    #1 chk(writes === 1'b1, "SET1 writes its base back");

    // CLR1, both ways round.
    op = ALU_CLR1;
    y = 32'hFFFF_FFFF; x = 32'h0000_0010;
    #1 chk(result === 32'hFFFE_FFFF, "CLR1 clears the designated bit and no other");
    #1 chk(flags_out[PSW_CY] === 1'b1 && flags_out[PSW_Z] === 1'b0,
           "reporting the bit as it was");
    y = 32'h0000_0000; x = 32'h0000_0010;
    #1 chk(result === 32'h0000_0000, "CLR1 of a bit already 0 changes nothing");
    #1 chk(flags_out[PSW_CY] === 1'b0 && flags_out[PSW_Z] === 1'b1, "and says so");

    // NOT1, which is the one whose result depends on the bit both ways.
    op = ALU_NOT1;
    y = 32'h0000_0100; x = 32'h0000_0008;
    #1 chk(result === 32'h0000_0000, "NOT1 of a set bit clears it");
    #1 chk(flags_out[PSW_CY] === 1'b1 && flags_out[PSW_Z] === 1'b0, "reporting it set");
    y = 32'h0000_0000; x = 32'h0000_0008;
    #1 chk(result === 32'h0000_0100, "NOT1 of a clear bit sets it");
    #1 chk(flags_out[PSW_CY] === 1'b0 && flags_out[PSW_Z] === 1'b1, "reporting it clear");

    // =======================================================================
    // The bit field group.  One shift and one mask over the word the sequencer
    // read, which is all "the sum of the bit offset and the bit field length
    // must not exceed thirty-two" permits it to be.
    //
    // The word arrives as x for EXTBF and CMPBF, whose bit-addressed operand is
    // the first, and as y for INSBF, whose bit-addressed operand is the
    // destination.
    // =======================================================================
    opbytes = 4'd4; xbytes = 4'd4; flags_in = 4'b0000;

    // A five-bit field at bit 3 of 0x98: (0x98 >> 3) & 0x1F = 0x13, whose own
    // top bit -- bit 4, because the length says so -- is set.
    bf_resid = 3'd3; bf_len = 6'd5; x = 32'h0000_0098; y = 32'd0;

    op = ALU_EXTBFZ;
    #1 chk(result === 32'h0000_0013, "EXTBFZ extracts the field and zero extends it");
    #1 chk(writes === 1'b1 && flags_out === 4'b0000,
           "writing its destination and moving no flag");

    op = ALU_EXTBFS;
    #1 chk(result === 32'hFFFF_FFF3,
           "EXTBFS sign extends from the FIELD's top bit, which moves with the length");

    op = ALU_EXTBFL;
    #1 chk(result === 32'h9800_0000, "EXTBFL puts the field at the top of the word");

    // A field whose own top bit is clear sign extends to itself.
    bf_len = 6'd6;
    op = ALU_EXTBFS;
    #1 chk(result === 32'h0000_0013,
           "a six-bit field of the same word has a clear top bit and does not extend");
    bf_len = 6'd5;

    // "If the bit field length is zero, zero will be stored in the destination
    // operand."
    bf_len = 6'd0;
    op = ALU_EXTBFZ;  #1 chk(result === 32'd0, "a zero-length EXTBF stores zero");
    op = ALU_EXTBFS;  #1 chk(result === 32'd0, "sign extended too");
    op = ALU_EXTBFL;  #1 chk(result === 32'd0, "and left justified, which would shift by 32");

    // The maximum: 32 bits at residual 0, which is the only place it fits.
    bf_resid = 3'd0; bf_len = 6'd32; x = 32'hDEAD_BEEF;
    op = ALU_EXTBFZ;
    #1 chk(result === 32'hDEAD_BEEF, "a 32-bit field at residual 0 is the whole word");
    op = ALU_EXTBFL;
    #1 chk(result === 32'hDEAD_BEEF, "and left justifying it moves nothing");

    // INSBF: the word is y and the source is x.
    bf_resid = 3'd3; bf_len = 6'd5;
    y = 32'hFFFF_FFFF; x = 32'h0000_0002;
    op = ALU_INSBFR;
    #1 chk(result === 32'hFFFF_FF17,
           "INSBFR replaces just the field and leaves every neighbouring bit");
    #1 chk(flags_out === 4'b0000, "moving no flag");

    // "Insert Left Justified" takes the source's HIGH bits, not its low ones.
    x = 32'hA000_0000;
    op = ALU_INSBFL;
    #1 chk(result === 32'hFFFF_FFA7,
           "INSBFL takes the source's TOP bits, which is what distinguishes it from INSBFR");
    op = ALU_INSBFR;
    #1 chk(result === 32'hFFFF_FF07,
           "where INSBFR of the same source takes its low ones -- here zero");

    // "No transfer will occur if the bit field length is zero" -- which is a
    // DIFFERENT rule from EXTBF's at zero length.
    bf_len = 6'd0; x = 32'hFFFF_FFFF; y = 32'h1234_5678;
    op = ALU_INSBFR;
    #1 chk(result === 32'h1234_5678,
           "a zero-length INSBF leaves the destination alone -- not zero, unlike EXTBF");

    // CMPBF: "flags <- src - bitfield", the source being operand TWO.
    bf_resid = 3'd3; bf_len = 6'd5;
    x = 32'h0000_0098;                   // the word holding the field, 0x13
    y = 32'h0000_0013;                   // the source: equal to it
    op = ALU_CMPBFZ;
    #1 chk(flags_out[PSW_Z] === 1'b1, "CMPBF of an equal source sets Z");
    #1 chk(writes === 1'b0, "and writes nothing: three reads and no write");

    y = 32'h0000_0014;
    #1 chk(flags_out[PSW_Z] === 1'b0 && flags_out[PSW_CY] === 1'b0,
           "a larger source neither equals it nor borrows");
    y = 32'h0000_0012;
    #1 chk(flags_out[PSW_CY] === 1'b1,
           "and a smaller one borrows -- CY is a BORROW here, which is CMP's convention");

    // The direction is fixed twice on the page, so a reversed subtraction is
    // worth an assertion of its own.
    y = 32'h0000_0000;
    #1 chk(flags_out[PSW_S] === 1'b1,
           "0 - field is negative: the subtraction is src - field, not field - src");

    // "If the bit field length is zero, zero will be subtracted from the source
    // operand."
    bf_len = 6'd0; y = 32'h0000_0005;
    #1 chk(flags_out[PSW_Z] === 1'b0 && flags_out[PSW_S] === 1'b0,
           "a zero-length CMPBF subtracts zero, leaving the source's own sign");

    bf_resid = 3'd0; bf_len = 6'd0;

    // =======================================================================
    // The decimal group.  Both data operands of the arithmetic three are BYTES
    // -- two packed digits -- so these are a primitive, not a string
    // operation, and CY is an INPUT: they are the inner step of a multi-byte
    // loop and the carry threads the digits together.
    // =======================================================================
    opbytes = 4'd1; xbytes = 4'd1; bf_resid = 3'd0; bf_len = 6'd0;

    // The carry is DECIMAL and not binary, which is the whole point.
    // 0x59 + 0x59 as binary is 0xB2 with no carry out; as decimal it is
    // 59 + 59 = 118, which is 0x18 with CY set.
    op = ALU_ADDDC; flags_in = 4'b0000; x = 32'h59; y = 32'h59;
    #1 chk(result === 32'h18, "ADDDC 59 + 59 is 118: the low two digits are 18");
    #1 chk(flags_out[PSW_CY] === 1'b1,
           "with CY set -- a DECIMAL carry out of the top digit, not bit 8 of a binary sum");

    // CY on the way IN is what chains the bytes.
    flags_in = 4'b1000;                  // CY set
    #1 chk(result === 32'h19, "and the incoming CY is added: 59 + 59 + 1 is 119");

    // No carry either way.
    flags_in = 4'b0000; x = 32'h12; y = 32'h34;
    #1 chk(result === 32'h46 && flags_out[PSW_CY] === 1'b0,
           "12 + 34 is 46 with no carry");

    // SUBDC borrows.
    op = ALU_SUBDC; x = 32'h34; y = 32'h12;
    #1 chk(result === 32'h78 && flags_out[PSW_CY] === 1'b1,
           "SUBDC 12 - 34 borrows: 78 with CY set");
    x = 32'h12; y = 32'h34;
    #1 chk(result === 32'h22 && flags_out[PSW_CY] === 1'b0,
           "and 34 - 12 is 22 with none");

    // SUBRDC reverses the OPERANDS, not the result's home.
    op = ALU_SUBRDC; x = 32'h34; y = 32'h12;
    #1 chk(result === 32'h22 && flags_out[PSW_CY] === 1'b0,
           "SUBRDC computes src - dst: 34 - 12 is 22");

    // Z is STICKY and is never SET.  "Unchanged if the result is zero,
    // otherwise cleared."
    op = ALU_ADDDC; flags_in = 4'b0001;   // Z preset
    x = 32'h00; y = 32'h00;
    #1 chk(flags_out[PSW_Z] === 1'b1, "a zero result LEAVES a preset Z alone");
    x = 32'h01; y = 32'h00;
    #1 chk(flags_out[PSW_Z] === 1'b0, "a non-zero one clears it");
    flags_in = 4'b0000; x = 32'h00; y = 32'h00;
    #1 chk(flags_out[PSW_Z] === 1'b0,
           "and a zero result never SETS it: Z is accumulated across a chain, not per byte");

    // The Description's extra clearing condition, which the Condition Codes
    // block omits: "if the result is non-zero OR A CARRY IS GENERATED".
    // 50 + 50 is 100, whose low two digits are 00 with a carry out.
    flags_in = 4'b0001; x = 32'h50; y = 32'h50;
    #1 chk(result === 32'h00, "50 + 50 leaves 00 in the byte");
    #1 chk(flags_out[PSW_CY] === 1'b1, "with a carry");
    #1 chk(flags_out[PSW_Z] === 1'b0,
           "and Z is CLEARED -- a zero byte with a carry is not a zero number");

    // OV and S never move on any of the five.
    flags_in = 4'b0110;                   // OV and S set
    x = 32'h12; y = 32'h34;
    #1 chk(flags_out[PSW_OV] === 1'b1 && flags_out[PSW_S] === 1'b1,
           "OV and S are Unchanged: decimal has no sign and no range beyond the byte");

    // The Decimal Format exception, checked on the RESULT for the arithmetic
    // three -- not on the operands, which the page is explicit about.
    flags_in = 4'b0000;
    x = 32'h12; y = 32'h34;
    #1 chk(dec_bad === 1'b0, "a valid result raises nothing");

    // An INVALID INPUT raises, which §3 requires of the DATA rather than of any
    // instruction: "When a nibble is expected to contain a digit, only the
    // valid BCD values [0..9] can be specified.  Any other value will cause an
    // illegal decimal format exception to occur."
    //
    // This assertion used to say the opposite -- that an input nibble of A does
    // NOT raise -- which was true of the 0x1A it tested and false of 0xA0 two
    // lines away.  See docs/v60/DECIMAL-AUDIT.md's D1.
    x = 32'h1A; y = 32'h00;
    #1 chk(dec_bad === 1'b1, "an input nibble of A raises: §3 is an OPERAND rule");
    x = 32'hA0; y = 32'hA0;
    #1 chk(dec_bad === 1'b1, "and so does a high nibble of A on both operands");
    // The case the result check alone MISSED: 0xF0 + 0xF0 gives dec_val 150,
    // whose /10 is 15 -- but 0xFF + 0xFF reaches 165+165, and above 159 the
    // four-bit quotient folds back into 0..9 and looks like a digit.
    x = 32'hFF; y = 32'hFF;
    #1 chk(dec_bad === 1'b1,
           "including the magnitudes the result check folded back into looking valid");
    // Each operand and each nibble on its own, because a check that reads only
    // one of the four passes every test above -- they all have more than one
    // bad nibble.
    x = 32'h00; y = 32'h0A;
    #1 chk(dec_bad === 1'b1, "a bad nibble in the DESTINATION alone raises");
    x = 32'h0A; y = 32'h00;
    #1 chk(dec_bad === 1'b1, "and in the SOURCE alone");
    x = 32'hA0; y = 32'h00;
    #1 chk(dec_bad === 1'b1, "a bad HIGH nibble raises");
    x = 32'h0A; y = 32'h00;
    #1 chk(dec_bad === 1'b1, "and a bad LOW one -- all four positions, not a subset");

    x = 32'h99; y = 32'h99;
    #1 chk(dec_bad === 1'b0, "while the largest VALID pair raises nothing");
    #1 chk(result === 32'h98 && flags_out[PSW_CY] === 1'b1,
           "and computes 99 + 99 = 198 correctly");

    // CVTD.PZ: the digit order CROSSES and `pat` supplies the zone by OR.
    // Its destination is a HALFWORD, which is what opbytes carries here -- the
    // sequencer takes it from the table's (1, 2) for this row.
    opbytes = 4'd2; flags_in = 4'b1000;   // CY set, so "Unchanged" can fail
    op = ALU_CVTDPZ; dec_pat = 8'h30; x = 32'h59;
    #1 chk(result === 32'h3935,
           "CVTD.PZ 0x59 with pattern 0x30 gives 0x3935 -- the digits cross");
    #1 chk(dec_bad === 1'b0, "and 5 and 9 are both valid BCD");
    #1 chk(flags_out[PSW_CY] === flags_in[PSW_CY],
           "CY is Unchanged on a conversion -- it moves only on the arithmetic three");
    x = 32'h5A;
    #1 chk(dec_bad === 1'b1, "a nibble of A is not a digit, and CVTD.PZ checks its SOURCE");

    // CVTD.ZP is the exact inverse -- a halfword source into a byte
    // destination -- and checks the ZONE against pat[7:4].
    opbytes = 4'd1; xbytes = 4'd2;
    op = ALU_CVTDZP; dec_pat = 8'h30; x = 32'h3935;
    #1 chk(result === 32'h59, "CVTD.ZP 0x3935 with pattern 0x30 gives back 0x59");
    #1 chk(dec_bad === 1'b0, "with both zones matching");
    #1 chk(flags_out[PSW_CY] === flags_in[PSW_CY], "and CY Unchanged here too");
    x = 32'h3945;
    #1 chk(dec_bad === 1'b1,
           "a zone of 4 where the pattern says 3 raises -- the only case in the group "
           );
    x = 32'h393A;
    #1 chk(dec_bad === 1'b1, "and a digit nibble of A raises too");

    dec_pat = 8'd0; flags_in = 4'b0000;

    // =======================================================================
    // The floating point three that contain no arithmetic.  IEEE 754 single
    // and double, and the flag sentences are written in terms of the four
    // classes -- zero, denormal, infinity, NaN -- so the classification is
    // what is really being tested.
    // =======================================================================
    flags_in = 4'b0000; f_ffl = 5'd0;

    // ---- short real ----
    f_bytes = 4'd4;

    // 1.0f = 0x3F800000: a plain positive normal.
    op = ALU_MOVF; f_a = 64'h0000_0000_3F80_0000;
    #1 chk(f_res[31:0] === 32'h3F80_0000, "MOVF copies a short real unchanged");
    #1 chk(f_flags === 4'b0000, "1.0 is positive, non-zero and not negative");
    #1 chk(f_resv === 1'b0 && f_ffl_out === 5'd0, "and raises nothing");

    // -1.0f = 0xBF800000.
    f_a = 64'h0000_0000_BF80_0000;
    #1 chk(f_flags[PSW_S] === 1'b1 && f_flags[PSW_CY] === 1'b1,
           "-1.0 sets both S and CY: negative and non-zero");
    #1 chk(f_flags[PSW_Z] === 1'b0, "and is not zero");

    // NEGATIVE ZERO, which is where CY and S part company.  "CY Set if the
    // destination is negative AND NON-ZERO"; "S Set if the destination
    // MANTISSA SIGN BIT is set" -- the bit, not the value.
    f_a = 64'h0000_0000_8000_0000;
    #1 chk(f_flags[PSW_S] === 1'b1,
           "negative zero sets S, because S is the sign BIT");
    #1 chk(f_flags[PSW_CY] === 1'b0,
           "and clears CY, because CY needs negative AND non-zero");
    #1 chk(f_flags[PSW_Z] === 1'b1, "with Z set");

    // Positive zero.
    f_a = 64'd0;
    #1 chk(f_flags === 4'b0001, "positive zero sets Z alone");

    // A NaN: exponent all ones, mantissa non-zero.
    f_a = 64'h0000_0000_7FC0_0000;
    #1 chk(f_resv === 1'b1, "a NaN source raises Reserved Floating Point Operand");
    #1 chk(f_ffl_out[4] === 1'b1, "and sets FIV");

    // An infinity: exponent all ones, mantissa zero.
    f_a = 64'h0000_0000_7F80_0000;
    #1 chk(f_resv === 1'b1, "an infinity raises it too");
    #1 chk(f_ffl_out[4] === 1'b1, "and sets FIV -- MOVF names both directly");

    // A denormal: exponent zero, mantissa non-zero.
    f_a = 64'h0000_0000_0000_0001;
    #1 chk(f_resv === 1'b0, "a denormal is not a reserved operand");
    #1 chk(f_ffl_out[1] === 1'b1, "but it sets FUD");
    #1 chk(f_flags[PSW_Z] === 1'b0, "and is not zero");

    // The floating point flags are STICKY: every sentence is "otherwise
    // unchanged", so a clean value does not clear what was there.
    f_ffl = 5'b10000; f_a = 64'h0000_0000_3F80_0000;
    #1 chk(f_ffl_out[4] === 1'b1, "a clean value leaves FIV as it was: they are sticky");
    f_ffl = 5'd0;

    // NEGF flips the sign bit and nothing else.
    op = ALU_NEGF; f_a = 64'h0000_0000_3F80_0000;
    #1 chk(f_res[31:0] === 32'hBF80_0000, "NEGF 1.0 gives -1.0");
    #1 chk(f_flags[PSW_S] === 1'b1 && f_flags[PSW_CY] === 1'b1,
           "with S and CY from the RESULT, not the source");
    f_a = 64'h0000_0000_BF80_0000;
    #1 chk(f_res[31:0] === 32'h3F80_0000, "and NEGF -1.0 gives 1.0");
    #1 chk(f_flags[PSW_S] === 1'b0, "clearing S");

    // ABSF clears the sign bit, and its flag block is the group's distinctive
    // one: THREE of the four integer flags are unconditionally cleared.
    op = ALU_ABSF; flags_in = 4'b1111; f_a = 64'h0000_0000_BF80_0000;
    #1 chk(f_res[31:0] === 32'h3F80_0000, "ABSF -1.0 gives 1.0");
    #1 chk(f_flags[PSW_CY] === 1'b0 && f_flags[PSW_OV] === 1'b0 &&
           f_flags[PSW_S] === 1'b0,
           "and clears CY, OV and S unconditionally -- the result cannot be negative");
    #1 chk(f_flags[PSW_Z] === 1'b0, "with Z from the result");
    f_a = 64'h0000_0000_8000_0000;
    #1 chk(f_res[31:0] === 32'h0000_0000, "ABSF of negative zero gives positive zero");
    #1 chk(f_flags[PSW_Z] === 1'b1, "and sets Z");
    flags_in = 4'b0000;

    // ---- long real, where the fields are 1/11/52 rather than 1/8/23 ----
    f_bytes = 4'd8;
    op = ALU_MOVF;

    // 1.0 = 0x3FF0000000000000.
    f_a = 64'h3FF0_0000_0000_0000;
    #1 chk(f_res === 64'h3FF0_0000_0000_0000, "MOVF copies a long real unchanged");
    #1 chk(f_flags === 4'b0000, "1.0 is a plain positive normal at double precision too");
    #1 chk(f_resv === 1'b0, "and raises nothing");

    // The bit pattern that is a NaN at DOUBLE precision is an ordinary normal
    // at single -- which is the whole reason the width is an input.
    f_a = 64'h7FF8_0000_0000_0000;
    #1 chk(f_resv === 1'b1, "a double NaN raises");
    f_bytes = 4'd4;
    #1 chk(f_resv === 1'b0,
           "and the SAME low word read as a short real does not: the width decides the class");
    f_bytes = 4'd8;

    // A double infinity and a double denormal.
    f_a = 64'h7FF0_0000_0000_0000;
    #1 chk(f_resv === 1'b1, "a double infinity raises");
    f_a = 64'h0000_0000_0000_0001;
    #1 chk(f_resv === 1'b0 && f_ffl_out[1] === 1'b1, "a double denormal sets FUD");
    f_a = 64'h8000_0000_0000_0000;
    #1 chk(f_flags[PSW_Z] === 1'b1 && f_flags[PSW_S] === 1'b1 &&
           f_flags[PSW_CY] === 1'b0,
           "and double negative zero behaves as single: S set, CY clear, Z set");

    f_bytes = 4'd4; f_a = 64'd0;

    if (errors == 0) $display("V60 ALU PASS");
    else             $display("V60 ALU FAIL (%0d errors)", errors);
    $finish;
end

endmodule
