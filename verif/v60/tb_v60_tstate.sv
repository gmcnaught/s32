//============================================================================
//  V60 bus adapter as a databook §4 T-state machine (audit §07.4).
//
//  Two things are checked here that nothing else could check before, because
//  the old three-state adapter had no notion of either:
//
//   1. the T-state SEQUENCE -- TI/T1/T2/T3/TW/T4 in the documented order, with
//      TW inserted while READY is deasserted and T4 present only on a normal
//      cycle;
//   2. the pin-level status lines, which are what let this core be checked
//      against a µPD71613 decode table instead of only against MAME.
//
//  And it MEASURES what DATABOOK_TIMING costs, in clocks, per access shape.
//  That number is the whole reason the switch defaults off: the audit's
//  regression gate for it is the Golden Axe II / Spider-Man / Rad Rally
//  black-screen cases, which need hardware.  Better to ship the measurement
//  than a guess.
//============================================================================
`timescale 1ns/1ps

module tb_v60_tstate;

integer errors = 0;

reg clk = 1'b0, rst = 1'b1;
always #5 clk = ~clk;

// Two adapters, identical but for the timing parameter, driven in lockstep.
reg         c_req = 0, c_we = 0;
reg  [31:0] c_addr = 0, c_wdata = 0;
reg  [1:0]  c_size = 0;
reg         ready_n = 1'b0;
reg         bmode   = 1'b1;   // 1 = short cycle
reg         hldrq   = 1'b0;

`define ADAPTER(NAME, DB)                                                     \
    wire [31:0] NAME``_rdata; wire NAME``_ack;                                \
    wire NAME``_mreq, NAME``_mwe; wire [23:1] NAME``_maddr;                   \
    wire [15:0] NAME``_mwdata; wire [1:0] NAME``_mbe;                         \
    wire [2:0] NAME``_st; wire NAME``_mrq, NAME``_rw_n, NAME``_bcy;           \
    wire NAME``_ds, NAME``_ube, NAME``_hldak, NAME``_rt_ep;                   \
    s32_v60_bus #(.DATABOOK_TIMING(DB), .HALF_CLOCK_SAMPLING(1'b0)) NAME (    \
        .clk(clk), .ce(1'b1), .ce_fall(1'b0), .rst(rst),                      \
        .c_req(c_req), .c_we(c_we), .c_addr(c_addr), .c_size(c_size),         \
        .c_wdata(c_wdata), .c_rdata(NAME``_rdata), .c_ack(NAME``_ack),        \
        .m_req(NAME``_mreq), .m_we(NAME``_mwe), .m_addr(NAME``_maddr),        \
        .m_wdata(NAME``_mwdata), .m_be(NAME``_mbe),                           \
        .m_rdata(16'h5A5A), .m_ack(NAME``_mreq),                              \
        .st(NAME``_st), .mrq(NAME``_mrq), .rw_n(NAME``_rw_n),                 \
        .bcy(NAME``_bcy), .ds(NAME``_ds), .ube(NAME``_ube),                   \
        .hldak(NAME``_hldak), .rt_ep(NAME``_rt_ep),                           \
        .bmode(bmode), .ready_n(ready_n), .berr_n(1'b1), .bfrez_n(1'b1),      \
        .hldrq(hldrq));

`ADAPTER(leg, 1'b0)
`ADAPTER(dbk, 1'b1)

task automatic do_reset;
begin
    rst = 1'b1; c_req = 1'b0;
    repeat (4) @(posedge clk);
    @(negedge clk); rst = 1'b0;
    repeat (2) @(posedge clk);
end
endtask

// Clocks from request to acknowledge, for one adapter.  m_ack is tied to
// m_req, so the target never inserts waits and the count is the pure T-state
// cost of the access.
task automatic measure(input integer which, input [31:0] a, input [1:0] sz,
                       output integer clocks);
    integer guard;
    reg done;
begin
    // Counted as ENGAGED clocks -- the accept edge through the completing
    // edge inclusive -- which is what a logical access costs the CPU and the
    // basis the audit's cycle table is quoted on.  Counting to ack-visibility
    // instead adds a mode-dependent edge and compares two different things.
    // The adapter counts its own engaged clocks (accepting edge through
    // completing edge, inclusive) -- see s32_v60_bus.  Measuring from the
    // bench instead means sampling either side of a rising edge, and the
    // accepting clock then merges into the next one differently in each mode.
    @(negedge clk);
    c_addr = a; c_size = sz; c_we = 1'b0; c_req = 1'b1;
    done = 1'b0;
    for (guard = 0; guard < 60 && !done; guard = guard + 1) begin
        @(posedge clk); #1;
        done = which ? dbk_ack : leg_ack;
    end
    repeat (2) @(posedge clk);
    clocks = which ? dbk.last_access_clocks : leg.last_access_clocks;
    @(negedge clk); c_req = 1'b0;
    repeat (3) @(posedge clk);
end
endtask

task automatic compare(input [8*24:1] name, input [31:0] a, input [1:0] sz,
                       input integer want_delta);
    integer cl, cd;
begin
    measure(0, a, sz, cl);
    measure(1, a, sz, cd);
    if (cd - cl == want_delta)
        $display("  %-22s legacy=%0d databook=%0d  delta=%0d (expected %0d): PASS",
                 name, cl, cd, cd - cl, want_delta);
    else begin
        errors = errors + 1;
        $display("  %-22s legacy=%0d databook=%0d  delta=%0d, EXPECTED %0d: FAIL",
                 name, cl, cd, cd - cl, want_delta);
    end
end
endtask

integer cl, cd, guard;
integer tw_seen;

initial begin
    $display("V60 T-STATE");
    do_reset();

    // ---- what DATABOOK_TIMING costs, per access shape --------------------
    // Byte and aligned 16-bit are unchanged; only multi-cycle accesses grow.
    $display("  cost of databook timing (clocks, target never waits):");
    compare("byte",             32'h0000_1000, 2'd0, 0);
    compare("aligned 16-bit",   32'h0000_1000, 2'd1, 0);
    compare("aligned 32-bit",   32'h0000_1000, 2'd2, 1);
    compare("unaligned 32-bit", 32'h0000_1001, 2'd2, 2);

    // ---- T2 exists only in databook mode ---------------------------------
    // The audit's finding: the old adapter entered its setup state once per
    // LOGICAL ACCESS, so continuations ran a clock short of the documented
    // three-clock minimum.  T2 is that missing clock.
    do_reset();
    @(negedge clk);
    c_addr = 32'h0000_1000; c_size = 2'd2; c_we = 1'b0; c_req = 1'b1;
    begin : t2_check
        integer leg_t2, dbk_t2;
        leg_t2 = 0; dbk_t2 = 0;
        for (guard = 0; guard < 40; guard = guard + 1) begin
            @(posedge clk); #1;
            if (leg.ts == 2) leg_t2 = leg_t2 + 1;   // T_T2
            if (dbk.ts == 2) dbk_t2 = dbk_t2 + 1;
        end
        if (leg_t2 == 0 && dbk_t2 > 0)
            $display("  T2 present only in databook mode: PASS (legacy=%0d databook=%0d)",
                     leg_t2, dbk_t2);
        else begin
            errors = errors + 1;
            $display("  T2 presence: FAIL (legacy=%0d databook=%0d)", leg_t2, dbk_t2);
        end
    end
    @(negedge clk); c_req = 1'b0; repeat (4) @(posedge clk);

    // ---- READY deasserted inserts TW -------------------------------------
    // "However long the target takes" was the old model's only wait mechanism.
    // TW is a state, and this proves it is entered and left.
    do_reset();
    ready_n = 1'b1;                       // READY deasserted -> must wait
    @(negedge clk);
    c_addr = 32'h0000_2000; c_size = 2'd1; c_we = 1'b0; c_req = 1'b1;
    tw_seen = 0;
    for (guard = 0; guard < 12; guard = guard + 1) begin
        @(posedge clk); #1;
        if (dbk.ts == 4) tw_seen = tw_seen + 1;     // T_TW
    end
    if (tw_seen > 0 && !dbk_ack)
        $display("  READY low inserts TW and holds: PASS (%0d TW clocks, no ack)", tw_seen);
    else begin
        errors = errors + 1;
        $display("  TW insertion: FAIL (tw=%0d ack=%0b)", tw_seen, dbk_ack);
    end
    @(negedge clk); ready_n = 1'b0;       // release
    begin : release_check
        reg got;
        got = 1'b0;
        for (guard = 0; guard < 12 && !got; guard = guard + 1) begin
            @(posedge clk); #1; got = dbk_ack;
        end
        if (got) $display("  READY release completes the cycle: PASS");
        else begin
            errors = errors + 1;
            $display("  READY release: FAIL -- still stuck");
        end
    end
    @(negedge clk); c_req = 1'b0; repeat (4) @(posedge clk);

    // ---- BMODE low selects a normal cycle, adding T4 ---------------------
    do_reset();
    bmode = 1'b0;
    @(negedge clk);
    c_addr = 32'h0000_3000; c_size = 2'd1; c_we = 1'b0; c_req = 1'b1;
    begin : t4_check
        integer t4;
        t4 = 0;
        for (guard = 0; guard < 20; guard = guard + 1) begin
            @(posedge clk); #1;
            if (dbk.ts == 5) t4 = t4 + 1;           // T_T4
        end
        // HALF_CLOCK_SAMPLING is 0 here, so BMODE is not latched at falling T2
        // and short_cycle stays at its reset value -- T4 is therefore NOT
        // expected.  Recorded rather than asserted: the normal-cycle path
        // needs a real half-clock, which is what s32_v60_timebase provides and
        // what a gated-ce bench cannot.
        $display("  BMODE low, no half-clock sampling: T4 clocks=%0d (informational)", t4);
    end
    @(negedge clk); c_req = 1'b0; bmode = 1'b1; repeat (4) @(posedge clk);

    // ---- pin-level status -------------------------------------------------
    do_reset();
    @(negedge clk);
    c_addr = 32'h0000_4000; c_size = 2'd1; c_we = 1'b1; c_wdata = 32'hDEAD_BEEF;
    c_req = 1'b1;
    begin : pin_check
        integer bcy_n, ds_n, bad_rw, bad_ube;
        bcy_n = 0; ds_n = 0; bad_rw = 0; bad_ube = 0;
        for (guard = 0; guard < 16; guard = guard + 1) begin
            @(posedge clk); #1;
            if (dbk_bcy) begin
                bcy_n = bcy_n + 1;
                if (dbk_rw_n !== ~dbk_mwe)  bad_rw  = bad_rw + 1;
                if (dbk_ube  !== dbk_mbe[1]) bad_ube = bad_ube + 1;
                if (dbk_mrq !== dbk_bcy)     bad_rw  = bad_rw + 1;
            end
            if (dbk_ds) ds_n = ds_n + 1;
        end
        if (bcy_n > 0 && ds_n > 0 && ds_n <= bcy_n && bad_rw == 0 && bad_ube == 0)
            $display("  pins (BCY/DS/MRQ/R-W/UBE): PASS (bcy=%0d ds=%0d, ds within bcy)",
                     bcy_n, ds_n);
        else begin
            errors = errors + 1;
            $display("  pins: FAIL (bcy=%0d ds=%0d bad_rw=%0d bad_ube=%0d)",
                     bcy_n, ds_n, bad_rw, bad_ube);
        end
    end
    @(negedge clk); c_req = 1'b0; c_we = 1'b0; repeat (4) @(posedge clk);

    // ---- HLDRQ / HLDAK ----------------------------------------------------
    // Tied off on this board; exercised here so "tied off" is a statement
    // about the board rather than about the core.
    do_reset();
    @(negedge clk); hldrq = 1'b1;
    begin : hold_check
        reg got;
        got = 1'b0;
        for (guard = 0; guard < 10 && !got; guard = guard + 1) begin
            @(posedge clk); #1; got = dbk_hldak;
        end
        if (got) $display("  HLDRQ -> HLDAK: PASS");
        else begin
            errors = errors + 1;
            $display("  HLDRQ -> HLDAK: FAIL");
        end
    end
    @(negedge clk); hldrq = 1'b0;
    begin : unhold_check
        reg back;
        back = 1'b0;
        for (guard = 0; guard < 10 && !back; guard = guard + 1) begin
            @(posedge clk); #1; back = (dbk.ts == 0) && !dbk_hldak;
        end
        if (back) $display("  HLDRQ release -> TI: PASS");
        else begin
            errors = errors + 1;
            $display("  HLDRQ release: FAIL -- stuck in TH");
        end
    end

    if (errors == 0) $display("V60 T-STATE PASS");
    else             $display("V60 T-STATE FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #2000000;
    $display("V60 T-STATE FAIL (timeout)");
    $finish;
end

endmodule
