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
//
//  ---------------------------------------------------------------------------
//  The three externally raised conditions: BERR*, NMI* and INT
//  ---------------------------------------------------------------------------
//  Two different kinds of pin arrive here for one reason -- this is the module
//  that has pins.
//
//  BERR* IS a bus signal and belongs to a bus cycle.  "External logic can
//  assert the BERR* input to indicate the presence of a fault in the current
//  bus cycle and request a retry of the bus cycle or force an exception if the
//  bus fault cannot be corrected.  The decision to retry or terminate a bus
//  cycle with an error is determined by the state of the RT/EP* input pin"
//  (p.3.236), and RT/EP*'s own entry gives the two levels: "RT/EP* will
//  determine whether to retry the faulty bus cycle (RT/EP* = 1) or cause an
//  exception (RT/EP* = 0)" (p.3.237).
//
//  WHEN they are sampled is the one place the databook contradicts itself, and
//  the plate wins.  The BERR* pin's prose says "at the rising edge of the T4
//  state" (p.3.236).  The AC characteristics table gives tSBEK/tHKBE and
//  tSRTK/tHKRT as setup and hold to CLK-falling for both pins (p.3.239-40), and
//  the Bus Error Timing plate on p.3.243 draws the sampling instant in the
//  middle of the state it labels T4 -- on the falling edge, between the two
//  state boundaries it ticks above the clock.  Two renderings against one
//  sentence, and the two are the ones with numbers on them, so BERR* and RT/EP*
//  are sampled at the FALLING edge of T4: the same midpoint that latches read
//  data and negates DS*.
//
//  A retry needs no state of its own.  Withholding `ack` is the whole of it:
//  the master is still asserting `req` (v60_dxu holds it until the ack of the
//  last bus cycle) and v60_bus_arb holds the grant until an ack, so the cycle
//  ends in TI and starts again from the same latched request -- through
//  `may_start`, which means an I/O retry still waits out the three-TI recovery
//  gap.
//
//  NMI* and INT are NOT bus signals.  They are asynchronous inputs -- the
//  databook gives them no setup or hold parameter and no waveform plate, where
//  READY*, BMODE, HLDRQ*, BERR* and RT/EP* all have both -- so they are
//  synchronised here and reported as level and pending flags.  The
//  synchronisers are an implementation necessity and not from a page; what IS
//  from a page is which of the two is a level and which is an event:
//
//    "The NMI* pin is an active low interrupt input that cannot be masked by
//     software.  At the completion of the current instruction, the PC and PSW
//     are pushed" (p.3.237)          -- an EVENT, so it latches until taken.
//
//    "The INT input is an active high interrupt input that can be masked by
//     the IE bit ... The INT input must be asserted until acknowledged by the
//     uPD70616" (p.3.237)            -- a LEVEL, so it is reported as one and
//                                       nothing here has to remember it.
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
    input               first,      // this is the FIRST bus cycle of a logical
                                    // access -- drives FAS*, see below
    // "The BLOCK* output is asserted during a bus cycle to indicate an
    // indivisible read-modify-write bus cycle (TASI, CAXI instructions) is
    // taking place.  It is used by external logic to guarantee the integrity
    // of the bus cycle in a multiple bus master system.  BLOCK* is also
    // asserted for the duration of an interrupt acknowledge bus cycle."
    // -- databook p.3.236, read on the plate.
    //
    // So it is an ANNOUNCEMENT and nothing else: the processor enforces
    // nothing with it, and its only consumer is external.  Whoever asserts it
    // owes the enforcement separately -- see v60_bus_arb, which is where the
    // prefetch unit is actually held off.
    input               lock,
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
    // BLOCK* (MSMAT).  One pin with two jobs: BLOCK* in master mode and
    // MSMAT* -- the FRM checker's mismatch output -- in checker mode, which is
    // why docs/v60/BUS-CYCLE-TIMING.md lists it under both names.  Only the
    // master-mode meaning is driven here.
    output logic        block_n,
    output logic        ds_n,
    output logic [15:0] d_out,
    output logic        d_oe,
    input        [15:0] d_in,
    output logic        bus_hiz,    // all three-state pins released (TH)

    input               ready_n,    // sampled at falling T3 and each falling TW
    input               bmode,      // sampled at falling T2: 1 normal, 0 short
    input               hldrq_n,    // sampled at rising T4 or TI
    output logic        hldak_n,

    // ---- the externally raised conditions ---------------------------------
    input               berr_n,     // BERR*:  sampled at falling T4
    input               rt_ep_n,    // RT/EP*: 1 retry the cycle, 0 raise
    input               nmi_n,      // NMI*:   asynchronous, active low, an event
    input               int_req,    // INT:    asynchronous, active high, a level

    output logic        berr,       // one pulse: this cycle ended in a fault
    output bus_status_e berr_status,// what kind of cycle it was -- the code
    output logic [23:0] berr_addr,  // and where: the frame's Exception Address
    output logic        berr_we,
    output logic        berr_retry, // one pulse: the cycle is being re-run

    output logic        nmi_pending,// latched NMI*, held until nmi_take
    input               nmi_take,
    output logic        int_pending,// the synchronised INT level

    output bus_state_e  state       // observable, for verification
);

bus_state_e  st_r, st_next;
bus_status_e status_r;
logic        we_r;
logic  [1:0] io_recovery;          // three TI states between I/O cycles
logic        short_cycle;          // BMODE sampled low at falling T2
logic        ready_seen;           // READY* sampled low at falling T3 / TW
logic        take_hold;            // HLDRQ* sampled low at rising T4 or TI

