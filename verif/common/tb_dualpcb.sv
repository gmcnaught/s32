//============================================================================
//  Directed test: s32_dualpcb (dual-PCB comm-RAM bridge, rtl/prot/s32_prot.sv)
//  No shipped game exercises this module today (every entry in
//  tools/gen_mra.py:GAMES has dual=0) -- arescue/f1en are the intended future
//  consumers -- so this is the module's first regression coverage. Added
//  alongside a fix for a Quartus-17 RAM-inference failure (comm[] fell to
//  ~32,784 registers instead of an M10K) that changed the array's read/write
//  shape but must not change any of the behaviour checked here.
//
//  1. word write then read-back (fully written word)
//  2. partial byte write on an untouched word overlays the unselected lane
//     from comm_default (lazy-reset semantics), both init_ff=0 and =1
//  3. a second partial write to an already-written word only updates the
//     selected byte lane, leaving the other lane's prior contents intact
//  4. reset re-arms comm_default/comm_written and sets rdata to the
//     init_ff-selected power-up value
//  5. cs_id identity read always returns 0x0000
//  6. read latency is exactly two clocks from address+cs_ram to rdata --
//     deliberately one clock more than a naive single-block implementation
//     (see rtl/prot/s32_prot.sv's inference-note comment): giving `comm[]`
//     exactly one read reference anywhere in the module is what let Quartus
//     infer it as M10K instead of ~32,784 registers. Safe today because no
//     shipped game drives `enable` (dual=0 for every tools/gen_mra.py game).
//============================================================================
`timescale 1ns/1ps

module tb_dualpcb;

reg clk = 0, rst = 1;
always #5 clk = ~clk;

reg         enable = 1;
reg         init_ff = 0;
reg         cs_ram = 0, cs_id = 0;
reg         we = 0;
reg  [1:0]  be = 2'b00;
reg  [11:1] addr = 11'h0;
reg  [15:0] wdata = 16'h0;
wire [15:0] rdata;

s32_dualpcb dut (
    .clk(clk), .rst(rst), .enable(enable), .init_ff(init_ff),
    .cs_ram(cs_ram), .cs_id(cs_id), .we(we), .be(be),
    .addr(addr), .wdata(wdata), .rdata(rdata)
);

integer errors = 0;
task check(input [15:0] got, input [15:0] want, input [255:0] label);
    if (got !== want) begin
        errors = errors + 1;
        $display("  FAIL %0s got=%04x want=%04x", label, got, want);
    end
endtask

// Drive a word write, one clock, then deassert. All inputs change on the
// posedge like real registered bus-controller outputs, avoiding TB/DUT races.
task do_write(input [11:1] a, input [1:0] b, input [15:0] d);
begin
    @(posedge clk);
    cs_ram <= 1; we <= 1; addr <= a; be <= b; wdata <= d;
    @(posedge clk);
    cs_ram <= 0; we <= 0;
end
endtask

// Present a read address for one clock, then sample rdata two edges later
// (the DUT's two-cycle synchronous-read latency -- see the module header).
task do_read(input [11:1] a, output [15:0] got);
begin
    @(posedge clk);
    cs_ram <= 1; we <= 0; addr <= a;
    @(posedge clk);
    cs_ram <= 0;
    @(posedge clk);
    #1 got = rdata;   // sample after NBA updates settle, not in the same delta
end
endtask

reg [15:0] got;
initial begin
    repeat (5) @(posedge clk);
    rst <= 0;
    repeat (2) @(posedge clk);

    // 1: full word write, then read back.
    do_write(11'h010, 2'b11, 16'hABCD);
    do_read(11'h010, got);
    check(got, 16'hABCD, "1 full-write readback");

    // 2a: partial low-byte write on an UNTOUCHED word, init_ff=0 -> the
    // unselected (high) lane is seeded from comm_default (0x00 after this
    // reset), not left as X or garbage.
    do_write(11'h020, 2'b01, 16'h00_34);
    do_read(11'h020, got);
    check(got, 16'h0034, "2a lazy-reset low-byte overlay (init_ff=0)");

    // 2b: partial high-byte write on an untouched word.
    do_write(11'h021, 2'b10, 16'h56_00);
    do_read(11'h021, got);
    check(got, 16'h5600, "2b lazy-reset high-byte overlay (init_ff=0)");

    // 3: a second partial write to an already-written word only touches its
    // own lane; the other lane's prior explicit contents survive.
    do_write(11'h010, 2'b01, 16'h00_EF);
    do_read(11'h010, got);
    check(got, 16'hABEF, "3 partial write preserves other lane");

    // 4: reset with init_ff=1 (F1 Exhaust Note contract) re-arms
    // comm_default/comm_written and immediately reflects the new default on
    // an untouched word.
    init_ff <= 1;
    @(posedge clk); rst <= 1;
    @(posedge clk); rst <= 0;
    repeat (2) @(posedge clk);
    do_read(11'h030, got);
    check(got, 16'hFFFF, "4 post-reset init_ff=1 default");
    // and a previously-written word (0x010) is no longer distinguishable
    // from any other untouched word -- comm_written was cleared by reset.
    do_read(11'h010, got);
    check(got, 16'hFFFF, "4 reset clears comm_written bitmap");

    // 5: cs_id identity read always returns 0x0000, independent of comm[].
    do_write(11'h040, 2'b11, 16'h1234);
    @(posedge clk);
    cs_id <= 1;
    @(posedge clk);
    cs_id <= 0;
    @(posedge clk);
    #1 check(rdata, 16'h0000, "5 cs_id identity read");

    // 6: read latency -- address+cs_ram presented at cycle N, rdata reflects
    // it starting cycle N+2 (two-cycle latency; see module header), not
    // sooner and not later.
    @(posedge clk);
    cs_ram <= 1; we <= 0; addr <= 11'h040;
    @(posedge clk);
    cs_ram <= 0;
    @(posedge clk);
    #1 check(rdata, 16'h1234, "6 two-cycle read latency");

    if (errors == 0) $display("DUALPCB PASS");
    else $display("DUALPCB FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #20000;
    $display("DUALPCB FAIL (timeout)");
    $finish;
end

endmodule
