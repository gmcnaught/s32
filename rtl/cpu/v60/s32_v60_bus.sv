//============================================================================
//  V60 logical-bus adapter (DESIGN.md §5.4 "bus unit")
//  Turns the CPU's logical accesses (any address, size 1/2/4 bytes) into
//  1..3 aligned 16-bit cycles on the system bus (V60 has a 16-bit external
//  data bus).
//
//  This is a V60 bus unit and should stay one.  It used to carry an IS_V70
//  parameter that was declared and never referenced, while the header claimed
//  V70 support -- setting it promised a 32-bit bus and silently delivered a
//  16-bit one.  The V70's bus is a different machine, not this one with a
//  width parameter: 32-bit data, B3E-B0E instead of UBE+A0, a TWO-clock
//  minimum cycle with no T3 or T4, three extra TIO states for I/O sizing, and
//  no BMODE.  See docs/v60/V70-SEPARATION.md before adding it back.
//
//  Sequenced as a databook §4 T-state machine (audit §07.4).  The states are
//  the real ones -- TI, T1, T2, T3, TW, T4, TH -- and the pin-level status
//  lines are driven from them, which is what makes the core electrically
//  describable rather than merely functionally correct.  What the old
//  three-state I_IDLE/I_CYC/I_WAIT adapter could not express: a bus cycle with
//  a distinct address phase and data phase, a wait state that is a state
//  rather than "however long the target takes", a normal-vs-short cycle
//  selection, and any notion of bus status at all.
//
//  Two behaviours are parameterised because they change what the bus COSTS,
//  and the audit is explicit that changing the execute:bus ratio in isolation
//  breaks shipped games:
//
//    DATABOOK_TIMING   0 = the cycle counts this core has always had
//                          (1 setup clock per logical access + 2 clocks per
//                          physical cycle: 3/5/7 clocks for a 1/2/3-cycle
//                          access).
//                      1 = databook §4 (3 clocks per physical cycle, T4 added
//                          when BMODE selects a normal cycle, three TI states
//                          of I/O recovery between back-to-back cycles:
//                          3/6/9 clocks short-cycle).
//
//                      Byte and aligned 16-bit accesses cost the SAME either
//                      way; only multi-cycle accesses lengthen.  Default 0:
//                      the regression gate for this change is the Golden Axe
//                      II / Spider-Man / Rad Rally black-screen cases, which
//                      need real hardware, so the faithful timing ships
//                      switched off until it has been run there.
//
//    HALF_CLOCK_SAMPLING
//                      0 = sample BMODE/READY on the enabled clock edge.
//                      1 = sample them on the V60 clock's FALLING edge, per
//                          databook §4 -- BMODE on the falling edge of T2,
//                          READY on the falling edge of T3 and of each TW.
//                          Requires a ce_fall from s32_v60_timebase; the unit
//                          benches run one V60 clock per bench clock and have
//                          no half-cycle to sample on, so they leave it 0.
//============================================================================

