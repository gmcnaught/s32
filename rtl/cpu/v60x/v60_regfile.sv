//============================================================================
//  v60_regfile -- thirty-two registers, and the five stack pointers behind R31.
//
//  Clean-room.  Sources:
//
//    databook p.3.247   R0-R31, all 32 bits; R29 AP, R30 FP, R31 SP.
//    databook p.3.249   the privileged register set, and: "A set of five
//                       separate stack pointers are used ... The general
//                       purpose register R31 contains a pointer to the current
//                       TOS and is saved and loaded whenever the execution
//                       level changes or the processor switches to the
//                       interrupt stack.  The active stack pointer can be
//                       identified by examining the contents of the PSW.EL and
//                       PSW.IS fields."
//    PgmRef S8          "The cache of five stack pointer registers (L0SP-L3SP,
//                       ISP) are independent of the user SP (R31).  The user
//                       stack is switched whenever the execution level changes
//                       due to an interrupt or exception.  Before changing
//                       stacks, the contents of the SP register are saved back
//                       in the contents of the corresponding stack pointer
//                       register.  Because the SP is updated by any instruction
//                       affecting R31, the contents of the SP and the
//                       associated stack pointer register can differ during the
//                       execution of a program."
//    PgmRef S3 Fig 3-2  the privileged register ids and, per id, whether LDPR
//                       and STPR may touch it.
//
//  That last sentence is what fixes the implementation.  R31 is a REGISTER,
//  not a window onto the selected stack pointer: the two are allowed to
//  disagree while a program runs, and they are reconciled only when the stack
//  is switched.  A model where R31 aliases the cache entry would be simpler
//  and would contradict the page.
//============================================================================
`timescale 1ns/1ps

module v60_regfile
    import v60_psw_pkg::*;
(
    input               clk,
    input               rst,

    // ---- general registers -------------------------------------------------
    input         [4:0] ra_sel,
    input         [4:0] rb_sel,
    output logic [31:0] ra,
    output logic [31:0] rb,
    // A doubleword operand is a register PAIR, low register first
    // (Programmer's Reference S3).
    output logic [63:0] ra_pair,

    input               wr_en,
    input         [4:0] wr_sel,
    input        [31:0] wr_data,

    // ---- the stack ----------------------------------------------------------
    input         [1:0] psw_el,        // which stack pointer R31 is
    input               psw_is,
    // A change of execution level, or a switch to or from the interrupt
    // stack.  R31 is saved into the entry the OLD selection names and reloaded
    // from the entry the NEW one does.
    input               stack_switch,
    input         [1:0] new_el,
    input               new_is,

    // ---- privileged registers (LDPR / STPR) --------------------------------
    input         [4:0] pr_id,
    input               pr_wr,         // LDPR: load a privileged register
    input        [31:0] pr_wdata,
    output logic [31:0] pr_rdata,      // STPR: store one into a general one
    output logic        pr_rd_ok,      // this id may be read
    output logic        pr_wr_ok,      // this id may be written

    // ---- for the units above ------------------------------------------------
    output logic [31:0] sbr            // the system base register, for v60_exc
);

// ---------------------------------------------------------------------------
// Privileged register ids -- PgmRef S3, Figure 3-2.
// ---------------------------------------------------------------------------
localparam int PR_ISP  = 0;
localparam int PR_L0SP = 1;
localparam int PR_L1SP = 2;
localparam int PR_L2SP = 3;
localparam int PR_L3SP = 4;
localparam int PR_SBR  = 5;
localparam int PR_TR   = 6;    // STPR only
localparam int PR_SYCW = 7;
localparam int PR_TKCW = 8;
localparam int PR_PIR  = 9;    // STPR only
localparam int PR_PSW2 = 15;
// 16-23 are the area table registers, 24 TRMOD, 25-28 the address trap
// registers: memory management and address traps, neither of which this
// stage implements.  They exist as storage so a system that writes them is
// not silently ignored, and are marked in PR_PRESENT.
localparam int PR_TRMOD = 24;

// Which ids exist at all: 0-9, 15-28.  10-14 and 29-31 are "Reserved for
// future use" and marked X in both permission columns.
localparam logic [31:0] PR_PRESENT = 32'b0001_1111_1111_1111_1000_0011_1111_1111;
// LDPR may not write TR (6) or PIR (9): the figure prints "-" for those.
localparam logic [31:0] PR_LDPR_OK = PR_PRESENT & ~((32'h1 << PR_TR) |
                                                    (32'h1 << PR_PIR));
localparam logic [31:0] PR_STPR_OK = PR_PRESENT;

logic [31:0] gpr [0:31];
logic [31:0] pr  [0:31];

integer i;

// Which stack pointer R31 currently is.  PSW.IS selects the interrupt stack
// pointer; otherwise the execution level selects one of the four.
function automatic logic [4:0] sp_id(input logic is_bit, input logic [1:0] el);
    if (is_bit) sp_id = 5'(PR_ISP);
    else        sp_id = 5'(PR_L0SP) + {3'd0, el};
endfunction

assign ra      = gpr[ra_sel];
assign rb      = gpr[rb_sel];
assign ra_pair = {gpr[ra_sel + 5'd1], gpr[ra_sel]};
assign sbr     = pr[PR_SBR];

assign pr_rdata = pr[pr_id];
assign pr_rd_ok = PR_STPR_OK[pr_id];
assign pr_wr_ok = PR_LDPR_OK[pr_id];

always_ff @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < 32; i = i + 1) begin
            gpr[i] <= 32'd0;
            pr[i]  <= 32'd0;
        end
    end else begin
        if (wr_en) gpr[wr_sel] <= wr_data;

        // LDPR.  A write to an id the figure does not allow is dropped here;
        // raising the privileged-instruction exception is the sequencer's.
        if (pr_wr && pr_wr_ok) pr[pr_id] <= pr_wdata;

        // The stack switch, in the order the page gives: save first, then
        // load.  Doing both in one cycle is what makes a switch to the SAME
        // entry a no-op rather than a corruption.
        if (stack_switch) begin
            pr[sp_id(psw_is, psw_el)] <= gpr[31];
            if (sp_id(new_is, new_el) == sp_id(psw_is, psw_el))
                gpr[31] <= gpr[31];
            else
                gpr[31] <= pr[sp_id(new_is, new_el)];
        end
    end
end

// synthesis translate_off
always_ff @(posedge clk) begin
    if (!rst && pr_wr && !pr_wr_ok)
        $display("WARN v60_regfile: LDPR to privileged register %0d, which Figure 3-2 does not allow (t=%0t)",
                 pr_id, $time);
    if (!rst && stack_switch && wr_en && (wr_sel == 5'd31))
        $display("WARN v60_regfile: R31 written in the same cycle as a stack switch (t=%0t)",
                 $time);
end
// synthesis translate_on

endmodule
