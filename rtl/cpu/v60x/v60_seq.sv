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
//  What this does not do
//  ---------------------------------------------------------------------------
//  * Anything v60_alu does not implement: the multiplies and divides, the
//    shifts and rotates, and every instruction outside the integer set.  The
//    generated table says which by returning ALU_NONE, and this stops on it
//    rather than doing something arbitrary.
//  * Branches, and therefore control flow.  Nothing redirects the prefetch
//    unit yet; the PC advances by the instruction's length and no other way.
//  * Exceptions.  v60_exc exists and is not wired in: it would want the data
//    unit that v60_ea is holding, which is the mux the plan describes.
//============================================================================
`timescale 1ns/1ps

module v60_seq
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

localparam logic [1:0] STOP_RESERVED = 2'd0;   // reserved opcode or mode
localparam logic [1:0] STOP_NO_ALU   = 2'd1;   // not an operation v60_alu has
localparam logic [1:0] STOP_FORMAT   = 2'd2;   // not a format this executes

typedef enum logic [3:0] {
    S_IDLE, S_FETCH,
    S_OP1, S_OP1R, S_OP1S, S_OP1W,     // describe, read registers, start, wait
    S_OP2, S_OP2R, S_OP2S, S_OP2W,
    S_EXEC, S_WB, S_WBW, S_RETIRE, S_STOP
} state_e;

state_e      state;
logic [63:0] val1, val2;
alu_op_e     aop;
logic [31:0] wb_rn_val;
logic        wb_rn_en;
logic  [4:0] wb_rn_sel;

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

v60_alu alu (
    .op(aop), .opbytes(alu_bytes),
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
        stop_reason   <= STOP_RESERVED;
        val1          <= 64'd0;
        val2          <= 64'd0;
        aop           <= ALU_NONE;
        wb_rn_en      <= 1'b0;
        wb_rn_sel     <= 5'd0;
        wb_rn_val     <= 32'd0;
    end else begin
        idu_start <= 1'b0;
        ea_start  <= 1'b0;
        ea_rmw_go <= 1'b0;
        rf_wr_en  <= 1'b0;
        retired   <= 1'b0;

        case (state)
        S_IDLE: if (run && !stopped) begin
            idu_start   <= 1'b1;
            insn_cycles <= 5'd0;
            wb_rn_en    <= 1'b0;
            state       <= S_FETCH;
        end

        S_FETCH: if (idu_done) begin
            pc  <= idu_pc;
            aop <= op_alu(idu_op);

            if (idu_res_op || idu_res_mode) begin
                stopped     <= 1'b1;
                stop_reason <= STOP_RESERVED;
                state       <= S_STOP;
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

        // ---- the source ------------------------------------------------------
        S_OP1: begin
            if (src_is_reg) begin
                // Format I with d = 0: the source is the register field.
                rf_ra_sel <= reg_operand;
                state     <= S_OP1R;
            end else begin
                rf_ra_sel     <= op1_rn;
                rf_rb_sel     <= op1_rx;
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
                val1        <= ea_rdata;
                insn_cycles <= insn_cycles + {1'b0, ea_bus_cycles};
                if (ea_rn_wb) begin
                    wb_rn_en  <= 1'b1;
                    wb_rn_sel <= op1_rn;
                    wb_rn_val <= ea_rn_wb_val;
                end
                state <= S_OP2;
            end
        end

        // ---- the destination, read as well when the operation needs its old
        // ---- value.
        S_OP2: begin
            if (dst_is_reg) begin
                // A register destination needs no address and no bus cycle:
                // its old value is read here and the result is written to the
                // file at retirement.
                rf_ra_sel <= reg_operand;
                state     <= S_OP2R;
            end else begin
                rf_ra_sel     <= dst_am_is_op2 ? op2_rn    : op1_rn;
                rf_rb_sel     <= dst_am_is_op2 ? op2_rx    : op1_rx;
                // The enum needs the branch spelled out: a ternary between
                // two enum values is not an enum to every tool.
                if (dst_am_is_op2) ea_mode <= op2_mode;
                else               ea_mode <= op1_mode;
                ea_index      <= dst_am_is_op2 ? op2_index : op1_index;
                ea_disp       <= dst_am_is_op2 ? op2_disp  : op1_disp;
                ea_disp_outer <= dst_am_is_op2 ? op2_disp_outer : op1_disp_outer;
                ea_imm        <= dst_am_is_op2 ? op2_imm   : op1_imm;
                ea_opbytes    <= w_dst;
                ea_we         <= 1'b0;
                // Everything except MOV reads its destination and writes the
                // same place, so the address is computed once.
                ea_rmw        <= (aop != ALU_MOV);
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
                val2  <= ea_rdata;
                state <= S_EXEC;
            end else if (ea_done) begin
                val2        <= ea_rdata;
                insn_cycles <= insn_cycles + {1'b0, ea_bus_cycles};
                state       <= S_EXEC;
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
            state       <= S_RETIRE;
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

        S_STOP: ;

        default: state <= S_IDLE;
        endcase
    end
end

endmodule