module s32_v60_bus #(
    parameter DATABOOK_TIMING = 1'b0,
    parameter HALF_CLOCK_SAMPLING = 1'b0
)(
    input             clk,
    input             ce,           // V60 clock rising edge (T-state boundary)
    input             ce_fall,      // V60 clock falling edge; used only when
                                    // HALF_CLOCK_SAMPLING=1
    input             rst,

    // CPU side (logical)
    input             c_req,
    input             c_we,
    input      [31:0] c_addr,
    input       [1:0] c_size,      // 0=B 1=H 2=W
    input      [31:0] c_wdata,
    output reg [31:0] c_rdata,
    output reg        c_ack,

    // system side: 16-bit bus
    output reg        m_req,
    output reg        m_we,
    output reg [23:1] m_addr,
    output reg [15:0] m_wdata,
    output reg  [1:0] m_be,
    input      [15:0] m_rdata,
    input             m_ack,

    // ---------------------------------------------------------------------
    // databook §4 pin-level interface
    // ---------------------------------------------------------------------
    // System 32 ties most of these off, but exposing them is the point: it is
    // what lets the core be checked against a µPD71613 decode table instead of
    // only against MAME's behaviour.
    //
    // `st` and `mrq_n` now carry NEC's encoding, from the µPD70632 (V70)
    // Advance Product Information, May 1987, p.2 -- see docs/v60/REFERENCES.md.
    // The V70 is the same V-Series architecture ("The µPD70632 has the same
    // architecture as the µPD70616 (V60)", ibid. p.7) and carries the same
    // ST2-ST0 + MRQ + DL1-DL0 pin set, which the 1987 short-form V60 data
    // sheet's PGA table confirms.  The audit independently reports that the
    // V60 databook's own table covers the same cases (string mode, demand-mode
    // fetch, machine-fault ack, halt ack).
    //
    // STILL TO CONFIRM against databook §1: that the V60 assigns the same
    // CODES, not merely the same cases.  The V70's BUS differs -- 32-bit,
    // two-clock, eight states, no BMODE -- so nothing about its TIMING is
    // carried across here, only the status encoding.
    output      [2:0] st,          // ST2-ST0 bus status
    output            mrq_n,       // memory request, ACTIVE LOW
    output            rw_n,        // 0 = write, 1 = read
    output            bcy,         // bus cycle in progress
    output            ds,          // data strobe
    output            ube,         // upper byte enable
    output            hldak,       // hold acknowledge
    // BLOCK, active low: asserted for the whole of an indivisible operation.
    // Semantics from the µPD70632 document (TASI/CAXI, lock spans the whole
    // operation); the WHEN is this part's own bus sequence, not the V70's
    // two-clock T1/T2 -- see docs/v60/V70-SEPARATION.md.
    output            block_n,
    output            rt_ep,       // retry / error-processing

    input             c_fetch,     // 1 = this access is an instruction prefetch
    input             c_lock,      // indivisible operation in progress
    input             bmode,       // sampled falling T2: 1 = short cycle
    input             ready_n,     // sampled falling T3 and each TW, active low
    input             berr_n,      // bus error, active low
    input             bfrez_n,     // bus freeze, active low
    input             hldrq        // hold request
);

// T-states, databook §4.  With DATABOOK_TIMING=0 the machine runs
// TI -> T1 -> T3(/TW) and T2/T4 are unreachable, which reproduces the
// pre-existing I_IDLE -> I_CYC -> I_WAIT sequence clock for clock.
typedef enum logic [2:0] {
    T_TI, T_T1, T_T2, T_T3, T_TW, T_T4, T_TH
} tstate_t;
tstate_t ts;

// NEC bus-status codes, µPD70632 Advance Product Information May 1987 p.2.
// Listed in full so a diff against databook §1 is mechanical; only the ones
// this core can actually emit are driven.
//                                              MRQ  ST2 ST1 ST0
localparam [2:0] ST_RESERVED_0  = 3'b000;   //   0    reserved
localparam [2:0] ST_STRING_DATA = 3'b001;   //   0    string mode data access
localparam [2:0] ST_SHORT_PATH  = 3'b010;   //   0    short path data access
localparam [2:0] ST_SINGLE_DATA = 3'b011;   //   0    single mode data access
localparam [2:0] ST_SBT         = 3'b100;   //   0    system base table access
localparam [2:0] ST_XLAT_TABLE  = 3'b101;   //   0    translation table access
localparam [2:0] ST_DEMAND_FETCH= 3'b110;   //   0    demand mode instruction fetch
localparam [2:0] ST_PREFETCH    = 3'b111;   //   0    instruction prefetch
// With MRQ high: 001 string I/O, 011 single I/O, 100 machine fault ack,
// 101 halt ack, 110 interrupt ack.  This core emits none of them: System 32
// has no separate I/O space (MAME maps it as memory), and the audit records
// that there is no INTAK bus cycle -- the vector arrives on a wire.

