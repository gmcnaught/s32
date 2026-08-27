//============================================================================
//  v60_idu -- one instruction, from the byte stream.
//
//  Clean-room.  This is the unit the databook names:
//
//    "The IDU (instruction decode unit) ... examines the instruction for
//     operand references and passes the operand addressing mode information to
//     the logic performing the effective address calculation."  -- p.3.246
//
//  It owns no format knowledge of its own.  v60_fmt_decode says what the
//  instruction's shape is and what follows the base word; v60_am_decode
//  decodes each mod field; this walks the plan:
//
//      base  ->  mod  ->  ext  ->  mod'  ->  ext'
//
//  in that order (p.3.293), taking bytes one at a time from v60_pfu and
//  handing back two operand descriptions in the shape v60_ea takes, plus the
//  instruction's length and the PC it started at.
//
//  What it does NOT do: execute, or decide what the operands MEAN.  Which
//  operand is the source and which the destination is the instruction's
//  semantics, not its encoding -- Format I has a `d` (direction) bit for
//  exactly that reason, and it is reported rather than acted on.
//============================================================================
`timescale 1ns/1ps

module v60_idu
    import v60_fmt_pkg::*;
    import v60_op_pkg::*;
    import v60_am_pkg::*;
(
    input               clk,
    input               rst,

    // ---- instruction stream, from v60_pfu ---------------------------------
    input         [7:0] byte_in,
    input               byte_valid,
    input        [31:0] byte_pc,
    output logic        byte_take,

    input               start,
    output logic        busy,
    output logic        done,

    // ---- the instruction ---------------------------------------------------
    output insn_fmt_e   fmt,
    output logic  [7:0] op,
    output logic        m,
    output logic        m2,
    output logic        d,              // Format I direction bit
    output logic  [4:0] reg_field,
    output logic  [4:0] subop,
    output logic [31:0] br_disp,        // Format IV / VI displacement
    output logic [31:0] insn_pc,        // the PC the opcode byte came from
    output logic  [4:0] insn_len,       // bytes, base and operands together
    // Two exceptions, not one: Table 8-1 gives the reserved OPCODE code 1000
    // and the reserved ADDRESSING MODE code 1200, and the system base table
    // gives them different vectors, so a sequencer has to tell them apart.
    output logic        reserved_op,
    output logic        reserved_mode,

    // ---- operand 1 ---------------------------------------------------------
    output logic        op1_valid,
    output am_mode_e    op1_mode,
    output logic  [4:0] op1_rn,
    output logic  [4:0] op1_rx,
    output logic        op1_index,
    output logic [31:0] op1_disp,
    output logic [31:0] op1_disp_outer,
    output logic [63:0] op1_imm,
    output logic        op1_ext_valid,
    output logic  [7:0] op1_ext,
    output logic  [3:0] op1_bytes,      // the operand's unit size

    // ---- operand 2 ---------------------------------------------------------
    output logic        op2_valid,
    output am_mode_e    op2_mode,
    output logic  [4:0] op2_rn,
    output logic  [4:0] op2_rx,
    output logic        op2_index,
    output logic [31:0] op2_disp,
    output logic [31:0] op2_disp_outer,
    output logic [63:0] op2_imm,
    output logic        op2_ext_valid,
    output logic  [7:0] op2_ext,
    output logic  [3:0] op2_bytes
);

typedef enum logic [2:0] {
    S_IDLE, S_BASE, S_MOD1, S_EXT1, S_MOD2, S_EXT2
} state_e;

state_e state;
logic   mod_first;     // the next byte starts a mod field
logic   in_op2;        // the mod field being decoded is the second

// ---- the format decoder ----------------------------------------------------
logic        f_start, f_bv;
wire         f_busy, f_done;
insn_fmt_e   f_fmt;
wire   [7:0] f_op;
wire         f_m, f_m2, f_d;
wire   [4:0] f_reg, f_subop;
wire  [31:0] f_disp;
wire   [3:0] f_len;
wire         f_need_mod, f_need_ext, f_need_mod2, f_need_ext2, f_m_mod, f_m_mod2;

v60_fmt_decode fd (
    .clk(clk), .rst(rst),
    .start(f_start), .byte_valid(f_bv), .byte_in(byte_in),
    .busy(f_busy), .done(f_done), .fmt_out(f_fmt),
    .op(f_op), .m(f_m), .m2(f_m2), .d(f_d), .reg_field(f_reg),
    .subop(f_subop), .disp(f_disp), .base_len(f_len),
    .need_mod(f_need_mod), .need_ext(f_need_ext), .need_mod2(f_need_mod2),
    .need_ext2(f_need_ext2), .m_mod(f_m_mod), .m_mod2(f_m_mod2)
);

// ---- the addressing-mode decoder, used once per mod field ------------------
logic        a_start, a_bv, a_m;
logic  [3:0] a_opbytes;
wire         a_busy, a_done;
am_mode_e    a_mode;
wire   [4:0] a_rn, a_rx;
wire         a_index, a_reserved;
wire  [31:0] a_disp, a_disp_outer;
wire  [63:0] a_imm;
wire   [3:0] a_len;

v60_am_decode amd (
    .clk(clk), .rst(rst),
    .start(a_start), .m(a_m), .opbytes(a_opbytes),
    .byte_valid(a_bv), .byte_in(byte_in),
    .busy(a_busy), .done(a_done), .mode(a_mode),
    .rn(a_rn), .rx(a_rx), .has_index(a_index),
    .disp(a_disp), .disp_outer(a_disp_outer),
    .imm(a_imm), .imm_bytes(), .len(a_len),
    .base_pc(), .base_none(), .reg_direct(), .immediate(),
    .mem_operand(), .ea_indirect(), .autoinc(), .autodec(),
    .reserved(a_reserved)
);

// The operand's data type, from the same generated table as the format: it is
// what an immed.N's width is (p.3.294 gives one mode code three rows), what a
// scaled index is multiplied by and what [Rn+] steps by (p.3.257, p.3.261).
//
// Two of the table's answers are not a width -- 0 for an operand that is not a
// datum, 15 for an instruction whose width the table does not carry -- and
// both fall back to four bytes here.  The fallback is visible: `bytes_known`
// says whether the width used was the table's, and the simulation check below
// names the opcode when it is not.
wire [3:0] tbl_bytes   = op_data_bytes(op, subop, in_op2);
wire       bytes_known = (tbl_bytes == 4'd1) || (tbl_bytes == 4'd2) ||
                         (tbl_bytes == 4'd4) || (tbl_bytes == 4'd8);
assign a_opbytes = bytes_known ? tbl_bytes : 4'd4;

// ---- stream ----------------------------------------------------------------
// Both sub-decoders acknowledge one cycle AFTER their last byte, so the byte
// present on that cycle belongs to the next stage and must not be taken here.
// `busy` on each of them is what says the difference.
wire feeding_base = (state == S_BASE) && ((insn_len == 5'd0) || f_busy);
wire feeding_mod  = ((state == S_MOD1) || (state == S_MOD2)) &&
                    (mod_first || a_busy);
wire feeding_ext  = (state == S_EXT1) || (state == S_EXT2);

assign f_bv      = byte_valid && feeding_base;
assign a_bv      = byte_valid && feeding_mod;
assign byte_take = byte_valid && (feeding_base || feeding_mod || feeding_ext);
assign busy      = (state != S_IDLE);

wire took = byte_take;

always_comb begin
    f_start = 1'b0;
    a_start = 1'b0;
    if (feeding_base && byte_valid && (insn_len == 5'd0)) f_start = 1'b1;
    if (feeding_mod  && byte_valid && mod_first)          a_start = 1'b1;

end

always_ff @(posedge clk) begin
    if (rst) begin
        state          <= S_IDLE;
        done           <= 1'b0;
        mod_first      <= 1'b0;
        in_op2         <= 1'b0;
        fmt            <= FMT_UNKNOWN;
        op             <= 8'd0;
        m              <= 1'b0;
        m2             <= 1'b0;
        d              <= 1'b0;
        reg_field      <= 5'd0;
        subop          <= 5'd0;
        br_disp        <= 32'd0;
        insn_pc        <= 32'd0;
        insn_len       <= 5'd0;
        reserved_op    <= 1'b0;
        reserved_mode  <= 1'b0;
        op1_bytes      <= 4'd0;
        op2_bytes      <= 4'd0;
        op1_valid      <= 1'b0;
        op1_ext_valid  <= 1'b0;
        op1_ext        <= 8'd0;
        op2_valid      <= 1'b0;
        op2_ext_valid  <= 1'b0;
        op2_ext        <= 8'd0;
        a_m            <= 1'b0;
    end else begin
        done <= 1'b0;

        case (state)
        S_IDLE: if (start) begin
            state         <= S_BASE;
            insn_len      <= 5'd0;
            reserved_op   <= 1'b0;
            reserved_mode <= 1'b0;
            op1_valid     <= 1'b0;
            op2_valid     <= 1'b0;
            op1_ext_valid <= 1'b0;
            op2_ext_valid <= 1'b0;
            in_op2        <= 1'b0;
        end

        S_BASE: begin
            if (took) begin
                // The opcode byte's PC is the instruction's PC.
                if (insn_len == 5'd0) insn_pc <= byte_pc;
                insn_len <= insn_len + 5'd1;
            end
            if (f_done) begin
                fmt       <= f_fmt;
                op        <= f_op;
                m         <= f_m;
                m2        <= f_m2;
                d         <= f_d;
                reg_field <= f_reg;
                subop     <= f_subop;
                br_disp   <= f_disp;
                a_m       <= f_m_mod;
                mod_first <= 1'b1;
                in_op2    <= 1'b0;

                if (f_fmt == FMT_UNKNOWN) begin
                    // Nothing can be said about what follows a reserved
                    // opcode, so this stops and says so.
                    reserved_op <= 1'b1;
                    state       <= S_IDLE;
                    done        <= 1'b1;
                end else if (f_need_mod) begin
                    state <= S_MOD1;
                end else begin
                    state <= S_IDLE;
                    done  <= 1'b1;
                end
            end
        end

        S_MOD1, S_MOD2: begin
            if (took) begin
                insn_len  <= insn_len + 5'd1;
                mod_first <= 1'b0;
            end
            if (a_done) begin
                if (!in_op2) begin
                    op1_valid      <= 1'b1;
                    op1_mode       <= a_mode;
                    op1_rn         <= a_rn;
                    op1_rx         <= a_rx;
                    op1_index      <= a_index;
                    op1_disp       <= a_disp;
                    op1_disp_outer <= a_disp_outer;
                    op1_imm        <= a_imm;
                    op1_bytes      <= a_opbytes;
                end else begin
                    op2_valid      <= 1'b1;
                    op2_mode       <= a_mode;
                    op2_rn         <= a_rn;
                    op2_rx         <= a_rx;
                    op2_index      <= a_index;
                    op2_disp       <= a_disp;
                    op2_disp_outer <= a_disp_outer;
                    op2_imm        <= a_imm;
                    op2_bytes      <= a_opbytes;
                end
                if (a_reserved) reserved_mode <= 1'b1;

                if (a_reserved) begin
                    // A reserved addressing mode has no length either.
                    state <= S_IDLE;
                    done  <= 1'b1;
                end else if (!in_op2) begin
                    if (f_need_ext)       state <= S_EXT1;
                    else if (f_need_mod2) begin
                        state     <= S_MOD2;
                        mod_first <= 1'b1;
                        in_op2    <= 1'b1;
                        a_m       <= f_m_mod2;
                    end else begin
                        state <= S_IDLE;
                        done  <= 1'b1;
                    end
                end else begin
                    if (f_need_ext2) state <= S_EXT2;
                    else begin
                        state <= S_IDLE;
                        done  <= 1'b1;
                    end
                end
            end
        end

        // The extension field is one byte, and its encoding -- a length, or a
        // register holding one -- is v60_fmt_pkg's ext_value/ext_is_register.
        S_EXT1: if (took) begin
            insn_len      <= insn_len + 5'd1;
            op1_ext       <= byte_in;
            op1_ext_valid <= 1'b1;
            if (f_need_mod2) begin
                state     <= S_MOD2;
                mod_first <= 1'b1;
                in_op2    <= 1'b1;
                a_m       <= f_m_mod2;
            end else begin
                state <= S_IDLE;
                done  <= 1'b1;
            end
        end

        S_EXT2: if (took) begin
            insn_len      <= insn_len + 5'd1;
            op2_ext       <= byte_in;
            op2_ext_valid <= 1'b1;
            state         <= S_IDLE;
            done          <= 1'b1;
        end

        default: state <= S_IDLE;
        endcase
    end
end

// synthesis translate_off
always_ff @(posedge clk) begin
    if (!rst && (state == S_MOD1 || state == S_MOD2) && a_start && !bytes_known)
        $display("WARN v60_idu: opcode %02X operand %0d has no width in the instruction table -- four bytes assumed (t=%0t)",
                 op, in_op2 + 1, $time);
    // "Instructions formats have a 1 to 9 byte mod (modifier) field" (p.3.294)
    // and the longest base is four bytes, so no instruction this decodes can
    // be longer than two mod fields, two extension bytes and that base.
    if (!rst && done && (insn_len > 5'd24))
        $display("WARN v60_idu: decoded a %0d byte instruction (t=%0t)",
                 insn_len, $time);
end
// synthesis translate_on

endmodule
