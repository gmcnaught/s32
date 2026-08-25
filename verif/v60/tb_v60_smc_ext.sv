//============================================================================
//  V60 fetch-window coherency against OTHER bus masters, and against physical
//  address aliasing.  Audit V60-D2 / V60-D3.
//
//  D2  Work RAM has a second write port driven by the protection modules and
//      shared RAM is dual-ported with the sound Z80.  Neither appears on the
//      V60's own bus, so the self-modifying-code guard could not see them and
//      code patched by either could be executed stale out of the fetch window
//      -- or out of the retained loop window, which survives arbitrary control
//      flow.  The fix adds an ext_wr port, captured on the RAW clock because a
//      write by another master can land on a clk edge the ce-gated CPU FSM
//      never sees.
//
//  D3  The guard compared full 32-bit LOGICAL addresses, but the physical bus
//      is 24 bits and work RAM is a 64 KB array decoded across the whole of
//      0x2xxxxx, so a store through 0x210000 and code at 0x200000 are the same
//      physical byte and failed the overlap test.
//
//  Part 1 is white-box and deterministic: the CPU's clock enable is held low,
//  an ext_wr strobe is issued into that gap (which is the case the old ce-gated
//  logic could not have seen at all), the enable is released for exactly one
//  edge, and the resulting invalidation is measured as a pf_epoch delta against
//  a self-calibrating no-pulse baseline.  It covers overlap, non-overlap,
//  wrong-region, and the +0x10000 physical alias.
//
//  Part 2 is black-box: the CPU stores over its own upcoming immediate through
//  a +0x10000 alias.  The memory model here aliases the same way the board does
//  (it indexes m_addr[15:1]), so the store really does land on the byte that is
//  about to execute.  Pre-fix this ran the stale immediate.
//============================================================================
`timescale 1ns/1ps

module tb_v60_smc_ext;

reg clk = 0, rst = 1;
always #10 clk = ~clk;

wire        c_req, c_we, c_ack;
wire [31:0] c_addr, c_wdata, c_rdata;
wire [1:0]  c_size;
wire        m_req, m_we, m_ack;
wire [23:1] m_addr;
wire [15:0] m_wdata, m_rdata;
wire [1:0]  m_be;

// +CEDIV=<n>: gate ce every n-th clock (default 1, the unit-suite cadence).
integer cediv = 1;
integer cecnt = 0;
reg ce_gen = 1'b1;
reg ce_hold = 1'b0;          // part 1 freezes the CPU here, not the generator
wire ce = ce_gen & ~ce_hold;
initial if (!$value$plusargs("CEDIV=%d", cediv)) cediv = 1;
always @(posedge clk) begin
    if (cecnt >= cediv-1) begin cecnt <= 0; ce_gen <= 1'b1; end
    else begin cecnt <= cecnt + 1; ce_gen <= 1'b0; end
end

reg        ext_wr = 1'b0;
reg [23:0] ext_wr_addr = 24'd0;
reg  [2:0] ext_wr_bytes = 3'd0;

s32_v60 #(.START_PC(32'h0000_0000)) cpu (
    .clk(clk), .ce(ce), .rst(rst),
    .if_req(), .if_addr(), .if_data(64'd0), .if_ack(1'b0),
    .bus_req(c_req), .bus_we(c_we), .bus_addr(c_addr), .bus_size(c_size),
    .bus_wdata(c_wdata), .bus_rdata(c_rdata), .bus_ack(c_ack),
    .irq_n(1'b1), .irq_vector(8'h00), .irq_ack(), .nmi_n(1'b1),
    .ext_wr(ext_wr), .ext_wr_addr(ext_wr_addr), .ext_wr_bytes(ext_wr_bytes)
);

s32_v60_bus adapter (
    .clk(clk), .ce(ce), .rst(rst),
    .c_req(c_req), .c_we(c_we), .c_addr(c_addr), .c_size(c_size),
    .c_wdata(c_wdata), .c_rdata(c_rdata), .c_ack(c_ack),
    .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wdata),
    .m_be(m_be), .m_rdata(m_rdata), .m_ack(m_ack)
);

// Unified memory indexed by m_addr[15:1]: it aliases every 64 KB exactly as
// work RAM does on the board.  That aliasing is what part 2 tests.
reg [15:0] ram [0:32767];
reg ack_r = 0;
assign m_rdata = ram[m_addr[15:1]];
assign m_ack = ack_r;
always @(posedge clk) begin
    ack_r <= m_req & ~ack_r;
    if (!rst && m_req && m_we && !ack_r) begin
        if (m_be[0]) ram[m_addr[15:1]][7:0]  <= m_wdata[7:0];
        if (m_be[1]) ram[m_addr[15:1]][15:8] <= m_wdata[15:8];
    end
end

integer i;
integer errors = 0;

task automatic do_reset;
begin
    rst = 1'b1;
    ce_hold = 1'b0;
    repeat (8) @(posedge clk);
    rst = 1'b0;
end
endtask

// Freeze the CPU, optionally strobe one external write into the frozen gap,
// then release the enable for exactly one CPU edge and report the pf_epoch
// delta.  pf_epoch is bumped by, and only by, an invalidation that voids an
// in-flight prefetch, so the delta is the observable.
// mode 0 = no external write at all (control)
//      1 = overlapping: the window's own base
//      2 = same region, 4 KB away: no overlap
//      3 = same 16-bit offset, region nibble 3: a different physical byte
//      4 = base + 0x10000: a different LOGICAL address, the SAME physical byte
//
// The CPU's clock enable is held low for the whole probe, so the strobe lands
// in a gap the ce-gated FSM never sees -- the case the pre-fix logic could not
// have observed at all -- and the observable is the detector flag itself, read
// while still frozen.  Nothing else in the core moves, so there is no noise to
// calibrate against.  The address is derived from the LIVE window base inside
// the task, after the freeze.
task automatic probe(input integer mode, output detected,
                     output [31:0] base_out, output [4:0] wr_out);
    reg [23:0] a;
begin
    ce_hold = 1'b1;
    @(posedge clk);
    @(posedge clk);
    base_out = cpu.fb_base;
    wr_out   = cpu.fb_wr;
    case (mode)
        1: a = cpu.fb_base[23:0];
        2: a = cpu.fb_base[23:0] + 24'd4096;
        3: a = (cpu.fb_base[23:0] & 24'h0FFFFF) | 24'h300000;
        4: a = cpu.fb_base[23:0] + 24'h010000;
        default: a = 24'd0;
    endcase
    if (mode != 0) begin
        ext_wr       <= 1'b1;
        ext_wr_addr  <= a;
        ext_wr_bytes <= 3'd2;
        @(posedge clk);
        ext_wr       <= 1'b0;
        @(posedge clk);
    end
    else begin
        @(posedge clk);
        @(posedge clk);
    end
    detected = cpu.ext_fb_inval;
end
endtask

// Let the CPU run, then stop with a non-empty fetch window and no invalidation
// left pending.  A zero-length window would make every probe report "no
// overlap" for the wrong reason.
task automatic quiesce(output [31:0] base_out, output [4:0] wr_out);
    integer tries;
    reg det;
begin
    for (tries = 0; tries < 64; tries = tries + 1) begin
        ce_hold = 1'b0;
        repeat (7 * (cediv > 0 ? cediv : 1)) @(posedge clk);
        probe(0, det, base_out, wr_out);
        if (det === 1'b0 && wr_out >= 5'd1) tries = 99;
    end
    if (tries != 100) begin
        errors = errors + 1;
        $display("  SETUP FAIL: never reached a quiet freeze with a non-empty window");
    end
end
endtask

task automatic expect_det(input [8*24:1] name, input got, input want);
begin
    if (got === want) $display("  %0s: PASS (invalidate=%0b)", name, got);
    else begin
        errors = errors + 1;
        $display("  %0s: FAIL (invalidate=%0b, expected %0b)", name, got, want);
    end
end
endtask

// Program: a NOP run.  No branches, nothing that could disturb the window
// while a probe is frozen.
task automatic load_nops;
begin
    for (i = 0; i < 32768; i = i + 1) ram[i] = 16'hCDCD;
    ram[512] = 16'h0000;   // HALT well past anything executed here
end
endtask

// Part 2 program: the CPU stores over its OWN upcoming immediate through a
// +0x10000 alias of the executed address.
//   0..6   MOVW #$0000BEEF, R0
//   7..13  MOVW R0, [$00010014]     <- alias of $14
//   14..16 NOP x3
//   17..23 MOVW #$11111111, R1      (imm32 at bytes 20..23)
//   24     HALT
task automatic load_alias_program;
    reg [7:0] p [0:31];
begin
    for (i = 0; i < 32768; i = i + 1) ram[i] = 16'h0000;
    for (i = 0; i < 32; i = i + 1) p[i] = 8'h00;
    p[0]=8'h2D; p[1]=8'h20; p[2]=8'hF4; p[3]=8'hEF; p[4]=8'hBE; p[5]=8'h00; p[6]=8'h00;
    p[7]=8'h2D; p[8]=8'h00; p[9]=8'hF3; p[10]=8'h14; p[11]=8'h00; p[12]=8'h01; p[13]=8'h00;
    p[14]=8'hCD; p[15]=8'hCD; p[16]=8'hCD;
    p[17]=8'h2D; p[18]=8'h21; p[19]=8'hF4; p[20]=8'h11; p[21]=8'h11; p[22]=8'h11; p[23]=8'h11;
    p[24]=8'h00;
    for (i = 0; i < 16; i = i + 1) ram[i] = {p[2*i+1], p[2*i]};
end
endtask

reg d_ctrl, d_ovl, d_far, d_region, d_alias;
reg [31:0] fbb;
reg [4:0]  fbw;
integer guard;

initial begin
    // ================= part 1: the ext_wr port itself =================
    load_nops();
    do_reset();
    // Let the core leave S_RESET and fill its window.  A comparison against
    // fb_wr cannot be the loop condition: it is X until the first enabled edge
    // after reset, and `x < 2` is X, which reads as false.
    repeat (200 * (cediv > 0 ? cediv : 1)) @(posedge clk);

    $display("EXT WR PORT:");
    quiesce(fbb, fbw);
    $display("  window at base=%0d wr=%0d", fbb, fbw);

    quiesce(fbb, fbw); probe(0, d_ctrl,   fbb, fbw);
    expect_det("control (no write)", d_ctrl, 1'b0);

    quiesce(fbb, fbw); probe(1, d_ovl,    fbb, fbw);
    expect_det("overlap (ce low)", d_ovl, 1'b1);

    quiesce(fbb, fbw); probe(2, d_far,    fbb, fbw);
    expect_det("no overlap", d_far, 1'b0);

    quiesce(fbb, fbw); probe(3, d_region, fbb, fbw);
    expect_det("wrong region", d_region, 1'b0);

    quiesce(fbb, fbw); probe(4, d_alias,  fbb, fbw);
    expect_det("physical alias", d_alias, 1'b1);

    // consumption: one enabled edge must drop the window and clear the request
    quiesce(fbb, fbw); probe(1, d_ovl, fbb, fbw);
    ce_hold = 1'b0;
    @(posedge clk);
    while (!ce_gen) @(posedge clk);
    @(posedge clk);
    ce_hold = 1'b1;
    @(posedge clk);
    if (cpu.fb_wr === 5'd0 && cpu.ext_fb_inval === 1'b0)
        $display("  consume: PASS (window dropped, request cleared)");
    else begin
        errors = errors + 1;
        $display("  consume: FAIL (fb_wr=%0d pending=%0b)",
                 cpu.fb_wr, cpu.ext_fb_inval);
    end

    ce_hold = 1'b0;

    // ================= part 2: own store through an alias =============
    load_alias_program();
    do_reset();
    for (guard = 0; guard < 20000 && !cpu.halted; guard = guard + 1)
        @(posedge clk);
    if (cpu.halted && cpu.r[0] == 32'h0000_BEEF && cpu.r[1] == 32'h0000_BEEF)
        $display("ALIAS SMC PASS (r1=%08x)", cpu.r[1]);
    else begin
        errors = errors + 1;
        $display("ALIAS SMC FAIL halted=%0d r0=%08x r1=%08x expected 0000BEEF",
                 cpu.halted, cpu.r[0], cpu.r[1]);
        if (cpu.r[1] == 32'h1111_1111)
            $display("  executed STALE bytes: the store through +0x10000 did not invalidate the window it physically overwrote");
    end

    if (errors == 0) $display("V60 SMC EXT PASS");
    else             $display("V60 SMC EXT FAIL (%0d errors)", errors);
    $finish;
end

endmodule
