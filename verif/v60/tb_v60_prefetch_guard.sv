//============================================================================
//  V60 speculative-prefetch address-range guard (audit §07.5).
//
//  The prefetch issue condition reads up to pf_high (20, or 24 under a loop
//  hint) bytes past PC.  `fetch_is_rom` next to it selects the TRANSPORT, not
//  safety -- when it is false the fetch still goes out on the shared bus,
//  which reaches the whole System 32 map.  One peripheral there has a real
//  read side effect: the MSM6253 ADC at 0xC00050-57 shifts its serial
//  register on every read (rtl/io/s32_io.sv `cs && !we && !rd_d`), so a stray
//  lookahead corrupts an analog conversion in progress.
//
//  This bench walks STRAIGHT-LINE code toward the very top of shared RAM, so
//  the lookahead frontier necessarily crosses 0x800000 -- out of every region
//  a speculative fetch is allowed to touch.  Straight-line matters: a tight
//  loop is served from the retained-window cache with no bus traffic at all
//  (pf_suppress), and a loop-based version of this bench passes with the guard
//  removed, proving nothing.  It asserts two things:
//
//    1. no bus read is ever issued at or above 0x800000   (the guard works)
//    2. the program still runs to HALT                    (the guard does not
//                                                          starve demand fetch)
//
//  Without the guard in s32_v60.sv, check 1 fails.
//============================================================================
`timescale 1ns/1ps

module tb_v60_prefetch_guard;

// Top of shared RAM (0x700000-0x7FFFFF).  Above it, 0x800000 is the comm
// board -- not a region a speculative instruction fetch may enter.
localparam [31:0] PROG_BASE  = 32'h007F_FF00;
localparam [23:0] UNSAFE_LO  = 24'h80_0000;

reg clk = 0, rst = 1;
always #10 clk = ~clk;

wire        c_req, c_we, c_ack;
wire [31:0] c_addr, c_wdata, c_rdata;
wire [1:0]  c_size;
wire        m_req, m_we, m_ack;
wire [23:1] m_addr;
wire [15:0] m_wdata, m_rdata;
wire [1:0]  m_be;

s32_v60 #(.START_PC(PROG_BASE)) cpu (
    .clk(clk), .ce(1'b1), .rst(rst),
    .fast_ifetch(1'b0),
    .if_req(), .if_addr(), .if_data(64'd0), .if_ack(1'b0),
    .bus_req(c_req), .bus_we(c_we), .bus_addr(c_addr), .bus_size(c_size),
    .bus_wdata(c_wdata), .bus_rdata(c_rdata), .bus_ack(c_ack),
    .irq_n(1'b1), .irq_vector(8'h00), .irq_ack(), .nmi_n(1'b1),
    .ext_wr(1'b0), .ext_wr_addr(24'd0), .ext_wr_bytes(3'd0)
);

s32_v60_bus adapter (
    .clk(clk), .ce(1'b1), .rst(rst),
    .ce_fall(1'b0), .c_fetch(1'b0), .c_lock(1'b0), .bmode(1'b1), .ready_n(1'b0),
    .berr_n(1'b1), .bfrez_n(1'b1), .hldrq(1'b0),
    .c_req(c_req), .c_we(c_we), .c_addr(c_addr), .c_size(c_size),
    .c_wdata(c_wdata), .c_rdata(c_rdata), .c_ack(c_ack),
    .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wdata),
    .m_be(m_be), .m_rdata(m_rdata), .m_ack(m_ack)
);

// 64 KiB window backing 0x7F0000-0x7FFFFF; everything else reads as 0.
reg  [15:0] ram [0:32767];
wire [23:0] byte_addr = {m_addr, 1'b0};
wire        in_window = (byte_addr[23:16] == 8'h7F);

reg ack_r = 0;
assign m_rdata = in_window ? ram[byte_addr[15:1]] : 16'h0000;
assign m_ack   = ack_r;

integer reads_total  = 0;
integer reads_unsafe = 0;
reg [23:0] first_unsafe = 24'hFFFFFF;

always @(posedge clk) begin
    ack_r <= m_req & ~ack_r;
    if (!rst && m_req && !m_we && !ack_r) begin
        reads_total = reads_total + 1;
        if (byte_addr >= UNSAFE_LO) begin
            reads_unsafe = reads_unsafe + 1;
            if (first_unsafe == 24'hFFFFFF) first_unsafe = byte_addr;
            $display("  UNSAFE FETCH: read at %06x (pc=%08x)", byte_addr, cpu.pc);
        end
    end
end

integer i;
initial begin : init_program
    for (i = 0; i < 32768; i = i + 1) ram[i] = 16'h0000;
    // 0x7FFF00 .. 0x7FFFFD: NOP (0xCD, one byte).  0x7FFFFE: HALT (0x00).
    // PC walks forward for 254 bytes; once PC passes 0x7FFFEC the 20-byte
    // lookahead frontier is above 0x800000 while PC is still below it, which
    // is exactly the window the guard has to close.
    for (i = 0; i < 127; i = i + 1)
        ram[PROG_BASE[15:1] + i] = 16'hCDCD;
    ram[15'h7FFF] = 16'h0000;          // bytes 0x7FFFE-0x7FFFF: HALT + pad
end

integer cycles = 0;
integer errors = 0;
initial begin
    repeat (8) @(posedge clk);
    rst = 0;
    while (!cpu.halted && cycles < 200000) begin
        @(posedge clk);
        cycles = cycles + 1;
    end

    if (!cpu.halted) begin
        $display("FAIL: program did not reach HALT in %0d cycles -- the guard "
                 , cycles);
        $display("      starved demand fetch (it must only gate LOOKAHEAD)");
        errors = errors + 1;
    end

    if (reads_unsafe != 0) begin
        $display("FAIL: %0d speculative read(s) at or above %06x, first %06x",
                 reads_unsafe, UNSAFE_LO, first_unsafe);
        errors = errors + 1;
    end

    if (reads_total == 0) begin
        $display("FAIL: no bus reads at all -- harness is not exercising fetch");
        errors = errors + 1;
    end

    $display("PREFETCH GUARD: cycles=%0d reads=%0d unsafe=%0d halted=%0d",
             cycles, reads_total, reads_unsafe, cpu.halted);
    if (errors == 0) $display("V60 PREFETCH GUARD PASS");
    else             $display("V60 PREFETCH GUARD FAIL (%0d)", errors);
    $finish;
end

endmodule
