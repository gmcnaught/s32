`timescale 1ns/1ps
`default_nettype none

//============================================================================
//  Arabian Fight real-V25 boot replay.
//
//  Runs the genuine arabfgt MCU firmware on s32_v25_cpu + s80x86 from reset
//  and logs every byte the V25 writes into the MB8421, in order, so the
//  sequence can be diffed against the same window captured from MAME's real
//  V25 (verif/mame/arab_v25_boot_vector.lua).
//
//  Why boot, and why no V60 model: MAME shows the V60 does not touch the
//  dual-port RAM until frame 13, while the V25 writes ~1,237 bytes on every
//  frame from frame 1.  Frames 0..12 are therefore a pure function of the V25
//  firmware alone — the only window on this board where the two sides can be
//  compared with no hidden state and no handshake to align.  That is what
//  makes a divergence here attributable to an instruction rather than to
//  accumulated drift, which is the reason the arabfgt floor-flicker
//  investigation could not close from full-game runs.
//
//  This bench proves nothing about the per-frame transform once the V60 starts
//  feeding it; it bounds the question to "is the CPU itself right first".
//
//  Plusargs:
//    +MCU=<path>     raw 64 KiB MCU image (default roms/sim/arabfgt/mcu.bin)
//    +OUT=<path>     write log (default scratch/arab_v25_rtl/writes.txt)
//    +MAXWR=<n>      stop after this many logged byte writes (default 4000)
//    +MAXCYC=<n>     clk_sys cycle cap (default 40,000,000)
//============================================================================
module tb_v25_arab_replay;

reg clk = 1'b0;
always #10.35 clk = ~clk;              // ~48.3 MHz clk_sys
reg clk_v25 = 1'b0;
always @(posedge clk) clk_v25 <= ~clk_v25;

reg rst = 1'b1;
reg enable = 1'b0;
wire [7:0] rdata;
wire rom_req;
wire [15:3] rom_addr;
reg [63:0] rom_data = 64'hffffffffffffffff;
reg rom_ack = 1'b0;

