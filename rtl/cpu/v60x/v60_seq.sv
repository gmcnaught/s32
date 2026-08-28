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
//  The two return pairs, and the one engine underneath them
//  ---------------------------------------------------------------------------
//  CALL/RET and RETIU/RETIS are three different instructions with one shape:
//  compute something, touch the stack twice, then write two registers and
//  redirect.  S_STK_* is that shape once, and the operation each of them
//  performs is the Programmer's Reference's own pseudo-code:
//
//    CALL   tmp1 <- effective_address( target ) ; tmp2 <- effective_address( arg )
//           [-SP] <- AP ; AP <- tmp2 ; [-SP] <- NextPC ; PC <- tmp1
//    RET    tmp1 <- num ; tmp2 <- [SP+] ; AP <- [SP+] ; SP <- SP + tmp1 ;
//           PC <- tmp2
//    RETIS  PC <- [SP+] ; PSW <- [SP+] ; SP <- SP + count
//    RETIU  the same operation, exactly
//
//  Four things about them are worth stating because each one was read off a
//  page rather than assumed:
//
//  * AP is R29.  RET's Description says so outright -- "the return address and
//    argument pointer register (R29) are restored from the stack" -- and it is
//    the databook's own p.3.247 assignment.  R30 is FP.
//  * The frame RETIS and RETIU pop is the one v60_exc pushes.  The PC is on
//    top and the PSW under it, which is the order the operation prints, and
//    which is why v60_exc pushes the return PC last.
//  * The count is an OPERAND, not something read out of the frame.  Both pages
//    print "retis count.h.r" / "retiu count.h.r" and both say the count
//    "allows the interrupt or exception handler to specify the number of bytes
//    to be automatically discarded from the stack".  §8's "the parameter count
//    ... is used by exception handlers to determine the number of bytes to
//    discard" describes what the HANDLER does with the frame's count field:
//    it reads it and passes it here.  The processor never reads that word.
//  * RETIU and RETIS differ by privilege and by nothing else in these pages.
//    RETIS's Exceptions list begins "Privileged Instruction" and RETIU's does
//    not -- System against User, which is what the names say.  Their
//    Operation, Condition Codes and Addressing Modes blocks are identical.
//
//  Both also list Illegal Data Field, and RETIU's page gives a condition for
//  it: "an Illegal Data Field exception will occur if the execution level
//  field in the PSW is not [0] and the ISP flag is set or if an attempt is
//  made to return to a more privileged execution level."  The bracketed digit
//  did not survive the scan in the copy held here and the databook does not
//  reprint the page, so only the second clause is implemented -- returning to
//  a numerically lower execution level -- and the first is recorded unread.
//
//  What the pair does NOT do here: check for asynchronous system and task
//  traps, which both pages say they do.  There are no AST or ATT in this tree.
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
//  * Anything neither v60_alu nor v60_muldiv implements.  The generated table
//    says which by returning ALU_NONE, and this stops on it rather than doing
//    something arbitrary.  The X forms of the multiplies and divides are among
//    them: their destination is a doubleword register pair and nothing here
//    addresses one.
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
    output logic        ea_io,
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
    // The privileged register port, which LDPR and STPR drive and TRAPFL
    // reads.  `pr_rdata` is combinational off `pr_id` in v60_regfile, the same
    // way `ra` is off `ra_sel`, so the id is presented in one state and the
    // value read in the next.
    output logic  [4:0] rf_pr_id,
    output logic        rf_pr_wr,
    output logic [31:0] rf_pr_wdata,
    input        [31:0] rf_pr_rdata,
    input               rf_pr_rd_ok,
    input               rf_pr_wr_ok,

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
//    +68  Privileged Instruction Exception  vector 17   code 1100
//    +80  Illegal Data Field Exception       vector 20   code 1400
localparam logic [7:0] VEC_RESERVED_OP   = 8'd16;
localparam logic [7:0] VEC_PRIVILEGED    = 8'd17;
localparam logic [7:0] VEC_RESERVED_MODE = 8'd18;
localparam logic [7:0] VEC_ILLEGAL_MODE  = 8'd19;
localparam logic [7:0] VEC_ILLEGAL_DATA  = 8'd20;
// +84  Integer Arithmetic Exception       vector 21   code 1500 (zero divide)
localparam logic [7:0] VEC_INT_ARITH     = 8'd21;
// +52  Instruction Breakpoint Exception   vector 13   code 0D00
localparam logic [7:0] VEC_BREAKPOINT    = 8'd13;
// +88  Floating Point Arithmetic Exception   vector 22
// Named on the databook's p.3.270 SBT plate.  TRAPFL is the only thing here
// that reaches it, and it shares the Arithmetic Exceptions frame with the
// integer overflow and the zero divide above.
localparam logic [7:0] VEC_FP_ARITH      = 8'd22;
localparam logic [15:0] CODE_RESERVED_OP   = 16'h1000;
localparam logic [15:0] CODE_PRIVILEGED    = 16'h1100;
localparam logic [15:0] CODE_RESERVED_MODE = 16'h1200;
localparam logic [15:0] CODE_ILLEGAL_MODE  = 16'h1300;
localparam logic [15:0] CODE_ILLEGAL_DATA  = 16'h1400;
localparam logic [15:0] CODE_ZERO_DIVIDE   = 16'h1500;
// The other Arithmetic Exceptions code, and the one BRKV raises.
localparam logic [15:0] CODE_INT_OVERFLOW  = 16'h1501;
localparam logic [15:0] CODE_BREAKPOINT    = 16'h0D00;

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
localparam logic [2:0] EK_INSN = 3'd0;
localparam logic [2:0] EK_BERR = 3'd1;
localparam logic [2:0] EK_INT  = 3'd2;
// Figure 8-5's Arithmetic Exceptions frame, which is BRKV's operation printed
// as a diagram: "+12 PC (Current PC) / +8 Exception Code | 8 / +4 PSW /
// PC (Next PC)".  One parameter word, and it is the Current PC -- so unlike
// the Instruction Exceptions, the return PC on top is the NEXT one.
localparam logic [2:0] EK_ARITH = 3'd3;
// Figure 8-5's "#48-63 Software Traps" frame: "+8 Exception Code | 4 / +4 PSW /
// PC (Next PC)".  Three words and no parameter, like an instruction exception
// -- and the NEXT PC, unlike one.  That single difference is why it is its own
// kind rather than EK_INSN with a flag: a software trap is how user code asks
// the supervisor for something, so it must return PAST the trap instruction,
// while an instruction exception returns TO the instruction that faulted.
//
// TRAP's own Operation block and Figure 8-5 agree here, which is worth stating
// because its neighbour BRK's do not (docs/v60/BREAK-AND-TRAP.md).
localparam logic [2:0] EK_TRAP = 3'd4;

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

