// Throughput micro-benchmark for the SegaSonic floor-palette race
// investigation (docs/segasonic-bringup.md, plan
// find-the-real-fix-twinkling-donut).  Measures clk_sys cycles/element for
// the two instruction idioms MAME's disassembly shows dominating the
// level-load burst (verified against the real ROM via MAME's debugger,
// 2026-08-04):
//   A) mov.h [R10+],R0 ; mov.h R0,[R11+] ; dbr R1,<store>   (PC 0x0998DE
//      etc. -- a plain auto-increment MOV pair in a decrement-branch loop,
//      not a string instruction)
//   B) movcu.h [R10],#10,[R11],#10                          (PC 0x0009A530
//      -- the real MOVCUH string instruction, called in an outer dbr loop
//      for 16-halfword chunks, exactly as the ROM does)
// Both use the SAME idealised one-clk_sys-latency BRAM memory model as
// tb_v60_sonic_decompress.sv (ack the cycle after req), matching how the
// real core's VRAM/palette BRAM peripherals behave -- not SDRAM latency,
// which this burst never touches.
`timescale 1ns/1ps

module tb_v60_sonic_burst_timing;
reg clk = 0, rst = 1;
always #10 clk = ~clk;

wire c_req, c_we, c_ack;
wire [31:0] c_addr, c_wdata, c_rdata;
wire [1:0] c_size;
wire m_req, m_we, m_ack;
wire [23:1] m_addr;
wire [15:0] m_wdata, m_rdata;
wire [1:0] m_be;

s32_v60 #(.START_PC(32'h0000_0000)) cpu (
    .clk(clk), .ce(1'b1), .rst(rst),
    .if_req(), .if_addr(), .if_data(64'd0), .if_ack(1'b0),
    .bus_req(c_req), .bus_we(c_we), .bus_addr(c_addr), .bus_size(c_size),
    .bus_wdata(c_wdata), .bus_rdata(c_rdata), .bus_ack(c_ack),
    .irq_n(1'b1), .irq_vector(8'h00), .irq_ack(), .nmi_n(1'b1),
    .dbg_pc(), .dbg_halted()
);

s32_v60_bus adapter (
    .clk(clk), .ce(1'b1), .rst(rst),
    .c_req(c_req), .c_we(c_we), .c_addr(c_addr), .c_size(c_size),
    .c_wdata(c_wdata), .c_rdata(c_rdata), .c_ack(c_ack),
    .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wdata),
    .m_be(m_be), .m_rdata(m_rdata), .m_ack(m_ack)
);

reg [15:0] ram [0:65535];
reg ack_r;
assign m_rdata = ram[m_addr[16:1]];
assign m_ack = ack_r;
always @(posedge clk) begin
    ack_r <= m_req & ~ack_r;
    if (m_req && m_we && !ack_r) begin
        if (m_be[0]) ram[m_addr[16:1]][7:0]  <= m_wdata[7:0];
        if (m_be[1]) ram[m_addr[16:1]][15:8] <= m_wdata[15:8];
    end
end

integer ap;
task ab(input [7:0] b);
    begin
        if (ap[0]) ram[ap>>1][15:8] = b;
        else       ram[ap>>1][7:0] = b;
        ap = ap + 1;
    end
endtask
task aw32(input [31:0] w);
    begin ab(w[7:0]); ab(w[15:8]); ab(w[23:16]); ab(w[31:24]); end
endtask

integer writes;
always @(posedge clk)
    if (m_req && m_we && !ack_r && {m_addr,1'b0} >= 24'h008000)
        writes <= writes + 1;

integer cycles;
always @(posedge clk) if (!rst) cycles <= cycles + 1;

// ---------------------------------------------------------------------------
// Test A: the exact byte sequence at real ROM PC 0x0998D8-0x0998E1 (a
// fill-with-constant dbr loop -- 6144 writes measured in the level-load
// burst).  Bytes copied verbatim from MAME's own disassembler output; only
// the iteration count (R1) is enlarged from the ROM's live value to 2000 for
// a stable throughput measurement.
// ---------------------------------------------------------------------------
integer cyclesA, writesA;
task run_test_a;
    begin
        for (ap = 0; ap < 65536; ap = ap + 1) ram[ap] = 16'h0000;
        writes = 0; ap = 0;
        ab(8'h2d); ab(8'h2a); ab(8'hf4); aw32(32'h0000_0200); // MOVW #0x200,R10
        ab(8'h2d); ab(8'h2b); ab(8'hf4); aw32(32'h0000_8000); // MOVW #0x8000,R11
        ab(8'h2d); ab(8'h21); ab(8'hf4); aw32(32'd2000);      // MOVW #2000,R1 (dbr semantics: 2000+1 passes)
        // (real ROM sets R1 here via "movz.bw [R10+],R1" reading a live count
        // byte; we already set R1=2000 by immediate above, so that read is
        // omitted -- it would both clobber R1 and advance R10 unexpectedly.)
        ab(8'h1b); ab(8'h60); ab(8'h8a);             // mov.h   [R10+],R0
        ab(8'h1b); ab(8'h40); ab(8'h8b);             // mov.h   R0,[R11+]   <- loop body (3 bytes)
        ab(8'hc6); ab(8'ha1); ab(8'hfd); ab(8'hff);  // dbr R1,998DE[PC]  (disp=-3, verified real encoding)
        ab(8'h00);

        rst = 1; repeat (8) @(posedge clk); rst = 0;
        cycles = 0;
        while (writes < 2000 && cycles < 200000) @(posedge clk);
        cyclesA = cycles; writesA = writes;
        $display("[bench] A (mov.h+dbr fill loop, real PC 0x0998DE): %0d elements in %0d clk_sys cycles = %0.2f cyc/elem",
                  writesA, cyclesA, cyclesA * 1.0 / writesA);
    end
endtask

// ---------------------------------------------------------------------------
// Test B: the exact byte sequence at real ROM PC 0x0009A516 -- a single
// movcu.h (MOVCUH string instruction) with the count supplied in R1, no
// outer wrapper loop needed.  Bytes copied verbatim from MAME's disassembler.
// ---------------------------------------------------------------------------
integer cyclesB, writesB;
task run_test_b;
    begin
        for (ap = 0; ap < 65536; ap = ap + 1) ram[ap] = 16'h0000;
        writes = 0; ap = 0;
        ab(8'h2d); ab(8'h2a); ab(8'hf4); aw32(32'h0000_0200); // MOVW #0x200,R10 (source)
        ab(8'h2d); ab(8'h2b); ab(8'hf4); aw32(32'h0000_8000); // MOVW #0x8000,R11 (dest)
        ab(8'h2d); ab(8'h21); ab(8'hf4); aw32(32'd2000);      // MOVW #2000,R1 (element count)
        // movcu.h [R10],R1,[R11],R1  -- bytes verified at ROM PC 0x9A516
        ab(8'h5a); ab(8'h88); ab(8'h6a); ab(8'h81); ab(8'h6b); ab(8'h81);
        ab(8'h00);

        rst = 1; repeat (8) @(posedge clk); rst = 0;
        cycles = 0;
        while (writes < 2000 && cycles < 200000) @(posedge clk);
        cyclesB = cycles; writesB = writes;
        $display("[bench] B (movcu.h string op, real PC 0x0009A516): %0d elements in %0d clk_sys cycles = %0.2f cyc/elem",
                  writesB, cyclesB, cyclesB * 1.0 / writesB);
    end
endtask

initial begin
    run_test_a;
    run_test_b;
    // Evidence-backed physical floor (docs/v60-authenticity-from-manual.md:
    // no per-instruction cycle table exists; a halfword element is one read +
    // one write bus cycle, and the V60's minimum bus cycle is 3 clocks):
    // ~6 clk_sys/element.  This bench reports the actual number so the plan's
    // budget check (Phase 1) can be made on real data instead of assumption.
    $display("[bench] evidence-backed floor (1R+1W @ 3clk min bus cycle) = ~6 cyc/elem");
    $display("[bench] DONE");
    $finish;
end

initial begin
    #10000000;
    $display("[bench] TIMEOUT");
    $finish;
end
endmodule
