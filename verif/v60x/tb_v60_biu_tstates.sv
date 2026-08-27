//============================================================================
//  tb_v60_biu_tstates -- check v60_biu against databook S4, instant by
//  instant.
//
//  Every check below quotes the sentence it enforces.  The point of this bench
//  is that the specification is a list of things that happen at named clock
//  EDGES, so the bench asserts at those edges rather than sampling whenever it
//  is convenient.
//
//  Runs under Icarus and under the other simulator.  Stimulus is driven on the
//  negedge of the fast clock and the DUT is clocked on the posedge, so there
//  is no blocking/non-blocking race to schedule differently -- a bench in this
//  project was already caught passing under one simulator and failing under
//  the other for exactly that reason.
//============================================================================
`timescale 1ns/1ps

module tb_v60_biu_tstates;
    import v60_bus_pkg::*;

localparam integer DIV = 6;         // clk_ram ticks per V60 clock (System 32)

reg clk = 1'b0;
always #5 clk = ~clk;

reg rst = 1'b1;

// V60 clock reconstruction: one ce_rise and one ce_fall per V60 period, with
// the fall at the midpoint.  DIV must be even or the midpoint does not exist.
reg [2:0] tick = 3'd0;
always @(posedge clk) if (!rst) tick <= (tick == DIV-1) ? 3'd0 : tick + 3'd1;
wire ce_rise = !rst && (tick == 3'd0);
wire ce_fall = !rst && (tick == DIV/2);

reg          req = 1'b0, we = 1'b0, ube = 1'b1;
bus_status_e status = BST_MEM_SINGLE;
reg   [23:0] addr = 24'h0;
reg    [1:0] dl   = 2'b01;
reg   [15:0] wdata = 16'h0;
reg          ready_n = 1'b0, bmode = 1'b1, hldrq_n = 1'b1;
reg   [15:0] d_in = 16'hBEEF;

wire         ack, busy, d_oe, bus_hiz;
wire  [15:0] rdata, d_out;
wire  [23:0] a;
wire   [1:0] dl_o;
wire   [2:0] st;
wire         mrq_n, rw_n, ube_n, fas_n, bcy_n, ds_n, hldak_n;
bus_state_e  state;

v60_biu dut (
    .clk(clk), .rst(rst), .ce_rise(ce_rise), .ce_fall(ce_fall),
    .req(req), .status(status), .addr(addr), .we(we), .dl(dl), .ube(ube),
    .wdata(wdata), .ack(ack), .rdata(rdata), .busy(busy),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .ds_n(ds_n),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .bus_hiz(bus_hiz),
    .ready_n(ready_n), .bmode(bmode), .hldrq_n(hldrq_n), .hldak_n(hldak_n),
    .state(state)
);

integer errors = 0;
task chk(input cond, input [8*72:1] what);
begin
    if (!cond) begin
        errors = errors + 1;
        $display("FAIL  %0s (state=%0d t=%0t)", what, state, $time);
    end
end
endtask

// Trace of states at each V60 rising edge, so a whole cycle shape can be
// asserted rather than spot-checked.
integer trace_n = 0;
reg [2:0] trace [0:63];
reg       tracing = 1'b0;
always @(posedge clk) if (ce_rise && tracing && trace_n < 64) begin
    trace[trace_n] = state;
    trace_n = trace_n + 1;
end

function [8*8:1] nm(input [2:0] s);
begin
    case (s)
        T_TI: nm = "TI"; T_T1: nm = "T1"; T_T2: nm = "T2"; T_T3: nm = "T3";
        T_TW: nm = "TW"; T_T4: nm = "T4"; T_TH: nm = "TH"; default: nm = "??";
    endcase
end
endfunction

// trace[k] counted from the first T1: tracing starts before the cycle does,
// so the leading TI states are not part of the shape being asserted.  The scan
// is inline because Icarus will not bind a function called from another one
// here.  Returns 3'b111 -- not a state this machine emits -- past the end.
function [2:0] tr(input integer k);
    integer i, b;
begin
    b = -1;
    for (i = trace_n-1; i >= 0; i = i - 1)
        if (trace[i] === T_T1) b = i;
    if (b < 0 || b + k >= trace_n) tr = 3'b111;
    else                           tr = trace[b + k];
end
endfunction

task show_trace(input [8*32:1] label);
    integer i;
    reg [8*160:1] line;
begin
    line = "";
    for (i = 0; i < trace_n; i = i + 1) line = {line, nm(trace[i]), " "};
    $display("      %0s: %0s", label, line);
end
endtask

// Run one bus cycle and stop tracing when it completes.
task run_cycle(input bus_status_e s, input wr, input [23:0] ad, input [15:0] wd);
begin
    @(negedge clk);
    status = s; we = wr; addr = ad; wdata = wd; req = 1'b1;
    trace_n = 0; tracing = 1'b1;
    @(posedge ack);
    @(negedge clk);
    req = 1'b0;
    repeat (DIV*5) @(negedge clk);
    tracing = 1'b0;
end
endtask

// ---------------------------------------------------------------------------
initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (DIV*2) @(negedge clk);

    // --- normal memory read: T1 T2 T3 T4 -----------------------------------
    ready_n = 1'b0; bmode = 1'b1;
    run_cycle(BST_MEM_SINGLE, 1'b0, 24'h123456, 16'h0);
    show_trace("normal read ");
    chk(tr(0) === T_T1 && tr(1) === T_T2 && tr(2) === T_T3 && tr(3) === T_T4 && tr(4) === T_TI,
        "normal read is T1 T2 T3 T4");
    chk(rdata === 16'hBEEF, "read data latched at falling T4");

    // --- short cycle: BMODE low at falling T2 skips T3 ----------------------
    bmode = 1'b0;
    run_cycle(BST_MEM_SINGLE, 1'b0, 24'h001000, 16'h0);
    show_trace("short read  ");
    chk(tr(0) === T_T1 && tr(1) === T_T2 && tr(2) === T_T4,
        "BMODE low at falling T2 skips T3");
    bmode = 1'b1;

    // --- READY negated at falling T3 inserts TW ----------------------------
    ready_n = 1'b1;
    fork
        begin : release_ready
            @(negedge clk);
            wait (state === T_TW);
            repeat (DIV*2) @(negedge clk);   // hold for two TW states
            ready_n = 1'b0;
        end
    join_none
    run_cycle(BST_MEM_SINGLE, 1'b0, 24'h002000, 16'h0);
    show_trace("read + TW   ");
    chk(tr(2) === T_T3 && tr(3) === T_TW && tr(4) === T_TW,
        "READY high at falling T3 inserts TW after T3");
    chk(tr(5) === T_TW && tr(6) === T_T4,
        "TW ends and T4 follows once READY is sampled low");

    // --- write cycle -------------------------------------------------------
    ready_n = 1'b0;
    run_cycle(BST_MEM_SINGLE, 1'b1, 24'h003000, 16'hA5A5);
    show_trace("write       ");
    chk(tr(0) === T_T1 && tr(1) === T_T2 && tr(2) === T_T3 && tr(3) === T_T4,
        "write is T1 T2 T3 T4");

    // --- status codes reach the pins unaltered ------------------------------
    run_cycle(BST_PREFETCH, 1'b0, 24'h004000, 16'h0);
    chk(st === 3'b111 && mrq_n === 1'b0, "prefetch drives MRQ=0 ST=111");
    run_cycle(BST_IO_SINGLE, 1'b0, 24'h005000, 16'h0);
    chk(st === 3'b011 && mrq_n === 1'b1, "single mode I/O drives MRQ=1 ST=011");

    if (errors == 0) $display("V60 BIU T-STATE PASS");
    else             $display("V60 BIU T-STATE FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #2_000_000;
    $display("V60 BIU T-STATE FAIL (timeout)");
    $finish;
end

endmodule
