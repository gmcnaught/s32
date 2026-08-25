//============================================================================
//  V60 bus timebase: a V60 clock reconstructed on clk_ram, with a REPRESENTABLE
//  falling edge.  Audit S01 / S07.3.
//
//  Why this exists.  Every half-clock event in databook S4 -- BMODE sampled on
//  the falling edge of T2, READY on the falling edge of T3 and of each TW,
//  HLDAK a half-clock after the buses tri-state -- needs a falling edge that
//  the fabric can actually name.  On clk_sys there isn't one:
//
//      clk_sys / f_V60 = 48,317,307 / 16,107,950 = 2.9996
//
//  Three is odd, so a V60 clock reconstructed on clk_sys has no clk_sys edge at
//  its half-period and those sampling points cannot be expressed at all.  On
//  clk_ram the ratio is 5.9992 -- six, even -- so both edges land on real
//  clock ticks, three ticks apart.  That is the whole reason the BIU moves to
//  clk_ram before the T-state machine is written rather than after: a T-state
//  machine built on clk_sys would have to be thrown away.
//
//  Why `div` is an input and not a parameter.  The production bitstream is one
//  universal profile serving every supported board, so the divisor is selected
//  at runtime from the board descriptor:
//
//      System 32 / Golden Axe II   div=6   16,105,769 Hz   -122 ppm
//      Arabian Fight               div=4   24,158,654 Hz      0 ppm  (exact)
//
//  Arabian Fight is exact because its cadence is already clk_sys/2, which is
//  clk_ram/4.  System 32 shifts by 122 parts per million -- 0.0122%, against a
//  documented history in which a +50% bus-rate change black-screened Golden
//  Axe: The Revenge of Death Adder, Spider-Man and Rad Rally.  This is four
//  thousand times smaller than that change and preserves the cadence the
//  standing rule protects.
//
//  Multi 32's V70 (20 MHz) is NOT expressible: the nearest integer divisor is
//  five, which is odd and therefore has no representable falling edge, which
//  defeats the point.  It is out of production scope (s32_core forces
//  is_multi32 to 0 whenever SYSTEM32_ONLY is set, which the QSF sets) and
//  s32_core keeps it on the original NCO instead of silently re-rating it.
//
//  div MUST be even.  An odd divisor has no half-period tick and would put
//  ce_fall on the wrong side of centre; the assertion below refuses it.
//============================================================================

module s32_v60_timebase (
    input        clk_ram,
    input        rst,
    input        pause,
    input  [2:0] div,        // clk_ram ticks per V60 clock: 4 or 6, even

    output       ce_rise,    // V60 clock rising edge  -- the T-state boundary
    output       ce_fall,    // V60 clock falling edge -- the S4 sampling point
    output [2:0] phase       // 0 .. div-1, for a T-state machine to decode
);

wire [2:0] last = div - 3'd1;
wire [2:0] half = {1'b0, div[2:1]};   // div/2: 4->2, 6->3

reg [2:0] cnt = 3'd0;

always @(posedge clk_ram) begin
    if (rst)         cnt <= 3'd0;
    else if (!pause) cnt <= (cnt >= last) ? 3'd0 : cnt + 3'd1;
end

assign phase = cnt;

// Held off during reset and pause so the bus sees no enables while the rest of
// the core is held, matching what the NCO did (the top level zeroes ce_cpu on
// pause and the NCO resets to 0).
assign ce_rise = !rst && !pause && (cnt == 3'd0);
assign ce_fall = !rst && !pause && (cnt == half);

// ---------------------------------------------------------------------------
// Invariants (audit S07.2 idiom: immediate assertions, Icarus runs no others)
// ---------------------------------------------------------------------------
`ifndef SYNTHESIS
integer tb_inv_fails = 0;

task automatic tb_inv_fail(input [8*64:1] what);
begin
    tb_inv_fails = tb_inv_fails + 1;
    $display("V60-TIMEBASE FAIL: %0s (div=%0d cnt=%0d)", what, div, cnt);
`ifndef V60_INVARIANT_NONFATAL
    $fatal(1, "V60 timebase invariant violated");
`endif
end
endtask

reg [3:0] since_rise = 4'd0;
reg       seen_rise  = 1'b0;

always @(posedge clk_ram) begin
    if (rst) begin
        since_rise <= 4'd0;
        seen_rise  <= 1'b0;
    end
    else if (!pause) begin
        // T1  An odd divisor cannot place a falling edge at the half period.
        if (div[0] === 1'b1)
            tb_inv_fail("div is odd -- there is no representable falling edge");
        // T2  A divisor below 2 leaves no room for a distinct half-cycle.
        if (div < 3'd2)
            tb_inv_fail("div < 2 -- rise and fall would coincide");

        // T3  The two edges must never coincide, or every S4 sampling point
        //     collapses onto the T-state boundary it is meant to sit between.
        if (ce_rise === 1'b1 && ce_fall === 1'b1)
            tb_inv_fail("ce_rise and ce_fall asserted on the same tick");

        // T4  Exactly div ticks between rising edges, and the falling edge
        //     exactly half way.  This is the property the whole module exists
        //     for; if the counter is ever reloaded early it dies here.
        if (ce_rise === 1'b1) begin
            if (seen_rise === 1'b1 && since_rise !== {1'b0, div})
                tb_inv_fail("V60 clock period is not div clk_ram ticks");
            since_rise <= 4'd1;
            seen_rise  <= 1'b1;
        end
        else begin
            if (ce_fall === 1'b1 && seen_rise === 1'b1
                && since_rise !== {1'b0, half})
                tb_inv_fail("falling edge is not at the half period");
            since_rise <= since_rise + 4'd1;
        end
    end
end
`endif

endmodule
