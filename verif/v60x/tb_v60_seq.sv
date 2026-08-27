//============================================================================
//  tb_v60_seq -- instructions executed, off the bus, end to end.
//
//  The whole processor this project has: v60_biu fetching through
//  v60_bus_arb for v60_pfu, v60_idu decoding, v60_regfile holding the
//  registers, v60_ea resolving operands through v60_dxu on the same bus, and
//  v60_seq sequencing and retiring.
//
//  The program below moves an immediate into a register, adds to it, compares
//  it, stores it to memory through a register-indirect destination, and adds a
//  word to memory in place -- which is the read-modify-write path, and the one
//  where the address must be computed once rather than twice.
//
//  Results are observed the way a program would: through memory, through the
//  PSW, and through the PC.
//============================================================================
`timescale 1ns/1ps

module tb_v60_seq;
    import v60_bus_pkg::*;
    import v60_fmt_pkg::*;
    import v60_am_pkg::*;
    import v60_alu_pkg::*;
    import v60_psw_pkg::*;

localparam integer DIV = 6;

reg clk = 1'b0;
always #5 clk = ~clk;

reg rst = 1'b1;

reg [2:0] tick = 3'd0;
always @(posedge clk) if (!rst) tick <= (tick == DIV-1) ? 3'd0 : tick + 3'd1;
wire ce_rise = !rst && (tick == 3'd0);
wire ce_fall = !rst && (tick == DIV/2);

// ---- prefetch ----------------------------------------------------------------
reg          redirect = 1'b0;
reg   [31:0] redirect_pc = 32'd0;
wire   [7:0] byte_out;
wire         byte_valid, byte_take;
wire  [31:0] byte_pc;
wire         p_req, p_ack;
bus_status_e p_status;
wire  [23:0] p_addr;
wire   [1:0] p_dl;
wire  [15:0] biu_rdata;

v60_pfu pfu (
    .clk(clk), .rst(rst),
    .byte_out(byte_out), .byte_valid(byte_valid), .byte_take(byte_take),
    .byte_pc(byte_pc), .redirect(redirect), .redirect_pc(redirect_pc),
    .bus_req(p_req), .bus_status(p_status), .bus_addr(p_addr), .bus_dl(p_dl),
    .bus_ack(p_ack), .bus_rdata(biu_rdata), .level()
);

// ---- decode ------------------------------------------------------------------
wire         idu_start, idu_done, res_op, res_mode;
insn_fmt_e   idu_fmt;
wire   [7:0] idu_op;
wire  [31:0] idu_pc;
wire   [4:0] idu_len;
wire         o1_valid, o1_index, o2_valid, o2_index;
am_mode_e    o1_mode, o2_mode;
wire   [4:0] o1_rn, o1_rx, o2_rn, o2_rx;
wire  [31:0] o1_disp, o1_douter, o2_disp, o2_douter;
wire  [63:0] o1_imm, o2_imm;
wire   [3:0] o1_bytes, o2_bytes;

v60_idu idu (
    .clk(clk), .rst(rst),
    .byte_in(byte_out), .byte_valid(byte_valid), .byte_pc(byte_pc),
    .byte_take(byte_take),
    .start(idu_start), .busy(), .done(idu_done),
    .fmt(idu_fmt), .op(idu_op), .m(), .m2(), .d(), .reg_field(), .subop(),
    .br_disp(), .insn_pc(idu_pc), .insn_len(idu_len),
    .reserved_op(res_op), .reserved_mode(res_mode),
    .op1_valid(o1_valid), .op1_mode(o1_mode), .op1_rn(o1_rn), .op1_rx(o1_rx),
    .op1_index(o1_index), .op1_disp(o1_disp), .op1_disp_outer(o1_douter),
    .op1_imm(o1_imm), .op1_ext_valid(), .op1_ext(), .op1_bytes(o1_bytes),
    .op2_valid(o2_valid), .op2_mode(o2_mode), .op2_rn(o2_rn), .op2_rx(o2_rx),
    .op2_index(o2_index), .op2_disp(o2_disp), .op2_disp_outer(o2_douter),
    .op2_imm(o2_imm), .op2_ext_valid(), .op2_ext(), .op2_bytes(o2_bytes)
);

// ---- registers ----------------------------------------------------------------
wire  [4:0] rf_ra_sel, rf_rb_sel, rf_wr_sel;
wire [31:0] rf_ra, rf_rb, rf_wr_data;
wire        rf_wr_en;

v60_regfile rf (
    .clk(clk), .rst(rst),
    .ra_sel(rf_ra_sel), .rb_sel(rf_rb_sel), .ra(rf_ra), .rb(rf_rb), .ra_pair(),
    .wr_en(rf_wr_en), .wr_sel(rf_wr_sel), .wr_data(rf_wr_data),
    .psw_el(2'd0), .psw_is(1'b0),
    .stack_switch(1'b0), .new_el(2'd0), .new_is(1'b0),
    .pr_id(5'd0), .pr_wr(1'b0), .pr_wdata(32'd0),
    .pr_rdata(), .pr_rd_ok(), .pr_wr_ok(), .sbr()
);

// ---- address unit and data unit ------------------------------------------------
wire        ea_start, ea_index, ea_we, ea_rmw, ea_rmw_go, ea_rmw_pending;
am_mode_e   ea_mode;
wire [31:0] ea_disp, ea_douter, ea_rn_val, ea_rx_val, ea_pc_val, ea_ea;
wire [63:0] ea_imm, ea_wdata, ea_rmw_data, ea_rdata;
wire  [3:0] ea_opbytes, ea_cycles;
wire        ea_done, ea_rn_wb;
wire [31:0] ea_rn_wb_val;

wire        dx_req, dx_we, dx_done;
wire [23:0] dx_addr;
wire  [3:0] dx_nbytes, dx_cycles;
wire [63:0] dx_wdata, dx_rdata;

v60_ea ea (
    .clk(clk), .rst(rst),
    .start(ea_start), .mode(ea_mode), .has_index(ea_index),
    .disp(ea_disp), .disp_outer(ea_douter), .imm(ea_imm),
    .rn_val(ea_rn_val), .rx_val(ea_rx_val), .pc_val(ea_pc_val),
    .opbytes(ea_opbytes), .we(ea_we), .wdata(ea_wdata),
    .rmw(ea_rmw), .rmw_pending(ea_rmw_pending), .rmw_go(ea_rmw_go),
    .rmw_data(ea_rmw_data),
    .ea(ea_ea), .rdata(ea_rdata), .rn_wb(ea_rn_wb), .rn_wb_val(ea_rn_wb_val),
    .illegal(), .busy(), .done(ea_done), .bus_cycles(ea_cycles),
    .dx_req(dx_req), .dx_addr(dx_addr), .dx_nbytes(dx_nbytes), .dx_we(dx_we),
    .dx_wdata(dx_wdata), .dx_rdata(dx_rdata), .dx_done(dx_done),
    .dx_cycles(dx_cycles)
);

wire         d_req, d_we, d_ube, d_first, d_ack;
bus_status_e d_status;
wire  [23:0] d_addr;
wire   [1:0] d_dl;
wire  [15:0] d_wdata;

v60_dxu dxu (
    .clk(clk), .rst(rst),
    .req(dx_req), .addr(dx_addr), .nbytes(dx_nbytes), .we(dx_we), .io(1'b0),
    .wdata(dx_wdata), .rdata(dx_rdata), .busy(), .done(dx_done),
    .cycles(dx_cycles),
    .biu_req(d_req), .biu_status(d_status), .biu_addr(d_addr),
    .biu_we(d_we), .biu_dl(d_dl), .biu_ube(d_ube), .biu_first(d_first),
    .biu_wdata(d_wdata), .biu_ack(d_ack), .biu_rdata(biu_rdata)
);

// ---- the sequencer --------------------------------------------------------------
reg          run = 1'b0;
wire  [31:0] seq_pc, seq_psw;
wire         retired, stopped;
wire   [1:0] stop_reason;
wire   [4:0] insn_cycles;

v60_seq seq (
    .clk(clk), .rst(rst), .run(run),
    .idu_start(idu_start), .idu_done(idu_done), .idu_fmt(idu_fmt),
    .idu_op(idu_op), .idu_pc(idu_pc), .idu_len(idu_len),
    .idu_res_op(res_op), .idu_res_mode(res_mode),
    .op1_valid(o1_valid), .op1_mode(o1_mode), .op1_rn(o1_rn), .op1_rx(o1_rx),
    .op1_index(o1_index), .op1_disp(o1_disp), .op1_disp_outer(o1_douter),
    .op1_imm(o1_imm), .op1_bytes(o1_bytes),
    .op2_valid(o2_valid), .op2_mode(o2_mode), .op2_rn(o2_rn), .op2_rx(o2_rx),
    .op2_index(o2_index), .op2_disp(o2_disp), .op2_disp_outer(o2_douter),
    .op2_imm(o2_imm), .op2_bytes(o2_bytes),
    .rf_ra_sel(rf_ra_sel), .rf_rb_sel(rf_rb_sel), .rf_ra(rf_ra), .rf_rb(rf_rb),
    .rf_wr_en(rf_wr_en), .rf_wr_sel(rf_wr_sel), .rf_wr_data(rf_wr_data),
    .ea_start(ea_start), .ea_mode(ea_mode), .ea_index(ea_index),
    .ea_disp(ea_disp), .ea_disp_outer(ea_douter), .ea_imm(ea_imm),
    .ea_rn_val(ea_rn_val), .ea_rx_val(ea_rx_val), .ea_pc_val(ea_pc_val),
    .ea_opbytes(ea_opbytes), .ea_we(ea_we), .ea_wdata(ea_wdata),
    .ea_rmw(ea_rmw), .ea_rmw_go(ea_rmw_go), .ea_rmw_data(ea_rmw_data),
    .ea_rmw_pending(ea_rmw_pending), .ea_ea(ea_ea), .ea_rdata(ea_rdata),
    .ea_rn_wb(ea_rn_wb), .ea_rn_wb_val(ea_rn_wb_val), .ea_done(ea_done),
    .ea_bus_cycles(ea_cycles),
    .pc(seq_pc), .psw(seq_psw), .retired(retired), .insn_cycles(insn_cycles),
    .stopped(stopped), .stop_reason(stop_reason)
);

// ---- arbiter, bus, memory --------------------------------------------------------
wire         biu_req, biu_we, biu_ube, biu_first, biu_ack, biu_busy, own_pfu;
bus_status_e biu_status;
wire  [23:0] biu_addr;
wire   [1:0] biu_dl;
wire  [15:0] biu_wdata;

v60_bus_arb arb (
    .clk(clk), .rst(rst),
    .d_req(d_req), .d_status(d_status), .d_addr(d_addr), .d_we(d_we),
    .d_dl(d_dl), .d_ube(d_ube), .d_first(d_first), .d_wdata(d_wdata),
    .d_ack(d_ack),
    .p_req(p_req), .p_status(p_status), .p_addr(p_addr), .p_dl(p_dl),
    .p_ack(p_ack),
    .biu_req(biu_req), .biu_status(biu_status), .biu_addr(biu_addr),
    .biu_we(biu_we), .biu_dl(biu_dl), .biu_ube(biu_ube), .biu_first(biu_first),
    .biu_wdata(biu_wdata), .biu_ack(biu_ack), .biu_busy(biu_busy),
    .own_pfu(own_pfu)
);

wire [23:0] a;
wire  [1:0] dl_o;
wire  [2:0] st;
wire        mrq_n, rw_n, ube_n, fas_n, bcy_n, ds_n, d_oe, bus_hiz, hldak_n;
wire [15:0] d_out;
reg  [15:0] d_in;
bus_state_e state;

v60_biu biu (
    .clk(clk), .rst(rst), .ce_rise(ce_rise), .ce_fall(ce_fall),
    .req(biu_req), .status(biu_status), .addr(biu_addr), .we(biu_we),
    .dl(biu_dl), .ube(biu_ube), .first(biu_first), .wdata(biu_wdata),
    .ack(biu_ack), .rdata(biu_rdata), .busy(biu_busy),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .ds_n(ds_n),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .bus_hiz(bus_hiz),
    .ready_n(1'b0), .bmode(1'b1), .hldrq_n(1'b1), .hldak_n(hldak_n),
    .state(state)
);

reg  [7:0] mem [0:2047];
wire [10:0] bank_even = {a[10:1], 1'b0};
always @(*) d_in = {mem[bank_even + 11'd1], mem[bank_even]};

always @(posedge clk) if (!rst && biu_ack && !rw_n) begin
    case ({ube_n, a[0]})
        2'b00: begin mem[bank_even] = d_out[7:0];
                     mem[bank_even + 11'd1] = d_out[15:8]; end
        2'b01: mem[bank_even + 11'd1] = d_out[15:8];
        2'b10: mem[bank_even] = d_out[7:0];
        default: ;
    endcase
end

integer errors = 0;
task chk(input cond, input [8*72:1] what);
begin
    if (!cond) begin
        errors = errors + 1;
        $display("FAIL  %0s (t=%0t)", what, $time);
    end
end
endtask

// Run one instruction and stop on its retirement.
reg [31:0] last_pc;
task step;
begin
    last_pc = seq_pc;
    run = 1'b1;
    @(negedge clk);
    while (!retired && !stopped) @(negedge clk);
    run = 1'b0;
    @(negedge clk);
end
endtask

integer i;

initial begin
    for (i = 0; i < 2048; i = i + 1) mem[i] = 8'h00;

    // ---- the program, at 0x100 -----------------------------------------------
    // MOV.B #0x5A, R8        09 A0 F4 5A 68     (source immediate, dest register)
    mem[11'h100] = 8'h09; mem[11'h101] = 8'hA0; mem[11'h102] = 8'hF4;
    mem[11'h103] = 8'h5A; mem[11'h104] = 8'h68;
    // ADD.b #1, R8           80 A0 F4 01 68
    mem[11'h105] = 8'h80; mem[11'h106] = 8'hA0; mem[11'h107] = 8'hF4;
    mem[11'h108] = 8'h01; mem[11'h109] = 8'h68;
    // CMP.b #0x5B, R8        B8 A0 F4 5B 68     (equal: sets Z, writes nothing)
    mem[11'h10A] = 8'hB8; mem[11'h10B] = 8'hA0; mem[11'h10C] = 8'hF4;
    mem[11'h10D] = 8'h5B; mem[11'h10E] = 8'h68;
    // MOV.W #0x600, R9       2D A0 F4 00 06 00 00 69
    mem[11'h10F] = 8'h2D; mem[11'h110] = 8'hA0; mem[11'h111] = 8'hF4;
    mem[11'h112] = 8'h00; mem[11'h113] = 8'h06; mem[11'h114] = 8'h00;
    mem[11'h115] = 8'h00; mem[11'h116] = 8'h69;
    // MOV.B R8, [R9]         09 C0 68 69        (register source, memory dest)
    mem[11'h117] = 8'h09; mem[11'h118] = 8'hC0; mem[11'h119] = 8'h68;
    mem[11'h11A] = 8'h69;
    // MOV.W #0x610, R9      2D A0 F4 10 06 00 00 69   (R9 now points at a pointer)
    mem[11'h11B] = 8'h2D; mem[11'h11C] = 8'hA0; mem[11'h11D] = 8'hF4;
    mem[11'h11E] = 8'h10; mem[11'h11F] = 8'h06; mem[11'h120] = 8'h00;
    mem[11'h121] = 8'h00; mem[11'h122] = 8'h69;
    // ADD.b R8, [disp.8[R9]] 80 C0 68 89 00
    //   The destination is INDIRECT, so its address costs a pointer read.  A
    //   read-modify-write does that once; addressing it twice would do it
    //   again, and the bus cycle count is where the difference shows.
    mem[11'h123] = 8'h80; mem[11'h124] = 8'hC0; mem[11'h125] = 8'h68;
    mem[11'h126] = 8'h89; mem[11'h127] = 8'h00;
    // SHL.b #1, R8          A9 A0 F4 01 68
    //   A shift: decoded and addressed, and not one of the operations v60_alu
    //   implements, so the sequencer stops rather than inventing one.
    mem[11'h128] = 8'hA9; mem[11'h129] = 8'hA0; mem[11'h12A] = 8'hF4;
    mem[11'h12B] = 8'h01; mem[11'h12C] = 8'h68;

    // A second program: MOV.B Format I -- 09 45 67, bit 15 clear.
    mem[11'h200] = 8'h09; mem[11'h201] = 8'h45; mem[11'h202] = 8'h67;

    // the pointer the indirect destination goes through
    mem[11'h610] = 8'h00; mem[11'h611] = 8'h06;
    mem[11'h612] = 8'h00; mem[11'h613] = 8'h00;

    repeat (4) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);

    @(negedge clk);
    redirect_pc = 32'h00000100;
    redirect    = 1'b1;
    @(negedge clk);
    redirect = 1'b0;

    // ---- 1. an immediate into a register --------------------------------------
    step;
    chk(!stopped,                     "MOV.B with an immediate source executes");
    chk(seq_pc === 32'h00000105,      "and the PC advances by its length");

    // ---- 2. add to it ----------------------------------------------------------
    step;
    chk(!stopped,                     "ADD.b executes");
    chk(seq_psw[PSW_Z] === 1'b0,      "0x5A + 1 is not zero");
    chk(seq_psw[PSW_CY] === 1'b0,     "and does not carry");
    chk(seq_pc === 32'h0000010A,      "the PC advances again");

    // ---- 3. compare it ---------------------------------------------------------
    step;
    chk(seq_psw[PSW_Z] === 1'b1,      "comparing 0x5B against 0x5B sets Z");
    chk(seq_psw[PSW_CY] === 1'b0,     "and borrows nothing");
    chk(seq_pc === 32'h0000010F,      "and CMP still advances the PC");

    // ---- 4. a word immediate into a register -----------------------------------
    step;
    chk(!stopped,                "MOV.W with a four byte immediate executes");
    chk(seq_pc === 32'h00000117, "and its length is eight bytes");

    // ---- 5. a register into memory ---------------------------------------------
    step;
    chk(mem[11'h600] === 8'h5B,  "MOV.B stored the register through [R9]");
    chk(seq_pc === 32'h0000011B, "and the PC advanced by four");
    chk(insn_cycles === 5'd1,
        "a MOV to memory is one bus cycle: it does not read its destination");

    // ---- 6. point R9 at a pointer ----------------------------------------------
    step;
    chk(!stopped,                "the second MOV.W executes");
    chk(seq_pc === 32'h00000123, "and the PC advances by eight");

    // ---- 7. read, add, write back, through one pointer --------------------------
    step;
    chk(mem[11'h600] === 8'hB6,
        "ADD.b read the destination through the pointer, added and wrote it back");
    chk(insn_cycles === 5'd4,
        "which is two cycles for the pointer and one each way -- the address is "
        );
    chk(seq_psw[PSW_S] === 1'b1,
        "0x5B + 0x5B is negative AT BYTE WIDTH, which is the width that counts");
    chk(seq_psw[PSW_CY] === 1'b0, "and does not carry out of a byte");

    // ---- 8. something it cannot execute -----------------------------------------
    step;
    chk(stopped === 1'b1,
        "a shift is decoded and addressed and not executed");
    chk(stop_reason === 2'd1,
        "and it says why: the table has the opcode, v60_alu does not have the operation");

    // ---- 9. a format whose semantics are not documented --------------------------
    // Format I's `d` bit decides which operand is the destination and no page
    // held here says what it means, so a Format I instruction stops the
    // machine for a different reason than a missing operation does.  A reset
    // and a second program, because a stop is a stop.
    @(negedge clk);
    rst = 1'b1;
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);
    redirect_pc = 32'h00000200;
    redirect    = 1'b1;
    @(negedge clk);
    redirect = 1'b0;
    step;
    chk(stopped === 1'b1,      "a Format I instruction is not executed");
    chk(stop_reason === 2'd2,  "and it says which of the three reasons it was");

    if (errors == 0) $display("V60 SEQ PASS");
    else             $display("V60 SEQ FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #40_000_000;
    $display("V60 SEQ FAIL (timeout)");
    $finish;
end

endmodule
