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
reg   [3:0]  opbytes;
reg  [31:0]  x, y;
reg   [3:0]  flags_in;
wire [31:0]  result;
wire  [3:0]  flags_out;
wire         writes;

v60_alu dut (.op(op), .opbytes(opbytes), .x(x), .y(y), .flags_in(flags_in),
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

    $display("V60 ALU: %0d checks", checked);
    if (errors == 0) $display("V60 ALU PASS");
    else             $display("V60 ALU FAIL (%0d errors)", errors);
    $finish;
end

endmodule