typedef enum logic [5:0] {
    S_IDLE, S_FETCH,
    S_OP1, S_OP1R, S_OP1S, S_OP1W,     // describe, read registers, start, wait
    S_OP2, S_OP2R, S_OP2S, S_OP2W,
    S_EXEC, S_MD, S_WB, S_WBW, S_RETIRE, S_STOP,
    // TRAPFL: one state, to let the privileged register id it asked for in
    // S_FETCH reach v60_regfile's read port and come back.
    S_TRAPFL,
    // STPR: present the id its FIRST operand carried to the register file's
    // privileged port, then take the value back.  Two states because
    // `pr_rdata` is combinational off a REGISTERED `pr_id`, so the id has to
    // be presented a cycle before it can be read.
    S_PR_SEL, S_PR_RD,
    // PUSH and POP's one stack access: read R31, make the access, then write
    // R31 back.  The pointer is computed HERE and the access uses AM_RN_IND,
    // exactly as the stack engine below does -- so v60_ea raises no
    // addressing-mode writeback of its own for it, and the single writeback
    // slot stays free for the operand's own mode.  Without that, `push [R5+]`
    // would be two writebacks and stop the sequencer.
    S_PSH_R, S_PSH_SP, S_PSH_S, S_PSH_W, S_PSH_FIN,
    // The control transfers: a register to test, an address to compute, a
    // stack access to make, and then the redirect.
    S_CTRL, S_CTRL_REG, S_CTRL_EAR, S_CTRL_EAS, S_CTRL_EAW, S_CTRL_FIN,

    // an exception: switch the stack, let the switch land, take it, then run
    // the handler
    S_EXC_SW, S_EXC_SETTLE, S_EXC_REQ, S_EXC_W,

    // the stack engine CALL, RET, RETIU and RETIS share: read the stack
    // pointer, two accesses, the addressing mode's own writeback, then the two
    // register writes and the redirect.  The two writes are two states because
    // the register file has one write port, and the stack switch is a third
    // because it is a registered request that lands a cycle after it is made
    // -- the same reason S_EXC_SETTLE exists.
    S_STK_SP, S_STK_S, S_STK_W, S_STK_WB,
    S_STK_FIN1, S_STK_FIN2, S_STK_FIN3
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
logic  [2:0] exc_kind;    // which of the shapes of frame it wants
logic        exc_ack_r;   // and whether its vector comes off the bus
logic [31:0] sp_r;        // the stack pointer the stack engine is walking
logic [31:0] stk_val;     // what its second access produced: a PSW, an AP,
                          // or -- for CALL, before either -- the argument list
logic [31:0] stk_cnt;     // RET's `num` and RETIU/RETIS's `count`
logic        stk_phase;   // which of the two stack accesses is running
// HALT's state, and the only thing in this sequencer that outlives an
// instruction.  "The processor halts and waits for an interrupt" -- so HALT
// retires like anything else, advancing the PC past itself, and what is held
// here is the refusal to fetch the next one.  Advancing FIRST is what the page
// requires: "program execution will continue with the instruction following
// the HALT instruction", so the interrupt's frame carries HALT + 1 and the
// handler's return does not land back on the HALT.
logic        halted_r;
logic        berr_r;      // a bus fault is outstanding
logic [23:0] berr_addr_r; // where it happened -- the frame's parameter word
logic [15:0] berr_code_r;

// ---------------------------------------------------------------------------
// Which operand is the source and which the destination.
// ---------------------------------------------------------------------------
// Format II has two mod fields and the syntax order settles it: operand 1 is
// the source, operand 2 the destination.  Format I has one mod field and one
// register, and `d` says which way round they go -- see the header.
wire fmt_i   = (idu_fmt == FMT_I);
wire fmt_ii  = (idu_fmt == FMT_II);
// Format III has ONE mod field and no `reg` field, so its single operand is
// both the thing read and the thing written: "inc.b dst.b.rw", "test.b
// dst.b.r".  There is no source to fetch, which is why S_FETCH sends it
// straight to the destination path below.
wire fmt_iii = (idu_fmt == FMT_III);

wire        src_is_reg  = fmt_i && !idu_d;   // d = 0: the register is the source
wire        dst_is_reg  = (fmt_i &&  idu_d) ||          // d = 1: it is the dest
                          (fmt_ii  && (op2_mode == AM_RN)) ||
                          (fmt_iii && (op1_mode == AM_RN));
wire  [4:0] reg_operand = fmt_iii ? op1_rn : (fmt_i ? idu_reg : op2_rn);

// NOT a correctness requirement for Format III, and marked so nobody proves it
// with a test that cannot fail.  v60_ea writes a register-direct destination
// through its own Rn writeback slot (`am_is_reg_direct` -> `rn_wb`), so a
// Format III instruction whose operand is a register reaches the same
// architectural result down either path, with the same zero bus cycles.  The
// fast path is kept because it leaves the writeback slot free and states the
// intent, not because anything can tell the difference: with one operand there
// is no second writeback to collide with.  For Formats I and II it IS load
// bearing, which is why the guard exists at all.

// The mod field that is NOT the register operand.  Format I has only one, and
// it is whichever side `d` did not take.
wire        dst_am_is_op2 = fmt_ii;

// Which operations WRITE their destination without reading it first.  It is
// the syntax line that says so: MOV's is "dst.w" where ADD's is "dst.rw", and
// RVBIT, RVBYT and SETF all print "dst.b.w" or "dst.w.w" too.  A destination
// that is only written costs one bus cycle instead of two, and an operation
// that read a write-only destination would also touch memory the page says it
// does not.
//
// MOVS, MOVZ and MOVT are deliberately NOT here even though their syntax lines
// also print a write-only destination: they are left as they were until their
// bus-cycle counts are checked, because changing them silently would move a
// number tb_v60_seq does not currently assert.  Recorded as an open item in
// docs/v60/TRANCHE-ONE.md rather than changed in passing.
wire        dst_write_only = (aop == ALU_MOV)   || (aop == ALU_RVBIT) ||
                             (aop == ALU_RVBYT) || (aop == ALU_SETF) ||
                             (aop == ALU_GETPSW) || (aop == ALU_MOVEA) ||
                             // "stpr regID.w.r, dst.w.w"
                             (aop == ALU_STPR) ||
                             // "in.b port.b.r, dst.b.w" and
                             // "out.b src.b.r, port.b.w" -- in both, the
                             // SECOND operand is written and not read.
                             (aop == ALU_IN) || (aop == ALU_OUT) ||
                             // "dst <- [SP+]": POP's one encoded operand is
                             // written and never read.
                             (aop == ALU_POP);

// And which ones READ their operand and never write it.  The pages do not call
// these a destination at all: CMP's syntax line is "cmp.b src1.b.r, src2.b.r"
// and TEST's is "test.b src.b.r" -- two reads and one read, no `rw` anywhere.
//
// DEFECT this fixes.  Both were treated as read-modify-writes, which opened an
// access v60_ea then had to close: S_WB's `!writes` branch fed the value
// straight back with `ea_rmw_go`, so a CMP or TEST against a memory operand
// cost TWO bus cycles and, worse, performed a bus WRITE to an operand the page
// marks read-only.  Writing the same bytes back is not harmless -- it is a
// write cycle on the pins, and on a read-sensitive location it is a write that
// should never have happened.  Neither instruction had a memory-operand cycle
// count asserted anywhere, which is how it survived.
// TRAP is here for the same reason: "trap cond&vector.b.r" -- one operand, and
// it is `.r`.  Its byte is a condition and a vector, and writing it back would
// be a bus write to a location the page never calls a destination.
wire        dst_read_only = (aop == ALU_CMP) || (aop == ALU_TEST) ||
                            (aop == ALU_UPDPSWH) || (aop == ALU_UPDPSWW) ||
                            (aop == ALU_TRAP) ||
                            // LDPR's second operand is marked ".w.w" on the
                            // page, which is the one place the notation names
                            // the thing the operand DESIGNATES rather than the
                            // operand itself: "PrivilegedRegister( regID ) <-
                            // src" cannot know which register to load without
                            // READING regID.  So it is fetched like any source
                            // and nothing is ever written back to it.  MAME's
                            // s32_v60.sv reads it the same way ("op2 = priv
                            // reg #"), which is a second implementation
                            // agreeing against the syntax line.
                            (aop == ALU_LDPR) ||
                            // "test1 offset.w.r, base.w.r" -- the only one of
                            // the four bit instructions that writes nothing.
                            // Its three siblings print "base.w.rw".
                            (aop == ALU_TEST1);

// And the one whose SOURCE is an address rather than a value.  MOVEA's syntax
// line is "movea.b src.b.n, dst.w.w": the `.n` access type means no bus cycle
// is issued for the source at all, and "the source operand is not referenced
// and remains unchanged".  Its size field still matters, because it is what
// [Rn+] steps by and what (Rx) scales by.
wire        src_addr_only = (aop == ALU_MOVEA);

// The PSW merge, which is the whole of UPDPSW: "PSW <- ( PSW & ~mask ) |
// ( newPSW & mask )".  val1 is the first operand and val2 the second, which
// the syntax line names newPSW and mask in that order.
//
// UPDPSW.H "is restricted to modifying only the condition code fields", and §3
// names those as "the integer and floating point condition codes" -- CY OV S Z
// at 3:0 and FPR FUD FOV FZD FIV at 12:8.  That is the low halfword minus its
// reserved bits, which v60_psw_pkg already states once as PSW_RFU, so this
// takes it from there rather than restating it as a literal.
//
// DEFECT this replaces: it was written as the literal 32'h0000_10FF, which is
// a transposition -- 0x1000 | 0x00FF instead of 0x1F00 | 0x000F.  That
// excluded bits 8 to 11, four of the five floating point condition codes the
// page explicitly permits, so a mask of 0x00000F00 wrote nothing; and it
// included the reserved bits 4 to 7, which only the `& ~PSW_RFU` below made
// harmless.  The package held the right mask in psw_update_h and nothing
// called it.
localparam logic [31:0] UPDPSW_H_FIELDS = ~PSW_RFU & 32'h0000_FFFF;
wire [31:0] updpsw_mask = (aop == ALU_UPDPSWH)
                          ? (val2[31:0] & UPDPSW_H_FIELDS) : val2[31:0];
// "Reserved for future use (Must be 0)" at 4-7, 13-15 and 19-23 (p.3.248), so
// the merge cannot write them whatever the mask says.
wire [31:0] updpsw_next = (((psw & ~updpsw_mask) |
                            (val1[31:0] & updpsw_mask)) & ~PSW_RFU);
wire        is_updpsw   = (aop == ALU_UPDPSWH) || (aop == ALU_UPDPSWW);

// TRAP's operand, taken apart.  "The upper four bit field of the operand
// contains the condition code field which indicates under what circumstances
// the trap will be taken.  The lower four bit field contains the vector offset
// from the software trap base vector."
//
// The nibble order is the opposite of SETF's, whose condition is the LOW
// nibble ("setf cond.b.r").  Sharing one condition evaluator between the two is
// right; sharing the extraction would be a defect, so the two nibbles are named
// here and nowhere else.
wire  [3:0] trap_cond   = val2[7:4];
wire  [3:0] trap_vector = val2[3:0];
wire        trap_taken  = (aop == ALU_TRAP) &&
                          cond_true(trap_cond, psw_flags(psw));
// SBT entry 48 + n.  The databook's p.3.270 plate prints these one per line for
// n = 0 to 15 -- "48 Software Trap 0" through "63 Software Trap 15" -- with
// entry 47 and below marked RFU, so the mapping is read off the figure rather
// than inferred from a range label.
wire  [7:0] trap_vec_no = 8'd48 + {4'd0, trap_vector};
// Databook p.3.272's Software Traps block: 3000, 3100, 3200 ... 3F00.  The trap
// number sits in bits 11:8 -- the SECOND nibble -- and not in the low byte.
// The Change Execution Level group on the same plate is indexed the same way
// (1800/1900/1A00/1B00), and s32_v60.sv builds THAT one as 0x1800 + level,
// which is wrong; there is no group in the table indexed in the low byte.
wire [15:0] trap_code   = {4'h3, trap_vector, 8'h00};

