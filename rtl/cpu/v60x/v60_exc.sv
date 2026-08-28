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
//  THE EXCEPTION CODE WORD.  Both books draw the exception frame with a "31
//  ... 0" ruler over a row that reads "Exception Code   Parameter Count" --
//  Figure 8-3 in the Reference and the same figure in the databook at p.3.269.
//  That is ONE 32-bit word with the code in the high half and the count in the
//  low half, not two words and not the code alone.  The count is "the number
//  of bytes of exception information in addition to the PC and PSW", and it
//  counts this word too: the Instruction Exceptions group prints 4 and has
//  nothing else, and the Change Execution Level group prints 8 and has one
//  Parameter word above it.
//
//  So an exception's frame is
//
//      [-SP] <- parameter words, if any, deepest first
//      [-SP] <- { exception code, 4 x (parameters + 1) }
//      [-SP] <- PSW
//      [-SP] <- return PC
//
//  and an INTERRUPT's is the last two only: Figure 8-3 draws the interrupt
//  stack format as PSW and PC and nothing else.  `nparams` here counts the
//  words above the code word, not including it.
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
//  * Nothing in the recognition sequence: EL, IE, TE, TP, AE, EM and ASA are
//    all set, and the stack is selected.  The three digits the Programmer's
//    Reference's printing of that sequence lost to the scan are legible in
//    the databook's, pp.3.269-3.270 -- see docs/v60/EXCEPTIONS.md.
//  * A double bus error.  "When a bus error involves the interrupt stack or a
//    second bus error occurs during the processing of the initial bus error,
//    the situation is deemed unrecoverable and the processor will halt" (S8).
//    Nothing here halts: a bus error while this module is pushing is reported
//    to v60_seq like any other and raised again afterwards.  There is no halt
//    state in this tree and BST_MACHINE_FAULT, which is what the databook says
//    a fatal double bus error puts on the pins (p.3.234), is never issued.
//
//  ---------------------------------------------------------------------------
//  Where a maskable interrupt's vector comes from
//  ---------------------------------------------------------------------------
//  Not from the caller.  "If set, the uPD70616 will perform a pair of
//  back-to-back interrupt acknowledge cycles.  On the second interrupt
//  acknowledge cycle, an 8-bit interrupt vector is read from the external
//  uPD71059 Interrupt Controller and used as an offset into the System Base
//  Table" (p.3.237).  `ack_vector` asks for exactly that, and the two cycles
//  are made through the same data unit as everything else, with
//  BST_INTERRUPT_ACK on the status pins.  Their back-to-backness is not
//  arranged here: the status code has MRQ = 1, so v60_biu's own p.3.291 rule
//  puts the three TI states between them.
//
//  The vector that comes back is checked before it is used, because §8 makes
//  that a named exception rather than a diagnostic: "An invalid interrupt
//  exception occurs when an external interrupt controller supplies a system
//  base table vector in the range of 0 to 63.  These interrupt/exception
//  vectors are reserved for system use and attempted use will result in an
//  exception."  So a vector under 64 becomes the System Fault -- vector 4,
//  code 0400, and an exception's frame rather than an interrupt's, which is
//  what Figure 8-5 draws for it: "#4 System Fault / Invalid Interrupt, +8
//  Exception Code | 4, +4 PSW, 0 PC".  That substitution is made here rather
//  than in the sequencer because the vector never leaves this module: it is
//  read, checked and used between two of its own bus accesses.
//
//  ---------------------------------------------------------------------------
//  Which stack, when the frame is not an interrupt's
//  ---------------------------------------------------------------------------
//  Step (vii) of the recognition sequence says interrupt -> IS and exception
//  -> L0SP, and §8's prose overrides it for two whole groups: the serious
//  system faults' "exception information is pushed onto the interrupt stack",
//  and the system faults' "exception information is pushed on the interrupt
//  stack".  Both are exceptions and neither goes on the level stack.  So
//  `int_stack` says which stack independently of `is_interrupt`; the caller
//  drives it, and PSW.IS is set for either.
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

    // The exception code, which shares its word with the parameter count --
    // see the header.  Ignored for an interrupt, whose frame has no such word.
    input        [15:0] code,

    input               is_interrupt,  // an interrupt, not an exception
    input               disable_ie,    // bus error / stack invalid (Note 2)
    input               int_stack,     // the frame goes on the interrupt stack
    // Take the vector off a pair of interrupt acknowledge cycles rather than
    // from `vector`.  Only meaningful with is_interrupt.
    input               ack_vector,

    output logic [31:0] sp_out,
    output logic [31:0] psw_out,
    output logic [31:0] handler_pc,
    output logic        busy,
    output logic        done,
    output logic  [3:0] bus_cycles,

    // Observable, for verification: what the interrupt controller supplied and
    // whether it was one of the 64 the processor reserves.
    output logic  [7:0] int_vector,
    output logic        invalid_int,

    // ---- data access unit --------------------------------------------------
    output logic        dx_req,
    output logic [23:0] dx_addr,
    output logic  [3:0] dx_nbytes,
    output logic        dx_we,
    output logic        dx_intack,
    output logic [63:0] dx_wdata,
    input        [63:0] dx_rdata,
    input               dx_done,
    input         [3:0] dx_cycles
);