reg [1:0]  cyc, cycs;        // current / total 16-bit cycles - 1
reg [31:0] acc;
reg [31:0] addr_r;
reg [31:0] wdata_r;
reg [1:0]  size_r;
reg        we_r;
reg        short_cycle;      // latched from BMODE at the falling edge of T2
reg        ready_q;          // latched from READY at the falling edge of T3/TW
reg  [1:0] io_recover;       // databook §4 three-TI recovery between cycles
// Four-phase CPU-side handshake.  The V60 microsequencer may advance between
// physical bus enables, so observe the request-low re-arm phase on every
// clk edge and hold ACK until it is seen.  Every T-state transition and every
// m_req change remain gated by the board-rate `ce` input.
reg        c_req_armed;

// Accepting a new logical access on this edge.  In databook timing the address
// phase IS T1, so TI drives the first physical cycle straight from the CPU's
// inputs; in legacy timing TI only latches and T_SETUP spends the extra clock.
wire accept_now = (ts == T_TI) && (io_recover == 2'd0)
                  && c_req && c_req_armed && !c_ack;
wire first_now  = DATABOOK_TIMING && accept_now;

// Physical 16-bit cycles - 1 for the access currently being accepted, computed
// from the CPU's inputs.  Latched on every accept in both timing modes.
wire [1:0]  acc_cycs  = (c_size == 2'd0) ? 2'd0
                      : (c_size == 2'd1) ? (c_addr[0] ? 2'd1 : 2'd0)
                                         : (c_addr[0] ? 2'd2 : 2'd1);

// NOTE: there were six eff_* wires here selecting between the CPU's inputs and
// the latched copies.  Every one of them was dead -- drive_cycle is called
// with c_* directly from T_TI and with the latched regs from T_T1, so nothing
// ever read them.  Removed: they synthesised away, but they described a
// datapath that does not exist, which is worse than useless when someone is
// tracing a critical path through this module.

// READY.  With half-clock sampling the falling-edge latch decides; without it
// the transition uses m_ack at the enabled edge exactly as the pre-existing
// adapter did, which is what keeps DATABOOK_TIMING=0 bit-identical.
wire ready_now = HALF_CLOCK_SAMPLING ? ready_q : (m_ack && ready_n !== 1'b1);

// Pin-level status, driven from the T-state.
// BCY covers the whole bus cycle.  first_now is part of it: with databook
// timing the address phase IS the accepting edge (TI doing T1's work), so
// leaving it out would drop the first cycle's address phase off the pin --
// visible to anyone decoding this against a µPD71613 table.
assign bcy   = (ts == T_T1) || (ts == T_T2) || (ts == T_T3)
             || (ts == T_TW) || (ts == T_T4) || first_now;

// Engaged: the accept edge through to the completing edge, inclusive.  This is
// what a logical access actually costs the CPU, and it is the figure the
// audit's cycle table is quoted in.
wire busy = (ts != T_TI) || accept_now;
assign ds    = (ts == T_T2) || (ts == T_T3) || (ts == T_TW);
// MRQ is active low and asserted when the cycle is directed at memory space.
// Every cycle this core issues is a memory cycle.
assign mrq_n = ~bcy;
assign rw_n  = ~m_we;
assign ube   = m_be[1];
assign hldak = (ts == T_TH);
assign block_n = ~c_lock;
assign rt_ep = ~berr_n;
// Data accesses are single mode: this adapter is only ever handed one operand
// at a time, and string-mode accesses are an architectural feature the core
// does not implement (the audit records string instructions as
// non-interruptible and non-resumable, driven from internal registers).
// c_fetch distinguishes the CPU's instruction prefetch from its data port.
assign st    = bcy ? (c_fetch ? ST_PREFETCH : ST_SINGLE_DATA)
                   : ST_RESERVED_0;

// Physical-cycle payload for one 16-bit cycle.  Lifted verbatim from the
// pre-existing I_CYC body -- this decode is bit-exact against the reference
// model and against tb_v60_bus_lanes, and is deliberately NOT touched by the
// T-state rework.
task automatic drive_cycle(input [31:0] a, input [1:0] sz, input [31:0] wd,
                           input w, input [1:0] k, input [1:0] ks);
begin
    m_req <= 1'b1;
    m_we  <= w;
    if (!a[0]) begin
        m_addr <= a[23:1] + {21'b0, k};
        case (sz)
            2'd0: begin m_be <= 2'b01; m_wdata <= {8'h00, wd[7:0]}; end
            2'd1: begin m_be <= 2'b11; m_wdata <= wd[15:0]; end
            default: begin
                m_be <= 2'b11;
                m_wdata <= (k == 0) ? wd[15:0] : wd[31:16];
            end
        endcase
    end
    else begin
        if (k == 0) begin
            m_addr  <= a[23:1];
            m_be    <= 2'b10;
            m_wdata <= {wd[7:0], 8'h00};
        end
        else begin
            m_addr <= a[23:1] + {21'b0, k};
            if (k == ks && sz == 2'd2) begin
                m_be <= 2'b01; m_wdata <= {8'h00, wd[31:24]};
            end
            else if (k == ks && sz == 2'd1) begin
                m_be <= 2'b01; m_wdata <= {8'h00, wd[15:8]};
            end
            else begin
                m_be <= 2'b11; m_wdata <= wd[23:8];
            end
        end
    end
end
endtask

// Read-data lane assembly, likewise lifted verbatim from I_WAIT.
task automatic assemble_read;
begin
    if (!we_r) begin
        if (!addr_r[0]) begin
            case (size_r)
                2'd0: acc[7:0]  <= m_rdata[7:0];
                2'd1: acc[15:0] <= m_rdata;
                default: begin
                    if (cyc == 0) acc[15:0]  <= m_rdata;
                    else          acc[31:16] <= m_rdata;
                end
            endcase
        end
        else begin
            if (cyc == 0) acc[7:0] <= m_rdata[15:8];
            else if (cyc == cycs && size_r == 2'd2) acc[31:24] <= m_rdata[7:0];
            else if (cyc == cycs && size_r == 2'd1) acc[15:8]  <= m_rdata[7:0];
            else acc[23:8] <= m_rdata;
        end
    end
end
endtask

// ---------------------------------------------------------------------------
// The T-state machine (databook §4)
// ---------------------------------------------------------------------------
always @(posedge clk) begin
    if (rst) begin
        ts <= T_TI; m_req <= 0; c_ack <= 0; c_req_armed <= 1;
        short_cycle <= 1'b1; ready_q <= 1'b0; io_recover <= 2'd0;
    end
    else begin
        if (!c_req) begin
            c_ack <= 1'b0;
            c_req_armed <= 1'b1;
        end

        // --- half-clock sampling points, databook §4 ----------------------
        // BMODE on the falling edge of T2 selects short (skip T4) or normal.
        // READY on the falling edge of T3 and of each TW.  These are the
        // events that do not exist on clk_sys at all -- see s32_v60_timebase.
        if (HALF_CLOCK_SAMPLING && ce_fall) begin
            if (ts == T_T2)                    short_cycle <= bmode;
            if (ts == T_T3 || ts == T_TW)      ready_q <= m_ack && (ready_n !== 1'b1);
        end

        if (ce) begin
        case (ts)

        T_TI: begin
            // HLDRQ is sampled in T4 and TI (databook §4).  System 32 ties it
            // low, so this path is dormant -- but it exists, which is the
            // difference between "not modelled" and "tied off".
            if (hldrq === 1'b1) ts <= T_TH;
            // BFREZ holds the bus in TI without completing anything.  Also
            // tied off on this board.
            else if (bfrez_n === 1'b0) ts <= T_TI;
            // Three TI states of I/O recovery between back-to-back cycles.
            else if (io_recover != 2'd0) io_recover <= io_recover - 2'd1;
            else if (accept_now) begin
                c_req_armed <= 1'b0;
                addr_r      <= c_addr;
                wdata_r     <= c_wdata;
                size_r      <= c_size;
                we_r        <= c_we;
                cyc         <= 2'd0;
                cycs        <= acc_cycs;
                short_cycle <= 1'b1;
                ready_q     <= 1'b0;
                if (DATABOOK_TIMING) begin
                    // TI *is* the address phase; there is no separate setup
                    // clock.  This is the fix for the audit's finding that
                    // I_IDLE was entered once per logical access rather than
                    // once per bus cycle, so every continuation ran a clock
                    // short of the documented three-clock minimum.
                    drive_cycle(c_addr, c_size, c_wdata, c_we, 2'd0, acc_cycs);
                    ts <= T_T2;
                end
                // Legacy: TI is the old I_IDLE (accept + address setup) and
                // T1 is the old I_CYC (drive the cycle).  No extra state --
                // adding one would make this mode slower than what it is
                // meant to reproduce exactly.
                else ts <= T_T1;
            end
        end

        T_T1: begin
            drive_cycle(addr_r, size_r, wdata_r, we_r, cyc, cycs);
            ready_q <= 1'b0;
            ts <= DATABOOK_TIMING ? T_T2 : T_T3;
        end

        T_T2: ts <= T_T3;

        T_T3, T_TW: begin
            if (ready_now) begin
                m_req <= 1'b0;
                assemble_read();
                if (DATABOOK_TIMING && !short_cycle) begin
                    ts <= T_T4;              // normal cycle: one clock more
                end
                else if (cyc == cycs) begin
                    ts <= T_TI;
                    if (c_req) c_ack <= 1'b1;
                    if (DATABOOK_TIMING) io_recover <= 2'd3;
                end
                else begin
                    cyc <= cyc + 2'd1;
                    ts  <= T_T1;
                end
            end
            else ts <= T_TW;                 // READY low: insert a wait state
        end

        T_T4: begin
            if (cyc == cycs) begin
                ts <= T_TI;
                if (c_req) c_ack <= 1'b1;
                io_recover <= 2'd3;
            end
            else begin
                cyc <= cyc + 2'd1;
                ts  <= T_T1;
            end
        end

        T_TH: if (hldrq !== 1'b1) ts <= T_TI;

        default: ts <= T_TI;
        endcase

        // read data out (combinable timing: valid with c_ack).  Lifted from
        // the pre-existing I_WAIT completion; the condition is the same
        // moment, now named as the end of T3/TW.
        if ((ts == T_T3 || ts == T_TW) && ready_now && cyc == cycs && !we_r) begin
            c_rdata <= acc;
            if (!addr_r[0]) begin
                case (size_r)
                    2'd0: c_rdata <= {24'b0, m_rdata[7:0]};
                    2'd1: c_rdata <= {16'b0, m_rdata};
                    default: c_rdata <= (cycs == 2'd1) ? {m_rdata, acc[15:0]} : acc;
                endcase
            end
            else begin
                case (size_r)
                    2'd0: c_rdata <= {24'b0, m_rdata[15:8]};
                    2'd1: c_rdata <= {16'b0, m_rdata[7:0], acc[7:0]};
                    default: c_rdata <= {m_rdata[7:0], acc[23:0]};
                endcase
            end
        end
        end
    end
end

// ---------------------------------------------------------------------------
// Engaged-clock counter (simulation only)
// ---------------------------------------------------------------------------
// Counts the clocks one logical access occupies -- the accepting edge through
// the completing edge, inclusive.  That is the basis the audit's cycle table
// is quoted on, and measuring it inside the module avoids the sampling
// ambiguity a bench has: read the state after a rising edge and the accepting
// clock merges into the next one, differently in each timing mode, because
// databook timing does the address phase ON the accepting edge.
`ifndef SYNTHESIS
integer eng_cnt = 0;
integer last_access_clocks = 0;

always @(posedge clk) begin
    if (rst) begin
        eng_cnt <= 0;
    end
    else if (ce) begin
        if (busy) eng_cnt <= eng_cnt + 1;
        else if (eng_cnt != 0) begin
            last_access_clocks <= eng_cnt;
            eng_cnt <= 0;
        end
    end
end
`endif

// ---------------------------------------------------------------------------
// Adapter-side handshake invariants (audit S03 / S07.2)
// ---------------------------------------------------------------------------
// Immediate assertions rather than concurrent SVA: Icarus, which is what this
// repo's benches and CI run, rejects `assert property`.  The audit's
// `c_ack |-> $stable(c_addr, c_size, c_we)` is therefore expressed as a shadow
// copy latched at accept and compared while the access is in flight.
//
// Fatal by default; verif/v60/tb_v60_invariants.sv builds with
// +define+V60_INVARIANT_NONFATAL to observe a fire and keep running.
`ifndef SYNTHESIS
integer v60bus_inv_fails = 0;

task automatic v60bus_inv_fail(input [8*8:1] id, input [8*64:1] what);
begin
    v60bus_inv_fails = v60bus_inv_fails + 1;
    $display("V60BUS-INVARIANT FAIL %0s: %0s  (ts=%0d c_req=%0b c_ack=%0b)",
             id, what, ts, c_req, c_ack);
`ifndef V60_INVARIANT_NONFATAL
    $fatal(1, "V60 bus-adapter invariant violated");
`endif
end
endtask

// B1  Reset is a bus epoch boundary: neither a held CPU acknowledgement nor an
//     in-flight physical request may survive it.
//
//     This check is pre-existing but was doing nothing under Icarus, in two
//     separate ways, and both are worth recording because they are easy to
//     re-introduce:
//
//       * its guard was `!$isunknown({c_ack, m_req})`, and Icarus 13.0 returns
//         1 from $isunknown() for ANY concatenation argument regardless of the
//         values in it -- so the guard was permanently false and the assertion
//         never ran.  Verified with a two-line reproducer; $isunknown() on the
//         individual signals is correct.  Nothing anywhere in this tree should
//         pass a concatenation to $isunknown().  Use === / !==, which are
//         X-safe by construction and need no guard at all.
//       * the checks were bare `assert (...)` statements.  Icarus prints a
//         failure and walks on, so even had the guard passed, the bench would
//         still have reached its own PASS marker and the runner would have
//         reported success.
reg reset_sampled = 1'b0;
always @(posedge clk) reset_sampled <= rst;
always @(negedge clk)
    if (reset_sampled === 1'b1) begin
        if (c_ack === 1'b1) v60bus_inv_fail("B1", "c_ack survived reset");
        if (m_req === 1'b1) v60bus_inv_fail("B1", "m_req survived reset");
    end

// B2  The accepted payload is stable from accept to acknowledgement.  The
//     adapter latches addr/size/we into addr_r/size_r/we_r on the accepting
//     edge and never re-reads the CPU-side inputs, so a payload that moved
//     underneath it would complete a transaction against an address the CPU
//     believes it never issued -- silently, and only on some cadences, since
//     the accept and the ack sit on opposite sides of the enable split.
//     c_wdata is deliberately NOT in the contract: it is latched into wdata_r
//     at accept and never sampled again.
reg        inv_inflight = 1'b0;
reg [31:0] inv_addr;
reg [1:0]  inv_size;
reg        inv_we;

always @(posedge clk) begin
    if (rst) begin
        inv_inflight <= 1'b0;
    end
    else begin
        // No blanket $isunknown() guard: !== is already X-safe, and a guard
        // over every signal disables all three checks whenever any one of them
        // is momentarily X.  inv_inflight is only ever set alongside the
        // shadow copies, so they cannot be X while it is high.
        if (inv_inflight === 1'b1) begin
            if (c_addr !== inv_addr)
                v60bus_inv_fail("B2", "c_addr changed while the access was in flight");
            else if (c_size !== inv_size)
                v60bus_inv_fail("B2", "c_size changed while the access was in flight");
            else if (c_we !== inv_we)
                v60bus_inv_fail("B2", "c_we changed while the access was in flight");
        end
        if (ce) begin
            // accept: the same condition I_IDLE uses to latch
            if (ts == T_TI && c_req && c_req_armed && !c_ack) begin
                inv_inflight <= 1'b1;
                inv_addr     <= c_addr;
                inv_size     <= c_size;
                inv_we       <= c_we;
            end
            // completion: the edge that raises c_ack ends the contract
            else if ((ts == T_T3 || ts == T_TW) && ready_now && cyc == cycs) begin
                inv_inflight <= 1'b0;
            end
        end
    end
end
`endif

endmodule
