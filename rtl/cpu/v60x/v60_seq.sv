//============================================================================
//  v60_seq -- an instruction, executed.
//
//  The join.  Everything below this has existed for a while and none of it was
//  wired together: v60_idu describes an instruction's operands, v60_ea can
//  resolve one, v60_regfile holds what they name, v60_alu combines them.  This
//  sequences them, and retires the result.
//
//      fetch -> operand 1 -> operand 2 -> execute -> write back -> retire
//
//  and a second path beside it for the control transfers, which have no ALU
//  operation and end by redirecting the prefetch unit rather than by writing a
//  result:
//
//      fetch -> condition / target -> (push or pop) -> redirect
//
//  What is on a page, and where:
//
//    * The operand order.  The Programmer's Reference's syntax lines are
//      "src, dst" -- "add.b src.b.r, dst.b.rw" -- so operand 1 is the source
//      and operand 2 is the destination, read and written.  CMP's operation,
//      "src2 - src1", is the same statement from the other end: the ALU's
//      second input is the destination operand.
//    * Which PC.  "The PC ... contains the memory address of the first byte of
//      the instruction currently being executed" (S3), which is v60_idu's
//      insn_pc, and it is what a PC-relative operand is relative to.
//    * The next PC is this one plus the instruction's length, which v60_idu
//      measures rather than assumes.
//    * What a branch displacement is measured from: "the value of the PC used
//      to compute the target address is the first byte of the branch
//      instruction" (Bcc, S7) -- the same PC as above, not the next one.
//    * The stack operations are addressing modes, not a separate mechanism:
//      BSR's "[-SP] <- NextPC" and RSR's "PC <- [SP+]" are the autodecrement
//      and autoincrement modes on R31, so they go through v60_ea like any
//      other operand and cost what the page's operand-access counts say.
//    * JMP and JSR take the effective ADDRESS of their operand, not its
//      contents, and "the destination operand is treated as byte data for the
//      purpose of computing pointer changes" (S7) -- hence one byte.
//    * DBcc's condition is four bits split across the encoding: the low one is
//      the opcode's bit 0 and the other three are the Format VI subop.  TB
//      occupies the subop that would spell the never-taken condition, which is
//      why the two share opcode C7.
//
//  ---------------------------------------------------------------------------
//  Format I's `d` bit: the one thing here that is not from a document
//  ---------------------------------------------------------------------------
//  Format I has one mod field and one `reg` field, and `d` says which of them
//  is the source.  No page held by this project states its polarity: p.3.293's
//  legend gives only "d : direction field", and the Programmer's Reference's
//  Appendix B reprints the same figure with no legend at all.
//
//  It is taken from MAME's V60 core, which this project's README already
//  admits as an architectural oracle for execution semantics, by way of the
//  Sega System 32 core's s32_v60.sv (whose header cites optable.hxx and
//  am1-3.hxx).  There, at s32_v60.sv:1864 and :1948:
//
//      d = 1  ->  "op2 = reg, op1 = AM"       the mod field is the source
//      d = 0  ->  "op1 = reg value, op2 = AM" the register is the source
//
//  Three things make it believable.  It is the only thing a one-bit direction
//  field can do in a format with exactly one register and one mod field -- an
//  assembler must be able to write both `add.b R1,[R2]` and `add.b [R2],R1`,
//  and nothing else in the encoding separates them.  The field extraction
//  around it in that core matches p.3.293 bit for bit, so the transcription it
//  sits in is faithful.  And both polarities are exercised by shipping code:
//  that file carries a bug note for the d=0 path mishandling XCH, traced to
//  `xch.w R19,R20` at 0x063BEB in Golden Axe 2.
//
//  Beware the naming: MAME calls the two-mod-field form F1 and this one F2,
//  which is the opposite way round from the databook's Format I and II.
//
//  ---------------------------------------------------------------------------
//  Exceptions
//  ---------------------------------------------------------------------------
//  Three of Table 8-1's Instruction Exceptions are raised here rather than
//  stopping: a reserved opcode, a reserved addressing mode and an immediate
//  used as a destination.  v60_exc does the taking -- the vector read, the
//  frame, the PSW -- and reaches the data access unit through v60_dmux, which
//  is a mux and not a third bus master because an exception is raised between
//  operand accesses and never during one.
//
//  One thing about that path is NOT observable from this module's bench, and
//  is recorded rather than left to be assumed: the PSW the handler runs with.
//  v60_exc computes it (execution level 0, and the interrupt rules), and this
//  sequencer runs at execution level 0 already, so for these three exceptions
//  the handler's PSW equals the faulting one and a sequencer that failed to
//  take the new PSW would behave identically.  tb_v60_exc holds that claim
//  instead: it drives execution level 3 and checks what comes back.  Nothing
//  reachable from reset in this tree sets the execution level to anything
//  else -- there is no LDPSW, no task switch, and RETIU/RETIS are not here.
//
//  ---------------------------------------------------------------------------
//  The three externally raised conditions
//  ---------------------------------------------------------------------------
//  v60_biu has the pins; this has the recognition point.  All three are taken
//  where the instruction exceptions already are, and all three put their frame
//  on the INTERRUPT stack -- an interrupt by step (vii) of the recognition
//  sequence, a bus fault and a system fault by §8's prose, which says of both
//  groups that "the exception information is pushed onto the interrupt stack".
//
//    NMI*  -- vector 2 (Figure 8-2's +8, and the databook's own vector column
//             at p.3.270).  "At the completion of the current instruction, the
//             PC and PSW are pushed" (p.3.237), so it is recognised in S_IDLE
//             and its frame is Figure 8-5's "#2 Non-Maskable Interrupt: PSW,
//             PC (Next PC)" -- which is `pc`, because S_RETIRE has already
//             advanced it.
//
//    INT   -- masked by PSW.IE, and the vector is not this module's to choose:
//             it comes off a pair of interrupt acknowledge cycles, which
//             v60_exc makes.  Holding it off while PSW.IE is clear is the
//             whole of "any interrupt requests are held pending until unmasked
//             by software" (p.3.237), because the pin is a level the source
//             holds until it is acknowledged.
//
//    BERR* -- vector 3, the Serious System Fault.  Figure 8-5's "#3 Bus Fault"
//             frame is the only one in this tree with a parameter word above
//             the code: "+12 Exception Address, +8 Exception Code | 8, +4 PSW,
//             0 PC", and the note under it says the exception address is a
//             physical address -- which is the failed cycle's A23-A0.  The
//             code is one of the thirteen in the 0300-031E group and says
//             which KIND of cycle failed, so it is decoded from the status the
//             bus interface unit reports with the fault.
//
//  Two things about the bus fault are marked rather than assumed.  It is
//  recognised at the first access completion after the fault, which is where
//  the sequencer can abandon the instruction cleanly -- the faulting
//  instruction does not retire, and its addressing-mode writeback is dropped
//  with it -- but a read-modify-write whose read had already completed still
//  closes with its write, one bus cycle later.  And the double bus error is
//  not modelled: §8 says the processor halts, and nothing here halts.
//
//  ---------------------------------------------------------------------------
//  What this does not do
//  ---------------------------------------------------------------------------
//  * Anything v60_alu does not implement: the multiplies and divides, the
//    shifts and rotates, and every instruction outside the integer set.  The
//    generated table says which by returning ALU_NONE, and this stops on it
//    rather than doing something arbitrary.
//  * CALL and RET, which pass the argument pointer: "tmp2 <- [SP+] ; AP <-
//    [SP+] ; SP <- SP + tmp1" (RET, S7).  They are each other's partner and
//    neither is here; BSR and JSR pair with RSR, which is.
//  * RETIU and RETIS, which restore the PSW as well as the PC, and belong with
//    v60_exc when it is wired in.
//  * The exceptions that need machinery this tree does not have: no MMU, so no
//    page fault; no trace or breakpoint; no address traps; no coprocessor.
//  * Two addressing-mode register writebacks in one instruction -- `mov.w
//    [R1+], [R2+]` -- which needs two retirement slots and has one.  This
//    stops with STOP_TWO_WB rather than dropping one of them silently.
//============================================================================
`timescale 1ns/1ps

module v60_seq
    import v60_bus_pkg::*;
    import v60_fmt_pkg::*;
    import v60_op_pkg::*;
    import v60_am_pkg::*;
    import v60_alu_pkg::*;
    import v60_psw_pkg::*;
(
    input               clk,
    input               rst,

    input               run,            // execute instructions while high

    // ---- the instruction stream, from v60_idu ------------------------------
    output logic        idu_start,
    input               idu_done,
    input  insn_fmt_e   idu_fmt,
    input         [7:0] idu_op,
    input        [31:0] idu_pc,
    input         [4:0] idu_len,
    input               idu_d,          // Format I's direction bit
    input         [4:0] idu_reg,        // Format I's register operand
    input         [4:0] idu_subop,
    input        [31:0] idu_disp,       // Format IV / VI displacement
    input               idu_res_op,
    input               idu_res_mode,

    input               op1_valid,
    input  am_mode_e    op1_mode,
    input         [4:0] op1_rn,
    input         [4:0] op1_rx,
    input               op1_index,
    input        [31:0] op1_disp,
    input        [31:0] op1_disp_outer,
    input        [63:0] op1_imm,
    input         [3:0] op1_bytes,

    input               op2_valid,
    input  am_mode_e    op2_mode,
    input         [4:0] op2_rn,
    input         [4:0] op2_rx,
    input               op2_index,
    input        [31:0] op2_disp,
    input        [31:0] op2_disp_outer,
    input        [63:0] op2_imm,
    input         [3:0] op2_bytes,

    // ---- the register file --------------------------------------------------
    output logic  [4:0] rf_ra_sel,
    output logic  [4:0] rf_rb_sel,
    input        [31:0] rf_ra,
    input        [31:0] rf_rb,
    output logic        rf_wr_en,
    output logic  [4:0] rf_wr_sel,
    output logic [31:0] rf_wr_data,

    // ---- the address unit ----------------------------------------------------
    output logic        ea_start,
    output am_mode_e    ea_mode,
    output logic        ea_index,
    output logic [31:0] ea_disp,
    output logic [31:0] ea_disp_outer,
    output logic [63:0] ea_imm,
    output logic [31:0] ea_rn_val,
    output logic [31:0] ea_rx_val,
    output logic [31:0] ea_pc_val,
    output logic  [3:0] ea_opbytes,
    output logic        ea_we,
    output logic [63:0] ea_wdata,
    output logic        ea_addr_only,
    output logic        ea_rmw,
    output logic        ea_rmw_go,
    output logic [63:0] ea_rmw_data,
    input               ea_rmw_pending,
    input        [31:0] ea_ea,
    input        [63:0] ea_rdata,
    input               ea_rn_wb,
    input        [31:0] ea_rn_wb_val,
    input               ea_done,
    input         [3:0] ea_bus_cycles,

    // ---- the exception unit --------------------------------------------------
    // Raised between instructions, never during an operand access, which is
    // what lets v60_dmux be a mux rather than a third bus master.
    input        [31:0] sbr,            // from the register file
    output logic        exc_req,
    output logic  [7:0] exc_vector,
    output logic [31:0] exc_ret_pc,
    output logic [31:0] exc_psw_in,
    output logic [31:0] exc_sp_in,
    output logic [31:0] exc_sbr,
    output logic  [1:0] exc_nparams,
    output logic [15:0] exc_code,
    output logic [31:0] exc_param0,
    output logic [31:0] exc_param1,
    output logic        exc_is_interrupt,
    output logic        exc_disable_ie,
    output logic        exc_int_stack,
    output logic        exc_ack_vector,
    input        [31:0] exc_sp_out,
    input        [31:0] exc_psw_out,
    input        [31:0] exc_handler_pc,
    input               exc_done,
    input         [3:0] exc_bus_cycles,

    // The stack the frame goes on is the one the NEW execution level names:
    // "the PC and PSW are saved on the interrupt stack" (PgmRef S8), so the
    // register file switches R31 before v60_exc pushes anything.
    output logic        rf_stack_switch,
    output logic  [1:0] rf_new_el,
    output logic        rf_new_is,

    // ---- the externally raised conditions, from v60_biu -----------------------
    input               nmi_pending,    // latched NMI*, held until taken
    output logic        nmi_take,
    input               int_pending,    // the INT level, masked here by PSW.IE
    input               berr,           // one pulse: a bus cycle faulted
    input  bus_status_e berr_status,    // which kind of cycle it was
    input        [23:0] berr_addr,      // and its physical address
    input               berr_we,

    // ---- control transfers ---------------------------------------------------
    // A taken branch flushes the prefetch queue and refills it from the target
    // -- "in the event of a control transfer ... the instruction queue contents
    // are flushed and a demand mode instruction fetch is made" (p.3.246).
    output logic        redirect,
    output logic [31:0] redirect_pc,

    // ---- state ---------------------------------------------------------------
    output logic [31:0] pc,             // the architectural PC
    output logic [31:0] psw,
    output logic        retired,        // one pulse per instruction
    output logic  [4:0] insn_cycles,    // bus cycles the operands cost
    output logic        stopped,        // hit something it cannot execute
    // Why, because the three are different things and a machine with an
    // exception unit would raise a different vector for each: a reserved
    // opcode or addressing mode is an exception (Table 8-1 codes 1000 and
    // 1200), an operation v60_alu does not implement is this project's own
    // boundary, and a format whose semantics are not documented is another.
    output logic  [1:0] stop_reason
);

// The exception vectors this stage can raise, from Figure 8-2's offsets --
// the entry is at SBR + 4 x vector, so the vector is the printed offset over
// four -- and the codes from the exception-code table in the same section:
//
//    +64  Reserved Opcode Exception          vector 16   code 1000
//    +72  Reserved Addressing Mode           vector 18   code 1200
//    +76  Illegal Addressing Mode            vector 19   code 1300
//
// All three are Instruction Exceptions, whose frame the same table gives as
// "+8 Exception Code / +4 PSW / PC (Current PC)" with a parameter count of 4 --
// one parameter word, and the return PC is the faulting instruction's own.
localparam logic [7:0] VEC_RESERVED_OP   = 8'd16;
localparam logic [7:0] VEC_RESERVED_MODE = 8'd18;
localparam logic [7:0] VEC_ILLEGAL_MODE  = 8'd19;
localparam logic [15:0] CODE_RESERVED_OP   = 16'h1000;
localparam logic [15:0] CODE_RESERVED_MODE = 16'h1200;
localparam logic [15:0] CODE_ILLEGAL_MODE  = 16'h1300;

// The two externally raised vectors this module names.  A maskable interrupt's
// is not here because it is not chosen here -- it comes off the acknowledge
// cycles.  Both read off the low end of the system base table, which is the
// part of Figure 8-2 whose OCR cannot be trusted in either book: taken from
// the databook's plate at p.3.270, where the vector NUMBER is printed in its
// own column beside the offset, and cross-checked against the Programmer's
// Reference's Figure 8-2, which prints the same two rows as offsets +8 and
// +12.
//
//    +8   Non-Maskable Interrupt    vector 2
//    +12  Serious System Fault      vector 3   -- the bus fault
localparam logic [7:0] VEC_NMI       = 8'd2;
localparam logic [7:0] VEC_BUS_FAULT = 8'd3;

// Which exception is being raised, which decides the frame rather than the
// vector: an interrupt has no code word, a bus fault has a parameter above
// one, and the three instruction exceptions have neither.
localparam logic [1:0] EK_INSN = 2'd0;
localparam logic [1:0] EK_BERR = 2'd1;
localparam logic [1:0] EK_INT  = 2'd2;

// Table 8-1's Serious System Exceptions, all thirteen, keyed by the bus status
// of the cycle that failed and its direction.  The group is one code per KIND
// of cycle, which is exactly what MRQ + ST2-ST0 already says, so the mapping is
// the two tables laid against each other rather than a choice:
//
//   0301 string data write     0311 string data read     0317 instruction fetch
//   0303 fixed length write    0313 fixed length read    0319 string I/O read
//   0305 translation write     0314 system base table    031B fixed length I/O
//   0309 string I/O write      0315 translation read     031E interrupt vector
//   030B fixed length I/O write
//
// A short path access "is substituted for a single mode data access" (p.3.233),
// so it is a fixed length data access and takes its codes.  There is no system
// base table WRITE code, and nothing writes one.
function automatic logic [15:0] berr_code(input bus_status_e st_in,
                                          input logic       wr);
    case (st_in)
        BST_MEM_STRING:                     berr_code = wr ? 16'h0301 : 16'h0311;
        BST_MEM_SHORT_PATH, BST_MEM_SINGLE: berr_code = wr ? 16'h0303 : 16'h0313;
        BST_TRANS_TABLE:                    berr_code = wr ? 16'h0305 : 16'h0315;
        BST_SYS_BASE_TABLE:                 berr_code = 16'h0314;
        BST_IO_STRING:                      berr_code = wr ? 16'h0309 : 16'h0319;
        BST_IO_SINGLE:                      berr_code = wr ? 16'h030B : 16'h031B;
        BST_DEMAND_FETCH, BST_PREFETCH:     berr_code = 16'h0317;
        BST_INTERRUPT_ACK:                  berr_code = 16'h031E;
        // The four reserved codes and the two acknowledge statuses are not
        // cycles this processor issues, so a fault on one is reported as the
        // ordinary data access it cannot be.
        default:                            berr_code = wr ? 16'h0303 : 16'h0313;
    endcase
endfunction

// A reserved opcode or addressing mode used to stop here.  It is an
// exception now -- vectors 16 and 18, Figure 8-2 -- so what is left are the
// three things this sequencer cannot do rather than the ones the architecture
// says are wrong.
localparam logic [1:0] STOP_NO_ALU   = 2'd0;   // not an operation v60_alu has
localparam logic [1:0] STOP_FORMAT   = 2'd1;   // not a format this executes
localparam logic [1:0] STOP_TWO_WB   = 2'd2;   // two addressing-mode writebacks

typedef enum logic [4:0] {
    S_IDLE, S_FETCH,
    S_OP1, S_OP1R, S_OP1S, S_OP1W,     // describe, read registers, start, wait
    S_OP2, S_OP2R, S_OP2S, S_OP2W,
    S_EXEC, S_WB, S_WBW, S_RETIRE, S_STOP,
    // The control transfers: a register to test, an address to compute, a
    // stack access to make, and then the redirect.
    S_CTRL, S_CTRL_REG, S_CTRL_EAR, S_CTRL_EAS, S_CTRL_EAW, S_CTRL_FIN,

    // an exception: switch the stack, let the switch land, take it, then run
    // the handler
    S_EXC_SW, S_EXC_SETTLE, S_EXC_REQ, S_EXC_W
} state_e;

state_e      state;
logic [63:0] val1, val2;
alu_op_e     aop;
ctrl_op_e    cop;
logic [31:0] target;        // where a control transfer is going
logic        taken;
logic        cpush;         // the stack access after JSR's address
logic [31:0] next_pc;
logic [31:0] wb_rn_val;
logic        wb_rn_en;
logic  [4:0] wb_rn_sel;
logic  [4:0] ea_rn_sel;   // whose Rn the running access will move
logic  [7:0] exc_vec_r;   // the exception being raised, and its code
logic [15:0] exc_code_r;
logic  [1:0] exc_kind;    // which of the three shapes of frame it wants
logic        exc_ack_r;   // and whether its vector comes off the bus
logic        berr_r;      // a bus fault is outstanding
logic [23:0] berr_addr_r; // where it happened -- the frame's parameter word
logic [15:0] berr_code_r;

// ---------------------------------------------------------------------------
// Which operand is the source and which the destination.
// ---------------------------------------------------------------------------
// Format II has two mod fields and the syntax order settles it: operand 1 is
// the source, operand 2 the destination.  Format I has one mod field and one
// register, and `d` says which way round they go -- see the header.
wire fmt_i  = (idu_fmt == FMT_I);
wire fmt_ii = (idu_fmt == FMT_II);

wire        src_is_reg  = fmt_i && !idu_d;   // d = 0: the register is the source
wire        dst_is_reg  = (fmt_i &&  idu_d) ||          // d = 1: it is the dest
                          (fmt_ii && (op2_mode == AM_RN));
wire  [4:0] reg_operand = fmt_i ? idu_reg : op2_rn;

// The mod field that is NOT the register operand.  Format I has only one, and
// it is whichever side `d` did not take.
wire        dst_am_is_op2 = fmt_ii;

// The destination operand's addressing mode.  Spelled out rather than
// selected with a ternary: a ternary between two enum values is not an enum to
// every tool.
am_mode_e    dst_mode;
always_comb begin
    if (dst_am_is_op2) dst_mode = op2_mode;
    else               dst_mode = op1_mode;
end


// The operand widths are the instruction's, not the addressing mode's, so they
// come straight from the table rather than from whichever mod field decoded.
wire [3:0] w_src = op_data_bytes(idu_op, idu_subop, 1'b0);
wire [3:0] w_dst = op_data_bytes(idu_op, idu_subop, 1'b1);

// The ALU is combinational; its inputs are the two operand values.
wire  [3:0] alu_flags;
wire [31:0] alu_result;
wire        alu_writes;

wire [3:0] alu_bytes = ((w_dst == 4'd1) || (w_dst == 4'd2) ||
                        (w_dst == 4'd4)) ? w_dst : 4'd4;
// The source's width, which only the extending moves read.
wire [3:0] alu_xbytes = ((w_src == 4'd1) || (w_src == 4'd2) ||
                         (w_src == 4'd4)) ? w_src : 4'd4;

v60_alu alu (
    .op(aop), .opbytes(alu_bytes), .xbytes(alu_xbytes),
    .x(val1[31:0]), .y(val2[31:0]), .flags_in(psw_flags(psw)),
    .result(alu_result), .flags_out(alu_flags), .writes(alu_writes)
);


always_ff @(posedge clk) begin
    if (rst) begin
        state         <= S_IDLE;
        idu_start     <= 1'b0;
        ea_start      <= 1'b0;
        ea_rmw_go     <= 1'b0;
        rf_wr_en      <= 1'b0;
        pc            <= 32'd0;
        psw           <= PSW_RESET;
        retired       <= 1'b0;
        insn_cycles   <= 5'd0;
        stopped       <= 1'b0;
        stop_reason   <= STOP_NO_ALU;
        redirect      <= 1'b0;
        redirect_pc   <= 32'd0;
        exc_req         <= 1'b0;
        exc_vector      <= 8'd0;
        exc_ret_pc      <= 32'd0;
        exc_psw_in      <= 32'd0;
        exc_sp_in       <= 32'd0;
        exc_sbr         <= 32'd0;
        exc_nparams     <= 2'd0;
        exc_code        <= 16'd0;
        exc_param0      <= 32'd0;
        exc_param1      <= 32'd0;
        exc_is_interrupt<= 1'b0;
        exc_disable_ie  <= 1'b0;
        exc_int_stack   <= 1'b0;
        exc_ack_vector  <= 1'b0;
        exc_kind        <= EK_INSN;
        exc_ack_r       <= 1'b0;
        nmi_take        <= 1'b0;
        berr_r          <= 1'b0;
        berr_addr_r     <= 24'd0;
        berr_code_r     <= 16'd0;
        rf_stack_switch <= 1'b0;
        rf_new_el       <= 2'd0;
        rf_new_is       <= 1'b0;
        exc_vec_r       <= 8'd0;
        exc_code_r      <= 16'd0;
        cop           <= CTRL_NONE;
        target        <= 32'd0;
        taken         <= 1'b0;
        cpush         <= 1'b0;
        next_pc       <= 32'd0;
        ea_addr_only  <= 1'b0;
        val1          <= 64'd0;
        val2          <= 64'd0;
        aop           <= ALU_NONE;
        wb_rn_en      <= 1'b0;
        wb_rn_sel     <= 5'd0;
        ea_rn_sel     <= 5'd0;
        wb_rn_val     <= 32'd0;
    end else begin
        idu_start <= 1'b0;
        ea_start  <= 1'b0;
        ea_rmw_go <= 1'b0;
        rf_wr_en  <= 1'b0;
        retired   <= 1'b0;
        redirect  <= 1'b0;
        exc_req         <= 1'b0;
        rf_stack_switch <= 1'b0;
        nmi_take        <= 1'b0;

        // A bus fault is latched wherever it happens -- a prefetch's cycle is
        // not one this sequencer is waiting on -- and kept until it is raised.
        // The first one wins: a second before the first is taken is the double
        // bus error §8 halts on, and this does not halt.
        if (berr && !berr_r) begin
            berr_r      <= 1'b1;
            berr_addr_r <= berr_addr;
            berr_code_r <= berr_code(berr_status, berr_we);
        end

        // An addressing mode's register writeback -- the Rn that [Rn+] or
        // [-Rn] moved -- is a single cycle pulse, and v60_ea raises it when
        // the access STARTS, not when it finishes.  Taking it here rather than
        // in whichever state happens to be waiting is what makes it survive an
        // access that reaches memory: those finish several cycles later.
        if (ea_rn_wb) begin
            if (wb_rn_en && (wb_rn_sel != ea_rn_sel)) begin
                // Two operands in autoincrement or autodecrement modes, and
                // one slot to retire them from.  Stopping is not the V60's
                // behaviour; it is this sequencer refusing to drop one
                // silently.  See rtl/cpu/v60x/README.md.
                stopped     <= 1'b1;
                stop_reason <= STOP_TWO_WB;
                state       <= S_STOP;
            end
            wb_rn_en  <= 1'b1;
            wb_rn_sel <= ea_rn_sel;
            wb_rn_val <= ea_rn_wb_val;
        end

        case (state)
        // The recognition point.  "At the completion of the current
        // instruction" (NMI, p.3.237) is here, which is also where the three
        // instruction exceptions are raised from -- so an externally raised
        // one is taken instead of starting the next instruction, and the
        // frame's PC is the one that has not run yet.  The order is Figure
        // 8-2's: the bus fault is nearer the bottom of the table than the two
        // interrupts, and a machine that took an interrupt while a fault was
        // outstanding would run a handler on a broken bus.
        S_IDLE: if (run && !stopped) begin
            insn_cycles <= 5'd0;
            wb_rn_en    <= 1'b0;

            if (berr_r) begin
                exc_kind  <= EK_BERR;
                exc_vec_r <= VEC_BUS_FAULT;
                state     <= S_EXC_SW;
            end else if (nmi_pending) begin
                exc_kind  <= EK_INT;
                exc_vec_r <= VEC_NMI;
                exc_ack_r <= 1'b0;
                // The pin is an event and v60_biu holds it; taking it here is
                // what releases it.
                nmi_take  <= 1'b1;
                state     <= S_EXC_SW;
            end else if (int_pending && psw[PSW_IE]) begin
                // "can be masked by the IE bit in the PSW register.  If the IE
                // bit is cleared, the INT input is masked and any interrupt
                // requests are held pending until unmasked by software" --
                // which needs nothing held here, because INT "must be asserted
                // until acknowledged".  The vector is the controller's, so
                // this asks v60_exc for the acknowledge cycles rather than
                // naming one.
                exc_kind  <= EK_INT;
                exc_vec_r <= 8'd0;
                exc_ack_r <= 1'b1;
                state     <= S_EXC_SW;
            end else begin
                idu_start <= 1'b1;
                state     <= S_FETCH;
            end
        end

        S_FETCH: if (idu_done) begin
            // A fault on this instruction's own fetch.  The decode is let
            // finish -- v60_idu takes `start` only from its idle state, so
            // abandoning it mid-instruction would drop the next `idu_start`
            // and hang -- and the instruction is then not executed.
            if (berr_r) begin
                exc_kind  <= EK_BERR;
                exc_vec_r <= VEC_BUS_FAULT;
                state     <= S_EXC_SW;
            end else begin
            pc      <= idu_pc;
            aop     <= op_alu(idu_op);
            cop     <= op_ctrl(idu_op);
            cpush   <= 1'b0;
            taken   <= 1'b0;
            next_pc <= idu_pc + {27'd0, idu_len};

            if (idu_res_op || idu_res_mode) begin
                // Two different exceptions, which is why v60_idu reports them
                // separately: Figure 8-2 gives the reserved opcode and the
                // reserved addressing mode different entries.
                if (idu_res_op) begin
                    exc_vec_r  <= VEC_RESERVED_OP;
                    exc_code_r <= CODE_RESERVED_OP;
                end else begin
                    exc_vec_r  <= VEC_RESERVED_MODE;
                    exc_code_r <= CODE_RESERVED_MODE;
                end
                exc_kind <= EK_INSN;
                state    <= S_EXC_SW;
            end else if (op_ctrl(idu_op) != CTRL_NONE) begin
                state <= S_CTRL;
            end else if (op_alu(idu_op) == ALU_NONE) begin
                // Decoded and addressed, but not one of the operations
                // v60_alu implements.
                stopped     <= 1'b1;
                stop_reason <= STOP_NO_ALU;
                state       <= S_STOP;
            end else if ((idu_fmt != FMT_II) && (idu_fmt != FMT_I)) begin
                // Formats III to VII: not sequenced here.
                stopped     <= 1'b1;
                stop_reason <= STOP_FORMAT;
                state       <= S_STOP;
            end else begin
                state <= S_OP1;
            end
            end
        end

        // ---- the source ------------------------------------------------------
        S_OP1: begin
            if (src_is_reg) begin
                // Format I with d = 0: the source is the register field.
                rf_ra_sel <= reg_operand;
                state     <= S_OP1R;
            end else begin
                rf_ra_sel     <= op1_rn;
                rf_rb_sel     <= op1_rx;
                ea_rn_sel     <= op1_rn;
                ea_mode       <= op1_mode;
                ea_index      <= op1_index;
                ea_disp       <= op1_disp;
                ea_disp_outer <= op1_disp_outer;
                ea_imm        <= op1_imm;
                ea_opbytes    <= w_src;
                ea_we         <= 1'b0;
                ea_rmw        <= 1'b0;
                ea_pc_val     <= idu_pc;
                state         <= S_OP1R;
            end
        end

        // The register file's outputs are valid the cycle after its selects,
        // and v60_ea samples its inputs on the cycle `start` is high, so the
        // values are presented first and the start comes after.
        S_OP1R: begin
            ea_rn_val <= rf_ra;
            ea_rx_val <= rf_rb;
            if (src_is_reg) begin
                val1  <= {32'd0, rf_ra};
                state <= S_OP2;
            end else begin
                state <= S_OP1S;
            end
        end

        S_OP1S: begin
            ea_start <= 1'b1;
            state    <= S_OP1W;
        end

        S_OP1W: begin
            if (ea_done) begin
                insn_cycles <= insn_cycles + {1'b0, ea_bus_cycles};
                if (berr_r) begin
                // Abandoned: a bus cycle of this access failed, so the
                // instruction does not retire and its writeback is dropped.
                exc_kind  <= EK_BERR;
                exc_vec_r <= VEC_BUS_FAULT;
                state     <= S_EXC_SW;
                end else begin
                    val1  <= ea_rdata;
                    state <= S_OP2;
                end
            end
        end

        // ---- the destination, read as well when the operation needs its old
        // ---- value.
        S_OP2: begin
            // "An illegal addressing mode exception occurs when a valid
            // addressing mode is used improperly.  An example ... is an
            // attempt to use an immediate addressing mode as the destination
            // operand" (PgmRef S8).  It is caught here, from the mode, rather
            // than from v60_ea's own `illegal`: the read of a read-modify-write
            // destination is not a write, so the address unit does not see one
            // coming, and an access that must not happen is better not started.
            if (!dst_is_reg && am_is_immediate(dst_mode)) begin
                exc_vec_r  <= VEC_ILLEGAL_MODE;
                exc_code_r <= CODE_ILLEGAL_MODE;
                exc_kind   <= EK_INSN;
                state      <= S_EXC_SW;
            end else if (dst_is_reg) begin
                // A register destination needs no address and no bus cycle:
                // its old value is read here and the result is written to the
                // file at retirement.
                rf_ra_sel <= reg_operand;
                state     <= S_OP2R;
            end else begin
                rf_ra_sel     <= dst_am_is_op2 ? op2_rn    : op1_rn;
                ea_rn_sel     <= dst_am_is_op2 ? op2_rn    : op1_rn;
                rf_rb_sel     <= dst_am_is_op2 ? op2_rx    : op1_rx;
                ea_mode       <= dst_mode;
                ea_index      <= dst_am_is_op2 ? op2_index : op1_index;
                ea_disp       <= dst_am_is_op2 ? op2_disp  : op1_disp;
                ea_disp_outer <= dst_am_is_op2 ? op2_disp_outer : op1_disp_outer;
                ea_imm        <= dst_am_is_op2 ? op2_imm   : op1_imm;
                ea_opbytes    <= w_dst;
                ea_we         <= 1'b0;
                // Everything except MOV reads its destination and writes the
                // same place, so the address is computed once.
                ea_rmw        <= (aop != ALU_MOV);
                // Every field of the descriptor is set before an access
                // starts: JMP leaves this one set, and the next instruction
                // would otherwise compute its destination address and never
                // write to it.
                ea_addr_only  <= 1'b0;
                ea_pc_val     <= idu_pc;
                state         <= S_OP2R;
            end
        end

        S_OP2R: begin
            ea_rn_val <= rf_ra;
            ea_rx_val <= rf_rb;
            if (dst_is_reg) begin
                val2  <= {32'd0, rf_ra};
                state <= S_EXEC;
            end else if (aop == ALU_MOV) begin
                // MOV's destination is written and not read -- its syntax line
                // is "dst.w" where ADD's is "dst.rw" -- so the read is skipped
                // and only the write happens.  The descriptor is already set.
                state <= S_EXEC;
            end else begin
                state <= S_OP2S;
            end
        end

        S_OP2S: begin
            ea_start <= 1'b1;
            state    <= S_OP2W;
        end

        S_OP2W: begin
            if (ea_rmw_pending) begin
                // A read-modify-write whose read has completed: the access is
                // still open and closing it is the only way out, so a fault
                // here is taken one bus cycle later, at S_WBW.
                val2  <= ea_rdata;
                state <= S_EXEC;
            end else if (ea_done) begin
                insn_cycles <= insn_cycles + {1'b0, ea_bus_cycles};
                if (berr_r) begin
                // Abandoned: a bus cycle of this access failed, so the
                // instruction does not retire and its writeback is dropped.
                exc_kind  <= EK_BERR;
                exc_vec_r <= VEC_BUS_FAULT;
                state     <= S_EXC_SW;
                end else begin
                    val2  <= ea_rdata;
                    state <= S_EXEC;
                end
            end
        end

        // ---- execute ---------------------------------------------------------
        S_EXEC: begin
            // The ALU is combinational and its inputs are already presented.
            state <= S_WB;
        end

        S_WB: begin
            if (!alu_writes) begin
                // CMP and TEST leave no result.  If the destination was read
                // through a read-modify-write access, that access is still
                // open and has to be closed with what was already there;
                // a register operand has nothing open to close.
                if (ea_rmw_pending) begin
                    ea_rmw_data <= val2;
                    ea_rmw_go   <= 1'b1;
                    state       <= S_WBW;
                end else begin
                    state <= S_RETIRE;
                end
            end else if (dst_is_reg) begin
                rf_wr_en   <= 1'b1;
                rf_wr_sel  <= reg_operand;
                rf_wr_data <= alu_result;
                state      <= S_RETIRE;
            end else if (ea_rmw_pending) begin
                ea_rmw_data <= {32'd0, alu_result};
                ea_rmw_go   <= 1'b1;
                state       <= S_WBW;
            end else begin
                // MOV to memory: the address is computed for the write.
                ea_we    <= 1'b1;
                ea_wdata <= {32'd0, alu_result};
                ea_start <= 1'b1;
                state    <= S_WBW;
            end
        end

        S_WBW: if (ea_done) begin
            insn_cycles <= insn_cycles + {1'b0, ea_bus_cycles};
            if (berr_r) begin
                // Abandoned: a bus cycle of this access failed, so the
                // instruction does not retire and its writeback is dropped.
                exc_kind  <= EK_BERR;
                exc_vec_r <= VEC_BUS_FAULT;
                state     <= S_EXC_SW;
            end else begin
                state <= S_RETIRE;
            end
        end

        // ---- retire ----------------------------------------------------------
        S_RETIRE: begin
            // The flags the operation left, and an addressing mode's writeback.
            psw <= psw_set_flags(psw, alu_flags);
            if (wb_rn_en) begin
                rf_wr_en   <= 1'b1;
                rf_wr_sel  <= wb_rn_sel;
                rf_wr_data <= wb_rn_val;
            end
            pc      <= idu_pc + {27'd0, idu_len};
            retired <= 1'b1;
            state   <= S_IDLE;
        end

        // ---- control transfers ------------------------------------------------
        S_CTRL: begin
            case (cop)
                // "if condition then PC <- PC + sign_extended( disp )", and
                // "the value of the PC used to compute the target address is
                // the first byte of the branch instruction".
                CTRL_BCC: begin
                    taken   <= cond_true(idu_op[3:0], psw_flags(psw));
                    target  <= idu_pc + idu_disp;
                    state   <= S_CTRL_FIN;
                end
                // The register ones test a register first.
                CTRL_DBCC, CTRL_TB: begin
                    rf_ra_sel <= idu_reg;
                    target    <= idu_pc + idu_disp;
                    state     <= S_CTRL_REG;
                end
                // BSR pushes and branches; the push is the autodecrement
                // addressing mode on R31, which is what "[-SP]" means.
                CTRL_BSR: begin
                    target       <= idu_pc + idu_disp;
                    taken        <= 1'b1;
                    rf_ra_sel    <= 5'd31;
                    ea_rn_sel    <= 5'd31;
                    ea_mode      <= AM_RN_DEC;
                    ea_index     <= 1'b0;
                    ea_disp      <= 32'd0;
                    ea_disp_outer<= 32'd0;
                    ea_opbytes   <= 4'd4;
                    ea_we        <= 1'b1;
                    ea_rmw       <= 1'b0;
                    ea_addr_only <= 1'b0;
                    ea_wdata     <= {32'd0, idu_pc + {27'd0, idu_len}};
                    state        <= S_CTRL_EAR;
                end
                // RSR pops one: "PC <- [SP+]", the autoincrement mode on R31.
                CTRL_RSR: begin
                    taken        <= 1'b1;
                    rf_ra_sel    <= 5'd31;
                    ea_rn_sel    <= 5'd31;
                    ea_mode      <= AM_RN_INC;
                    ea_index     <= 1'b0;
                    ea_disp      <= 32'd0;
                    ea_disp_outer<= 32'd0;
                    ea_opbytes   <= 4'd4;
                    ea_we        <= 1'b0;
                    ea_rmw       <= 1'b0;
                    ea_addr_only <= 1'b0;
                    state        <= S_CTRL_EAR;
                end
                // JMP and JSR take the operand's ADDRESS.  "The destination
                // operand is treated as byte data for the purpose of computing
                // pointer changes for the autoincrement, autodecrement, or
                // scaled indexed addressing modes" -- hence one byte.
                default: begin
                    taken        <= 1'b1;
                    rf_ra_sel    <= op1_rn;
                    ea_rn_sel    <= op1_rn;
                    rf_rb_sel    <= op1_rx;
                    ea_mode      <= op1_mode;
                    ea_index     <= op1_index;
                    ea_disp      <= op1_disp;
                    ea_disp_outer<= op1_disp_outer;
                    ea_imm       <= op1_imm;
                    ea_opbytes   <= 4'd1;
                    ea_we        <= 1'b0;
                    ea_rmw       <= 1'b0;
                    ea_addr_only <= 1'b1;
                    ea_pc_val    <= idu_pc;
                    state        <= S_CTRL_EAR;
                end
            endcase
        end

        S_CTRL_REG: begin
            if (cop == CTRL_TB) begin
                // "if Rn = 0 then PC <- PC + sign_extended(disp16)"
                taken <= (rf_ra == 32'd0);
            end else begin
                // "Rn <- Rn - 1 ; if ( condition and Rn != 0 ) then ..."  The
                // condition's low bit is in the opcode and the other three are
                // the Format VI subop.
                taken      <= cond_true({idu_subop[2:0], idu_op[0]},
                                        psw_flags(psw)) &&
                              ((rf_ra - 32'd1) != 32'd0);
                wb_rn_en   <= 1'b1;
                wb_rn_sel  <= idu_reg;
                wb_rn_val  <= rf_ra - 32'd1;
            end
            state <= S_CTRL_FIN;
        end

        S_CTRL_EAR: begin
            ea_rn_val <= rf_ra;
            ea_rx_val <= rf_rb;
            state     <= S_CTRL_EAS;
        end

        S_CTRL_EAS: begin
            ea_start <= 1'b1;
            state    <= S_CTRL_EAW;
        end

        S_CTRL_EAW: if (ea_done) begin
            insn_cycles <= insn_cycles + {1'b0, ea_bus_cycles};
            if (berr_r) begin
                // Abandoned: a bus cycle of this access failed, so the
                // instruction does not retire and its writeback is dropped.
                exc_kind  <= EK_BERR;
                exc_vec_r <= VEC_BUS_FAULT;
                state     <= S_EXC_SW;
            end else if (cop == CTRL_RSR) begin
                target <= ea_rdata[31:0];
                state  <= S_CTRL_FIN;
            end else if ((cop == CTRL_JSR) && !cpush) begin
                // "temp <- target ; [-SP] <- NextPC ; PC <- temp": the address
                // is computed BEFORE the push, which matters when the operand
                // itself touches the stack.
                target       <= ea_ea;
                cpush        <= 1'b1;
                rf_ra_sel    <= 5'd31;
                ea_rn_sel    <= 5'd31;
                ea_mode      <= AM_RN_DEC;
                ea_index     <= 1'b0;
                ea_disp      <= 32'd0;
                ea_disp_outer<= 32'd0;
                ea_opbytes   <= 4'd4;
                ea_we        <= 1'b1;
                ea_addr_only <= 1'b0;
                ea_wdata     <= {32'd0, next_pc};
                state        <= S_CTRL_EAR;
            end else if (cop == CTRL_JMP) begin
                target <= ea_ea;
                state  <= S_CTRL_FIN;
            end else begin
                state <= S_CTRL_FIN;
            end
        end

        S_CTRL_FIN: begin
            if (taken) begin
                pc          <= target;
                redirect    <= 1'b1;
                redirect_pc <= target;
            end else begin
                pc <= next_pc;
            end
            if (wb_rn_en) begin
                rf_wr_en   <= 1'b1;
                rf_wr_sel  <= wb_rn_sel;
                rf_wr_data <= wb_rn_val;
            end
            retired <= 1'b1;
            state   <= S_IDLE;
        end

        // ---- an exception --------------------------------------------------
        // The stack first: R31 is the stack pointer the PSW's {IS, EL} names,
        // and the frame goes on the one the handler will run with, so the
        // register file switches before v60_exc pushes.  A switch to the same
        // entry is a no-op there, which is the ordinary case here -- this
        // sequencer runs at execution level 0 and these three exceptions
        // handle at execution level 0.
        S_EXC_SW: begin
            rf_stack_switch <= 1'b1;
            rf_new_el       <= 2'd0;
            // An instruction exception's frame goes on the stack the new
            // execution level names -- L0SP, or IS if that is where it already
            // was.  The other three go on the interrupt stack outright: an
            // interrupt by step (vii), a bus fault and a system fault by §8's
            // prose about each group.
            rf_new_is       <= (exc_kind == EK_INSN) ? psw[PSW_IS] : 1'b1;
            rf_ra_sel       <= 5'd31;
            state           <= S_EXC_SETTLE;
        end

        // One cycle, and it is not padding.  `rf_stack_switch` is a registered
        // output, so the register file performs the switch at the end of the
        // cycle it is HIGH in -- which is this one -- and R31 only reads back
        // as the new stack pointer in the cycle after.  Without this state,
        // S_EXC_REQ samples the OLD one and the frame is pushed on the stack
        // being switched away from.
        //
        // That was invisible until now: the three instruction exceptions
        // switch to the entry they are already on, which the register file
        // makes a no-op, so the old value and the new one were the same word.
        // The first exception here that genuinely changes stacks is an
        // externally raised one.
        S_EXC_SETTLE: state <= S_EXC_REQ;

        S_EXC_REQ: begin
            exc_req    <= 1'b1;
            exc_vector <= exc_vec_r;
            exc_psw_in <= psw;
            exc_sp_in  <= rf_ra;
            exc_sbr    <= sbr;
            exc_param1 <= 32'd0;

            case (exc_kind)
            // Figure 8-5's "#3 Bus Fault": one parameter word above the code,
            // and it is the physical address of the cycle that failed.  Note 2
            // of the recognition sequence, and §8 again, disable interrupts.
            EK_BERR: begin
                exc_ret_pc       <= pc;
                exc_nparams      <= 2'd1;
                exc_code         <= berr_code_r;
                exc_param0       <= {8'd0, berr_addr_r};
                exc_is_interrupt <= 1'b0;
                exc_disable_ie   <= 1'b1;
                exc_int_stack    <= 1'b1;
                exc_ack_vector   <= 1'b0;
                berr_r           <= 1'b0;
            end
            // Figure 8-5's "#2 Non-Maskable Interrupt / #64-255 Maskable
            // Interrupts": the PSW and the Next PC, and nothing else.  `pc` is
            // the next instruction's, because retirement has already moved it.
            EK_INT: begin
                exc_ret_pc       <= pc;
                exc_nparams      <= 2'd0;
                exc_code         <= 16'd0;
                exc_param0       <= 32'd0;
                exc_is_interrupt <= 1'b1;
                exc_disable_ie   <= 1'b0;
                exc_int_stack    <= 1'b1;
                exc_ack_vector   <= exc_ack_r;
            end
            // "An exception during the execution of an instruction stacks the
            // PC of the instruction causing the exception (Current PC)", and
            // the Instruction Exceptions frame prints "PC (Current PC)".
            // Parameter count 4: one word, and that word is the exception code
            // beside the count itself -- so there are no parameter words ABOVE
            // it, which is what nparams counts.
            default: begin
                exc_ret_pc       <= idu_pc;
                exc_nparams      <= 2'd0;
                exc_code         <= exc_code_r;
                exc_param0       <= 32'd0;
                exc_is_interrupt <= 1'b0;
                exc_disable_ie   <= 1'b0;
                exc_int_stack    <= 1'b0;
                exc_ack_vector   <= 1'b0;
            end
            endcase
            state <= S_EXC_W;
        end

        S_EXC_W: if (exc_done) begin
            insn_cycles <= insn_cycles + {1'b0, exc_bus_cycles};
            psw         <= exc_psw_out;
            rf_wr_en    <= 1'b1;
            rf_wr_sel   <= 5'd31;
            rf_wr_data  <= exc_sp_out;
            pc          <= exc_handler_pc;
            redirect    <= 1'b1;
            redirect_pc <= exc_handler_pc;
            retired     <= 1'b1;
            state       <= S_IDLE;
        end

        S_STOP: ;

        default: state <= S_IDLE;
        endcase
    end
end

endmodule
