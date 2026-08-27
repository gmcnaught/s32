//============================================================================
//  tb_v60_dmux -- the data unit's two masters, tested directly.
//
//  v60_dmux's job is invisible from tb_v60_seq: the address unit and the
//  exception unit are never live at once there, so a mux that delivered every
//  completion to both of them would behave identically.  That is the same
//  situation as the p.3.294 rows no FSM can reach, and it is handled the same
//  way -- the property is checked here against the module itself rather than
//  left as a claim no test can fail.
//============================================================================
`timescale 1ns/1ps

module tb_v60_dmux;

reg         a_req = 1'b0, a_we = 1'b0;
reg  [23:0] a_addr = 24'd0;
reg   [3:0] a_nbytes = 4'd0;
reg  [63:0] a_wdata = 64'd0;
wire [63:0] a_rdata;
wire        a_done;
wire  [3:0] a_cycles;

reg         b_req = 1'b0, b_we = 1'b0;
reg  [23:0] b_addr = 24'd0;
reg   [3:0] b_nbytes = 4'd0;
reg  [63:0] b_wdata = 64'd0;
wire [63:0] b_rdata;
wire        b_done;
wire  [3:0] b_cycles;

wire        dx_req, dx_we;
wire [23:0] dx_addr;
wire  [3:0] dx_nbytes;
wire [63:0] dx_wdata;
reg  [63:0] dx_rdata = 64'd0;
reg         dx_done = 1'b0;
reg   [3:0] dx_cycles = 4'd0;
wire        overlap;

v60_dmux dut (
    .a_req(a_req), .a_addr(a_addr), .a_nbytes(a_nbytes), .a_we(a_we),
    .a_wdata(a_wdata), .a_rdata(a_rdata), .a_done(a_done), .a_cycles(a_cycles),
    .b_req(b_req), .b_addr(b_addr), .b_nbytes(b_nbytes), .b_we(b_we),
    .b_wdata(b_wdata), .b_rdata(b_rdata), .b_done(b_done), .b_cycles(b_cycles),
    .dx_req(dx_req), .dx_addr(dx_addr), .dx_nbytes(dx_nbytes), .dx_we(dx_we),
    .dx_wdata(dx_wdata), .dx_rdata(dx_rdata), .dx_done(dx_done),
    .dx_cycles(dx_cycles), .overlap(overlap)
);

integer errors = 0;
task chk(input cond, input [8*72:1] what);
begin
    if (!cond) begin
        errors = errors + 1;
        $display("FAIL  %0s", what);
    end
end
endtask

initial begin
    #1;
    chk(dx_req === 1'b0, "with neither master asking, the data unit is idle");

    // ---- the address unit alone ------------------------------------------
    a_req = 1'b1; a_addr = 24'h001234; a_nbytes = 4'd4; a_we = 1'b1;
    a_wdata = 64'hAAAA_BBBB_CCCC_DDDD;
    #1;
    chk(dx_req === 1'b1,               "one master asking drives the data unit");
    chk(dx_addr === 24'h001234,        "with its address");
    chk(dx_nbytes === 4'd4,            "its length");
    chk(dx_we === 1'b1,                "its direction");
    chk(dx_wdata === 64'hAAAA_BBBB_CCCC_DDDD, "and its data");
    chk(overlap === 1'b0,              "and no overlap");

    dx_done = 1'b1; dx_rdata = 64'h1111_2222_3333_4444; dx_cycles = 4'd2;
    #1;
    chk(a_done === 1'b1,   "the completion reaches the master that asked");
    chk(b_done === 1'b0,   "and not the one that did not");
    chk(a_rdata === 64'h1111_2222_3333_4444, "with the data");
    chk(a_cycles === 4'd2, "and the cycle count");
    dx_done = 1'b0; a_req = 1'b0;

    // ---- the exception unit alone -----------------------------------------
    #1;
    b_req = 1'b1; b_addr = 24'h005678; b_nbytes = 4'd4; b_we = 1'b0;
    #1;
    chk(dx_addr === 24'h005678, "the other master reaches the data unit too");
    dx_done = 1'b1;
    #1;
    chk(b_done === 1'b1, "and its completion reaches it");
    chk(a_done === 1'b0, "and not the master that is idle");
    dx_done = 1'b0;

    // ---- both, which is the thing that must not happen ---------------------
    // The mux does not make an overlap safe.  It reports it, and it does not
    // hand one master's completion to the other while it is happening.
    a_req = 1'b1; a_addr = 24'h001234;
    #1;
    chk(overlap === 1'b1,       "both masters asking is reported");
    chk(dx_addr === 24'h005678, "and the exception unit is the one served");
    dx_done = 1'b1;
    #1;
    chk(b_done === 1'b1, "its completion goes to the exception unit");
    chk(a_done === 1'b0,
        "and not also to the address unit, which is mid-access of its own");
    dx_done = 1'b0;

    if (errors == 0) $display("V60 DMUX PASS");
    else             $display("V60 DMUX FAIL (%0d errors)", errors);
    $finish;
end

endmodule