s32_v25_cpu dut (
    .clk(clk), .clk_v25(clk_v25), .rst(rst), .enable(enable), .pause(1'b0),
    .table_sel(1'b1),                  // arabfgt opcode table
    .prg_wr(1'b0), .prg_waddr(16'd0), .prg_wdata(8'd0),
    .rom_req(rom_req), .rom_addr(rom_addr), .rom_data(rom_data), .rom_ack(rom_ack),
    // The V60 side stays idle for the whole replay window.
    .cs(1'b0), .we(1'b0), .addr(11'd0), .wdata(8'd0), .rdata(rdata),
    .debug_cpu_clk(), .debug_io_seen(), .debug_last_io_addr(),
    .debug_unmapped_seen(), .debug_last_unmapped_addr(),
    .debug_first_fetch_valid(), .debug_first_fetch_data(), .debug_first_fetch_addr()
);

reg [7:0] raw     [0:65535];
reg [7:0] ext_rom [0:65535];
reg rom_pending = 1'b0;
reg [15:3] rom_addr_latched = 13'd0;
integer rom_reads = 0;
integer fd, got, src;

// SDRAM-style program service, identical in shape to tb_v25_firmware.
always @(posedge clk) begin
    rom_ack <= 1'b0;
    if (rst) begin
        rom_pending <= 1'b0;
    end else begin
        if (rom_req) begin
            if (rom_pending)
                $fatal(1, "ARAB V25 REPLAY FAIL: second p5 miss while pending");
            rom_addr_latched <= rom_addr;
            rom_pending <= 1'b1;
            rom_reads <= rom_reads + 1;
        end
        if (rom_pending) begin
            rom_data <= {
                ext_rom[{rom_addr_latched, 3'd7}], ext_rom[{rom_addr_latched, 3'd6}],
                ext_rom[{rom_addr_latched, 3'd5}], ext_rom[{rom_addr_latched, 3'd4}],
                ext_rom[{rom_addr_latched, 3'd3}], ext_rom[{rom_addr_latched, 3'd2}],
                ext_rom[{rom_addr_latched, 3'd1}], ext_rom[{rom_addr_latched, 3'd0}]
            };
            rom_ack <= 1'b1;
            rom_pending <= 1'b0;
        end
    end
end

function automatic [15:0] descramble(input [15:0] i);
begin
    descramble = {i[14], i[11], i[15], i[12], i[13], i[4], i[3], i[7],
                  i[5], i[10], i[2], i[8], i[9], i[6], i[1], i[0]};
end
endfunction

// ---------------------------------------------------------------------------
// DPRAM write log.  The core issues one 16-bit access with a byte-enable pair;
// MAME's tap sees byte writes.  Expand to bytes in low-then-high order so the
// two sequences are directly comparable.
// ---------------------------------------------------------------------------
integer out_fd = 0;
integer writes = 0;
integer max_writes;
integer max_cycles;
integer cycle_count = 0;
string  out_path;
string  mcu_path;
reg     logging = 1'b0;

always @(posedge clk_v25) begin
    if (logging && dut.dpram_cpu_wren) begin
        if (dut.dpram_cpu_byteena[0]) begin
            writes = writes + 1;
            if (writes <= max_writes)
                $fwrite(out_fd, "%0d off=%03x d=%02x\n", writes,
                        {dut.dpram_cpu_addr, 1'b0}, dut.dpram_cpu_wdata[7:0]);
        end
        if (dut.dpram_cpu_byteena[1]) begin
            writes = writes + 1;
            if (writes <= max_writes)
                $fwrite(out_fd, "%0d off=%03x d=%02x\n", writes,
                        {dut.dpram_cpu_addr, 1'b1}, dut.dpram_cpu_wdata[15:8]);
        end
    end
end

always @(posedge clk) if (!rst) cycle_count = cycle_count + 1;

initial begin
    if (!$value$plusargs("MCU=%s", mcu_path)) mcu_path = "roms/sim/arabfgt/mcu.bin";
    if (!$value$plusargs("OUT=%s", out_path)) out_path = "scratch/arab_v25_rtl/writes.txt";
    if (!$value$plusargs("MAXWR=%d", max_writes)) max_writes = 4000;
    if (!$value$plusargs("MAXCYC=%d", max_cycles)) max_cycles = 40000000;

    fd = $fopen(mcu_path, "rb");
    if (fd == 0) begin
        $display("ARAB V25 REPLAY FAIL: cannot open %0s", mcu_path);
        $fatal(1);
    end
    got = $fread(raw, fd);
    $fclose(fd);
    if (got != 65536) begin
        $display("ARAB V25 REPLAY FAIL: MCU ROM is %0d bytes, expected 65536", got);
        $fatal(1);
    end
    for (src = 0; src < 65536; src = src + 1)
        ext_rom[src] = raw[descramble(src[15:0])];

    out_fd = $fopen(out_path, "w");
    if (out_fd == 0) begin
        $display("ARAB V25 REPLAY FAIL: cannot create %0s", out_path);
        $fatal(1);
    end

    repeat (4) @(posedge clk);
    rst = 1'b0;
    @(negedge clk);
    enable = 1'b1;
    logging = 1'b1;

    while (writes < max_writes && cycle_count < max_cycles)
        @(posedge clk);

    logging = 1'b0;
    $fclose(out_fd);
    $display("ARAB V25 REPLAY: writes=%0d rom_lines=%0d clk_sys_cycles=%0d out=%0s",
             writes, rom_reads, cycle_count, out_path);
    if (writes == 0)
        $display("ARAB V25 REPLAY FAIL: the V25 never wrote the mailbox");
    else
        $display("ARAB V25 REPLAY DONE");
    $finish;
end

endmodule
`default_nettype wire
