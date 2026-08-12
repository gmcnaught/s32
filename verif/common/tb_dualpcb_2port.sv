`timescale 1ns/1ps

module tb_dualpcb_2port;
reg clk = 0, rst = 1, enable = 1, init_ff = 0;
always #5 clk = ~clk;
reg mcs = 0, mid = 0, mwe = 0;
reg scs = 0, sid = 0, swe = 0;
reg [1:0] mbe = 0, sbe = 0;
reg [11:1] ma = 0, sa = 0;
reg [15:0] md = 0, sd = 0;
wire [15:0] mq, sq;
wire collision;
integer errors = 0;

s32_dualpcb_bridge dut (
    .clk(clk), .rst(rst), .enable(enable), .init_ff(init_ff),
    .main_cs_ram(mcs), .main_cs_id(mid), .main_we(mwe), .main_be(mbe),
    .main_addr(ma), .main_wdata(md), .main_rdata(mq),
    .sub_cs_ram(scs), .sub_cs_id(sid), .sub_we(swe), .sub_be(sbe),
    .sub_addr(sa), .sub_wdata(sd), .sub_rdata(sq), .collision(collision)
);

task check16(input [15:0] got, input [15:0] want, input [255:0] label);
begin
    if (got !== want) begin errors = errors + 1; $display("FAIL %0s got=%04x want=%04x", label, got, want); end
end endtask
task check1(input got, input want, input [255:0] label);
begin
    if (got !== want) begin errors = errors + 1; $display("FAIL %0s got=%b want=%b", label, got, want); end
end endtask
task read_both(input [11:1] am, input [11:1] as);
begin
    @(posedge clk); mcs <= 1; scs <= 1; mwe <= 0; swe <= 0; ma <= am; sa <= as;
    @(posedge clk); mcs <= 0; scs <= 0;
    @(posedge clk); #1;
end endtask
task write_both(input [11:1] am, input [1:0] bm, input [15:0] dm,
                input [11:1] as, input [1:0] bs, input [15:0] ds);
begin
    @(posedge clk); mcs <= 1; scs <= 1; mwe <= 1; swe <= 1;
    ma <= am; sa <= as; mbe <= bm; sbe <= bs; md <= dm; sd <= ds;
    @(posedge clk); #1; mcs <= 0; scs <= 0; mwe <= 0; swe <= 0;
end endtask

initial begin
    repeat (4) @(posedge clk); rst <= 0; repeat (2) @(posedge clk);

    // Both independent RAM ports must commit in one clock.
    write_both(11'h010, 2'b11, 16'ha1b2, 11'h011, 2'b11, 16'hc3d4);
    check1(collision, 0, "different-address collision");
    read_both(11'h011, 11'h010);
    check16(mq, 16'hc3d4, "main reads sub write");
    check16(sq, 16'ha1b2, "sub reads main write");

    // Same word, disjoint lanes merge without collision.
    write_both(11'h020, 2'b01, 16'h005a, 11'h020, 2'b10, 16'ha500);
    check1(collision, 0, "disjoint-lane collision");
    read_both(11'h020, 11'h020);
    check16(mq, 16'ha55a, "disjoint lanes merge main");
    check16(sq, 16'ha55a, "disjoint lanes merge sub");

    // Same-lane collision is visible during the accepted write; main wins.
    @(posedge clk); mcs <= 1; scs <= 1; mwe <= 1; swe <= 1; ma <= 11'h021; sa <= 11'h021;
    mbe <= 2'b01; sbe <= 2'b01; md <= 16'h0011; sd <= 16'h0022;
    @(negedge clk); check1(collision, 1, "same-lane collision asserted");
    @(posedge clk); #1; mcs <= 0; scs <= 0; mwe <= 0; swe <= 0;
    @(negedge clk); check1(collision, 0, "collision clears with request");
    read_both(11'h021, 11'h021);
    check16(mq, 16'h0011, "main wins collision and lazy zero fills");

    // IDs are board-specific and have the same two-clock response timing.
    @(posedge clk); mid <= 1; sid <= 1;
    @(posedge clk); mid <= 0; sid <= 0;
    @(posedge clk); #1; check16(mq, 16'h0000, "main identity"); check16(sq, 16'h0001, "sub identity");

    // Reset invalidates prior writes and selects the ffff lazy default.
    init_ff <= 1; @(posedge clk); rst <= 1; @(posedge clk); rst <= 0; repeat (2) @(posedge clk);
    read_both(11'h010, 11'h011);
    check16(mq, 16'hffff, "main lazy ffff"); check16(sq, 16'hffff, "sub lazy ffff");
    write_both(11'h030, 2'b10, 16'h7600, 11'h031, 2'b01, 16'h0089);
    read_both(11'h030, 11'h031);
    check16(mq, 16'h76ff, "main partial ffff merge"); check16(sq, 16'hff89, "sub partial ffff merge");

    enable <= 0;
    write_both(11'h040, 2'b11, 16'h1234, 11'h041, 2'b11, 16'h5678);
    enable <= 1;
    read_both(11'h040, 11'h041);
    check16(mq, 16'hffff, "disabled main write"); check16(sq, 16'hffff, "disabled sub write");

    if (errors == 0) $display("DUALPCB 2PORT PASS");
    else $display("DUALPCB 2PORT FAIL (%0d errors)", errors);
    $finish;
end
initial begin #20000; $display("DUALPCB 2PORT FAIL (timeout)"); $finish; end
endmodule
