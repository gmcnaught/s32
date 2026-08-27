//============================================================================
//  tb_v60_regfile -- the registers, and the stack pointer that is five.
//
//  The property worth having here is the one the Programmer's Reference states
//  outright and a simpler implementation would break: "the contents of the SP
//  and the associated stack pointer register can differ during the execution
//  of a program" (S8).  R31 is a register; the cache entry is written from it
//  only when the stack is switched.  A model where R31 aliased the entry would
//  pass every other check in this file.
//============================================================================
`timescale 1ns/1ps

module tb_v60_regfile;

reg clk = 1'b0;
always #5 clk = ~clk;

reg rst = 1'b1;

reg   [4:0] ra_sel = 5'd0, rb_sel = 5'd0, wr_sel = 5'd0, pr_id = 5'd0;
reg         wr_en = 1'b0, pr_wr = 1'b0;
reg  [31:0] wr_data = 32'd0, pr_wdata = 32'd0;
reg   [1:0] psw_el = 2'd0, new_el = 2'd0;
reg         psw_is = 1'b0, new_is = 1'b0, stack_switch = 1'b0;

wire [31:0] ra, rb, pr_rdata, sbr;
wire [63:0] ra_pair;
wire        pr_rd_ok, pr_wr_ok;

v60_regfile dut (
    .clk(clk), .rst(rst),
    .ra_sel(ra_sel), .rb_sel(rb_sel), .ra(ra), .rb(rb), .ra_pair(ra_pair),
    .wr_en(wr_en), .wr_sel(wr_sel), .wr_data(wr_data),
    .psw_el(psw_el), .psw_is(psw_is),
    .stack_switch(stack_switch), .new_el(new_el), .new_is(new_is),
    .pr_id(pr_id), .pr_wr(pr_wr), .pr_wdata(pr_wdata),
    .pr_rdata(pr_rdata), .pr_rd_ok(pr_rd_ok), .pr_wr_ok(pr_wr_ok),
    .sbr(sbr)
);

integer errors = 0;
task chk(input cond, input [8*72:1] what);
begin
    if (!cond) begin
        errors = errors + 1;
        $display("FAIL  %0s (t=%0t)", what, $time);
    end
end
endtask

task wr(input [4:0] sel, input [31:0] val);
begin
    @(negedge clk);
    wr_sel = sel; wr_data = val; wr_en = 1'b1;
    @(negedge clk);
    wr_en = 1'b0;
end
endtask

// LDPR
task ldpr(input [4:0] id, input [31:0] val);
begin
    @(negedge clk);
    pr_id = id; pr_wdata = val; pr_wr = 1'b1;
    @(negedge clk);
    pr_wr = 1'b0;
end
endtask

// STPR is a read: no edge needed, the value is combinational.
task stpr(input [4:0] id);
begin
    @(negedge clk);
    pr_id = id;
    #1;
end
endtask

task switch_to(input is_bit, input [1:0] el);
begin
    @(negedge clk);
    new_is = is_bit; new_el = el; stack_switch = 1'b1;
    @(negedge clk);
    stack_switch = 1'b0;
    psw_is = is_bit; psw_el = el;   // the PSW follows the switch
end
endtask

task rd(input [4:0] sel);
begin
    ra_sel = sel;
    #1;
end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);

    // =======================================================================
    // Thirty-two ordinary registers.  R29 and R30 are AP and FP by convention
    // and have no hardware of their own.
    // =======================================================================
    wr(5'd0,  32'h00000000);
    wr(5'd29, 32'hAAAA0029);
    wr(5'd30, 32'hAAAA0030);
    rd(5'd29); chk(ra === 32'hAAAA0029, "R29 is an ordinary register");
    rd(5'd30); chk(ra === 32'hAAAA0030, "R30 is an ordinary register");

    // A doubleword operand is a register pair, low register first.
    wr(5'd4, 32'h44444444);
    wr(5'd5, 32'h55555555);
    ra_sel = 5'd4; #1;
    chk(ra_pair === 64'h5555555544444444,
        "a doubleword reads as the pair, low register first");

    // =======================================================================
    // R31 and the cache are independent -- the page says so in as many words.
    // =======================================================================
    psw_el = 2'd0; psw_is = 1'b0;      // level 0, not the interrupt stack
    ldpr(5'd1, 32'h0000_0AA0);         // L0SP
    wr(5'd31, 32'h1111_1111);          // the program moves its stack pointer
    stpr(5'd1);
    chk(pr_rdata === 32'h0000_0AA0,
        "R31 and its stack pointer register can differ while a program runs");
    rd(5'd31);
    chk(ra === 32'h1111_1111, "R31 holds what the program put there");

    // =======================================================================
    // A change of execution level saves R31 and loads the new level's.
    // =======================================================================
    ldpr(5'd2, 32'h2222_2222);         // L1SP
    switch_to(1'b0, 2'd1);             // level 0 -> level 1
    rd(5'd31);
    chk(ra === 32'h2222_2222, "a level change loads R31 from the new level's pointer");
    stpr(5'd1);
    chk(pr_rdata === 32'h1111_1111, "and saves what R31 held into the old level's");

    // ... and back again, with R31 moved in between.
    wr(5'd31, 32'h3333_3333);
    switch_to(1'b0, 2'd0);             // level 1 -> level 0
    rd(5'd31);
    chk(ra === 32'h1111_1111, "going back restores the level's own pointer");
    stpr(5'd2);
    chk(pr_rdata === 32'h3333_3333, "and the level left behind keeps what it had");

    // =======================================================================
    // The interrupt stack: PSW.IS selects it whatever the execution level is.
    // =======================================================================
    ldpr(5'd0, 32'h1111_0000);         // ISP
    switch_to(1'b1, 2'd0);             // onto the interrupt stack
    rd(5'd31);
    chk(ra === 32'h1111_0000, "PSW.IS selects the interrupt stack pointer");
    switch_to(1'b1, 2'd3);             // level 3, still on the interrupt stack
    rd(5'd31);
    chk(ra === 32'h1111_0000,
        "and it stays selected whatever the execution level says");
    switch_to(1'b0, 2'd0);
    rd(5'd31);
    chk(ra === 32'h1111_1111, "leaving it restores level 0's pointer");

    // A switch that does not change the selection must not disturb R31.
    wr(5'd31, 32'h5555_5555);
    switch_to(1'b0, 2'd0);
    rd(5'd31);
    chk(ra === 32'h5555_5555, "a switch to the same stack leaves R31 alone");

    // =======================================================================
    // Which ids LDPR and STPR may touch -- PgmRef Figure 3-2's two columns.
    // =======================================================================
    stpr(5'd6);  chk(pr_rd_ok === 1'b1 && pr_wr_ok === 1'b0,
                     "TR is readable by STPR and not writable by LDPR");
    stpr(5'd9);  chk(pr_rd_ok === 1'b1 && pr_wr_ok === 1'b0,
                     "PIR likewise");
    stpr(5'd5);  chk(pr_rd_ok === 1'b1 && pr_wr_ok === 1'b1,
                     "SBR is both");
    stpr(5'd12); chk(pr_rd_ok === 1'b0 && pr_wr_ok === 1'b0,
                     "10-14 are reserved for future use and are neither");
    stpr(5'd30); chk(pr_rd_ok === 1'b0 && pr_wr_ok === 1'b0,
                     "and so are 29-31");
    stpr(5'd15); chk(pr_rd_ok === 1'b1 && pr_wr_ok === 1'b1,
                     "PSW2 at 15 is both");

    // An LDPR the figure does not allow changes nothing.
    ldpr(5'd6, 32'hDEADBEEF);
    stpr(5'd6);
    chk(pr_rdata !== 32'hDEADBEEF, "an LDPR to a read-only id writes nothing");

    // SBR comes out for the exception unit to use.
    ldpr(5'd5, 32'h0012_3000);
    #1;
    chk(sbr === 32'h0012_3000, "SBR is visible to the unit that needs it");

    if (errors == 0) $display("V60 REGFILE PASS");
    else             $display("V60 REGFILE FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #500_000;
    $display("V60 REGFILE FAIL (timeout)");
    $finish;
end

endmodule
