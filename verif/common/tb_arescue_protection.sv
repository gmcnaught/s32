`timescale 1ns/1ps

module tb_arescue_protection;

reg clk = 0, rst = 1, enable = 1, cs = 0, we = 0;
reg [1:0] be = 0, addr = 0;
reg [15:0] wdata = 0;
wire [15:0] rdata;
integer errors = 0;

always #5 clk = ~clk;

s32_arescue_dsp dut (
    .clk(clk), .rst(rst), .enable(enable), .cs(cs), .we(we), .be(be),
    .addr(addr), .wdata(wdata), .rdata(rdata)
);

task write_word(input [1:0] a, input [15:0] d, input [1:0] lanes);
begin
    @(posedge clk); cs <= 1; we <= 1; addr <= a; wdata <= d; be <= lanes;
    @(posedge clk); cs <= 0; we <= 0; be <= 0;
end
endtask

task read_word(input [1:0] a, output [15:0] d);
begin
    @(posedge clk); cs <= 1; we <= 0; addr <= a;
    @(posedge clk); cs <= 0;
    #1 d = rdata;
end
endtask

task check(input [15:0] got, input [15:0] want, input [255:0] label);
begin
    if (got !== want) begin
        errors = errors + 1;
        $display("FAIL %0s got=%04x want=%04x", label, got, want);
    end
end
endtask

reg [15:0] got;
initial begin
    repeat (3) @(posedge clk);
    rst <= 0;

    // MAME command 3: reading offset 2 acknowledges with 8000/0001.
    write_word(0, 16'h0003, 2'b11);
    read_word(2, got);
    read_word(0, got); check(got, 16'h8000, "command 3 status");
    read_word(1, got); check(got, 16'h0001, "command 3 result");

    // COMBINE_DATA semantics: byte writes preserve the opposite lane.
    write_word(1, 16'h1200, 2'b10);
    write_word(1, 16'h0034, 2'b01);
    read_word(1, got); check(got, 16'h1234, "byte-lane combine");

    // MAME command 6: word 0 becomes four times word 1, modulo 16 bits.
    write_word(0, 16'h0006, 2'b11);
    read_word(2, got);
    read_word(0, got); check(got, 16'h48d0, "command 6 multiply");

    if (errors == 0) $display("AIR RESCUE PROTECTION PASS");
    else $display("AIR RESCUE PROTECTION FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #10000;
    $display("AIR RESCUE PROTECTION FAIL (timeout)");
    $finish;
end

endmodule
