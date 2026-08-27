//============================================================================
//  v60_biu -- the V60 bus interface unit, as databook S4 specifies it.
//
//  Clean-room.  Written from NEC_uPD70616_V60_DataBook_1986.pdf pp.3.283-3.292
//  (see docs/v60/BUS-CYCLE-TIMING.md, which quotes every instant this module
//  implements and cites the page for each), not from the existing
//  s32_v60_bus.sv.
//
//  ---------------------------------------------------------------------------
//  Why this module takes ce_rise / ce_fall instead of a clock
//  ---------------------------------------------------------------------------
//  "Bus states are defined and measured from the rising edge of the clock to
//  the rising edge of the next" (p.3.233).  A bus state is therefore one V60
//  clock period, and every "falling edge of Tn" in the specification is the
//  MIDPOINT of a state.  Half the events in S4 happen at those midpoints:
//  DS asserted at falling T1, BMODE sampled at falling T2, READY at falling T3
//  and each falling TW, read data latched at falling T4.
//
//  So the V60 clock has to be reconstructed with both of its edges
//  representable.  ce_rise and ce_fall are exactly that -- one strobe per edge
//  of the reconstructed clock, from s32_v60_timebase -- and the module is
//  clocked on the fast clock those strobes are generated on.  Modelling the
//  V60 clock as a real dual-edge clock would be closer to the page and would
//  not survive synthesis.
//
//  Consequence worth stating: on a clock where the V60 period is an ODD number
//  of ticks there is no midpoint, and none of the instants above can be
//  expressed at all.  That is not an implementation preference, it is why the
//  bus adapter cannot live on clk_sys in this design.
//============================================================================
`timescale 1ns/1ps

module v60_biu
    import v60_bus_pkg::*;
(
    input               clk,        // fast clock the CE strobes are timed on
    input               rst,
    input               ce_rise,    // V60 clock rising edge  -- state boundary
    input               ce_fall,    // V60 clock falling edge -- sampling point

    // ---- core side -------------------------------------------------------
    input               req,        // a bus cycle is wanted
    input  bus_status_e status,     // what kind; drives MRQ and ST2-ST0
    input        [23:0] addr,
    input               we,         // 1 = write
    input         [1:0] dl,         // DL1-DL0 data length
    input               ube,        // upper byte enable, active low as a pin
    input        [15:0] wdata,
    output logic        ack,        // one fast-clock pulse at falling T4
    output logic [15:0] rdata,
    output logic        busy,

    // ---- pins ------------------------------------------------------------
    output logic [23:0] a,
    output logic  [1:0] dl_o,
    output logic  [2:0] st,
    output logic        mrq_n,
    output logic        rw_n,       // databook R/W*: high = read, low = write
    output logic        ube_n,
    output logic        fas_n,
    output logic        bcy_n,
    output logic        ds_n,
    output logic [15:0] d_out,
    output logic        d_oe,
    input        [15:0] d_in,
    output logic        bus_hiz,    // all three-state pins released (TH)

    input               ready_n,    // sampled at falling T3 and each falling TW
    input               bmode,      // sampled at falling T2: 1 normal, 0 short
    input               hldrq_n,    // sampled at rising T4 or TI
    output logic        hldak_n,

    output bus_state_e  state       // observable, for verification
);

bus_state_e  st_r, st_next;
bus_status_e status_r;
logic        we_r;
logic  [1:0] io_recovery;          // three TI states between I/O cycles
logic        short_cycle;          // BMODE sampled low at falling T2
logic        ready_seen;           // READY* sampled low at falling T3 / TW
logic        take_hold;            // HLDRQ* sampled low at rising T4 or TI

assign state = st_r;
assign busy  = (st_r != T_TI) && (st_r != T_TH);

// ---------------------------------------------------------------------------
// Cycle start.  The I/O recovery gap gates the START of an I/O cycle, because
// the rule is about "any consecutive pair of I/O bus cycles" (p.3.291) -- a
// memory cycle is not an I/O cycle and does not wait for it.
//
// ASSUMPTION, not from the page: an intervening memory cycle is taken to break
// the pair, so it clears the counter.  The databook scopes the rule but does
// not say what a memory cycle in the gap does.  Recorded here rather than
// buried, because it is the one place this module goes beyond its source.
// ---------------------------------------------------------------------------
wire io_gap_clear = (io_recovery == 2'd0);
wire may_start    = req && (!bst_is_io(status) || io_gap_clear);

always_comb begin
    st_next = st_r;
    case (st_r)
        T_TI: if (take_hold)                    st_next = T_TH;
              else if (may_start)               st_next = T_T1;
        T_T1:                                   st_next = T_T2;
        // "If the normal mode is selected, the T2 state progresses to the T3
        // state.  Otherwise the T3 state is skipped, the READY input ignored
        // and T4 is the next bus state." -- p.3.283
        T_T2: if (short_cycle)                  st_next = T_T4;
              else                              st_next = T_T3;
        T_T3: if (ready_seen)                   st_next = T_T4;
              else                              st_next = T_TW;
        T_TW: if (ready_seen)                   st_next = T_T4;
              else                              st_next = T_TW;
        T_T4: if (take_hold)                    st_next = T_TH;
              else                              st_next = T_TI;
        T_TH: if (hldrq_n)                      st_next = T_TI;   // exit through TI
        default:                                st_next = T_TI;
    endcase
end

// ---------------------------------------------------------------------------
// State boundaries and the events specified AT a rising edge.
// ---------------------------------------------------------------------------
always_ff @(posedge clk) begin
    if (rst) begin
        st_r        <= T_TI;
        io_recovery <= 2'd0;
        take_hold   <= 1'b0;
        short_cycle <= 1'b0;
        ready_seen  <= 1'b0;
        status_r    <= BST_MEM_SINGLE;
        we_r        <= 1'b0;
        a           <= 24'd0;
        dl_o        <= 2'd0;
        st          <= 3'd0;
        mrq_n       <= 1'b1;
        rw_n        <= 1'b1;
        ube_n       <= 1'b1;
        fas_n       <= 1'b1;
        bcy_n       <= 1'b1;
        ds_n        <= 1'b1;
        d_out       <= 16'd0;
        d_oe        <= 1'b0;
        bus_hiz     <= 1'b0;
        hldak_n     <= 1'b1;
        rdata       <= 16'd0;
    end
    else begin
        ack <= 1'b0;

        if (ce_rise) begin
            st_r <= st_next;

            // "The rising edge of the clock in the T4 or TI state is used to
            // sample the HLDRQ* input" -- p.3.292.
            take_hold <= (st_r == T_T4 || st_r == T_TI) ? ~hldrq_n : 1'b0;

            case (st_next)
                // "At the rising edge of the T1 bus state, the A23-A0,
                // DL1-DL0, ST2-ST0, FAS*, MRQ*, R/W* and UBE* outputs are
                // asserted and remain valid until the end of the bus cycle.
                // At the same time, the BCY* pin is asserted" -- p.3.283.
                T_T1: begin
                    a        <= addr;
                    dl_o     <= dl;
                    st       <= status[2:0];
                    mrq_n    <= status[3];      // pin level, not a decode
                    rw_n     <= ~we;            // R/W*: high read, low write
                    ube_n    <= ube;
                    fas_n    <= 1'b0;
                    bcy_n    <= 1'b0;
                    status_r <= status;
                    we_r     <= we;
                    // A cycle that is not I/O breaks the consecutive pair.
                    if (!bst_is_io(status)) io_recovery <= 2'd0;
                end
                // "the BCY* output is negated at the rising edge of the T4 bus
                // state" -- p.3.283.  Note DS* is NOT negated here.
                T_T4: bcy_n <= 1'b1;
                // "The rising edge of the clock in the TH state will see
                // [the three-state outputs] enter high impedance" -- p.3.292.
                T_TH: begin
                    bus_hiz <= 1'b1;
                    d_oe    <= 1'b0;
                end
                T_TI: begin
                    bus_hiz <= 1'b0;
                    fas_n   <= 1'b1;
                    // Arm the recovery gap on leaving an I/O cycle.
                    if (st_r == T_T4 && bst_is_io(status_r)) io_recovery <= 2'd3;
                    else if (io_recovery != 2'd0)            io_recovery <= io_recovery - 2'd1;
                end
                default: ;
            endcase
        end

        // -------------------------------------------------------------------
        // The midpoints.  Everything below is specified at a FALLING edge.
        // -------------------------------------------------------------------
        if (ce_fall) begin
            case (st_r)
                // "At the falling edge of the T1 clock, the DS* pin is
                // asserted, indicating that external data bus transceivers can
                // be enabled" -- p.3.283.  Write data is driven here too: it
                // "is driven a half period later at the falling edge of T1"
                // and "remains valid until the end of the T4 bus state".
                T_T1: begin
                    ds_n <= 1'b0;
                    if (we_r) begin
                        d_out <= wdata;
                        d_oe  <= 1'b1;
                    end
                end
                // "At the falling edge of the T2 state, the BMODE input is
                // sampled to determine if the bus cycle is normal (logic high)
                // or a short (logic low) bus cycle" -- p.3.283.
                T_T2: short_cycle <= ~bmode;
                // "The falling edge of the T3 state is used to sample the
                // READY* input and if found low, the transition to the T4
                // state occurs." -- p.3.283
                T_T3: ready_seen <= ~ready_n;
                // "The READY* input is continued to be sampled at the falling
                // edge of TW until it returns to a low level." -- p.3.283
                T_TW: ready_seen <= ~ready_n;
                // "The read data on the D15-D0 inputs is latched internally at
                // the falling edge of T4 and simultaneously the DS* output is
                // negated, completing the bus cycle." -- p.3.283
                T_T4: begin
                    if (!we_r) rdata <= d_in;
                    ds_n <= 1'b1;
                    d_oe <= 1'b0;
                    ack  <= 1'b1;
                end
                // "HLDAK a half-clock later" than the TH tri-state -- p.3.292.
                T_TH: hldak_n <= 1'b0;
                T_TI: hldak_n <= 1'b1;
                default: ;
            endcase
            if (st_r != T_T3 && st_r != T_TW) ready_seen <= 1'b0;
            if (st_r == T_T4)                 short_cycle <= 1'b0;
        end
    end
end

endmodule
