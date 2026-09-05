//============================================================================
//  v60_pfu -- the prefetch unit: sixteen bytes of instruction, kept ahead.
//
//  Clean-room.  The databook specifies this unit in one paragraph, and both
//  NEC documents say the same thing:
//
//    "The PFU (prefetch unit) performs prefetching of instructions for the
//     instruction decoding logic.  As the lowest priority bus requester, the
//     PFU uses otherwise idle bus cycles to keep the 16 byte instruction
//     prefetch queue filled. ... In the event of a control transfer, interrupt
//     or exception, the instruction queue contents are flushed and a demand
//     mode instruction fetch is made."            -- databook p.3.246
//
//    "The pre-fetch unit is designed to load the 16 byte instruction queue
//     from external memory during idle bus periods."
//                                       -- Programmer's Reference S2
//
//  and the bus status codes carry the same distinction, with the demand code
//  described as: "The instruction prefetch queue has been flushed by a control
//  transfer and a demand mode instruction fetch is taking place." (p.3.234)
//
//      BST_PREFETCH     0111   filling the queue from idle bus cycles
//      BST_DEMAND_FETCH 0110   the first fetch after a flush
//
//  So four things here are from the page: the queue is sixteen bytes, the
//  fetch is the lowest priority bus request (v60_bus_arb enforces that), a
//  control transfer flushes, and the fetch after a flush is demand mode.
//
//  The byte-at-a-time output is not an implementation convenience: it is the
//  interface v60_am_decode already takes, because a mod field is 1 to 9 bytes
//  and only decoding it says how long it is.
//
//  Two decisions, marked below: what DL1-DL0 says during a fetch, and what an
//  odd fetch address does.  See docs/v60/PREFETCH.md.
//============================================================================
`timescale 1ns/1ps

module v60_pfu
    import v60_bus_pkg::*;
(
    input               clk,
    input               rst,

    // ---- instruction stream, to the decoder -------------------------------
    output logic  [7:0] byte_out,
    output logic        byte_valid,
    input               byte_take,     // the decoder consumed byte_out
    output logic [31:0] byte_pc,       // the address that byte came from

    // ---- control transfer, interrupt, exception ---------------------------
    input               redirect,
    input        [31:0] redirect_pc,

    // ---- bus, through v60_bus_arb ------------------------------------------
    output logic        bus_req,
    output bus_status_e bus_status,
    output logic [23:0] bus_addr,
    output logic  [1:0] bus_dl,
    input               bus_ack,
    input        [15:0] bus_rdata,

    output logic  [4:0] level          // bytes queued, 0 to 16
);

localparam integer QBYTES = 16;            // "the 16 byte instruction prefetch
                                       // queue" -- p.3.246

logic  [7:0] q [0:QBYTES-1];
logic  [3:0] head, tail;
logic [31:0] fetch_pc;                 // address of the next fetch
logic        demand;                   // the next fetch is a demand fetch
logic        fetching;                 // a fetch is on the bus
logic        discard;                  // ... and it belongs to a flushed queue
logic        drop_low;                 // odd redirect: the low byte is not ours

// DECISION: the databook does not say what DL1-DL0 carries during an
// instruction fetch, the way it says FAS* is undefined there (p.3.235).  A
// fetch moves a halfword, so it says halfword.
assign bus_dl = DL_HALFWORD;

assign byte_out   = q[head];
assign byte_valid = (level != 5'd0);

// Room for a whole halfword, which is the only size this unit fetches.
wire may_fetch = !fetching && (level <= 5'd14);   // room for a halfword

always_ff @(posedge clk) begin
    if (rst) begin
        head       <= 4'd0;
        tail       <= 4'd0;
        level      <= 5'd0;
        // "The first instruction fetch is from 0FFFFF0H" -- databook p.3.282,
        // the RESET section (and see docs/v60/BUS-CYCLE-TIMING.md).  Reset is a
        // control transfer as far as this unit is concerned, so the first fetch
        // after it is a demand fetch.
        fetch_pc   <= 32'hFFFFFFF0;
        byte_pc    <= 32'hFFFFFFF0;
        demand     <= 1'b1;
        fetching   <= 1'b0;
        discard    <= 1'b0;
        drop_low   <= 1'b0;
        bus_req    <= 1'b0;
        bus_addr   <= 24'd0;
        bus_status <= BST_DEMAND_FETCH;
    end else begin

        // ---- the decoder takes a byte -------------------------------------
        if (byte_valid && byte_take && !redirect) begin
            head    <= head + 4'd1;
            level   <= level - 5'd1;
            byte_pc <= byte_pc + 32'd1;
        end

        // ---- a fetch comes back --------------------------------------------
        if (bus_ack && fetching) begin
            fetching <= 1'b0;
            bus_req  <= 1'b0;
            if (discard || redirect) begin
                // It was fetched for a queue that no longer exists.
                discard <= 1'b0;
            end else begin
                // DECISION: an odd fetch address.  The bus can only fetch an
                // aligned halfword, so the fetch went to pc & ~1 and the byte
                // BEFORE the target is not part of this instruction stream.
                // The databook does not say instructions are halfword aligned
                // ("in some special cases, instructions and data must be
                // aligned" -- Programmer's Reference S3, without saying which),
                // so this drops the low byte rather than assuming it cannot
                // happen.
                if (drop_low) begin
                    q[tail] <= bus_rdata[15:8];
                    tail    <= tail + 4'd1;
                    level   <= level + 5'd1 -
                               ((byte_valid && byte_take && !redirect) ? 5'd1 : 5'd0);
                end else begin
                    q[tail]          <= bus_rdata[7:0];
                    q[tail + 4'd1]   <= bus_rdata[15:8];
                    tail             <= tail + 4'd2;
                    level            <= level + 5'd2 -
                               ((byte_valid && byte_take && !redirect) ? 5'd1 : 5'd0);
                end
                drop_low <= 1'b0;
                demand   <= 1'b0;
                fetch_pc <= fetch_pc + 32'd2;
            end
        end

        // ---- issue a fetch --------------------------------------------------
        else if (may_fetch && !redirect) begin
            bus_req    <= 1'b1;
            bus_addr   <= fetch_pc[23:0];
            if (demand) bus_status <= BST_DEMAND_FETCH;
            else        bus_status <= BST_PREFETCH;
            fetching   <= 1'b1;
        end

        // ---- a control transfer, interrupt or exception ---------------------
        if (redirect) begin
            head     <= 4'd0;
            tail     <= 4'd0;
            level    <= 5'd0;
            byte_pc  <= redirect_pc;
            fetch_pc <= {redirect_pc[31:1], 1'b0};
            drop_low <= redirect_pc[0];
            demand   <= 1'b1;
            // A fetch already on the bus has to finish -- v60_biu has no way to
            // abort a cycle -- so it is marked and thrown away when it acks.
            if (fetching && !bus_ack) discard <= 1'b1;
            if (!fetching) begin
                bus_req  <= 1'b0;
                fetching <= 1'b0;
            end
        end
    end
end

// synthesis translate_off
always_ff @(posedge clk) begin
    if (!rst && (level > 5'd16))
        $display("WARN v60_pfu: %0d bytes queued -- the queue is 16 (t=%0t)", level, $time);
end
// synthesis translate_on

endmodule
