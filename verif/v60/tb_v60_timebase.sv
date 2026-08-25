//============================================================================
//  V60 bus timebase regression (audit S01 / S07.3).
//
//  The whole point of moving the BIU to clk_ram is that the V60 clock's
//  FALLING edge becomes representable, so databook S4's half-clock sampling
//  points can be expressed.  This bench pins that property numerically for
//  both production divisors and proves the module refuses a divisor that
//  cannot provide it.
//
//  Built with +define+V60_INVARIANT_NONFATAL so the negative case can observe
//  a fire and keep running.
//============================================================================
`timescale 1ns/1ps

module tb_v60_timebase;

integer errors = 0;

reg clk_ram = 1'b0;
reg rst     = 1'b1;
reg pause   = 1'b0;
reg [2:0] div = 3'd6;
wire ce_rise, ce_fall;
wire [2:0] phase;

always #5.174 clk_ram = ~clk_ram;   // 96.634615 MHz

s32_v60_timebase dut (
    .clk_ram(clk_ram), .rst(rst), .pause(pause), .div(div),
    .ce_rise(ce_rise), .ce_fall(ce_fall), .phase(phase)
);

task automatic reset_dut;
begin
    rst = 1'b1;
    repeat (4) @(posedge clk_ram);
    @(negedge clk_ram);
    rst = 1'b0;
end
endtask

// Measure, over many V60 clocks: ticks between rising edges, and where the
// falling edge lands relative to each rising edge.
task automatic measure(input [2:0] d, input integer periods,
                       output integer bad_period, output integer bad_half,
                       output integer n_rise);
    integer ticks, since, fall_at;
begin
    div = d;
    reset_dut();
    bad_period = 0; bad_half = 0; n_rise = 0;
    since = -1; fall_at = -1;
    for (ticks = 0; ticks < periods * d + 8; ticks = ticks + 1) begin
        @(posedge clk_ram);
        #1;
        if (ce_rise) begin
            if (n_rise > 0) begin
                if (since != d)      bad_period = bad_period + 1;
                if (fall_at != d/2)  bad_half   = bad_half + 1;
            end
            n_rise = n_rise + 1;
            since = 1;
            fall_at = -1;
        end
        else begin
            if (ce_fall) fall_at = since;
            if (since >= 0) since = since + 1;
        end
    end
end
endtask

integer bad_p, bad_h, nr;
integer guard;
integer fails_before;

initial begin
    $display("V60 TIMEBASE");

    // ---- div=6: System 32 / Golden Axe II, 16,105,769 Hz ----------------
    measure(3'd6, 200, bad_p, bad_h, nr);
    if (nr > 100 && bad_p == 0 && bad_h == 0)
        $display("  div=6 (System 32): PASS  %0d V60 clocks, period 6, fall at 3", nr);
    else begin
        errors = errors + 1;
        $display("  div=6: FAIL  rises=%0d bad_period=%0d bad_half=%0d", nr, bad_p, bad_h);
    end

    // ---- div=4: Arabian Fight, 24,158,654 Hz (exactly clk_sys/2) --------
    measure(3'd4, 200, bad_p, bad_h, nr);
    if (nr > 100 && bad_p == 0 && bad_h == 0)
        $display("  div=4 (Arabian Fight): PASS  %0d V60 clocks, period 4, fall at 2", nr);
    else begin
        errors = errors + 1;
        $display("  div=4: FAIL  rises=%0d bad_period=%0d bad_half=%0d", nr, bad_p, bad_h);
    end

    // ---- pause freezes the timebase -------------------------------------
    div = 3'd6; reset_dut();
    repeat (3) @(posedge clk_ram);
    @(negedge clk_ram); pause = 1'b1;
    begin : pause_check
        integer seen;
        seen = 0;
        for (guard = 0; guard < 40; guard = guard + 1) begin
            @(posedge clk_ram); #1;
            if (ce_rise || ce_fall) seen = seen + 1;
        end
        if (seen == 0) $display("  pause: PASS (no enables while paused)");
        else begin
            errors = errors + 1;
            $display("  pause: FAIL (%0d enables asserted while paused)", seen);
        end
    end
    @(negedge clk_ram); pause = 1'b0;

    // ---- reset holds both enables low -----------------------------------
    rst = 1'b1;
    begin : rst_check
        integer seen;
        seen = 0;
        for (guard = 0; guard < 20; guard = guard + 1) begin
            @(posedge clk_ram); #1;
            if (ce_rise || ce_fall) seen = seen + 1;
        end
        if (seen == 0) $display("  reset: PASS (no enables while in reset)");
        else begin
            errors = errors + 1;
            $display("  reset: FAIL (%0d enables asserted during reset)", seen);
        end
    end
    rst = 1'b0;

    // ---- negative: an ODD divisor has no representable falling edge ------
    // This is the property the module exists to guarantee, so it must refuse
    // rather than silently place ce_fall off centre.
    fails_before = dut.tb_inv_fails;
    div = 3'd5;
    reset_dut();
    repeat (20) @(posedge clk_ram);
    if (dut.tb_inv_fails > fails_before)
        $display("  odd div refused: PASS (caught, %0d fire(s))",
                 dut.tb_inv_fails - fails_before);
    else begin
        errors = errors + 1;
        $display("  odd div refused: FAIL -- div=5 was accepted");
    end

    if (errors == 0) $display("V60 TIMEBASE PASS");
    else             $display("V60 TIMEBASE FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #500000;
    $display("V60 TIMEBASE FAIL (timeout)");
    $finish;
end

endmodule
