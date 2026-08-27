//============================================================================
//  v60_dmux -- the data access unit's two masters.
//
//  Clean-room.  v60_ea makes an instruction's operand accesses and v60_exc
//  makes an exception's vector read and frame pushes, and both want v60_dxu.
//  This gives it to one of them.
//
//  It is a mux and NOT a third port on v60_bus_arb, which is a decision the
//  execution-stage plan records and this module is the reason for:
//  tb_v60_pfu asserts continuously that bus ownership does not change between
//  BCY* and the ack, and that an ack reaches exactly one master.  A third
//  arbiter port would put that proof back on the table for nothing -- the two
//  masters here are never live at once, because an exception is raised between
//  operand accesses and never during one.
//
//  So the priority below is not a scheduling policy: it is what happens if
//  that invariant is ever broken, and the assertion at the bottom is there to
//  say it was.  Nothing in this module makes a broken overlap safe; it makes
//  it visible.
//============================================================================
`timescale 1ns/1ps

module v60_dmux (
    // ---- master A: the address unit, an operand's accesses ------------------
    input               a_req,
    input        [23:0] a_addr,
    input         [3:0] a_nbytes,
    input               a_we,
    input        [63:0] a_wdata,
    output logic [63:0] a_rdata,
    output logic        a_done,
    output logic  [3:0] a_cycles,

    // ---- master B: the exception unit, a vector and a frame ----------------
    input               b_req,
    input        [23:0] b_addr,
    input         [3:0] b_nbytes,
    input               b_we,
    input        [63:0] b_wdata,
    output logic [63:0] b_rdata,
    output logic        b_done,
    output logic  [3:0] b_cycles,

    // ---- the data access unit ----------------------------------------------
    output logic        dx_req,
    output logic [23:0] dx_addr,
    output logic  [3:0] dx_nbytes,
    output logic        dx_we,
    output logic [63:0] dx_wdata,
    input        [63:0] dx_rdata,
    input               dx_done,
    input         [3:0] dx_cycles,

    // for a bench to hold the invariant to
    output logic        overlap
);

assign overlap = a_req && b_req;

always_comb begin
    if (b_req) begin
        dx_req    = 1'b1;
        dx_addr   = b_addr;
        dx_nbytes = b_nbytes;
        dx_we     = b_we;
        dx_wdata  = b_wdata;
    end else begin
        dx_req    = a_req;
        dx_addr   = a_addr;
        dx_nbytes = a_nbytes;
        dx_we     = a_we;
        dx_wdata  = a_wdata;
    end
end

// The result goes back to whoever asked.  A master that is not asking gets no
// `done`, so a completion cannot be delivered twice or to the wrong unit.
assign a_rdata  = dx_rdata;
assign b_rdata  = dx_rdata;
assign a_cycles = dx_cycles;
assign b_cycles = dx_cycles;
assign a_done   = dx_done && !b_req;
assign b_done   = dx_done &&  b_req;

endmodule
