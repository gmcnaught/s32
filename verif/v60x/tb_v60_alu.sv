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

integer errors = 0;
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

    $display("V60 ALU: %0d checks", checked);
    if (errors == 0) $display("V60 ALU PASS");
    else             $display("V60 ALU FAIL (%0d errors)", errors);
    $finish;
end

endmodule
