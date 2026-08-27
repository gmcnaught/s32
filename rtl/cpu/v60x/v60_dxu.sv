//============================================================================
//  v60_dxu -- one logical data access, split into bus cycles.
//
//  Clean-room.  Sources, all in the databook:
//
//    p.3.235  DL1-DL0 is the LOGICAL data length of the access, and FAS* says
//             "0: First bus cycle / 1: Subsequent bus cycles" -- so a logical
//             access is expected to take more than one bus cycle and the pins
//             already say which cycle you are looking at.
//    p.3.235  "Both memory and I/O address spaces are organized into a pair of
//             byte-wide banks and are addressed by A23-A1.  The even addressed
//             bank is selected whenever A0 is driven low ... Selection of the
//             odd addressed bank is controlled by the UBE* signal."
//    p.3.236  {UBE*, A0} = 00 halfword / 01 upper byte / 10 lower byte /
//             11 reserved.
//
//  Those three facts fix the split completely, without a rule having to be
//  quoted for it.  There are exactly three legal shapes of bus cycle, and a
//  halfword is only one of them when A0 is low; so at each step:
//
//      address even and two or more bytes left  ->  halfword cycle
//      otherwise                                ->  byte cycle,
//                                                   upper lane if A0 is 1,
//                                                   lower lane if A0 is 0
//
//  which gives 1 cycle for a byte, 1 or 2 for a halfword, 2 or 3 for a word
//  and 4 or 5 for a doubleword.  Unaligned operands are legal and have to
//  work: "generally there are no alignment requirements and only the
//  performance is affected by not aligning data on its boundary"
//  (Programmer's Reference S3).
//
//  See docs/v60/DATA-ACCESS-SPLIT.md for the table and the two decisions.
//
//  Protocol: raise `req` with the access described; it starts on the RISING
//  edge of req, so hold req until `done` and drop it -- a level left high
//  cannot start a second access by itself.
//============================================================================
`timescale 1ns/1ps

module v60_dxu
    import v60_bus_pkg::*;
(
    input               clk,
    input               rst,

    // ---- logical access ---------------------------------------------------
    input               req,
    input        [23:0] addr,       // byte address.  A23-A0 is the whole
                                    // external bus (p.3.235); the sequencer
                                    // truncates the V60's 32-bit address
    input         [3:0] nbytes,     // 1, 2, 4 or 8
    input               we,
    input               io,         // I/O address space rather than memory
    input        [63:0] wdata,

    output logic [63:0] rdata,
    output logic        busy,
    output logic        done,       // one-cycle pulse, with rdata settled
    output logic  [3:0] cycles,     // bus cycles this access took

    // ---- bus interface unit ----------------------------------------------
    output logic        biu_req,
    output bus_status_e biu_status,
    output logic [23:0] biu_addr,
    output logic        biu_we,
    output logic  [1:0] biu_dl,
    output logic        biu_ube,    // PIN level: UBE* is active low
    output logic        biu_first,  // drives FAS*
    output logic [15:0] biu_wdata,
    input               biu_ack,
    input        [15:0] biu_rdata
);

logic [23:0] cur;      // address of the next bus cycle
logic  [3:0] rem;      // bytes of the logical access still to move
logic  [3:0] pos;      // bytes already moved
logic  [3:0] len_r;    // the logical length, held for DL and for FAS*
logic        io_r, we_r;
logic [63:0] buf_r;
logic        req_d;

// The one thing that fixes the shape: a halfword cycle needs A0 low, because
// {UBE*, A0} has no encoding for a halfword at an odd address.
wire halfword_now = !cur[0] && (rem >= 4'd2);

assign busy = biu_req;

// DL1-DL0 is the LOGICAL length and does not change across the cycles of one
// access.  DECISION: the table has no code for a doubleword -- byte, halfword,
// word and reserved are all of it (p.3.235) -- so an eight-byte operand is
// driven as DL_WORD and is treated below as two word accesses for FAS*.
always_comb begin
    case (len_r)
        4'd1:    biu_dl = DL_BYTE;
        4'd2:    biu_dl = DL_HALFWORD;
        default: biu_dl = DL_WORD;
    endcase
end

always_comb begin
    if (io_r) biu_status = BST_IO_SINGLE;
    else      biu_status = BST_MEM_SINGLE;
end

assign biu_addr = cur;
assign biu_we   = we_r;

// UBE* is a pin level here, not a decode: 0 asserts the upper byte lane.
//   halfword                -> {UBE*, A0} = 00
//   byte at an odd address  -> 01, the upper byte
//   byte at an even address -> 10, the lower byte
assign biu_ube = halfword_now ? 1'b0 : (cur[0] ? 1'b0 : 1'b1);

// "FAS* = 0: First bus cycle" (p.3.235).  DECISION: for the doubleword that DL
// cannot express, the second word is a second logical access and asserts it
// again.
assign biu_first = (pos == 4'd0) || ((len_r == 4'd8) && (pos == 4'd4));

// Write data goes out on the lane the address selects; read data comes off it.
wire [63:0] buf_sh = buf_r >> ({2'b00, pos} * 8);
wire  [7:0] rd_lane = cur[0] ? biu_rdata[15:8] : biu_rdata[7:0];
wire [63:0] rd_ins  = (halfword_now ? {48'd0, biu_rdata} : {56'd0, rd_lane})
                      << ({2'b00, pos} * 8);

assign biu_wdata = halfword_now ? buf_sh[15:0]                  // halfword
                 : cur[0]       ? {buf_sh[7:0], 8'h00}         // upper lane
                                : {8'h00, buf_sh[7:0]};        // lower lane

wire last_cycle = (rem <= (halfword_now ? 4'd2 : 4'd1));

always_ff @(posedge clk) begin
    if (rst) begin
        biu_req <= 1'b0;
        done    <= 1'b0;
        cur     <= 24'd0;
        rem     <= 4'd0;
        pos     <= 4'd0;
        len_r   <= 4'd0;
        io_r    <= 1'b0;
        we_r    <= 1'b0;
        buf_r   <= 64'd0;
        rdata   <= 64'd0;
        cycles  <= 4'd0;
        req_d   <= 1'b0;
    end else begin
        done  <= 1'b0;
        req_d <= req;

        if (req && !req_d) begin
            biu_req <= 1'b1;
            cur     <= addr;
            rem     <= nbytes;
            pos     <= 4'd0;
            len_r   <= nbytes;
            io_r    <= io;
            we_r    <= we;
            buf_r   <= we ? wdata : 64'd0;
            cycles  <= 4'd0;
        end else if (biu_ack) begin
            cycles <= cycles + 4'd1;

            if (!we_r) buf_r <= buf_r | rd_ins;

            if (halfword_now) begin
                cur <= cur + 24'd2;
                rem <= rem - 4'd2;
                pos <= pos + 4'd2;
            end else begin
                cur <= cur + 24'd1;
                rem <= rem - 4'd1;
                pos <= pos + 4'd1;
            end

            if (last_cycle) begin
                biu_req <= 1'b0;
                done    <= 1'b1;
                if (!we_r) rdata <= buf_r | rd_ins;
            end
        end
    end
end

// synthesis translate_off
always_ff @(posedge clk) begin
    if (!rst && req && !req_d)
        if (!(nbytes == 4'd1 || nbytes == 4'd2 || nbytes == 4'd4 || nbytes == 4'd8))
            $display("WARN v60_dxu: %0d byte access -- the V60's access types are 1, 2, 4 and 8 (t=%0t)",
                     nbytes, $time);
end
// synthesis translate_on

endmodule
