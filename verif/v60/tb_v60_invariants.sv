//============================================================================
//  Negative bench for the V60 bus-handshake invariants (audit S03 / S07.2).
//
//  The invariants themselves live in the RTL and are silent on every other
//  bench in this suite.  Silence is not evidence: an assertion nobody has seen
//  fire is decoration.  This bench deliberately violates each one and requires
//  it to be caught.
//
//  Built with +define+V60_INVARIANT_NONFATAL so a fire increments a counter
//  and reports instead of killing the run.  Without that define -- i.e. in
//  every other bench and in CI -- these are $fatal, because each one means a
//  bus transaction completed against the wrong requester or a request vanished
//  mid-flight, and nothing checked afterwards would mean anything.
//
//  The CPU-side cases drive bus_ack directly rather than through the adapter,
//  and force the arbiter state, so each violation is produced exactly and
//  without depending on instruction timing.
//============================================================================
`timescale 1ns/1ps

module tb_v60_invariants;

integer errors = 0;
integer n_before;

// ---------------------------------------------------------------------------
// CPU under test, with the bench standing in for the bus adapter
// ---------------------------------------------------------------------------
reg clk = 0, rst = 1, ce = 1;
always #10 clk = ~clk;

wire        bus_req, bus_we;
wire [31:0] bus_addr, bus_wdata;
wire  [1:0] bus_size;
reg  [31:0] bus_rdata = 32'd0;
reg         bus_ack = 1'b0;

s32_v60 #(.START_PC(32'h0000_0000)) cpu (
    .clk(clk), .ce(ce), .rst(rst),
    .fast_ifetch(1'b0),
    .if_req(), .if_addr(), .if_data(64'd0), .if_ack(1'b0),
    .bus_req(bus_req), .bus_we(bus_we), .bus_addr(bus_addr), .bus_size(bus_size),
    .bus_wdata(bus_wdata), .bus_rdata(bus_rdata), .bus_ack(bus_ack),
    .irq_n(1'b1), .irq_vector(8'h00), .irq_ack(), .nmi_n(1'b1),
    .ext_wr(1'b0), .ext_wr_addr(24'd0), .ext_wr_bytes(3'd0)
);

// ---------------------------------------------------------------------------
// Adapter under test, driven directly
// ---------------------------------------------------------------------------
reg         a_req = 0, a_we = 0;
reg  [31:0] a_addr = 0, a_wdata = 0;
reg  [1:0]  a_size = 0;
wire [31:0] a_rdata;
wire        a_ack;
wire        am_req, am_we;
wire [23:1] am_addr;
wire [15:0] am_wdata;
wire [1:0]  am_be;
reg  [15:0] am_rdata = 16'h1234;
reg         am_ack = 0;

s32_v60_bus adapter (
    .clk(clk), .ce(ce), .rst(rst),
    .c_req(a_req), .c_we(a_we), .c_addr(a_addr), .c_size(a_size),
    .c_wdata(a_wdata), .c_rdata(a_rdata), .c_ack(a_ack),
    .m_req(am_req), .m_we(am_we), .m_addr(am_addr), .m_wdata(am_wdata),
    .m_be(am_be), .m_rdata(am_rdata), .m_ack(am_ack)
);

// ---------------------------------------------------------------------------
// Cadence generator under test
// ---------------------------------------------------------------------------
reg cad_rst = 1'b1;
wire cad_ce;
s32_v60_exec_cadence cadence (
    .clk(clk), .rst(cad_rst), .pause(1'b0), .ce(cad_ce)
);

task automatic expect_fire(input [8*40:1] name, input integer got,
                           input integer was);
begin
    if (got > was) $display("  %0s: PASS (caught, %0d fire(s))", name, got - was);
    else begin
        errors = errors + 1;
        $display("  %0s: FAIL -- the violation was NOT caught", name);
    end
end
endtask

task automatic expect_quiet(input [8*40:1] name, input integer got,
                            input integer was);
begin
    if (got == was) $display("  %0s: PASS (no false positive)", name);
    else begin
        errors = errors + 1;
        $display("  %0s: FAIL -- fired with nothing wrong (%0d)", name, got - was);
    end
end
endtask

initial begin
    $display("V60 INVARIANTS (negative bench)");

    repeat (8) @(posedge clk);
    rst = 0;
    cad_rst = 0;
    repeat (20) @(posedge clk);

    // ---- control: nothing forced, nothing should fire -------------------
    n_before = cpu.v60_inv_fails;
    repeat (40) @(posedge clk);
    expect_quiet("control (CPU idle-running)", cpu.v60_inv_fails, n_before);

    // ---- I1: a data ack with no outstanding data request ----------------
    n_before = cpu.v60_inv_fails;
    @(negedge clk);
    force cpu.bus_owner = 2'd1;    // OWN_D
    force cpu.dbus_req  = 1'b0;
    bus_ack = 1'b1;
    @(posedge clk); @(posedge clk);
    bus_ack = 1'b0;
    release cpu.bus_owner;
    release cpu.dbus_req;
    @(posedge clk);
    expect_fire("I1 stale dack", cpu.v60_inv_fails, n_before);

    // ---- I2: a prefetch ack with no outstanding prefetch ----------------
    n_before = cpu.v60_inv_fails;
    @(negedge clk);
    force cpu.bus_owner = 2'd2;    // OWN_PF
    force cpu.pf_req    = 1'b0;
    bus_ack = 1'b1;
    @(posedge clk); @(posedge clk);
    bus_ack = 1'b0;
    release cpu.bus_owner;
    release cpu.pf_req;
    @(posedge clk);
    expect_fire("I2 stale pf_ack", cpu.v60_inv_fails, n_before);

    // ---- I3: dbus_req cleared without a data acknowledgement ------------
    n_before = cpu.v60_inv_fails;
    @(negedge clk);
    force cpu.bus_owner = 2'd0;    // keep dack low throughout
    force cpu.dbus_req  = 1'b1;
    @(posedge clk); @(posedge clk);
    force cpu.dbus_req  = 1'b0;    // vanishes with no ack
    @(posedge clk); @(posedge clk);
    release cpu.dbus_req;
    release cpu.bus_owner;
    @(posedge clk);
    expect_fire("I3 request dropped unacked", cpu.v60_inv_fails, n_before);

    // ---- I4: request left un-granted for more than one execute cycle ----
    n_before = cpu.v60_inv_fails;
    @(negedge clk);
    force cpu.bus_owner = 2'd0;    // OWN_NONE
    force cpu.bus_req   = 1'b1;    // ... with a request standing
    repeat (4) @(posedge clk);
    release cpu.bus_req;
    release cpu.bus_owner;
    @(posedge clk);
    expect_fire("I4 grant stuck", cpu.v60_inv_fails, n_before);

    // ---- B2: adapter payload moved while the access was in flight -------
    n_before = adapter.v60bus_inv_fails;
    @(negedge clk);
    a_addr = 32'h0000_1000; a_size = 2'd1; a_we = 1'b0; a_req = 1'b1;
    repeat (3) @(posedge clk);     // accepted, now in flight
    @(negedge clk);
    a_addr = 32'h0000_2000;        // the violation
    repeat (2) @(posedge clk);
    expect_fire("B2 payload moved in flight", adapter.v60bus_inv_fails, n_before);
    a_req = 1'b0; a_addr = 32'h0000_1000;
    repeat (4) @(posedge clk);

    // ---- B1: a held acknowledgement survives reset ----------------------
    n_before = adapter.v60bus_inv_fails;
    @(negedge clk);
    rst = 1'b1;
    force adapter.c_ack = 1'b1;
    repeat (3) @(posedge clk);
    release adapter.c_ack;
    rst = 1'b0;
    @(posedge clk);
    expect_fire("B1 ack survived reset", adapter.v60bus_inv_fails, n_before);
    repeat (8) @(posedge clk);

    // ---- cadence: execution enable on adjacent clk_sys edges ------------
    n_before = cadence.cad_inv_fails;
    @(negedge clk);
    force cadence.phase = 1'b0;    // ce is !pause && !phase -> high every edge
    repeat (4) @(posedge clk);
    release cadence.phase;
    @(posedge clk);
    expect_fire("SDC premise (adjacent exec CE)", cadence.cad_inv_fails, n_before);

    if (errors == 0) $display("V60 INVARIANTS PASS");
    else             $display("V60 INVARIANTS FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #500000;
    $display("V60 INVARIANTS FAIL (timeout)");
    $finish;
end

endmodule