// TRAPFL, which is one AND: "if ( TKCW[8:4] AND PSW[12:8] ) != 0 then Floating
// Point Operation Exception".  PSW[12:8] is {FIV, FZD, FOV, FUD, FPR} read
// MSB-down, and TKCW[8:4] is the matching enable field -- the shift of four is
// what pairs them, so the correspondence is forced by the Operation block
// itself and is not a choice made here.
//
//   PSW 12 FIV  invalid operation   TKCW 8        PSW  9 FUD  underflow  TKCW 5 FUT
//   PSW 11 FZD  zero divide         TKCW 7 FZT    PSW  8 FPR  precision  TKCW 4 FPT
//   PSW 10 FOV  overflow            TKCW 6 FOT
wire  [4:0] trapfl_live = rf_pr_rdata[8:4] & psw[PSW_FIV:PSW_FPR];
wire        trapfl_take = (trapfl_live != 5'd0);
// And the exception code is that same five-bit result, placed.  Databook
// p.3.272's Arithmetic Exceptions block prints 1601 precision, 1602 underflow,
// 1604 overflow, 1608 zero divide, 1610 invalid operation, with a brace across
// them reading "these exception codes can combine in the case of simultaneous
// exceptions" -- so the low byte is ONE-HOT per condition precisely so that
// several can be reported at once, and 0x1606 means underflow and overflow
// together.  TRAPFL is the instruction that makes that matter: it ANDs a
// five-bit mask against a five-bit flag field, so more than one can be live.
//
// The five bits of `trapfl_live` are already in the plate's order, lowest
// first, so the code is the AND itself with 0x16 above it and nothing
// rearranged.  Whether the hardware really ORs all of them or reports one is
// not printed; OR is the only reading under which a one-hot low byte means
// anything.  Recorded in docs/v60/BREAK-AND-TRAP.md.
wire [15:0] trapfl_code = {8'h16, 3'd0, trapfl_live};

// The privileged register pair.  Which operand carries the id differs between
// them -- "ldpr src.w.r, regID.w.w" names it second, "stpr regID.w.r, dst.w.w"
// first -- so it is selected here once rather than at each use.
wire        is_pr_op  = (aop == ALU_LDPR) || (aop == ALU_STPR);
wire [31:0] pr_id_val = (aop == ALU_STPR) ? val1[31:0] : val2[31:0];
// The one rule the pages state as a rule.  STPR's is precise -- "An Illegal
// Data Field exception will occur if the register ID field is not in the range
// of [0] to 31.  Instruction execution results will also be unpredicatable if
// an undefined register ID is specified" -- which is two distinct cases, and
// only the first is an exception.  LDPR's page gives only the second half but
// still lists Illegal Data Field in its Exceptions block.
//
// So an id ABOVE 31 raises, and an id inside 0..31 that names no register --
// the gaps at 10-14 and 29-31, and 6 and 9 on LDPR -- is explicitly
// unpredictable and does NOT raise.  v60_regfile's per-id permission table
// drops those writes and warns, which is a policy the pages permit rather than
// one they require; a sequencer that raised on them would be going beyond the
// page.  Recorded as a choice in docs/v60/TRANCHE-ONE.md.
//
// s32_v60.sv raises on anything above 28, which catches 29-31 the pages call
// unpredictable, and raises it as vector 8 rather than the Illegal Data Field
// vector 20.
wire        pr_id_bad = is_pr_op && (pr_id_val[31:5] != 27'd0);
// Checked at different points, because the id arrives at different points:
// STPR's is its FIRST operand, so S_PR_SEL sees it before the destination is
// addressed at all, and LDPR's is its second, so S_EXEC is the first state
// that has it.  The two must not share a check -- by S_EXEC, STPR's val1 no
// longer holds an id but the privileged register's CONTENTS, which would be
// range-checked as though it were one.
wire        ldpr_id_bad = (aop == ALU_LDPR) && pr_id_bad;
wire        stpr_id_bad = (aop == ALU_STPR) && pr_id_bad;

// The four bit instructions, and the one thing any of them can raise: "An
// Illegal Data Field exception occurs if the bit offset is outside the range 0
// to 31."  A range check on the SOURCE operand's value -- not on an addressing
// mode -- which is why it is here and not in v60_am_decode.
//
// The consequence is worth stating, because the pages' "sum of the byte base
// address and bit offset" phrasing suggests otherwise: the reachable bits are
// base+0 through base+31 and no further, so a memory base designates a bit
// within ONE word.  That is what makes the register base and the memory base
// the same datapath here -- bit N of the word at the base address is bit N of
// the word, whichever way the base was named.  EXTBF and INSBF are what reach
// further.
//
// A quick immediate offset supplies four bits, zero extended, so it covers
// bits 0..15 and can never be out of range; reaching bits 16..31 needs a full
// immediate or a register.
wire        is_bit_op   = (aop == ALU_TEST1) || (aop == ALU_SET1) ||
                          (aop == ALU_CLR1)  || (aop == ALU_NOT1);
wire        bit_off_bad = is_bit_op && (val1[31:5] != 27'd0);

// The I/O pair, and the one asymmetry in them: "in.b port.b.r, dst.b.w" puts
// the port on the SOURCE and "out.b src.b.r, port.b.w" puts it on the
// DESTINATION.  So the access that goes to the I/O address space is op1's for
// IN and op2's for OUT, and the two can never be driven from one wire.
//
// "I/O space accesses are always generated by the execution of the privileged
// IN and OUT instructions" (PgmRef S4), which is also why v60_ea takes `io` as
// an input rather than deciding it from a mode.
wire        io_src = (aop == ALU_IN);
wire        io_dst = (aop == ALU_OUT);

// "Rn" is marked X -- Illegal -- in the Addressing Modes column of both pages,
// while every memory mode is permitted.  The reason is in the operand itself:
// the I/O address is the port operand's EFFECTIVE ADDRESS, and a register has
// no address to send.
//
// Not checked here: "bits 24:31 of a port address must be zero.  The operation
// using an I/O port address outside the range 0x00000000 to 0x00FFFFFF is
// unpredictable."  Unpredictable is not an exception, and the address bus is
// 24 bits, so v60_ea's `dx_addr` has already dropped the top byte -- the
// hardware does the only thing it can and the page permits it.
wire        io_src_bad = io_src && (src_is_reg || (op1_mode == AM_RN));

// MOVEA's source, which has the same shape of restriction and a different
// reason.  Its Addressing Modes table marks Rn, Immediate and Immediate.Quick
// as X -- Illegal Addressing Mode -- for the src column, and the page's own
// legend line spells X out.  "movea.b src.b.n, dst.w.w": the `.n` access type
// means the source is an ADDRESS and no bus cycle is issued for it, so a mode
// that has no address cannot be one.
//
// DEFECT this fixes (audit item M1).  Nothing raised it, and the two illegal
// mode groups failed two different ways: v60_ea's reg-direct and immediate
// branches both set `ea <= 0` without consulting `addr_only`, and `illegal` is
// driven from `we`, which a source never is -- so `movea.w R5, R9` and
// `movea.w #5, R9` quietly wrote 0.  Caught here, from the mode, for the same
// reason S_OP2's immediate-destination check is: an access that must not
// happen is better not started.
// PUSH and POP.  Each has ONE encoded operand and an implicit stack access,
// and they sit on opposite sides of it: PUSH's operand is the SOURCE of the
// word that goes on the stack, POP's is the DESTINATION of the word that comes
// off.  So PUSH reads its operand first and POP reads the stack first.
wire        is_push = (aop == ALU_PUSH);
wire        is_pop  = (aop == ALU_POP);
wire        is_stk1 = is_push || is_pop;

wire        movea_src_bad = src_addr_only &&
                            (src_is_reg || (op1_mode == AM_RN) ||
                             am_is_immediate(op1_mode));
wire        io_dst_bad = io_dst && dst_is_reg;

// Privileged instructions: "programs executing at other execution levels
// (levels 1, 2 and 3) are said to be non-privileged and attempts to execute a
// privileged instruction will cause an exception" (PgmRef §6).  p.3.299 groups
// them and marks every one with exception 12.
//
// UPDPSW.W is in that block and UPDPSW.H is not, which the Reference says the
// same way: one Exceptions block reading "Privileged Instruction (updpsw.w)".
//
// A function rather than a wire on `aop`, because the check has to happen in
// S_FETCH -- before any operand is fetched, since the exception is for
// attempting the instruction and not for what it would have read -- and `aop`
// is only assigned at the end of that state.
function automatic logic op_privileged(input alu_op_e o);
    op_privileged = (o == ALU_UPDPSWW) || (o == ALU_LDPR) || (o == ALU_STPR) ||
                    (o == ALU_HALT)   || (o == ALU_IN)   || (o == ALU_OUT);
endfunction

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
wire [3:0] w_dst_raw = op_data_bytes(idu_op, idu_subop, 1'b1);
// A Format III instruction has one operand and the table describes it as the
// FIRST one -- 'INC': ('siz', None) -- so the destination's width is w_src,
// and asking for the second operand's width returns "none" rather than a size.
wire [3:0] w_dst = fmt_iii ? w_src : w_dst_raw;

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

// The six that are not one cycle of combinational logic.  They take the same
// two operand values and produce the same three things -- a result, four flags
// and whether the destination is written at all -- so everything downstream of
// S_WB is unchanged and only the wait is new.
wire        md_is    = (aop == ALU_MUL)  || (aop == ALU_MULU) ||
                       (aop == ALU_DIV)  || (aop == ALU_DIVU) ||
                       (aop == ALU_REM)  || (aop == ALU_REMU);
logic       md_start;
wire        md_done, md_busy, md_writes, md_zero_div;
wire [31:0] md_result;
wire  [3:0] md_flags;

v60_muldiv muldiv (
    .clk(clk), .rst(rst),
    .start(md_start), .op(aop), .opbytes(alu_bytes),
    .x(val1[31:0]), .y(val2[31:0]), .flags_in(psw_flags(psw)),
    .result(md_result), .flags_out(md_flags), .writes(md_writes),
    .zero_div(md_zero_div), .busy(md_busy), .done(md_done)
);

// What S_WB and S_RETIRE see: the combinational unit's answer, or the
// iterative one's, held from the cycle it finished in.
logic [31:0] md_result_r;
logic  [3:0] md_flags_r;
logic        md_writes_r, md_zd_r, md_used;

wire [31:0] eff_result = md_used ? md_result_r : alu_result;
wire  [3:0] eff_flags  = md_used ? md_flags_r  : alu_flags;
wire        eff_writes = md_used ? md_writes_r : alu_writes;


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
        halted_r        <= 1'b0;
        berr_r          <= 1'b0;
        berr_addr_r     <= 24'd0;
        berr_code_r     <= 16'd0;
        sp_r            <= 32'd0;
        stk_val         <= 32'd0;
        stk_cnt         <= 32'd0;
        stk_phase       <= 1'b0;
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
        ea_io         <= 1'b0;
        val1          <= 64'd0;
        val2          <= 64'd0;
        aop           <= ALU_NONE;
        wb_rn_en      <= 1'b0;
        wb_rn_sel     <= 5'd0;
        ea_rn_sel     <= 5'd0;
        wb_rn_val     <= 32'd0;
        md_start      <= 1'b0;
        md_result_r   <= 32'd0;
        md_flags_r    <= 4'd0;
        md_writes_r   <= 1'b0;
        md_zd_r       <= 1'b0;
        md_used       <= 1'b0;
        rf_pr_id      <= 5'd0;
        rf_pr_wr      <= 1'b0;
        rf_pr_wdata   <= 32'd0;
    end else begin
        idu_start <= 1'b0;
        ea_start  <= 1'b0;
        ea_rmw_go <= 1'b0;
        rf_wr_en  <= 1'b0;
        rf_pr_wr  <= 1'b0;
        retired   <= 1'b0;
        redirect  <= 1'b0;
        exc_req         <= 1'b0;
        rf_stack_switch <= 1'b0;
        nmi_take        <= 1'b0;
        md_start        <= 1'b0;

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
            end else if (halted_r) begin
                // Waiting.  The three tests above are the only ways out, which
                // is exactly what the page says it waits for -- and note that
                // a maskable interrupt still has to pass PSW.IE, so a HALT
                // executed with interrupts disabled waits for an NMI or
                // nothing.  Nothing here re-fetches, so the instruction after
                // the HALT does not run until an interrupt has been through.
                state <= S_IDLE;
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
            end else if (op_privileged(op_alu(idu_op)) &&
                         (psw[PSW_EL_HI:PSW_EL_LO] != 2'b00)) begin
                // Checked before any operand is fetched: the exception is for
                // attempting the instruction, not for what it would have read.
                exc_vec_r  <= VEC_PRIVILEGED;
                exc_code_r <= CODE_PRIVILEGED;
                exc_kind   <= EK_INSN;
                state      <= S_EXC_SW;
            end else if (op_alu(idu_op) == ALU_BRK) begin
                // Vector 13, unconditionally, with the Instruction Exceptions
                // frame -- the code word, the PSW, and the CURRENT PC.
                //
                // The Current PC is the whole point and its own Operation
                // block gets it wrong, printing NextPC last.  §8's prose names
                // BRK as the only source of exception 13 and says the pushed
                // PC "contains the address of the instruction breakpoint ...
                // This allows the exception handler to restart the instruction
                // following the removal of the breakpoint" -- which only works
                // if the saved PC is the patched address.  §8's general rule
                // agrees: an exception DURING an instruction stacks the
                // Current PC, and BRK's whole effect is the exception.  See
                // docs/v60/BREAK-AND-TRAP.md.
                //
                // So a handler that returns with RETIS #4 without first
                // removing the breakpoint re-executes it forever, which is the
                // intended behaviour.
                exc_vec_r  <= VEC_BREAKPOINT;
                exc_code_r <= CODE_BREAKPOINT;
                exc_kind   <= EK_INSN;
                state      <= S_EXC_SW;
            end else if (op_alu(idu_op) == ALU_BRKV) begin
                // "The OV flag is tested and if set, an Integer Overflow
                // Exception occurs.  Otherwise, instruction execution
                // continues with the next instruction."  Its frame is
                // Figure 8-5's Arithmetic Exceptions frame -- the Current PC
                // as a parameter above the code word and the NEXT PC on top --
                // which is what EK_ARITH already builds for a zero divide, and
                // its Operation block is where v60_exc's header got the push
                // order in the first place.
                if (psw[PSW_OV]) begin
                    exc_vec_r  <= VEC_INT_ARITH;
                    exc_code_r <= CODE_INT_OVERFLOW;
                    exc_kind   <= EK_ARITH;
                    state      <= S_EXC_SW;
                end else begin
                    // One byte, and nothing happens.
                    state <= S_RETIRE;
                end
            end else if (op_alu(idu_op) == ALU_HALT) begin
                // Retire first, wait after: see halted_r above.  The privilege
                // check has already run, before this, because it runs before
                // any operand is fetched and HALT has none.
                halted_r <= 1'b1;
                state    <= S_RETIRE;
            end else if (op_alu(idu_op) == ALU_TRAPFL) begin
                // Its two inputs are both registers -- the PSW here and TKCW
                // in the register file -- so the only thing this state does is
                // ask for TKCW.  Privileged register id 8; see the ID table on
                // LDPR's and STPR's pages.
                rf_pr_id <= 5'd8;
                state    <= S_TRAPFL;
            end else if (op_alu(idu_op) == ALU_GETPSW) begin
                // Its one operand is write-only and the value it writes is the
                // PSW, which lives here rather than in the address unit.
                val1  <= {32'd0, psw};
                state <= S_OP2;
            end else if (op_alu(idu_op) == ALU_NOP) begin
                // Format V, no operands, "no action is taken".  Its Operation
                // line is "PC <- PC + 1", which S_RETIRE does from idu_len.
                state <= S_RETIRE;
            end else if (op_alu(idu_op) == ALU_POP) begin
                // Nothing to read before the stack: POP's one operand is where
                // the word GOES.
                state <= S_PSH_R;
            end else if (op_alu(idu_op) == ALU_PUSH) begin
                // PUSH's one operand is a SOURCE, so it goes down the source
                // path even though Format III normally means "destination".
                state <= S_OP1;
            end else if (fmt_iii) begin
                // One operand, and it is the destination.  There is no source
                // to read, so the source path is skipped outright -- and the
                // operand's value is given to BOTH val1 and val2 below, so
                // that TEST, whose operand is what v60_alu reads as `x`, and
                // INC and DEC, whose operand is `y`, are both served without
                // the sequencer having to know which.
                state <= S_OP2;
            end else if ((idu_fmt != FMT_II) && (idu_fmt != FMT_I)) begin
                // Formats IV to VII: not sequenced here.
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
            if (io_src_bad || movea_src_bad) begin
                // A source operand whose addressing mode the page marks X:
                // IN's port named a register, or MOVEA was asked for the
                // address of something that has none.  Raised before the
                // access, like every other Instruction Exception here.
                exc_vec_r  <= VEC_ILLEGAL_MODE;
                exc_code_r <= CODE_ILLEGAL_MODE;
                exc_kind   <= EK_INSN;
                state      <= S_EXC_SW;
            end else if (src_is_reg) begin
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
                // DEFECT this fixes, as well as implementing MOVEA.  Every
                // other field of the descriptor was set here and this one was
                // not, so a JMP or JSR -- which sets it -- left it set into the
                // NEXT instruction, whose source operand was then computed as
                // an address and never read.  The same defect was found and
                // fixed on the destination side in S_OP2 and the source side
                // was missed; it survived because no test had a memory source
                // in the instruction immediately after a control transfer.
                ea_addr_only  <= src_addr_only;
                // IN reads its port here; every other instruction's source is
                // memory.
                ea_io         <= io_src;
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
                // STPR's source is not a value but the NAME of one.
                if      (aop == ALU_STPR) state <= S_PR_SEL;
                else if (is_push)         state <= S_PSH_R;
                else                      state <= S_OP2;
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
                    // MOVEA wants the address, not what is at it.
                    val1  <= src_addr_only ? {32'd0, ea_ea} : ea_rdata;
                    if      (aop == ALU_STPR) state <= S_PR_SEL;
                    else if (is_push)         state <= S_PSH_R;
                    else                      state <= S_OP2;
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
            // ... and only when the second operand really IS a destination.
            // §8 defines the exception as "an attempt to use an immediate
            // addressing mode as the DESTINATION operand", and CMP, TEST and
            // the UPDPSW pair have no destination operand at all -- every one
            // of their syntax lines is ".r".  UPDPSW's page says so outright:
            // "if the immediate quick addressing mode is specified, the
            // immediate data is zero extended to 32-bit length and used as the
            // new PSW or MASK operand", and the mask is the second operand.
            //
            // DEFECT this fixes: the check was unconditional, so `cmp src, #imm`
            // and every UPDPSW with an immediate mask raised Illegal Addressing
            // Mode instead of executing.
            if (io_dst_bad) begin
                // OUT's port operand named a register: same rule, other side.
                exc_vec_r  <= VEC_ILLEGAL_MODE;
                exc_code_r <= CODE_ILLEGAL_MODE;
                exc_kind   <= EK_INSN;
                state      <= S_EXC_SW;
            end else if (bit_off_bad) begin
                // Before the base is addressed at all.  Illegal Data Field is
                // an Instruction Exception, so its frame carries the CURRENT
                // PC and the handler restarts the instruction -- which a
                // read-modify-write that had already read its base would make
                // a lie.  Same rule as LDPR's and STPR's id checks above.
                exc_vec_r  <= VEC_ILLEGAL_DATA;
                exc_code_r <= CODE_ILLEGAL_DATA;
                exc_kind   <= EK_INSN;
                state      <= S_EXC_SW;
            end else if (!dst_is_reg && !dst_read_only && am_is_immediate(dst_mode)) begin
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
                // An operation that reads its destination and writes the same
                // place computes the address once; one that only writes does
                // not read at all; and one that only reads must not leave a
                // write pending behind it.
                ea_rmw        <= !dst_write_only && !dst_read_only;
                // Every field of the descriptor is set before an access
                // starts: JMP leaves this one set, and the next instruction
                // would otherwise compute its destination address and never
                // write to it.
                ea_addr_only  <= 1'b0;
                // OUT writes its port here.
                ea_io         <= io_dst;
                ea_pc_val     <= idu_pc;
                state         <= S_OP2R;
            end
        end

        S_OP2R: begin
            ea_rn_val <= rf_ra;
            ea_rx_val <= rf_rb;
            if (dst_is_reg) begin
                val2  <= {32'd0, rf_ra};
                // Format III's one operand is usually both the thing read and
                // the thing written, so it is mirrored into val1 -- but not
                // when the operand is write-only.  GETPSW is Format III with a
                // "dst.w.w" operand and the value it writes is the PSW, which
                // S_FETCH has already put in val1; mirroring would overwrite
                // it with the destination register's old contents.
                if (fmt_iii && !dst_write_only) val1 <= {32'd0, rf_ra};
                state <= S_EXEC;
            end else if (dst_write_only) begin
                // Written and not read -- see dst_write_only above -- so the
                // read is skipped and only the write happens.  The descriptor
                // is already set.
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
                if (fmt_iii && !dst_write_only) val1 <= ea_rdata;
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
                    if (fmt_iii && !dst_write_only) val1 <= ea_rdata;
                    state <= S_EXEC;
                end
            end
        end

        // ---- execute ---------------------------------------------------------
        S_EXEC: begin
            // LDPR's id arrived with its SECOND operand, so this is the first
            // point it can be checked -- and, as at S_PR_SEL above, the first
            // point is the only correct one: the exception restarts the
            // instruction, so nothing may have been committed.  LDPR writes no
            // operand, so what is being protected here is the privileged
            // register itself.
            if (ldpr_id_bad) begin
                exc_vec_r  <= VEC_ILLEGAL_DATA;
                exc_code_r <= CODE_ILLEGAL_DATA;
                exc_kind   <= EK_INSN;
                state      <= S_EXC_SW;
            end
            // The ALU is combinational and its inputs are already presented.
            // v60_muldiv is not, so those six are started here and waited on.
            else if (md_is) begin
                md_start <= 1'b1;
                md_used  <= 1'b1;
                state    <= S_MD;
            end else begin
                md_used <= 1'b0;
                state   <= S_WB;
            end
        end

        S_MD: if (md_done) begin
            md_result_r <= md_result;
            md_flags_r  <= md_flags;
            md_writes_r <= md_writes;
            md_zd_r     <= md_zero_div;
            state       <= S_WB;
        end

        S_WB: begin
            if (!eff_writes) begin
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
                rf_wr_data <= eff_result;
                state      <= S_RETIRE;
            end else if (ea_rmw_pending) begin
                ea_rmw_data <= {32'd0, eff_result};
                ea_rmw_go   <= 1'b1;
                state       <= S_WBW;
            end else begin
                // MOV to memory: the address is computed for the write.
                // OUT's is a port, and `ea_io` was set with the rest of the
                // descriptor in S_OP2 -- it is still set here, which is what
                // makes the write an I/O cycle.
                ea_we    <= 1'b1;
                ea_wdata <= {32'd0, eff_result};
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
            // UPDPSW is the exception: it writes the whole PSW under a mask
            // rather than leaving four flags behind, and its Condition Codes
            // block is one line -- "Updated according to mask operand".
            if (is_updpsw) psw <= updpsw_next;
            else           psw <= psw_set_flags(psw, eff_flags);
            if (wb_rn_en) begin
                rf_wr_en   <= 1'b1;
                rf_wr_sel  <= wb_rn_sel;
                rf_wr_data <= wb_rn_val;
            end
            // LDPR's destination is not an operand, so it is written here
            // rather than at S_WB.  The id has already been range-checked at
            // S_EXEC; what v60_regfile does with an id inside 0..31 that names
            // no register is its own per-id table's business, and the pages
            // call that case unpredictable rather than an exception.
            if (aop == ALU_LDPR) begin
                rf_pr_id    <= val2[4:0];
                rf_pr_wr    <= 1'b1;
                rf_pr_wdata <= val1[31:0];
            end
            // A divide by zero is raised HERE and not in S_MD, because a
            // read-modify-write destination still has an access open at that
            // point and closing it -- with what was already there, since "the
            // destination operand remains unchanged" -- is what S_WB and
            // S_WBW have just done.  An exception is raised between operand
            // accesses and never during one, which is what lets v60_dmux be a
            // mux rather than a third bus master.
            if (md_zd_r) begin
                md_zd_r    <= 1'b0;
                exc_vec_r  <= VEC_INT_ARITH;
                exc_code_r <= CODE_ZERO_DIVIDE;
                exc_kind   <= EK_ARITH;
                state      <= S_EXC_SW;
            end else if (trap_taken) begin
                // Raised here rather than at S_EXEC for the reason above: the
                // operand's access is finished and its addressing-mode
                // writeback has just been issued, so the exception happens
                // between accesses.  TRAP's operand is read-only, so there is
                // no destination write to drop.
                exc_vec_r  <= trap_vec_no;
                exc_code_r <= trap_code;
                exc_kind   <= EK_TRAP;
                state      <= S_EXC_SW;
            end else begin
                pc      <= idu_pc + {27'd0, idu_len};
                retired <= 1'b1;
                state   <= S_IDLE;
            end
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
                // RETIU and RETIS: the count operand first.  RETIS is the
                // privileged half of the pair -- its Exceptions list begins
                // "Privileged Instruction" and RETIU's does not -- and "programs
                // executing at other execution levels (levels 1, 2 and 3) are
                // said to be non-privileged and attempts to execute a
                // privileged instruction will cause an exception" (PgmRef §6).
                CTRL_RETIU, CTRL_RETIS: begin
                    if ((cop == CTRL_RETIS) &&
                        (psw[PSW_EL_HI:PSW_EL_LO] != 2'b00)) begin
                        exc_vec_r  <= VEC_PRIVILEGED;
                        exc_code_r <= CODE_PRIVILEGED;
                        exc_kind   <= EK_INSN;
                        state      <= S_EXC_SW;
                    end else begin
                        rf_ra_sel    <= op1_rn;
                        ea_rn_sel    <= op1_rn;
                        rf_rb_sel    <= op1_rx;
                        ea_mode      <= op1_mode;
                        ea_index     <= op1_index;
                        ea_disp      <= op1_disp;
                        ea_disp_outer<= op1_disp_outer;
                        ea_imm       <= op1_imm;
                        ea_opbytes   <= w_src;      // a halfword, from the table
                        ea_we        <= 1'b0;
                        ea_rmw       <= 1'b0;
                        ea_addr_only <= 1'b0;
                        ea_pc_val    <= idu_pc;
                        state        <= S_CTRL_EAR;
                    end
                end
                // RET's `num`, the bytes of arguments to discard.  A word,
                // where the two RETIs take a halfword.
                CTRL_RET: begin
                    rf_ra_sel    <= op1_rn;
                    ea_rn_sel    <= op1_rn;
                    rf_rb_sel    <= op1_rx;
                    ea_mode      <= op1_mode;
                    ea_index     <= op1_index;
                    ea_disp      <= op1_disp;
                    ea_disp_outer<= op1_disp_outer;
                    ea_imm       <= op1_imm;
                    ea_opbytes   <= w_src;
                    ea_we        <= 1'b0;
                    ea_rmw       <= 1'b0;
                    ea_addr_only <= 1'b0;
                    ea_pc_val    <= idu_pc;
                    state        <= S_CTRL_EAR;
                end
                // CALL wants two effective ADDRESSES, the target's and the
                // argument list's, and neither operand's contents.  Both scale
                // by four: "when the autoincrement, autodecrement, or scaled
                // index addressing modes are used for either the target or
                // argument operands, the contents of the pointer are modified
                // by four" (§7 CALL) -- which is why this does not do what
                // JMP and JSR do below and pass one byte.
                CTRL_CALL: begin
                    taken        <= 1'b1;
                    cpush        <= 1'b0;
                    rf_ra_sel    <= op1_rn;
                    ea_rn_sel    <= op1_rn;
                    rf_rb_sel    <= op1_rx;
                    ea_mode      <= op1_mode;
                    ea_index     <= op1_index;
                    ea_disp      <= op1_disp;
                    ea_disp_outer<= op1_disp_outer;
                    ea_imm       <= op1_imm;
                    ea_opbytes   <= 4'd4;
                    ea_we        <= 1'b0;
                    ea_rmw       <= 1'b0;
                    ea_addr_only <= 1'b1;
                    ea_pc_val    <= idu_pc;
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
            end else if ((cop == CTRL_RETIU) || (cop == CTRL_RETIS)) begin
                // "the data is zero extended to 16-bit length and used as the
                // count operand", and the operand is a halfword whatever mode
                // supplied it.  A count of bytes to discard, so zero extended
                // the rest of the way too.
                stk_cnt   <= {16'd0, ea_rdata[15:0]};
                rf_ra_sel <= 5'd31;
                stk_phase <= 1'b0;
                state     <= S_STK_SP;
            end else if (cop == CTRL_RET) begin
                stk_cnt   <= ea_rdata[31:0];
                rf_ra_sel <= 5'd31;
                stk_phase <= 1'b0;
                state     <= S_STK_SP;
            end else if (cop == CTRL_CALL) begin
                if (!cpush) begin
                    // "tmp1 <- effective_address( target )", then the argument
                    // list's, and only then is anything pushed.
                    target       <= ea_ea;
                    cpush        <= 1'b1;
                    rf_ra_sel    <= op2_rn;
                    ea_rn_sel    <= op2_rn;
                    rf_rb_sel    <= op2_rx;
                    ea_mode      <= op2_mode;
                    ea_index     <= op2_index;
                    ea_disp      <= op2_disp;
                    ea_disp_outer<= op2_disp_outer;
                    ea_imm       <= op2_imm;
                    ea_opbytes   <= 4'd4;
                    ea_we        <= 1'b0;
                    ea_rmw       <= 1'b0;
                    ea_addr_only <= 1'b1;
                    ea_pc_val    <= idu_pc;
                    state        <= S_CTRL_EAR;
                end else begin
                    stk_val   <= ea_ea;      // tmp2, the new AP
                    // Both at once: R29 is what gets pushed and R31 is where.
                    rf_ra_sel <= 5'd29;
                    rf_rb_sel <= 5'd31;
                    stk_phase <= 1'b0;
                    state     <= S_STK_SP;
                end
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

        // ---- the stack engine: CALL, RET, RETIU, RETIS ----------------------
        // The register file's outputs are valid the cycle after its selects,
        // so the stack pointer arrives here and the first access is described
        // from it rather than from the register that has not been read yet.
        S_STK_SP: begin
            ea_mode       <= AM_RN_IND;
            ea_index      <= 1'b0;
            ea_disp       <= 32'd0;
            ea_disp_outer <= 32'd0;
            ea_opbytes    <= 4'd4;
            ea_rmw        <= 1'b0;
            ea_addr_only  <= 1'b0;
            // AM_RN_IND moves no pointer, so these accesses raise no
            // addressing-mode writeback of their own and the stack pointer is
            // this module's to compute.  That is deliberate: RET moves SP by
            // 8 + num and RETIU/RETIS by 8 + count, neither of which any
            // addressing mode expresses.
            ea_rn_sel     <= 5'd0;
            if (cop == CTRL_CALL) begin
                // "[-SP] <- AP": the push goes BELOW the stack pointer.
                sp_r      <= rf_rb;
                ea_rn_val <= rf_rb - 32'd4;
                ea_we     <= 1'b1;
                ea_wdata  <= {32'd0, rf_ra};      // the old AP, R29
            end else begin
                sp_r      <= rf_ra;
                ea_rn_val <= rf_ra;
                ea_we     <= 1'b0;
            end
            state <= S_STK_S;
        end

        S_STK_S: begin
            ea_start <= 1'b1;
            state    <= S_STK_W;
        end

        S_STK_W: if (ea_done) begin
            insn_cycles <= insn_cycles + {1'b0, ea_bus_cycles};
            if (berr_r) begin
                exc_kind  <= EK_BERR;
                exc_vec_r <= VEC_BUS_FAULT;
                state     <= S_EXC_SW;
            end else if (!stk_phase) begin
                stk_phase <= 1'b1;
                state     <= S_STK_S;
                if (cop == CTRL_CALL) begin
                    // "[-SP] <- NextPC", the second word down.
                    ea_rn_val <= sp_r - 32'd8;
                    ea_wdata  <= {32'd0, next_pc};
                end else begin
                    // The PC is on top of the frame -- which is where v60_exc
                    // leaves it -- and the PSW or the AP is under it.
                    target    <= ea_rdata[31:0];
                    ea_rn_val <= sp_r + 32'd4;
                end
            end else begin
                if (cop != CTRL_CALL) stk_val <= ea_rdata[31:0];
                state <= S_STK_WB;
            end
        end

        // The addressing mode the count operand used, if it moved a register.
        // It goes down before this module's own writes, so that a count read
        // through [R31+] does not land on top of the stack pointer the engine
        // computed.
        S_STK_WB: begin
            // "an attempt is made to return to a more privileged execution
            // level" is the Illegal Data Field exception (RETIU, §7).  Levels
            // are "numbered from 0 to 3 with level 0 being the most
            // privileged" (§6), so more privileged is numerically smaller.
            if (((cop == CTRL_RETIU) || (cop == CTRL_RETIS)) &&
                (stk_val[PSW_EL_HI:PSW_EL_LO] < psw[PSW_EL_HI:PSW_EL_LO])) begin
                exc_vec_r  <= VEC_ILLEGAL_DATA;
                exc_code_r <= CODE_ILLEGAL_DATA;
                exc_kind   <= EK_INSN;
                state      <= S_EXC_SW;
            end else begin
                if (wb_rn_en) begin
                    rf_wr_en   <= 1'b1;
                    rf_wr_sel  <= wb_rn_sel;
                    rf_wr_data <= wb_rn_val;
                end
                state <= S_STK_FIN1;
            end
        end

        // The first of the two registers each of these writes.
        S_STK_FIN1: begin
            rf_wr_en <= 1'b1;
            if (cop == CTRL_CALL) begin
                rf_wr_sel  <= 5'd29;              // "AP <- tmp2"
                rf_wr_data <= stk_val;
            end else if (cop == CTRL_RET) begin
                rf_wr_sel  <= 5'd29;              // "AP <- [SP+]"
                rf_wr_data <= stk_val;
            end else begin
                // RETIU / RETIS: "SP <- SP + count", and the two pops moved it
                // by four each.  It is written BEFORE the stack switch, because
                // the switch saves R31 into the entry the old PSW names and the
                // value it saves has to be the finished one.
                rf_wr_sel  <= 5'd31;
                rf_wr_data <= sp_r + 32'd8 + stk_cnt;
            end
            state <= S_STK_FIN2;
        end

        S_STK_FIN2: begin
            if ((cop == CTRL_RETIU) || (cop == CTRL_RETIS)) begin
                // The restored PSW's {IS, EL} names the stack the interrupted
                // program was on.  Requested here and landing in S_STK_FIN3,
                // where `psw` is still the old one -- which is what makes the
                // save go to the right entry.
                rf_stack_switch <= 1'b1;
                rf_new_el       <= stk_val[PSW_EL_HI:PSW_EL_LO];
                rf_new_is       <= stk_val[PSW_IS];
            end else begin
                rf_wr_en  <= 1'b1;
                rf_wr_sel <= 5'd31;
                if (cop == CTRL_CALL) rf_wr_data <= sp_r - 32'd8;
                else                  rf_wr_data <= sp_r + 32'd8 + stk_cnt;
            end
            state <= S_STK_FIN3;
        end

        S_STK_FIN3: begin
            if ((cop == CTRL_RETIU) || (cop == CTRL_RETIS)) begin
                // "Condition Codes: CY / OV / S / Z Restored" -- the whole PSW
                // comes back, flags included, so this is an assignment and not
                // a merge.
                psw <= stk_val;
            end
            pc          <= target;
            redirect    <= 1'b1;
            redirect_pc <= target;
            retired     <= 1'b1;
            state       <= S_IDLE;
        end

        // TRAPFL, with TKCW now on the register file's read port.
        //
        // It is NOT a no-op, and implementing it as one would be a defect.
        // Nothing in this tree's hardware sets PSW[12:8] yet, because no
        // floating point instruction is implemented -- so the AND is zero and
        // this falls through.  That is a default and not a property: PSW[12:8]
        // are in the LOW halfword, so the non-privileged UPDPSW.H can set them,
        // and LDPR can load TKCW.  Software can arm this on a machine with no
        // floating point datapath at all, and then it must trap.
        S_TRAPFL: begin
            if (trapfl_take) begin
                exc_vec_r  <= VEC_FP_ARITH;
                exc_code_r <= trapfl_code;
                // Figure 8-5 groups #21 Integer, #22 Floating Point and #23
                // Decimal on one frame, which is the one EK_ARITH already
                // builds for BRKV and the zero divide: the Current PC as a
                // parameter above the code word, count 8, and the NEXT PC on
                // top -- so a handler returns past the trapfl.
                exc_kind   <= EK_ARITH;
                state      <= S_EXC_SW;
            end else begin
                state <= S_RETIRE;
            end
        end

        // STPR, between its two operands: the id is known and the value it
        // names is not.
        S_PR_SEL: begin
            if (stpr_id_bad) begin
                // Raised HERE, before the destination is addressed at all.
                // The Illegal Data Field exception is an Instruction
                // Exception, and Figure 8-5 gives that group the CURRENT PC --
                // so the handler restarts the instruction, and an instruction
                // that is going to be restarted must not have written its
                // destination or stepped an autoincrement first.  That is the
                // opposite of the zero divide and TRAP below, whose frames
                // carry the NEXT PC and whose writebacks therefore stand.
                exc_vec_r  <= VEC_ILLEGAL_DATA;
                exc_code_r <= CODE_ILLEGAL_DATA;
                exc_kind   <= EK_INSN;
                state      <= S_EXC_SW;
            end else begin
                rf_pr_id <= val1[4:0];
                state    <= S_PR_RD;
            end
        end

        // The privileged register, now on the port, becomes what the ALU will
        // pass through to the destination -- the same shape as GETPSW, whose
        // value also comes from outside the operand path.
        S_PR_RD: begin
            val1  <= {32'd0, rf_pr_rdata};
            state <= S_OP2;
        end

        // ---- PUSH and POP's stack access -------------------------------------
        S_PSH_R: begin
            rf_ra_sel <= 5'd31;
            state     <= S_PSH_SP;
        end

        S_PSH_SP: begin
            sp_r          <= rf_ra;
            ea_mode       <= AM_RN_IND;
            ea_index      <= 1'b0;
            ea_disp       <= 32'd0;
            ea_disp_outer <= 32'd0;
            ea_opbytes    <= 4'd4;      // "Push Word" / "Pop Word"
            ea_rmw        <= 1'b0;
            ea_addr_only  <= 1'b0;
            ea_io         <= 1'b0;
            // AM_RN_IND moves no pointer, so this access raises no
            // addressing-mode writeback and R31 is this module's to write.
            ea_rn_sel     <= 5'd0;
            ea_pc_val     <= idu_pc;
            if (is_push) begin
                // "The stack pointer (R31) is decremented by four and the
                // contents of the source operand are copied onto the stack" --
                // decrement FIRST, which is what [-SP] means.
                ea_rn_val <= rf_ra - 32'd4;
                ea_we     <= 1'b1;
                ea_wdata  <= val1;
            end else begin
                // "The word data located on the top of the stack is copied to
                // the destination operand.  The stack pointer (R31) is THEN
                // incremented by four."
                ea_rn_val <= rf_ra;
                ea_we     <= 1'b0;
            end
            state <= S_PSH_S;
        end

        S_PSH_S: begin
            ea_start <= 1'b1;
            state    <= S_PSH_W;
        end

        S_PSH_W: if (ea_done) begin
            insn_cycles <= insn_cycles + {1'b0, ea_bus_cycles};
            if (berr_r) begin
                // The stack access faulted, so the instruction does not retire
                // and R31 is left where it was.
                exc_kind  <= EK_BERR;
                exc_vec_r <= VEC_BUS_FAULT;
                state     <= S_EXC_SW;
            end else begin
                if (is_pop) val1 <= ea_rdata;
                state <= S_PSH_FIN;
            end
        end

        S_PSH_FIN: begin
            rf_wr_en   <= 1'b1;
            rf_wr_sel  <= 5'd31;
            rf_wr_data <= is_push ? (sp_r - 32'd4) : (sp_r + 32'd4);
            // PUSH is finished -- its operand was read on the way in.  POP
            // still has to put the word somewhere, and its operand is
            // write-only, so it joins the ordinary destination path.
            if (is_push) state <= S_RETIRE;
            else         state <= S_OP2;
        end

        // ---- an exception --------------------------------------------------
        // The stack first: R31 is the stack pointer the PSW's {IS, EL} names,
        // and the frame goes on the one the handler will run with, so the
        // register file switches before v60_exc pushes.  A switch to the same
        // entry is a no-op there, which is the ordinary case here -- this
        // sequencer runs at execution level 0 and these three exceptions
        // handle at execution level 0.
        S_EXC_SW: begin
            // Whatever woke it, the wait is over.  Cleared here rather than in
            // S_IDLE's three branches because every one of them arrives here.
            halted_r        <= 1'b0;
            rf_stack_switch <= 1'b1;
            rf_new_el       <= 2'd0;
            // Step (vii) puts an exception's frame on the stack the new
            // execution level names -- L0SP, or IS if that is where it already
            // was -- and that covers the instruction exceptions and the
            // arithmetic ones alike.  Two groups override it: an interrupt by
            // step (vii) itself, and the bus fault and system fault by §8's
            // prose about each group, all three of which go on the interrupt
            // stack outright.
            rf_new_is       <= ((exc_kind == EK_BERR) || (exc_kind == EK_INT))
                               ? 1'b1 : psw[PSW_IS];
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
            // Figure 8-5's Arithmetic Exceptions frame: the Current PC is a
            // PARAMETER above the code word, and the return PC on top is the
            // NEXT one -- which is BRKV's operation printed as a diagram,
            // "[-SP] <- CurrentPC ; [-SP] <- Exception Code ; [-SP] <- PSW ;
            // [-SP] <- NextPC".  So a zero-divide handler returns past the
            // instruction that divided, and the destination it left alone
            // stays alone.
            EK_ARITH: begin
                exc_ret_pc       <= idu_pc + {27'd0, idu_len};
                exc_nparams      <= 2'd1;
                exc_code         <= exc_code_r;
                exc_param0       <= idu_pc;
                exc_is_interrupt <= 1'b0;
                exc_disable_ie   <= 1'b0;
                exc_int_stack    <= 1'b0;
                exc_ack_vector   <= 1'b0;
            end
            // Figure 8-5's "#48-63 Software Traps": three words, count 4, no
            // parameter -- and the NEXT PC, which is what TRAP's own Operation
            // block pushes too.  So a handler returns PAST the trap with a
            // plain RETIS #4, which is what a system call needs and the exact
            // opposite of what BRK needs.
            EK_TRAP: begin
                exc_ret_pc       <= idu_pc + {27'd0, idu_len};
                exc_nparams      <= 2'd0;
                exc_code         <= exc_code_r;
                exc_param0       <= 32'd0;
                exc_is_interrupt <= 1'b0;
                // Step (ii) of the recognition sequence, databook p.3.269:
                // only an INTERRUPT clears PSW.IE.  "exception ... PSW.IE
                // unchanged".
                exc_disable_ie   <= 1'b0;
                exc_int_stack    <= 1'b0;
                exc_ack_vector   <= 1'b0;
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