// The two asynchronous inputs, brought into this clock domain.  Two flops is
// an implementation necessity, not a databook instant -- see the header.
logic  [1:0] nmi_sync, int_sync;
logic        nmi_q;                // for the falling edge NMI* is

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
        block_n     <= 1'b1;
        ds_n        <= 1'b1;
        d_out       <= 16'd0;
        d_oe        <= 1'b0;
        bus_hiz     <= 1'b0;
        hldak_n     <= 1'b1;
        rdata       <= 16'd0;
        berr        <= 1'b0;
        berr_retry  <= 1'b0;
        berr_status <= BST_MEM_SINGLE;
        berr_addr   <= 24'd0;
        berr_we     <= 1'b0;
        nmi_sync    <= 2'b11;       // NMI* is active low: idle is high
        int_sync    <= 2'b00;
        nmi_q       <= 1'b1;
        nmi_pending <= 1'b0;
        int_pending <= 1'b0;
    end
    else begin
        ack        <= 1'b0;
        berr       <= 1'b0;
        berr_retry <= 1'b0;

        // -------------------------------------------------------------------
        // The two asynchronous inputs.  INT is a level the source holds "until
        // acknowledged"; NMI* is an event, so its assertion edge is latched
        // and held until the sequencer takes it.  Setting wins over taking in
        // the same cycle: a request that arrives as one is taken must not be
        // the one that is lost.
        // -------------------------------------------------------------------
        nmi_sync    <= {nmi_sync[0], nmi_n};
        int_sync    <= {int_sync[0], int_req};
        nmi_q       <= nmi_sync[1];
        int_pending <= int_sync[1];
        if (!nmi_sync[1] && nmi_q) nmi_pending <= 1'b1;
        else if (nmi_take)         nmi_pending <= 1'b0;

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
                    // "FAS* = 0: First bus cycle / FAS* = 1: Subsequent bus
                    // cycles" -- p.3.235.  A multi-cycle logical access (a
                    // word on a 16-bit bus, or a string) drives it low only
                    // for the first.  It was unconditionally low here until
                    // the DL1-DL0 table was read, which is a good argument for
                    // reading the whole page before implementing half of it.
                    //
                    // "FAS* is undefined during an instruction fetch bus
                    // access" (p.3.235), so a fetch may drive it either way.
                    fas_n    <= ~first;
                    bcy_n    <= 1'b0;
                    // "asserted during a bus cycle".  Raised with the rest of
                    // the pins at T1 and dropped at TI below, so it spans
                    // every cycle of the indivisible operation and the gap
                    // between them -- which is what "indivisible" has to mean
                    // for a read-modify-write that is two bus cycles.
                    block_n  <= ~(lock || (status == BST_INTERRUPT_ACK));
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
                    // BLOCK* is NOT dropped between the bus cycles of one
                    // indivisible operation -- that is the whole point of it.
                    // It falls when `lock` itself falls, which v60_ea does
                    // when the read-modify-write's write has completed.  An
                    // interrupt acknowledge, which raises it without `lock`,
                    // drops it here.
                    if (!lock) block_n <= 1'b1;
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
                //
                // BERR* and RT/EP* are sampled at this same instant -- the AC
                // table's tSBEK/tSRTK are setup to CLK-falling and the p.3.243
                // plate draws the sample in the middle of T4.  See the header
                // for why the pin prose's "rising edge" is not what is
                // implemented.
                T_T4: begin
                    ds_n <= 1'b1;
                    d_oe <= 1'b0;

                    if (!berr_n && rt_ep_n) begin
                        // "retry the faulty bus cycle (RT/EP* = 1)".  No ack:
                        // the master is still asking and the arbiter still
                        // holds the grant, so the cycle re-runs from TI on its
                        // own -- and an I/O cycle waits out its recovery gap
                        // on the way, because it restarts through `may_start`.
                        // Read data is NOT latched: the cycle that would have
                        // produced it failed.
                        berr_retry <= 1'b1;
                    end
                    else begin
                        if (!we_r) rdata <= d_in;
                        ack <= 1'b1;
                        if (!berr_n) begin
                            // "cause an exception (RT/EP* = 0)".
                            //
                            // DECISION, and the one thing in this module that
                            // no page settles: the cycle is acknowledged
                            // anyway.  A bus cycle here can only be ended by
                            // an ack -- it is what releases v60_bus_arb's
                            // grant and what advances v60_dxu -- and there is
                            // no abort path to a master, so withholding it
                            // would wedge the bus rather than abort the
                            // access.  The access therefore completes with
                            // whatever the failed cycle returned, and `berr`
                            // says it is meaningless.  Figure 8-5 marks the
                            // Bus Fault "Abort", and the abort is the
                            // sequencer's: v60_seq raises instead of retiring.
                            berr        <= 1'b1;
                            berr_status <= status_r;
                            berr_addr   <= a;
                            berr_we     <= we_r;
                        end
                    end
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

// ---------------------------------------------------------------------------
// The premise the board owes this module, and why it is NOT asserted here.
// ---------------------------------------------------------------------------
// "RESET must be held asserted for a minimum of 20 clock cycles before
// returning to a low level." -- p.3.281.
//
// That was written here as a simulation assertion counting ce_rise pulses
// during reset.  It could never have fired: ce_rise is gated on !rst, both in
// the bench and in s32_v60_timebase (`assign ce_rise = !rst && !pause && ...`),
// so the counter it incremented was dead for exactly the interval it was
// measuring.  It reported a pass on a bench that released reset after four
// fast clocks.
//
// A check that cannot fail is worse than no check, so it is gone rather than
// left to reassure.  The requirement is real and belongs where the raw clock
// is visible and the V60 period is known -- at the board level, next to the
// reset synchroniser -- not in a module whose only clock reference is a strobe
// that reset suppresses.
//
// Recorded as an open verification item in docs/v60/BUS-CYCLE-TIMING.md.

endmodule
