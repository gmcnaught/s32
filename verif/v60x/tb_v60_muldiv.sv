//============================================================================
//  tb_v60_muldiv -- the six against integer arithmetic, at every width.
//
//  The model is the bench's own arithmetic and not a second implementation of
//  the RTL: SystemVerilog's `*`, `/` and `%` on `longint`, which is what the
//  pages describe when they say "signed division" and "the sign of the
//  remainder is the same as the sign of the dividend" -- Verilog's `/`
//  truncates toward zero and its `%` takes the dividend's sign, which is the
//  same rule.
//
//  Byte width is EXHAUSTIVE -- all 65,536 operand pairs per operation, which
//  is what tb_v60_alu does for ADD and SUB -- so the flag rules are checked at
//  every boundary rather than at the ones the author thought of.  Halfword and
//  word are checked at their boundaries and at the values the pages name: the
//  negative maximum divided by -1, a divisor of zero, and the products that sit
//  either side of "fits within the precision of the destination operand".
//============================================================================
`timescale 1ns/1ps

module tb_v60_muldiv;
    import v60_alu_pkg::*;
    import v60_psw_pkg::*;

reg clk = 1'b0;
always #5 clk = ~clk;
reg rst = 1'b1;

reg          start = 1'b0;
alu_op_e     op    = ALU_MUL;
reg    [3:0] obytes = 4'd1;
reg   [31:0] x = 32'd0, y = 32'd0;
reg    [3:0] fin = 4'd0;

wire  [31:0] result;
wire   [3:0] flags;
wire         writes, zero_div, busy, done;

v60_muldiv dut (
    .clk(clk), .rst(rst),
    .start(start), .op(op), .opbytes(obytes), .x(x), .y(y), .flags_in(fin),
    .result(result), .flags_out(flags), .writes(writes),
    .zero_div(zero_div), .busy(busy), .done(done)
);

integer errors = 0;
task chk(input cond, input [8*80:1] what);
begin
    if (!cond) begin
        errors = errors + 1;
        if (errors < 30)
            $display("FAIL  %0s (op=%0d w=%0d x=%h y=%h -> %h f=%b wr=%b zd=%b) (t=%0t)",
                     what, op, obytes, x, y, result, flags, writes, zero_div, $time);
    end
end
endtask

task run(input [4:0] o, input [3:0] w, input [31:0] xv, input [31:0] yv,
         input [3:0] f);
begin
    @(negedge clk);
    op = alu_op_e'(o); obytes = w; x = xv; y = yv; fin = f;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    while (!done) @(negedge clk);
end
endtask

// ---------------------------------------------------------------------------
// The model.  Everything is computed at the operand's width, which is the same
// reading tb_v60_alu holds for the combinational operations: every one of
// these instructions has .b / .h / .w variants and the Condition Codes blocks
// say "the result", which for a byte operation can only mean the byte.
// ---------------------------------------------------------------------------
// 64 bits of plain Verilog rather than `longint`: one of the two simulators
// does not take it in a declaration, and this bench has to run under both.
function automatic [63:0] wmask(input [3:0] w);
    wmask = (w == 4'd1) ? 64'h0000_0000_0000_00FF :
            (w == 4'd2) ? 64'h0000_0000_0000_FFFF : 64'h0000_0000_FFFF_FFFF;
endfunction

function automatic signed [63:0] sx(input [31:0] v, input [3:0] w);
    case (w)
        4'd1:    sx = {{56{v[7]}},  v[7:0]};
        4'd2:    sx = {{48{v[15]}}, v[15:0]};
        default: sx = {{32{v[31]}}, v};
    endcase
endfunction

function automatic [63:0] zx(input [31:0] v, input [3:0] w);
    zx = {32'd0, v} & wmask(w);
endfunction

integer   nchk = 0;
reg signed [63:0] mx, my, mprod, mq, mr;
reg        [63:0] ux, uy, uprod, uq, ur;
logic [31:0] want;
logic        want_ov, want_s, want_z, want_wr;

task case_check(input [4:0] o, input [3:0] w, input [31:0] xv, input [31:0] yv,
            input [3:0] f);
begin
    mx = sx(xv, w);  my = sx(yv, w);
    ux = zx(xv, w);  uy = zx(yv, w);
    want_wr = 1'b1;
    want_ov = 1'b0;
    case (alu_op_e'(o))
        ALU_MUL: begin
            mprod   = mx * my;
            want    = mprod[31:0] & wmask(w);
            // "does [not] fit within the precision of the destination operand"
            want_ov = (mprod != sx(mprod[31:0], w));
        end
        ALU_MULU: begin
            uprod   = ux * uy;
            want    = uprod[31:0] & wmask(w);
            want_ov = (uprod != (uprod & wmask(w)));
        end
        ALU_DIV: begin
            if (ux == 0) begin want = 32'd0; want_wr = 1'b0; end
            else begin
                mq = (mx == -64'sd1) ? -my : (my / mx);  // guards the overflow below
                want    = mq[31:0] & wmask(w);
                // "Overflow occurs when the negative maximum integer is
                // divided by -1", and the destination is left alone.
                want_ov = (mx == -64'sd1) &&
                          (my == -(64'sd1 <<< (w*8 - 1)));
                if (want_ov) begin
                    want    = (64'd1 << (w*8 - 1)) & wmask(w);
                    want_wr = 1'b0;
                end
            end
        end
        ALU_DIVU: begin
            if (ux == 0) begin want = 32'd0; want_wr = 1'b0; end
            else begin uq = uy / ux; want = uq[31:0] & wmask(w); end
        end
        ALU_REM: begin
            if (ux == 0) begin want = 32'd0; want_wr = 1'b0; end
            else begin mr = my % mx; want = mr[31:0] & wmask(w); end
        end
        default: begin   // ALU_REMU
            if (ux == 0) begin want = 32'd0; want_wr = 1'b0; end
            else begin ur = uy % ux; want = ur[31:0] & wmask(w); end
        end
    endcase
    want_s = want[(w*8) - 1];
    want_z = (want == 32'd0);

    run(o, w, xv, yv, f);
    nchk = nchk + 1;

    if ((alu_op_e'(o) != ALU_MUL) && (alu_op_e'(o) != ALU_MULU) &&
        (zx(xv, w) == 0)) begin
        chk(zero_div, "a divisor of zero raises the Integer Arithmetic Exception");
        chk(!writes,  "and the destination operand remains unchanged");
        chk(flags === f, "and nothing is said about the flags, so none moves");
    end else begin
        chk(!zero_div,          "no exception");
        chk(writes === want_wr, "the destination is written unless the page says otherwise");
        if (want_wr) chk(result === want, "the result");
        chk(flags[PSW_OV] === want_ov, "OV");
        chk(flags[PSW_S]  === want_s,  "S");
        chk(flags[PSW_Z]  === want_z,  "Z");
        chk(flags[PSW_CY] === f[PSW_CY], "CY is unchanged by all six");
    end
end
endtask

integer i, j;
reg [4:0] ops [0:5];

initial begin
    ops[0] = ALU_MUL;  ops[1] = ALU_MULU;
    ops[2] = ALU_DIV;  ops[3] = ALU_DIVU;
    ops[4] = ALU_REM;  ops[5] = ALU_REMU;

    repeat (4) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);

    // =======================================================================
    // Byte width, exhaustively: 256 x 256 pairs per operation.
    // =======================================================================
    begin : byte_sweep
        integer o;
        for (o = 0; o < 6; o = o + 1)
            for (i = 0; i < 256; i = i + 1)
                for (j = 0; j < 256; j = j + 1)
                    // CY *and* OV set on the way in: CY has to survive all six
                    // and OV has to be cleared by the ones whose pages say
                    // "OV Cleared", which "unchanged" would not do.
                    case_check(ops[o], 4'd1, i[31:0], j[31:0], 4'b1100);
    end
    $display("      byte width: %0d checks", nchk);

    // =======================================================================
    // Halfword and word, at their boundaries and at the values the pages name.
    // =======================================================================
    begin : edges
        integer o, k, m;
        reg [31:0] hv [0:9];
        reg [31:0] wv [0:9];
        hv[0]=32'h0000; hv[1]=32'h0001; hv[2]=32'hFFFF; hv[3]=32'h7FFF;
        hv[4]=32'h8000; hv[5]=32'h00FF; hv[6]=32'h0100; hv[7]=32'h1234;
        hv[8]=32'hFFFE; hv[9]=32'h8001;
        wv[0]=32'h0000_0000; wv[1]=32'h0000_0001; wv[2]=32'hFFFF_FFFF;
        wv[3]=32'h7FFF_FFFF; wv[4]=32'h8000_0000; wv[5]=32'h0000_FFFF;
        wv[6]=32'h0001_0000; wv[7]=32'h1234_5678; wv[8]=32'hFFFF_FFFE;
        wv[9]=32'h8000_0001;
        for (o = 0; o < 6; o = o + 1)
            for (k = 0; k < 10; k = k + 1)
                for (m = 0; m < 10; m = m + 1) begin
                    case_check(ops[o], 4'd2, hv[k], hv[m], 4'b0100);
                    case_check(ops[o], 4'd4, wv[k], wv[m], 4'b1100);
                end
    end
    $display("      with halfword and word: %0d checks", nchk);

    // =======================================================================
    // The four claims the pages make that a sweep proves but does not point
    // at.  Each is re-run on its own so a failure names itself.
    // =======================================================================

    // "Overflow occurs when the negative maximum integer is divided by -1",
    // and the destination is left alone.
    run(ALU_DIV, 4'd1, 32'hFF, 32'h80, 4'd0);
    chk(flags[PSW_OV] === 1'b1, "DIV.b -128 / -1 overflows");
    chk(!writes,                "and the destination remains unchanged");
    run(ALU_DIV, 4'd4, 32'hFFFF_FFFF, 32'h8000_0000, 4'd0);
    chk(flags[PSW_OV] === 1'b1, "and so does DIV.w at the word's own minimum");
    chk(!writes,                "with the same result");
    // One away from it, in each direction, does not.
    run(ALU_DIV, 4'd1, 32'hFF, 32'h81, 4'd0);
    chk(flags[PSW_OV] === 1'b0 && writes && result === 32'h7F,
        "-127 / -1 is 127, which fits");
    run(ALU_DIV, 4'd1, 32'hFE, 32'h80, 4'd0);
    chk(flags[PSW_OV] === 1'b0 && writes && result === 32'h40,
        "-128 / -2 is 64, which fits");

    // The signed and unsigned pairs disagree, which is the point of having
    // both: 0xFF is -1 signed and 255 unsigned.
    run(ALU_MUL,  4'd1, 32'hFF, 32'hFF, 4'd0);
    chk(result === 32'h01 && flags[PSW_OV] === 1'b0,
        "MUL.b -1 x -1 is 1, and fits a signed byte");
    run(ALU_MULU, 4'd1, 32'hFF, 32'hFF, 4'd0);
    chk(result === 32'h01 && flags[PSW_OV] === 1'b1,
        "MULU.b 255 x 255 is 65025, and does not fit an unsigned byte");
    run(ALU_DIV,  4'd1, 32'h02, 32'hFE, 4'd0);
    chk(result === 32'hFF, "DIV.b -2 / 2 is -1");
    run(ALU_DIVU, 4'd1, 32'h02, 32'hFE, 4'd0);
    chk(result === 32'h7F, "DIVU.b 254 / 2 is 127");
    run(ALU_REM,  4'd1, 32'h03, 32'hFB, 4'd0);
    chk(result === 32'hFE,
        "REM.b -5 % 3 is -2: the remainder takes the sign of the dividend");
    run(ALU_REMU, 4'd1, 32'h03, 32'hFB, 4'd0);
    chk(result === 32'h02, "REMU.b 251 % 3 is 2");

    // MUL's overflow is a SIGNED fit, which is where this parts company with
    // MAME -- see v60_muldiv's header.  A product of -1 fits a signed word.
    run(ALU_MUL, 4'd4, 32'hFFFF_FFFF, 32'h0000_0001, 4'd0);
    chk(result === 32'hFFFF_FFFF && flags[PSW_OV] === 1'b0,
        "MUL.w -1 x 1 is -1, and fits: the page's test is a signed one");
    run(ALU_MUL, 4'd4, 32'h0001_0000, 32'h0001_0000, 4'd0);
    chk(flags[PSW_OV] === 1'b1, "and 65536 squared does not fit a word");

    // A divisor of zero, on each of the four that divide.
    run(ALU_DIV,  4'd2, 32'h0000, 32'h1234, 4'd0);
    chk(zero_div && !writes, "DIV by zero raises and leaves the destination");
    run(ALU_DIVU, 4'd2, 32'h0000, 32'h1234, 4'd0);
    chk(zero_div && !writes, "DIVU by zero too");
    run(ALU_REM,  4'd2, 32'h0000, 32'h1234, 4'd0);
    chk(zero_div && !writes, "and REM");
    run(ALU_REMU, 4'd2, 32'h0000, 32'h1234, 4'd0);
    chk(zero_div && !writes, "and REMU");
    // A multiply by zero does not.
    run(ALU_MUL,  4'd2, 32'h0000, 32'h1234, 4'd0);
    chk(!zero_div && writes && result === 32'h0000 && flags[PSW_Z] === 1'b1,
        "a multiply by zero is zero, and raises nothing");

    // It is not one cycle of combinational logic, and says so.
    @(negedge clk);
    op = ALU_MUL; obytes = 4'd4; x = 32'd3; y = 32'd5; fin = 4'd0;
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;
    chk(busy, "the unit is busy while it works");
    chk(!done, "and does not finish in the cycle it started");
    while (!done) @(negedge clk);
    chk(result === 32'd15, "3 x 5 is 15");
    @(negedge clk);
    chk(!busy, "and it is idle again afterwards");

    $display("      %0d checks", nchk);
    if (errors == 0) $display("V60 MULDIV PASS");
    else             $display("V60 MULDIV FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #4_000_000_000;
    $display("V60 MULDIV FAIL (timeout)");
    $finish;
end

endmodule
