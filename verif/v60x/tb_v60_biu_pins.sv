//============================================================================
//  tb_v60_biu_pins -- the pin events of databook S4, each at its named edge.
//
//  tb_v60_biu_tstates asserts the SHAPE of a cycle (which states, in what
//  order).  This asserts what the pins do, and when.  A machine can walk
//  T1 T2 T3 T4 perfectly and still assert DS a full state early.
//
//  The instants, all from p.3.283 unless noted:
//    rising T1   A23-A0, DL1-DL0, ST2-ST0, FAS*, MRQ*, R/W*, UBE* asserted and
//                valid until the end of the cycle; BCY* asserted
//    falling T1  DS* asserted; write data driven
//    rising T4   BCY* negated -- and DS* is NOT
//    falling T4  read data latched, DS* negated
//  plus back-to-back I/O recovery (p.3.291) and bus hold (p.3.292).
//============================================================================
`timescale 1ns/1ps

module tb_v60_biu_pins;
    import v60_bus_pkg::*;

localparam integer DIV = 6;

reg clk = 1'b0;
always #5 clk = ~clk;
reg rst = 1'b1;

reg [2:0] tick = 3'd0;
always @(posedge clk) if (!rst) tick <= (tick == DIV-1) ? 3'd0 : tick + 3'd1;
wire ce_rise = !rst && (tick == 3'd0);
wire ce_fall = !rst && (tick == DIV/2);

reg          req = 1'b0, we = 1'b0, ube = 1'b1, first = 1'b1;
bus_status_e status = BST_MEM_SINGLE;
reg   [23:0] addr = 24'h0;
reg    [1:0] dl = 2'b01;
reg   [15:0] wdata = 16'h0;
reg          ready_n = 1'b0, bmode = 1'b1, hldrq_n = 1'b1;
reg          berr_n = 1'b1, rt_ep_n = 1'b1, nmi_n = 1'b1, int_req = 1'b0;
reg          nmi_take = 1'b0;
reg   [15:0] d_in = 16'hBEEF;

wire         ack, busy, d_oe, bus_hiz;
wire         berr, berr_we, berr_retry, nmi_pending, int_pending;
bus_status_e berr_status;
wire  [23:0] berr_addr;
wire  [15:0] rdata, d_out;
wire  [23:0] a;
wire   [1:0] dl_o;
wire   [2:0] st;
wire         mrq_n, rw_n, ube_n, fas_n, bcy_n, ds_n, hldak_n;
bus_state_e  state;

v60_biu dut (
    .clk(clk), .rst(rst), .ce_rise(ce_rise), .ce_fall(ce_fall),
    .req(req), .status(status), .addr(addr), .we(we), .dl(dl), .ube(ube),
    .first(first), .lock(1'b0),
    .wdata(wdata), .ack(ack), .rdata(rdata), .busy(busy),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .block_n(), .ds_n(ds_n),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .bus_hiz(bus_hiz),
    .ready_n(ready_n), .bmode(bmode), .hldrq_n(hldrq_n), .hldak_n(hldak_n),
    .berr_n(berr_n), .rt_ep_n(rt_ep_n), .nmi_n(nmi_n), .int_req(int_req),
    .berr(berr), .berr_status(berr_status), .berr_addr(berr_addr),
    .berr_we(berr_we), .berr_retry(berr_retry),
    .nmi_pending(nmi_pending), .nmi_take(nmi_take), .int_pending(int_pending),
    .state(state)
);

integer errors = 0;
task chk(input cond, input [8*76:1] what);
begin
    if (!cond) begin
        errors = errors + 1;
        $display("FAIL  %0s (state=%0d t=%0t)", what, state, $time);
    end
end
endtask

// --- observed pin events, tagged with the instant they happened at ---------
// Recorded by the monitor, checked by the stimulus.  Each is the state the
// machine was in when the pin changed, so "BCY fell in T1" is checkable
// without the stimulus having to guess at timing.
reg [2:0] bcy_fell_in = 3'd7, bcy_rose_in = 3'd7;
reg [2:0] ds_fell_in  = 3'd7, ds_rose_in  = 3'd7;
reg       bcy_fell_on_rise = 1'b0, ds_fell_on_fall = 1'b0;
reg       ds_rose_on_fall  = 1'b0, bcy_rose_on_rise = 1'b0;
reg       ds_low_at_rising_t4 = 1'b0;
reg [2:0] hiz_set_in = 3'd7;
reg       hldak_low_on_fall = 1'b0;

// The DUT launches a pin change and its state update on the same edge, so the
// monitor can only OBSERVE the change one fast clock later -- by which time
// ce_rise/ce_fall have passed.  Compare against registered copies, which hold
// the strobe as it was on the launching edge, and against `state`, which by
// then holds the state the launch moved into.  Sampling the live strobes here
// reports every event as happening on neither edge.
reg pbcy = 1'b1, pds = 1'b1, phiz = 1'b0, phldak = 1'b1;
reg prev_rise = 1'b0, prev_fall = 1'b0;
always @(posedge clk) begin
    prev_rise <= ce_rise;
    prev_fall <= ce_fall;
    if (bcy_n != pbcy) begin
        if (!bcy_n) begin bcy_fell_in <= state; bcy_fell_on_rise <= prev_rise; end
        else        begin bcy_rose_in <= state; bcy_rose_on_rise <= prev_rise; end
    end
    if (ds_n != pds) begin
        if (!ds_n) begin ds_fell_in <= state; ds_fell_on_fall <= prev_fall; end
        else       begin ds_rose_in <= state; ds_rose_on_fall <= prev_fall; end
    end
    if (bus_hiz && !phiz)   hiz_set_in <= state;
    if (!hldak_n && phldak) hldak_low_on_fall <= prev_fall;
    // "the BCY* output is negated at the rising edge of the T4 bus state" --
    // and nothing says DS* is.  Catch a machine that negates both together.
    if (prev_rise && state == T_T4) ds_low_at_rising_t4 <= !ds_n;
    pbcy <= bcy_n; pds <= ds_n; phiz <= bus_hiz; phldak <= hldak_n;
end

task clear_events;
begin
    bcy_fell_in = 3'd7; bcy_rose_in = 3'd7; ds_fell_in = 3'd7; ds_rose_in = 3'd7;
    hiz_set_in = 3'd7; ds_low_at_rising_t4 = 1'b0;
end
endtask

task do_cycle(input bus_status_e s, input wr, input [23:0] ad, input [15:0] wd);
begin
    @(negedge clk);
    status = s; we = wr; addr = ad; wdata = wd; req = 1'b1;
    @(posedge ack);
    @(negedge clk);
    req = 1'b0;
    // ack and the falling-T4 pin events are launched on the same edge, so the
    // monitor has not observed them yet.  Give it two fast clocks before any
    // check reads what it recorded.
    repeat (2) @(posedge clk);
end
endtask

// The bus error observables.  BCY* falls once per bus cycle, so counting its
// falling edges is how a retried cycle is told from a completed one.
integer n_bcy = 0, n_ack = 0, n_berr = 0, n_retry = 0;
reg     pbcy2 = 1'b1;
always @(posedge clk) if (!rst) begin
    if (!bcy_n && pbcy2) n_bcy <= n_bcy + 1;
    if (ack)             n_ack <= n_ack + 1;
    if (berr)            n_berr <= n_berr + 1;
    if (berr_retry)      n_retry <= n_retry + 1;
    pbcy2 <= bcy_n;
end

// Count TI states between the end of one cycle and the start of the next.
integer ti_run = 0, ti_between = 0;
reg     counting = 1'b0;
always @(posedge clk) if (ce_rise) begin
    if (state == T_TI && counting) ti_run <= ti_run + 1;
    if (state == T_T1 && counting) begin ti_between <= ti_run; counting <= 1'b0; end
end

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (DIV*2) @(negedge clk);

    // ---- read cycle: every pin instant --------------------------------
    clear_events();
    do_cycle(BST_MEM_SINGLE, 1'b0, 24'hABCDEF, 16'h0);
    chk(bcy_fell_in === T_T1 && bcy_fell_on_rise, "BCY* asserted at the RISING edge of T1");
    chk(ds_fell_in  === T_T1 && ds_fell_on_fall,  "DS* asserted at the FALLING edge of T1");
    chk(bcy_rose_in === T_T4 && bcy_rose_on_rise, "BCY* negated at the RISING edge of T4");
    chk(ds_low_at_rising_t4, "DS* still asserted at the rising edge of T4");
    chk(ds_rose_in  === T_T4 && ds_rose_on_fall,  "DS* negated at the FALLING edge of T4");
    chk(a === 24'hABCDEF, "A23-A0 still valid at the end of the cycle");
    chk(rw_n === 1'b1, "R/W* high for a read");
    chk(rdata === 16'hBEEF, "read data latched");

    // ---- write cycle ---------------------------------------------------
    clear_events();
    do_cycle(BST_MEM_SINGLE, 1'b1, 24'h001122, 16'h5A5A);
    chk(rw_n === 1'b0, "R/W* low for a write");
    chk(a === 24'h001122, "A23-A0 valid to the end of a write cycle");

    // ---- all sixteen status codes reach the pins unaltered -------------
    begin : status_sweep
        integer c;
        for (c = 0; c < 16; c = c + 1) begin
            do_cycle(bus_status_e'(c[3:0]), 1'b0, 24'h002000 + c, 16'h0);
            chk(st === c[2:0] && mrq_n === c[3],
                "status code drives MRQ and ST2-ST0 unaltered");
        end
    end

    // ---- FAS* marks the first bus cycle of a logical access (p.3.235) ---
    first = 1'b1;
    do_cycle(BST_MEM_SINGLE, 1'b0, 24'h005000, 16'h0);
    chk(fas_n === 1'b0, "FAS* low on the first bus cycle of an access");
    first = 1'b0;
    do_cycle(BST_MEM_SINGLE, 1'b0, 24'h005002, 16'h0);
    chk(fas_n === 1'b1, "FAS* high on a subsequent bus cycle");
    first = 1'b1;

    // ---- UBE* + A0 select the byte lanes (p.3.236) ----------------------
    ube = 1'b0;
    do_cycle(BST_MEM_SINGLE, 1'b0, 24'h006000, 16'h0);   // A0 = 0
    chk(lane_of(ube_n, a[0]) === LANE_HALFWORD, "UBE*=0 A0=0 is a halfword access");
    do_cycle(BST_MEM_SINGLE, 1'b0, 24'h006001, 16'h0);   // A0 = 1
    chk(lane_of(ube_n, a[0]) === LANE_UPPER_BYTE, "UBE*=0 A0=1 is an upper byte access");
    ube = 1'b1;
    do_cycle(BST_MEM_SINGLE, 1'b0, 24'h006002, 16'h0);
    chk(lane_of(ube_n, a[0]) === LANE_LOWER_BYTE, "UBE*=1 A0=0 is a lower byte access");

    // ---- back-to-back I/O gets three TI states (p.3.291) ---------------
    do_cycle(BST_IO_SINGLE, 1'b0, 24'h003000, 16'h0);
    ti_run = 0; ti_between = 0; counting = 1'b1;
    do_cycle(BST_IO_SINGLE, 1'b0, 24'h003002, 16'h0);
    chk(ti_between >= 3, "three TI states between consecutive I/O bus cycles");
    $display("      I/O -> I/O idle states: %0d", ti_between);

    // ---- memory to memory does NOT (the rule is scoped to I/O) ---------
    do_cycle(BST_MEM_SINGLE, 1'b0, 24'h004000, 16'h0);
    ti_run = 0; ti_between = 0; counting = 1'b1;
    do_cycle(BST_MEM_SINGLE, 1'b0, 24'h004002, 16'h0);
    chk(ti_between < 3, "memory cycles are not separated by the I/O recovery gap");
    $display("      mem -> mem idle states: %0d", ti_between);

    // ---- bus hold (p.3.292) --------------------------------------------
    clear_events();
    @(negedge clk);
    hldrq_n = 1'b0;
    wait (state === T_TH);
    repeat (DIV) @(negedge clk);
    chk(hiz_set_in === T_TH, "outputs go high-Z at the rising edge of TH");
    chk(!hldak_n, "HLDAK* asserted during TH");
    chk(hldak_low_on_fall, "HLDAK* asserted a half clock after the TH tri-state");
    @(negedge clk);
    hldrq_n = 1'b1;
    repeat (DIV*3) @(negedge clk);
    chk(state === T_TI, "bus hold exits through TI");
    chk(!bus_hiz, "outputs driven again after the hold");

    // =====================================================================
    // BERR* and RT/EP*, at the instant the p.3.243 plate draws them.
    // =====================================================================
    // A fault that is present for T2 and T3 and gone by T4 is not a fault:
    // the pins are sampled once, in T4, and not watched across the cycle.
    n_bcy = 0; n_ack = 0; n_berr = 0; n_retry = 0;
    fork
        do_cycle(BST_MEM_SINGLE, 1'b0, 24'h007000, 16'h0);
        begin
            @(negedge clk);
            wait (state === T_T2); berr_n = 1'b0; rt_ep_n = 1'b0;
            wait (state === T_T4); berr_n = 1'b1; rt_ep_n = 1'b1;
        end
    join
    chk(n_berr == 0 && n_retry == 0 && n_ack == 1,
        "BERR* low in T2 and T3 and high in T4 is not a fault");

    // And one that is low at the RISING edge of T4 and high again before its
    // midpoint is not one either -- which is what separates the plate's
    // instant from the pin prose's "rising edge of the T4 state".
    n_bcy = 0; n_ack = 0; n_berr = 0; n_retry = 0;
    fork
        do_cycle(BST_MEM_SINGLE, 1'b0, 24'h007002, 16'h0);
        begin
            @(negedge clk);
            wait (state === T_T3); berr_n = 1'b0; rt_ep_n = 1'b0;
            // Into T4, then away well before tick 3, which is its midpoint.
            wait (state === T_T4);
            @(posedge clk); @(posedge clk);
            berr_n = 1'b1; rt_ep_n = 1'b1;
        end
    join
    chk(n_berr == 0 && n_retry == 0 && n_ack == 1,
        "BERR* is sampled at the FALLING edge of T4, not the rising one");

    // "retry the faulty bus cycle (RT/EP* = 1)".  The cycle makes no ack and
    // runs again from the same request; releasing BERR* lets the second one
    // finish.  Two BCY* assertions, one ack.
    n_bcy = 0; n_ack = 0; n_berr = 0; n_retry = 0;
    fork
        do_cycle(BST_MEM_SINGLE, 1'b0, 24'h007004, 16'h0);
        begin
            @(negedge clk);
            berr_n = 1'b0; rt_ep_n = 1'b1;
            @(posedge berr_retry);
            @(negedge clk);
            berr_n = 1'b1;
        end
    join
    chk(n_retry == 1, "RT/EP* = 1 retries the cycle");
    chk(n_berr  == 0, "and raises nothing");
    chk(n_bcy   == 2, "so BCY* is asserted twice: the cycle ran again");
    chk(n_ack   == 1, "and only the second one acknowledged");

    // "cause an exception (RT/EP* = 0)".  The cycle ends, and says what kind
    // of cycle it was and where -- the frame's Exception Address.
    n_bcy = 0; n_ack = 0; n_berr = 0; n_retry = 0;
    fork
        do_cycle(BST_IO_SINGLE, 1'b1, 24'h007006, 16'h1234);
        begin
            @(negedge clk);
            berr_n = 1'b0; rt_ep_n = 1'b0;
            @(posedge berr);
            @(negedge clk);
            berr_n = 1'b1; rt_ep_n = 1'b1;
        end
    join
    chk(n_berr  == 1, "RT/EP* = 0 raises instead of retrying");
    chk(n_retry == 0, "and does not retry");
    chk(n_bcy   == 1, "the cycle is not run again");
    chk(n_ack   == 1, "and it is acknowledged, which is what unwedges the bus");
    chk(berr_status === BST_IO_SINGLE,
        "the fault carries the status of the cycle that failed");
    chk(berr_addr === 24'h007006, "and its physical address");
    chk(berr_we === 1'b1,         "and its direction");

    // =====================================================================
    // NMI* is an event and INT is a level (p.3.237).
    // =====================================================================
    chk(!nmi_pending, "no NMI is pending out of reset");
    @(negedge clk);
    nmi_n = 1'b0;
    repeat (4) @(negedge clk);
    nmi_n = 1'b1;                       // a pulse, gone before it is taken
    repeat (4) @(negedge clk);
    chk(nmi_pending,
        "NMI* latches: the pin can be gone before the instruction completes");
    @(negedge clk); nmi_take = 1'b1;
    @(negedge clk); nmi_take = 1'b0;
    repeat (2) @(negedge clk);
    chk(!nmi_pending, "and taking it releases the latch");

    chk(!int_pending, "INT is low");
    @(negedge clk);
    int_req = 1'b1;
    repeat (4) @(negedge clk);
    chk(int_pending, "INT is reported as a level: the source holds it");
    @(negedge clk);
    int_req = 1'b0;
    repeat (4) @(negedge clk);
    chk(!int_pending, "and nothing here remembers it once the source drops it");

    if (errors == 0) $display("V60 BIU PINS PASS");
    else             $display("V60 BIU PINS FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #4_000_000;
    $display("V60 BIU PINS FAIL (timeout)");
    $finish;
end

endmodule