typedef enum logic [3:0] {
    S_IDLE, S_VECTOR, S_PUSH, S_ISSUE, S_FIN,
    // A maskable interrupt's vector: the first acknowledge cycle, the gap that
    // gives the data unit a fresh request edge, the second acknowledge cycle
    // which is the one carrying the vector, and the gap before the SBT read.
    S_IACK1, S_IACK_GAP, S_IACK2, S_VEC_GAP
} state_e;

state_e      state;
logic  [1:0] pushes_left;   // parameter words still to push
logic  [1:0] np_r;          // and how many there were
logic [15:0] code_r;
logic  [1:0] phase;         // 0: parameters, 1: the PSW, 2: the return PC
logic [31:0] sp;
logic [31:0] p0, p1;
logic        int_r, dis_r, ist_r;

assign busy = (state != S_IDLE);

// An interrupt's frame is the PSW and the PC: Figure 8-3 draws it with nothing
// above them, so it has neither parameter words nor a code word, and asking
// for parameters cannot mean anything.  Taken once, so the count and the phase
// the pushes start in cannot disagree about it.
wire [1:0] np_eff = is_interrupt ? 2'd0 : nparams;

// The next word to push, in the order BRKV prints.
// Which word goes down next.  The parameters go in order -- param0 first --
// so the first push is the one where nothing has been pushed yet, `left ==
// count`, and not "left == 2": with a single parameter that test picked
// param1.  Phase 1 is the exception code word, which an interrupt does not
// have; phases 2 and 3 are the PSW and the return PC.
function automatic logic [31:0] push_word(input logic [1:0] ph,
                                          input logic [1:0] left,
                                          input logic [1:0] count,
                                          input logic [31:0] a,
                                          input logic [31:0] b,
                                          input logic [15:0] code_v,
                                          input logic [31:0] psw_v,
                                          input logic [31:0] pc_v);
    if (ph == 2'd0)      push_word = (left == count) ? a : b;
    // "4 x (parameters + 1)" -- the count includes this word.
    else if (ph == 2'd1) push_word = {code_v, 12'd0, count + 2'd1, 2'd0};
    else if (ph == 2'd2) push_word = psw_v;
    else                 push_word = pc_v;
endfunction

// The PSW the handler runs with.
function automatic logic [31:0] psw_upd(input logic [31:0] p,
                                        input logic        is_int,
                                        input logic        dis,
                                        input logic        on_ist);
    logic [31:0] r;
    begin
        // The eight step recognition sequence, which the DATABOOK prints with
        // every digit legible where the Programmer's Reference's copy of it
        // lost three of them to the scan (pp.3.269-3.270 against S8):
        //
        //   (i)   PSW.EL <- 00
        //   (ii)  interrupt: PSW.IE <- 0;  exception: unchanged
        //   (iii) PSW.TE <- 0 ; PSW.TP <- 0 ; PSW.AE <- 0
        //   (iv)  PSW.EM <- 0 (native mode)
        //   (v)   PSW.ASA <- 1
        //
        // A handler starts with tracing off, no trace pending, address traps
        // off, in native mode, and with asynchronous system traps held off --
        // "an asynchronous system trap will be disregarded while the PSW.ASA
        // field indicates an earlier AST is being serviced".
        r                        = p;
        r[PSW_EL_HI:PSW_EL_LO]   = 2'b00;              // execution level 0
        if (is_int || dis) r[PSW_IE] = 1'b0;           // and Note 2
        r[PSW_TE]                = 1'b0;
        r[PSW_TP]                = 1'b0;
        r[PSW_AE]                = 1'b0;
        r[PSW_EM]                = 1'b0;
        r[PSW_ASA]               = 1'b1;
        // DECISION, marked in the header: an interrupt is "saved on the
        // interrupt stack", and PSW.IS is what selects it.  A serious system
        // fault and a system fault go there too, by §8's prose rather than by
        // step (vii), and say so through `int_stack`.
        if (is_int || on_ist) r[PSW_IS] = 1'b1;
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
        code_r      <= 16'd0;
        phase       <= 2'd0;
        p0          <= 32'd0;
        p1          <= 32'd0;
        int_r       <= 1'b0;
        dis_r       <= 1'b0;
        ist_r       <= 1'b0;
        dx_intack   <= 1'b0;
        int_vector  <= 8'd0;
        invalid_int <= 1'b0;
    end else begin
        done <= 1'b0;

        case (state)
        S_IDLE: if (req) begin
            p0          <= param0;
            p1          <= param1;
            pushes_left <= np_eff;
            np_r        <= np_eff;
            int_r       <= is_interrupt;
            dis_r       <= disable_ie;
            ist_r       <= int_stack;
            sp          <= sp_in;
            bus_cycles  <= 4'd0;
            code_r      <= code;
            invalid_int <= 1'b0;
            int_vector  <= 8'd0;
            // With no parameter words the code word is first -- and with none
            // of either, which is an interrupt, the PSW is.
            if (np_eff != 2'd0)     phase <= 2'd0;
            else if (!is_interrupt) phase <= 2'd1;
            else                    phase <= 2'd2;

            if (is_interrupt && ack_vector) begin
                // "a pair of back-to-back interrupt acknowledge cycles".  One
                // byte each, because what comes back is "an 8-bit interrupt
                // vector"; the address is not on any page held here -- the
                // databook names the status code and says nothing about
                // A23-A0 during it -- so it is driven at zero and marked.
                dx_addr   <= 24'd0;
                dx_nbytes <= 4'd1;
                dx_we     <= 1'b0;
                dx_intack <= 1'b1;
                dx_req    <= 1'b1;
                state     <= S_IACK1;
            end else begin
                // The vector first: SBR + 4 x vector, a 32-bit read.
                dx_addr   <= sbr[23:0] + {14'd0, vector, 2'b00};
                dx_nbytes <= 4'd4;
                dx_we     <= 1'b0;
                dx_req    <= 1'b1;
                state     <= S_VECTOR;
            end
        end

        // The first acknowledge cycle carries no vector -- the page puts it on
        // the second -- so this one is made and its data dropped.
        S_IACK1: if (dx_done) begin
            bus_cycles <= bus_cycles + dx_cycles;
            dx_req     <= 1'b0;
            state      <= S_IACK_GAP;
        end

        S_IACK_GAP: begin
            dx_addr   <= 24'd0;
            dx_nbytes <= 4'd1;
            dx_we     <= 1'b0;
            dx_intack <= 1'b1;
            dx_req    <= 1'b1;
            state     <= S_IACK2;
        end

        S_IACK2: if (dx_done) begin
            bus_cycles <= bus_cycles + dx_cycles;
            dx_req     <= 1'b0;
            dx_intack  <= 1'b0;
            int_vector <= dx_rdata[7:0];

            if (dx_rdata[7:0] < 8'd64) begin
                // The Invalid Interrupt: a System Fault, and an EXCEPTION's
                // frame -- vector 4 with the code word Figure 8-5 gives it.
                // Its information still goes on the interrupt stack, which
                // `ist_r` already says, and it disables interrupts.
                invalid_int <= 1'b1;
                code_r      <= 16'h0400;
                int_r       <= 1'b0;
                dis_r       <= 1'b1;
                pushes_left <= 2'd0;
                np_r        <= 2'd0;
                phase       <= 2'd1;      // the code word, then PSW, then PC
                dx_addr     <= sbr[23:0] + {14'd0, 8'd4, 2'b00};
            end else begin
                dx_addr <= sbr[23:0] + {14'd0, dx_rdata[7:0], 2'b00};
            end
            state <= S_VEC_GAP;
        end

        S_VEC_GAP: begin
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
                                           code_r, psw_in, ret_pc)};
            dx_req    <= 1'b1;
            sp        <= sp - 32'd4;
            state     <= S_PUSH;
        end

        S_PUSH: if (dx_done) begin
            bus_cycles <= bus_cycles + dx_cycles;
            dx_req     <= 1'b0;

            if (phase == 2'd0) begin
                pushes_left <= pushes_left - 2'd1;
                // The code word next, unless this is an interrupt, whose frame
                // is the PSW and the PC and nothing else.
                // Only an exception has parameter words, so the code word is
                // always what follows them.
                if (pushes_left == 2'd1) phase <= 2'd1;
                state <= S_ISSUE;
            end else if (phase != 2'd3) begin
                phase <= phase + 2'd1;
                state <= S_ISSUE;
            end else begin
                state <= S_FIN;
            end
        end

        S_FIN: begin
            // "transferred to the ... vector at execution level 0", and for an
            // interrupt "further maskable interrupts will be disabled".
            psw_out <= psw_upd(psw_in, int_r, dis_r, ist_r);
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
    if (!rst && req && is_interrupt && (nparams != 2'd0))
        $display("WARN v60_exc: an interrupt asked for %0d parameter words -- Figure 8-3's interrupt frame is the PSW and the PC (t=%0t)",
                 nparams, $time);
end

always_ff @(posedge clk) begin
    if (!rst && req && (sbr[11:0] != 12'd0))
        $display("WARN v60_exc: SBR %h is not page aligned -- 'the twelve low order bits' must be zero (t=%0t)",
                 sbr, $time);
    // Only for a vector the caller supplied.  One that comes off the
    // acknowledge cycles is not a diagnostic: §8 makes it the Invalid
    // Interrupt exception, and the S_IACK2 branch raises it.
    if (!rst && req && is_interrupt && !ack_vector && (vector < 8'd64))
        $display("WARN v60_exc: interrupt on vector %0d, which is one of the 64 the processor reserves (t=%0t)",
                 vector, $time);
end
// synthesis translate_on

endmodule
