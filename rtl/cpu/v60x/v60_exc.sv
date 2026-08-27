//============================================================================
//  v60_exc -- taking an exception: the vector, the frame, and the PSW.
//
//  Clean-room.  Programmer's Reference S8, and the databook's second printing
//  at pp.3.269-3.270.  What is on the page:
//
//    "The SBT consists of 256 entries each containing a vector to an interrupt
//     or exception handler.  An SBT entry consists of a 32-bit virtual address
//     ... The SBT is located in the memory address space aligned on a page
//     (4KB) boundary by the SBR ... The first 64 SBT entries (0-63) are
//     reserved for use by the uPD70616 ... The remaining 192 entries (64-255)
//     are available in user applications as maskable interrupt vectors."
//
//    "The parameter count indicates the number of bytes of exception
//     information IN ADDITION TO the PC and PSW in the exception data."
//
//    "An exception during the execution of an instruction stacks the PC of the
//     instruction causing the exception (Current PC).  An exception following
//     the execution of an instruction stacks the PC of the instruction
//     immediately following (Next PC)."  -- which of the two is the caller's
//     to decide, and it arrives here as `ret_pc`.
//
//    "Following the acknowledgement of an interrupt, the PC and PSW are saved
//     on the interrupt stack and program control is transferred to the
//     predesignated or supplied vector at execution level 0."
//
//    "Following the occurrence of a maskable interrupt, further maskable
//     interrupts will be disabled until the PSW.IE is again set."
//
//    Note 2: "Bus error and level stack invalid exceptions will disable
//     maskable interrupts."
//
//  The frame's order is the one the Programmer's Reference prints for BRKV,
//  which is the only place it is spelled out as an operation:
//
//      [-SP] <- CurrentPC ; [-SP] <- Exception Code ; [-SP] <- PSW ;
//      [-SP] <- NextPC ; PC <- [ Exception Vector 21 ]
//
//  so the parameter words go down first, then the PSW, then the return PC --
//  which leaves the return PC on top of the stack, where RETIU and RETIS will
//  want it.
//
//  ---------------------------------------------------------------------------
//  What this does NOT do, and why
//  ---------------------------------------------------------------------------
//  * PSW.IS.  The eight-step sequence never assigns it, and yet interrupts are
//    "saved on the interrupt stack" and PSW.IS is the bit that selects that
//    stack.  This sets IS on an interrupt, which is the only reading that makes
//    both sentences true, and marks it -- it is the fifth thing in this tree
//    that is not from a page.  Note 4 ("if the previous stack was the interrupt
//    stack then the IS is continued to be used") is consistent with it.
//  * TE, TP, AE, EM and ASA.  Table 8-1 has columns for them; those columns
//    have not been read off the scan, and this does not guess.  They are left
//    as they were, and docs/v60/EXECUTION-STAGE-PLAN.md records it.
//  * The externally raised exceptions -- bus error, NMI, maskable interrupt --
//    cannot be driven end to end, because v60_biu has no pin for any of them.
//    `is_interrupt` and `disable_ie` are inputs so the behaviour can be built
//    and tested before the pins exist.
//============================================================================
`timescale 1ns/1ps

module v60_exc
    import v60_psw_pkg::*;
(
    input               clk,
    input               rst,

    input               req,
    input         [7:0] vector,        // the SBT entry, 0-255
    input        [31:0] ret_pc,        // Current PC or Next PC: the caller's choice
    input        [31:0] psw_in,
    input        [31:0] sp_in,         // R31, the active stack pointer
    input        [31:0] sbr,           // the system base register

    // "the number of bytes of exception information in addition to the PC and
    // PSW", as words.  Up to two here, which covers every entry in Table 8-1
    // this stage can raise.
    input         [1:0] nparams,
    input        [31:0] param0,
    input        [31:0] param1,

    input               is_interrupt,  // an interrupt, not an exception
    input               disable_ie,    // bus error / stack invalid (Note 2)

    output logic [31:0] sp_out,
    output logic [31:0] psw_out,
    output logic [31:0] handler_pc,
    output logic        busy,
    output logic        done,
    output logic  [3:0] bus_cycles,

    // ---- data access unit --------------------------------------------------
    output logic        dx_req,
    output logic [23:0] dx_addr,
    output logic  [3:0] dx_nbytes,
    output logic        dx_we,
    output logic [63:0] dx_wdata,
    input        [63:0] dx_rdata,
    input               dx_done,
    input         [3:0] dx_cycles
);

typedef enum logic [2:0] {
    S_IDLE, S_VECTOR, S_PUSH, S_ISSUE, S_FIN
} state_e;

state_e      state;
logic  [1:0] pushes_left;   // parameter words still to push
logic  [1:0] np_r;          // and how many there were
logic  [1:0] phase;         // 0: parameters, 1: the PSW, 2: the return PC
logic [31:0] sp;
logic [31:0] p0, p1;
logic        int_r, dis_r;
logic  [7:0] vec_r;

assign busy = (state != S_IDLE);

// The next word to push, in the order BRKV prints.
// Which word goes down next.  The parameters go in order -- param0 first --
// so the first push is the one where nothing has been pushed yet, `left ==
// count`, and not "left == 2": with a single parameter that test picked
// param1, which is the word an instruction exception does not have.
function automatic logic [31:0] push_word(input logic [1:0] ph,
                                          input logic [1:0] left,
                                          input logic [1:0] count,
                                          input logic [31:0] a,
                                          input logic [31:0] b,
                                          input logic [31:0] psw_v,
                                          input logic [31:0] pc_v);
    if (ph == 2'd0)      push_word = (left == count) ? a : b;
    else if (ph == 2'd1) push_word = psw_v;
    else                 push_word = pc_v;
endfunction

// The PSW the handler runs with.
function automatic logic [31:0] psw_upd(input logic [31:0] p,
                                        input logic        is_int,
                                        input logic        dis);
    logic [31:0] r;
    begin
        r                        = p;
        r[PSW_EL_HI:PSW_EL_LO]   = 2'b00;              // execution level 0
        if (is_int || dis) r[PSW_IE] = 1'b0;           // and Note 2
        // DECISION, marked in the header: an interrupt is "saved on the
        // interrupt stack", and PSW.IS is what selects it.
        if (is_int)        r[PSW_IS] = 1'b1;
        psw_upd = r;
    end
endfunction

always_ff @(posedge clk) begin
    if (rst) begin
        state       <= S_IDLE;
        done        <= 1'b0;
        dx_req      <= 1'b0;
        dx_addr     <= 24'd0;
        dx_nbytes   <= 4'd0;
        dx_we       <= 1'b0;
        dx_wdata    <= 64'd0;
        sp          <= 32'd0;
        sp_out      <= 32'd0;
        psw_out     <= 32'd0;
        handler_pc  <= 32'd0;
        bus_cycles  <= 4'd0;
        pushes_left <= 2'd0;
        np_r        <= 2'd0;
        phase       <= 2'd0;
        p0          <= 32'd0;
        p1          <= 32'd0;
        int_r       <= 1'b0;
        dis_r       <= 1'b0;
        vec_r       <= 8'd0;
    end else begin
        done <= 1'b0;

        case (state)
        S_IDLE: if (req) begin
            vec_r       <= vector;
            p0          <= param0;
            p1          <= param1;
            pushes_left <= nparams;
            np_r        <= nparams;
            int_r       <= is_interrupt;
            dis_r       <= disable_ie;
            sp          <= sp_in;
            bus_cycles  <= 4'd0;
            phase       <= (nparams == 2'd0) ? 2'd1 : 2'd0;

            // The vector first: SBR + 4 x vector, a 32-bit read.
            dx_addr   <= sbr[23:0] + {14'd0, vector, 2'b00};
            dx_nbytes <= 4'd4;
            dx_we     <= 1'b0;
            dx_req    <= 1'b1;
            state     <= S_VECTOR;
        end

        S_VECTOR: if (dx_done) begin
            handler_pc <= dx_rdata[31:0];
            bus_cycles <= bus_cycles + dx_cycles;
            dx_req     <= 1'b0;
            state      <= S_ISSUE;
        end

        // One idle cycle so the data unit sees a fresh request edge.
        S_ISSUE: begin
            dx_addr   <= sp[23:0] - 24'd4;
            dx_nbytes <= 4'd4;
            dx_we     <= 1'b1;
            dx_wdata  <= {32'd0, push_word(phase, pushes_left, np_r, p0, p1,
                                           psw_in, ret_pc)};
            dx_req    <= 1'b1;
            sp        <= sp - 32'd4;
            state     <= S_PUSH;
        end

        S_PUSH: if (dx_done) begin
            bus_cycles <= bus_cycles + dx_cycles;
            dx_req     <= 1'b0;

            if (phase == 2'd0) begin
                pushes_left <= pushes_left - 2'd1;
                if (pushes_left == 2'd1) phase <= 2'd1;
                state <= S_ISSUE;
            end else if (phase == 2'd1) begin
                phase <= 2'd2;
                state <= S_ISSUE;
            end else begin
                state <= S_FIN;
            end
        end

        S_FIN: begin
            // "transferred to the ... vector at execution level 0", and for an
            // interrupt "further maskable interrupts will be disabled".
            psw_out <= psw_upd(psw_in, int_r, dis_r);
            sp_out  <= sp;
            done    <= 1'b1;
            state   <= S_IDLE;
        end

        default: state <= S_IDLE;
        endcase
    end
end

// synthesis translate_off
always_ff @(posedge clk) begin
    if (!rst && req && (sbr[11:0] != 12'd0))
        $display("WARN v60_exc: SBR %h is not page aligned -- 'the twelve low order bits' must be zero (t=%0t)",
                 sbr, $time);
    if (!rst && req && is_interrupt && (vector < 8'd64))
        $display("WARN v60_exc: interrupt on vector %0d, which is one of the 64 the processor reserves (t=%0t)",
                 vector, $time);
end
// synthesis translate_on

endmodule
