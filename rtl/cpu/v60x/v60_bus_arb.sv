//============================================================================
//  v60_bus_arb -- who gets the bus.  Data first, prefetch never.
//
//  Clean-room.  There is one sentence to implement:
//
//    "As the lowest priority bus requester, the PFU uses otherwise idle bus
//     cycles to keep the 16 byte instruction prefetch queue filled."
//     -- databook p.3.246
//
//  So: a grant is taken when the bus is free, the data unit wins whenever it
//  is asking, and the grant is HELD until the bus cycle acknowledges.  Holding
//  it is not a preference either -- v60_biu latches its pins at the rising
//  edge of T1 and acknowledges at the falling edge of T4 (p.3.283), so a
//  requester that lost the mux mid-cycle would have its cycle finished under
//  another master's name and would never see its own ack.
//
//  Re-arbitration happens at every ack, which is what makes "otherwise idle"
//  fine grained: v60_dxu holds its request across all the bus cycles of one
//  logical access and drops it on the last, so the prefetch unit takes the
//  first cycle after an access finishes, not one in the middle of it.
//============================================================================
`timescale 1ns/1ps

module v60_bus_arb
    import v60_bus_pkg::*;
(
    input               clk,
    input               rst,

    // ---- data unit (v60_dxu) ----------------------------------------------
    input               d_req,
    input  bus_status_e d_status,
    input        [23:0] d_addr,
    input               d_we,
    input         [1:0] d_dl,
    input               d_ube,
    input               d_first,
    // An indivisible read-modify-write is in progress.  This is where the
    // interlock is actually ENFORCED: databook p.3.236 says BLOCK* "is used by
    // external logic", so the pin announces and nothing more, and the hazard
    // that matters on this target is internal.  A read-modify-write is two
    // logical accesses with a gap between them, and re-arbitration happens at
    // every ack -- so without this the prefetch unit takes the cycle in the
    // middle of a TASI and the operation is divisible after all.
    //
    // It is a hold-off and not a priority change: the data unit already wins
    // whenever it asks.  What this adds is that the prefetch unit may not have
    // the bus when the data unit is between the halves of one indivisible
    // operation.
    input               d_lock,
    input        [15:0] d_wdata,
    output logic        d_ack,

    // ---- prefetch unit -----------------------------------------------------
    input               p_req,
    input  bus_status_e p_status,
    input        [23:0] p_addr,
    input         [1:0] p_dl,
    output logic        p_ack,

    // ---- bus interface unit ------------------------------------------------
    output logic        biu_lock,
    output logic        biu_req,
    output bus_status_e biu_status,
    output logic [23:0] biu_addr,
    output logic        biu_we,
    output logic  [1:0] biu_dl,
    output logic        biu_ube,
    output logic        biu_first,
    output logic [15:0] biu_wdata,
    input               biu_ack,
    input               biu_busy,   // a bus cycle is running (v60_biu.busy)

    output logic        own_pfu     // observable: whose cycle this is
);

logic granted;

always_ff @(posedge clk) begin
    if (rst) begin
        granted <= 1'b0;
        own_pfu <= 1'b0;
    end else if (biu_ack) begin
        granted <= 1'b0;
    end else if (granted) begin
        // While v60_biu is running the cycle -- T1 through T4, which is what
        // `biu_busy` reports -- the grant is HELD, whatever the master does
        // with its request.  There is no way to abort a bus cycle, and the ack
        // has to reach whoever asked for that one; handing the bus over here
        // would deliver a read to the wrong unit.
        //
        // Before the cycle starts is different: a master that withdraws then
        // has to release the grant, or the bus wedges waiting for a request
        // that is not coming.
        if (!biu_busy && !(own_pfu ? p_req : d_req)) granted <= 1'b0;
    end else if (d_req || (p_req && !d_lock)) begin
        // The data unit wins whenever it is asking.  A prefetch is only ever
        // granted an otherwise idle bus -- and an idle bus in the MIDDLE of an
        // indivisible operation is not idle.  `d_lock` is high across the gap
        // between a read-modify-write's two accesses, which is exactly the
        // window this has to close: an ungranted prefetch there would put a
        // fetch cycle between a TASI's read and its write.
        own_pfu <= !d_req;
        granted <= 1'b1;
    end
end

always_comb begin
    if (granted && own_pfu) begin
        biu_req    = p_req;
        biu_status = p_status;
        biu_addr   = p_addr;
        biu_we     = 1'b0;          // a fetch is a read
        biu_dl     = p_dl;
        biu_ube    = 1'b0;          // an aligned halfword: {UBE*, A0} = 00
        // "FAS* is undefined during an instruction fetch bus access" (p.3.235).
        biu_first  = 1'b1;
        biu_wdata  = 16'd0;
    end else begin
        biu_req    = granted && d_req;
        biu_status = d_status;
        biu_addr   = d_addr;
        biu_we     = d_we;
        biu_dl     = d_dl;
        biu_ube    = d_ube;
        biu_first  = d_first;
        biu_wdata  = d_wdata;
    end
end

assign biu_lock = d_lock;
assign d_ack = biu_ack && !own_pfu;
assign p_ack = biu_ack &&  own_pfu;

endmodule
