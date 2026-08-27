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

wire         seq_redirect;
wire  [31:0] seq_redirect_pc;

v60_pfu pfu (
    .clk(clk), .rst(rst),
    .byte_out(byte_out), .byte_valid(byte_valid), .byte_take(byte_take),
    .byte_pc(byte_pc),
    // A control transfer comes from the sequencer; the bench uses the same
    // input to place the program counter before a program starts.
    .redirect(redirect | seq_redirect),
    .redirect_pc(redirect ? redirect_pc : seq_redirect_pc),
    .bus_req(p_req), .bus_status(p_status), .bus_addr(p_addr), .bus_dl(p_dl),
    .bus_ack(p_ack), .bus_rdata(biu_rdata), .level()
);

// ---- decode ------------------------------------------------------------------
wire         idu_start, idu_done, res_op, res_mode;
insn_fmt_e   idu_fmt;
wire   [7:0] idu_op;
wire         idu_d;
wire   [4:0] idu_reg, idu_subop;
wire  [31:0] idu_disp;
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
    .fmt(idu_fmt), .op(idu_op), .m(), .m2(), .d(idu_d),
    .reg_field(idu_reg), .subop(idu_subop),
    .br_disp(idu_disp), .insn_pc(idu_pc), .insn_len(idu_len),
    .reserved_op(res_op), .reserved_mode(res_mode),
    .op1_valid(o1_valid), .op1_mode(o1_mode), .op1_rn(o1_rn), .op1_rx(o1_rx),
    .op1_index(o1_index), .op1_disp(o1_disp), .op1_disp_outer(o1_douter),
    .op1_imm(o1_imm), .op1_ext_valid(), .op1_ext(), .op1_bytes(o1_bytes),
    .op2_valid(o2_valid), .op2_mode(o2_mode), .op2_rn(o2_rn), .op2_rx(o2_rx),
    .op2_index(o2_index), .op2_disp(o2_disp), .op2_disp_outer(o2_douter),
    .op2_imm(o2_imm), .op2_ext_valid(), .op2_ext(), .op2_bytes(o2_bytes)
);

// ---- registers ----------------------------------------------------------------
wire [31:0] seq_pc, seq_psw;
reg   [4:0] pr_id    = 5'd0;
reg         pr_wr    = 1'b0;
reg  [31:0] pr_wdata = 32'd0;
wire  [4:0] rf_ra_sel, rf_rb_sel, rf_wr_sel;
wire        rf_stack_switch, rf_new_is;
wire  [1:0] rf_new_el;
wire [31:0] rf_sbr;
wire [31:0] rf_ra, rf_rb, rf_wr_data;
wire        rf_wr_en;

v60_regfile rf (
    .clk(clk), .rst(rst),
    .ra_sel(rf_ra_sel), .rb_sel(rf_rb_sel), .ra(rf_ra), .rb(rf_rb), .ra_pair(),
    .wr_en(rf_wr_en), .wr_sel(rf_wr_sel), .wr_data(rf_wr_data),
    .psw_el(seq_psw[PSW_EL_HI:PSW_EL_LO]), .psw_is(seq_psw[PSW_IS]),
    .stack_switch(rf_stack_switch), .new_el(rf_new_el), .new_is(rf_new_is),
    .pr_id(pr_id), .pr_wr(pr_wr), .pr_wdata(pr_wdata),
    .pr_rdata(), .pr_rd_ok(), .pr_wr_ok(), .sbr(rf_sbr)
);

// ---- address unit and data unit ------------------------------------------------
wire        ea_start, ea_index, ea_we, ea_rmw, ea_rmw_go, ea_rmw_pending;
wire        ea_addr_only;
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

wire        exc_req, exc_is_int, exc_dis_ie, exc_done;
wire  [7:0] exc_vector;
wire [31:0] exc_ret_pc, exc_psw_in, exc_sp_in, exc_sbr;
wire  [1:0] exc_nparams;
wire [31:0] exc_param0, exc_param1;
wire [31:0] exc_sp_out, exc_psw_out, exc_handler_pc;
wire  [3:0] exc_cycles;
wire        b_req, b_we, b_done;
wire [23:0] b_addr;
wire  [3:0] b_nbytes, b_cycles;
wire [63:0] b_wdata, b_rdata;
wire        a_req, a_we, a_done;
wire [23:0] a_addr;
wire  [3:0] a_nbytes, a_cycles;
wire [63:0] a_wdata, a_rdata;
wire        dmux_overlap;

v60_ea ea (
    .clk(clk), .rst(rst),
    .start(ea_start), .mode(ea_mode), .has_index(ea_index),
    .disp(ea_disp), .disp_outer(ea_douter), .imm(ea_imm),
    .rn_val(ea_rn_val), .rx_val(ea_rx_val), .pc_val(ea_pc_val),
    .opbytes(ea_opbytes), .we(ea_we), .wdata(ea_wdata),
    .addr_only(ea_addr_only),
    .rmw(ea_rmw), .rmw_pending(ea_rmw_pending), .rmw_go(ea_rmw_go),
    .rmw_data(ea_rmw_data),
    .ea(ea_ea), .rdata(ea_rdata), .rn_wb(ea_rn_wb), .rn_wb_val(ea_rn_wb_val),
    .illegal(), .busy(), .done(ea_done), .bus_cycles(ea_cycles),
    .dx_req(a_req), .dx_addr(a_addr), .dx_nbytes(a_nbytes), .dx_we(a_we),
    .dx_wdata(a_wdata), .dx_rdata(a_rdata), .dx_done(a_done),
    .dx_cycles(a_cycles)
);

// ---- the exception unit, and the mux that gives it the data unit -------------
v60_exc exc (
    .clk(clk), .rst(rst),
    .req(exc_req), .vector(exc_vector), .ret_pc(exc_ret_pc),
    .psw_in(exc_psw_in), .sp_in(exc_sp_in), .sbr(exc_sbr),
    .nparams(exc_nparams), .param0(exc_param0), .param1(exc_param1),
    .is_interrupt(exc_is_int), .disable_ie(exc_dis_ie),
    .sp_out(exc_sp_out), .psw_out(exc_psw_out), .handler_pc(exc_handler_pc),
    .busy(), .done(exc_done), .bus_cycles(exc_cycles),
    .dx_req(b_req), .dx_addr(b_addr), .dx_nbytes(b_nbytes), .dx_we(b_we),
    .dx_wdata(b_wdata), .dx_rdata(b_rdata), .dx_done(b_done),
    .dx_cycles(b_cycles)
);

v60_dmux dmux (
    .a_req(a_req), .a_addr(a_addr), .a_nbytes(a_nbytes), .a_we(a_we),
    .a_wdata(a_wdata), .a_rdata(a_rdata), .a_done(a_done), .a_cycles(a_cycles),
    .b_req(b_req), .b_addr(b_addr), .b_nbytes(b_nbytes), .b_we(b_we),
    .b_wdata(b_wdata), .b_rdata(b_rdata), .b_done(b_done), .b_cycles(b_cycles),
    .dx_req(dx_req), .dx_addr(dx_addr), .dx_nbytes(dx_nbytes), .dx_we(dx_we),
    .dx_wdata(dx_wdata), .dx_rdata(dx_rdata), .dx_done(dx_done),
    .dx_cycles(dx_cycles),
    .overlap(dmux_overlap)
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
wire         retired, stopped;
wire   [1:0] stop_reason;
wire   [4:0] insn_cycles;

v60_seq seq (
    .clk(clk), .rst(rst), .run(run),
    .idu_start(idu_start), .idu_done(idu_done), .idu_fmt(idu_fmt),
    .idu_op(idu_op), .idu_pc(idu_pc), .idu_len(idu_len),
    .idu_d(idu_d), .idu_reg(idu_reg), .idu_subop(idu_subop),
    .idu_disp(idu_disp),
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
    .ea_addr_only(ea_addr_only),
    .ea_rmw(ea_rmw), .ea_rmw_go(ea_rmw_go), .ea_rmw_data(ea_rmw_data),
    .ea_rmw_pending(ea_rmw_pending), .ea_ea(ea_ea), .ea_rdata(ea_rdata),
    .ea_rn_wb(ea_rn_wb), .ea_rn_wb_val(ea_rn_wb_val), .ea_done(ea_done),
    .ea_bus_cycles(ea_cycles),
    .sbr(rf_sbr),
    .exc_req(exc_req), .exc_vector(exc_vector), .exc_ret_pc(exc_ret_pc),
    .exc_psw_in(exc_psw_in), .exc_sp_in(exc_sp_in), .exc_sbr(exc_sbr),
    .exc_nparams(exc_nparams), .exc_param0(exc_param0),
    .exc_param1(exc_param1), .exc_is_interrupt(exc_is_int),
    .exc_disable_ie(exc_dis_ie),
    .exc_sp_out(exc_sp_out), .exc_psw_out(exc_psw_out),
    .exc_handler_pc(exc_handler_pc), .exc_done(exc_done),
    .exc_bus_cycles(exc_cycles),
    .rf_stack_switch(rf_stack_switch), .rf_new_el(rf_new_el),
    .rf_new_is(rf_new_is),
    .redirect(seq_redirect), .redirect_pc(seq_redirect_pc),
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
reg [31:0] psw_before;

// Place the program counter, the way a debugger would: the prefetch unit takes
// a redirect from the bench on the same input the sequencer drives.
// The address unit and the exception unit are never live at once -- that is
// what lets the data unit be muxed rather than arbitrated.  Held every cycle
// rather than checked at a moment, because it is an invariant and not an
// event.
always @(posedge clk) if (!rst && dmux_overlap)
    chk(1'b0, "the address unit and the exception unit both wanted the bus");

task jump(input [31:0] to);
begin
    @(negedge clk);
    redirect_pc = to;
    redirect    = 1'b1;
    @(negedge clk);
    redirect    = 1'b0;
    @(negedge clk);
end
endtask

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

function [31:0] mem_word(input [12:0] addr);
    mem_word = {mem[addr + 13'd3], mem[addr + 13'd2],
                mem[addr + 13'd1], mem[addr]};
endfunction

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

    // A second program, in Format I -- one mod field and one register, with
    // `d` saying which way round.  R8 is set up as a pointer, R9 and R10 hold
    // data, and the results are read back out of memory.
    // MOV.W #0x600, R8       2D A0 F4 00 06 00 00 68   (Format II)
    mem[11'h200] = 8'h2D; mem[11'h201] = 8'hA0; mem[11'h202] = 8'hF4;
    mem[11'h203] = 8'h00; mem[11'h204] = 8'h06; mem[11'h205] = 8'h00;
    mem[11'h206] = 8'h00; mem[11'h207] = 8'h68;
    // MOV.B #0x77, R9        09 A0 F4 77 69            (Format II)
    mem[11'h208] = 8'h09; mem[11'h209] = 8'hA0; mem[11'h20A] = 8'hF4;
    mem[11'h20B] = 8'h77; mem[11'h20C] = 8'h69;
    // MOV.B #0x40, R10       09 A0 F4 40 6A            (Format II)
    //   Deliberately NOT the same value as R9: with both registers holding
    //   0x77, an implementation that read the wrong one would pass.
    mem[11'h20D] = 8'h09; mem[11'h20E] = 8'hA0; mem[11'h20F] = 8'hF4;
    mem[11'h210] = 8'h40; mem[11'h211] = 8'h6A;
    // MOV.B R9, [R8]         09 09 68   Format I, d = 0: the REGISTER is the
    //                                   source and the mod field the dest
    mem[11'h212] = 8'h09; mem[11'h213] = 8'h09; mem[11'h214] = 8'h68;
    // ADD.b [R8], R10        80 2A 68   Format I, d = 1: the MOD FIELD is the
    //                                   source and the register the dest
    mem[11'h215] = 8'h80; mem[11'h216] = 8'h2A; mem[11'h217] = 8'h68;
    // MOV.B R10, [R8]        09 0A 68   d = 0 again, to read R10 back out
    mem[11'h218] = 8'h09; mem[11'h219] = 8'h0A; mem[11'h21A] = 8'h68;

    // ---- a third program, at 0x300: control flow -----------------------------
    // A counted loop, a subroutine call and return, an unconditional branch
    // over the subroutine's bytes, a jump through a register, and a
    // conditional branch that is NOT taken.  The byte at 0x700 records what
    // ran and in what order; the stack is at 0x600 and grows down.
    // MOV.W #0x600, R31   the stack pointer
    mem[11'h300] = 8'h2D; mem[11'h301] = 8'hA0; mem[11'h302] = 8'hF4;
    mem[11'h303] = 8'h00; mem[11'h304] = 8'h06; mem[11'h305] = 8'h00;
    mem[11'h306] = 8'h00; mem[11'h307] = 8'h7F;
    // MOV.W #3, R9        the loop counter
    mem[11'h308] = 8'h2D; mem[11'h309] = 8'hA0; mem[11'h30A] = 8'hF4;
    mem[11'h30B] = 8'h03; mem[11'h30C] = 8'h00; mem[11'h30D] = 8'h00;
    mem[11'h30E] = 8'h00; mem[11'h30F] = 8'h69;
    // MOV.W #0x700, R8    the address of the record
    mem[11'h310] = 8'h2D; mem[11'h311] = 8'hA0; mem[11'h312] = 8'hF4;
    mem[11'h313] = 8'h00; mem[11'h314] = 8'h07; mem[11'h315] = 8'h00;
    mem[11'h316] = 8'h00; mem[11'h317] = 8'h68;
    // MOV.W #0x348, R10   where the JMP below goes
    mem[11'h318] = 8'h2D; mem[11'h319] = 8'hA0; mem[11'h31A] = 8'hF4;
    mem[11'h31B] = 8'h48; mem[11'h31C] = 8'h03; mem[11'h31D] = 8'h00;
    mem[11'h31E] = 8'h00; mem[11'h31F] = 8'h6A;
    // MOV.B #0, [R8]      the record starts empty
    mem[11'h320] = 8'h09; mem[11'h321] = 8'h80; mem[11'h322] = 8'hF4;
    mem[11'h323] = 8'h00; mem[11'h324] = 8'h68;
    // loop: ADD.b #1, [R8]
    mem[11'h325] = 8'h80; mem[11'h326] = 8'h80; mem[11'h327] = 8'hF4;
    mem[11'h328] = 8'h01; mem[11'h329] = 8'h68;
    // DBcc(True) R9, loop  disp16 = 0x325 - 0x32A = -5
    mem[11'h32A] = 8'hC6; mem[11'h32B] = 8'hA9; mem[11'h32C] = 8'hFB;
    mem[11'h32D] = 8'hFF;
    // BSR sub              disp16 = 0x333 - 0x32E = 5
    mem[11'h32E] = 8'h48; mem[11'h32F] = 8'h05; mem[11'h330] = 8'h00;
    // BR after             disp8  = 0x33A - 0x331 = 9
    mem[11'h331] = 8'h6A; mem[11'h332] = 8'h09;
    // sub: ADD.b #0x10, [R8]
    mem[11'h333] = 8'h80; mem[11'h334] = 8'h80; mem[11'h335] = 8'hF4;
    mem[11'h336] = 8'h10; mem[11'h337] = 8'h68;
    // RSR                  back to 0x331
    mem[11'h338] = 8'hCA;
    // after: JMP [R10]     to the address in R10, not to what is there
    mem[11'h33A] = 8'hD6; mem[11'h33B] = 8'h6A;
    // MOV.B #0x77, [R8]
    mem[11'h348] = 8'h09; mem[11'h349] = 8'h80; mem[11'h34A] = 8'hF4;
    mem[11'h34B] = 8'h77; mem[11'h34C] = 8'h68;
    // BE +3, NOT taken     its target 0x350 is mid-instruction below
    mem[11'h34D] = 8'h64; mem[11'h34E] = 8'h03;
    // MOV.B #0x99, [R8]
    mem[11'h34F] = 8'h09; mem[11'h350] = 8'h80; mem[11'h351] = 8'hF4;
    mem[11'h352] = 8'h99; mem[11'h353] = 8'h68;

    // TB R9, +0x0C         R9 is zero, so this one branches
    mem[11'h354] = 8'hC7; mem[11'h355] = 8'hA9; mem[11'h356] = 8'h0C;
    mem[11'h357] = 8'h00;
    // MOV.B #0x11, [R8]    which this must not reach
    mem[11'h358] = 8'h09; mem[11'h359] = 8'h80; mem[11'h35A] = 8'hF4;
    mem[11'h35B] = 8'h11; mem[11'h35C] = 8'h68;
    // MOV.W #1, R9
    mem[11'h360] = 8'h2D; mem[11'h361] = 8'hA0; mem[11'h362] = 8'hF4;
    mem[11'h363] = 8'h01; mem[11'h364] = 8'h00; mem[11'h365] = 8'h00;
    mem[11'h366] = 8'h00; mem[11'h367] = 8'h69;
    // TB R9, +0x0C         R9 is one, so this one does not
    mem[11'h368] = 8'hC7; mem[11'h369] = 8'hA9; mem[11'h36A] = 8'h0C;
    mem[11'h36B] = 8'h00;
    // MOV.W #0x380, R10    the second subroutine
    mem[11'h36C] = 8'h2D; mem[11'h36D] = 8'hA0; mem[11'h36E] = 8'hF4;
    mem[11'h36F] = 8'h90; mem[11'h370] = 8'h03; mem[11'h371] = 8'h00;
    mem[11'h372] = 8'h00; mem[11'h373] = 8'h6A;
    // MOV.B #0x55, [R8]    between the MOV above and the JSR below, so that
    //                      the last operand READ is not the JSR's target: a
    //                      JSR that jumped to what it last read would pass
    //                      otherwise, and did.
    mem[11'h374] = 8'h09; mem[11'h375] = 8'h80; mem[11'h376] = 8'hF4;
    mem[11'h377] = 8'h55; mem[11'h378] = 8'h68;
    // JSR [R10]            call through the address in R10
    mem[11'h379] = 8'hE8; mem[11'h37A] = 8'h6A;
    // MOV.B #0x33, [R8]    where JSR returns to
    mem[11'h37B] = 8'h09; mem[11'h37C] = 8'h80; mem[11'h37D] = 8'hF4;
    mem[11'h37E] = 8'h33; mem[11'h37F] = 8'h68;
    // MOV.W [R1+], [R2+]   2D E0 81 82
    //   Two operands in autoincrement modes: two register writebacks in one
    //   instruction, and this sequencer retires one.  It stops rather than
    //   dropping one of them without saying so.
    mem[11'h380] = 8'h2D; mem[11'h381] = 8'hE0; mem[11'h382] = 8'h81;
    mem[11'h383] = 8'h82;
    // sub2: MOV.B #0x44, [R8]
    mem[11'h390] = 8'h09; mem[11'h391] = 8'h80; mem[11'h392] = 8'hF4;
    mem[11'h393] = 8'h44; mem[11'h394] = 8'h68;
    // RSR
    mem[11'h395] = 8'hCA;

    // ---- a fourth program, at 0x400: exceptions -------------------------------
    // Three of Table 8-1's Instruction Exceptions, each raised by an
    // instruction and each handled by one that writes a marker.  The system
    // base table is at SBR = 0, so entry N is at 4N: entry 16 at +64, entry 18
    // at +72 and entry 19 at +76, which are the offsets Figure 8-2 prints.
    // SBT entry 16, Reserved Opcode           -> 0x7A0
    mem[11'h040] = 8'hA0; mem[11'h041] = 8'h07; mem[11'h042] = 8'h00;
    mem[11'h043] = 8'h00;
    // SBT entry 18, Reserved Addressing Mode  -> 0x7B0
    mem[11'h048] = 8'hB0; mem[11'h049] = 8'h07; mem[11'h04A] = 8'h00;
    mem[11'h04B] = 8'h00;
    // SBT entry 19, Illegal Addressing Mode   -> 0x7C0
    mem[11'h04C] = 8'hC0; mem[11'h04D] = 8'h07; mem[11'h04E] = 8'h00;
    mem[11'h04F] = 8'h00;
    // MOV.W #0x600, R31    the stack the frame goes on
    mem[11'h400] = 8'h2D; mem[11'h401] = 8'hA0; mem[11'h402] = 8'hF4;
    mem[11'h403] = 8'h00; mem[11'h404] = 8'h06; mem[11'h405] = 8'h00;
    mem[11'h406] = 8'h00; mem[11'h407] = 8'h7F;
    // MOV.W #0x700, R8     where a handler leaves its mark
    mem[11'h408] = 8'h2D; mem[11'h409] = 8'hA0; mem[11'h40A] = 8'hF4;
    mem[11'h40B] = 8'h00; mem[11'h40C] = 8'h07; mem[11'h40D] = 8'h00;
    mem[11'h40E] = 8'h00; mem[11'h40F] = 8'h68;
    // opcode 06            which the table does not have
    mem[11'h410] = 8'h06;
    // MOV.B #0x12, #0x34   an immediate DESTINATION
    mem[11'h420] = 8'h09; mem[11'h421] = 8'hE0; mem[11'h422] = 8'hF4;
    mem[11'h423] = 8'h12; mem[11'h424] = 8'hF4; mem[11'h425] = 8'h34;
    // MOV.B <F5>, R8       a mod byte the figure does not print
    mem[11'h430] = 8'h09; mem[11'h431] = 8'hE0; mem[11'h432] = 8'hF5;
    mem[11'h433] = 8'h68;
    // handler 16: MOV.B #0xE1, [R8]
    mem[11'h7A0] = 8'h09; mem[11'h7A1] = 8'h80; mem[11'h7A2] = 8'hF4;
    mem[11'h7A3] = 8'hE1; mem[11'h7A4] = 8'h68;
    // handler 18: MOV.B #0xE2, [R8]
    mem[11'h7B0] = 8'h09; mem[11'h7B1] = 8'h80; mem[11'h7B2] = 8'hF4;
    mem[11'h7B3] = 8'hE2; mem[11'h7B4] = 8'h68;
    // handler 19: MOV.B #0xE3, [R8]
    mem[11'h7C0] = 8'h09; mem[11'h7C1] = 8'h80; mem[11'h7C2] = 8'hF4;
    mem[11'h7C3] = 8'hE3; mem[11'h7C4] = 8'h68;

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
        "two cycles for the pointer and one each way: one address, two accesses");
    chk(seq_psw[PSW_S] === 1'b1,
        "0x5B + 0x5B is negative AT BYTE WIDTH, which is the width that counts");
    chk(seq_psw[PSW_CY] === 1'b0, "and does not carry out of a byte");

    // ---- 8. something it cannot execute -----------------------------------------
    step;
    chk(stopped === 1'b1,
        "a shift is decoded and addressed and not executed");
    chk(stop_reason === 2'd0,
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
    // Format II, to set the three registers up.
    step; chk(!stopped, "the Format II setup executes");
    step; chk(!stopped, "and so does the second");
    step; chk(!stopped, "and the third");

    // Format I, d = 0: register source, mod-field destination.
    step;
    chk(!stopped,               "a Format I instruction executes");
    chk(mem[11'h600] === 8'h77,
        "d = 0 puts the REGISTER on the source side: R9 went to [R8]");

    // Format I, d = 1: mod-field source, register destination.  0x77 + 0x77.
    step;
    chk(!stopped,               "and so does the other direction");
    chk(seq_psw[PSW_S] === 1'b1,
        "d = 1 read [R8] as the source and added it into R10: 0xB7 is negative");
    chk(seq_psw[PSW_OV] === 1'b1,
        "and 0x40 + 0x77 overflows a signed byte");
    chk(seq_psw[PSW_CY] === 1'b0, "without carrying out of one");

    // Read R10 back out through a d = 0 store.
    step;
    chk(mem[11'h600] === 8'hB7,
        "and the register the d = 1 instruction wrote holds the sum");

    // What this bench does NOT distinguish: the source width from the
    // destination width.  Every operation v60_alu implements has them equal --
    // MOV.B is (1,1), ADD is (siz,siz) -- so swapping them changes nothing
    // observable.  The instructions that would show it are the conversions,
    // MOVS.BW and MOVT.WB, whose widths differ per operand and which are not
    // executable yet.  tb_v60_idu checks that they DECODE with different
    // widths; nothing here checks that they execute with them.

    // =======================================================================
    // Control flow.
    // =======================================================================
    @(negedge clk);
    rst = 1'b1;
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);
    redirect_pc = 32'h00000300;
    redirect    = 1'b1;
    @(negedge clk);
    redirect = 1'b0;

    step; step; step; step; step;   // the five setup moves
    chk(!stopped,               "the control-flow program's setup executes");
    chk(mem[11'h700] === 8'h00, "the record starts empty");
    chk(seq_pc === 32'h00000325, "and the PC is at the loop");

    // The loop: three passes of the ADD, and a DBcc that branches back twice
    // and falls through when the decrement reaches zero.
    step;
    chk(mem[11'h700] === 8'h01, "one pass of the loop");
    step;
    chk(insn_cycles === 5'd0,   "a branch makes no bus cycle of its own");
    chk(seq_pc === 32'h00000325,
        "and the branch measured its displacement from its own first byte");
    step; step;
    chk(mem[11'h700] === 8'h02, "two");
    step; step;
    chk(mem[11'h700] === 8'h03, "three");
    chk(seq_pc === 32'h0000032E,
        "and the third decrement reached zero, so that branch was not taken");

    // BSR into the subroutine and RSR back out of it.
    step;
    chk(seq_pc === 32'h00000333,  "BSR branched to the subroutine");
    chk(rf.gpr[31] === 32'h000005FC,
        "and pushed one word, which is what [-SP] moves the stack pointer by");
    chk(mem_word(13'h5FC) === 32'h00000331,
        "the word it pushed is the address of the instruction after it");
    chk(insn_cycles === 5'd2,
        "a word push on a sixteen bit bus is two bus cycles");
    step;
    chk(mem[11'h700] === 8'h13,   "the subroutine ran");
    step;
    chk(seq_pc === 32'h00000331,  "and RSR returned to what BSR pushed");
    chk(insn_cycles === 5'd2,     "the pop is two more");
    chk(rf.gpr[31] === 32'h00000600, "with the stack pointer back where it was");

    // An unconditional branch over the subroutine's bytes.
    step;
    chk(seq_pc === 32'h0000033A, "BR skipped the subroutine");

    // A jump whose operand is a register-indirect ADDRESS, not the contents of
    // that address.
    step;
    chk(seq_pc === 32'h00000348, "JMP went to the address the operand names");
    chk(insn_cycles === 5'd0,
        "and made no operand access: it wants the address, not what is there");
    step;
    chk(mem[11'h700] === 8'h77,  "and the instruction there ran");

    // A conditional branch that is not taken advances by its own length.  Its
    // target is the second byte of the instruction below, so a branch wrongly
    // taken decodes garbage rather than landing somewhere harmless.
    step;
    chk(seq_pc === 32'h0000034F, "an untaken branch falls through");
    step;
    chk(mem[11'h700] === 8'h99,  "to the instruction after it");

    // TB tests the register the way DBcc does but without decrementing it:
    // "if Rn = 0 then PC <- PC + sign_extended( disp16 )".  R9 is zero here,
    // left that way by the loop above.
    step;
    chk(seq_pc === 32'h00000360, "TB branched on a register that is zero");
    chk(mem[11'h700] === 8'h99,  "and did not run what it branched over");
    step; step;
    chk(seq_pc === 32'h0000036C, "and did not branch on one that is not");

    // JSR: the address is computed, the return address is pushed, and control
    // goes to the address -- not to what is at it.
    step; step;
    chk(mem[11'h700] === 8'h55,   "the last read before the JSR is not its target");
    step;
    chk(seq_pc === 32'h00000390,  "JSR called through the address in R10");
    chk(rf.gpr[31] === 32'h000005FC, "pushing one word");
    chk(mem_word(13'h5FC) === 32'h0000037B,
        "which is the address of the instruction after the JSR");
    step;
    chk(mem[11'h700] === 8'h44,   "the second subroutine ran");
    step;
    chk(seq_pc === 32'h0000037B,  "and RSR returned from it");
    step;
    chk(mem[11'h700] === 8'h33,   "to the instruction JSR pushed");

    // Two addressing-mode writebacks in one instruction, which this sequencer
    // has one retirement slot for.
    step;
    chk(stopped,                  "two autoincrement operands stop the sequencer");
    chk(stop_reason === 2'd2,     "saying which of the three reasons it was");

    // =======================================================================
    // Exceptions.  Each case runs the setup, then the one instruction that
    // raises, then the handler the vector points at.
    // =======================================================================
    @(negedge clk);
    rst = 1'b1;
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);

    // The system base register, placed the way the PC is: this sequencer has
    // no LDPR, and the register file's privileged port is where SBR lives.
    pr_id    = 5'd5;                 // PR_SBR
    pr_wdata = 32'h0000_0000;
    pr_wr    = 1'b1;
    @(negedge clk);
    pr_wr    = 1'b0;

    // ---- a reserved opcode -------------------------------------------------
    jump(32'h00000400);
    step; step;                                  // the setup
    psw_before = seq_psw;
    step;
    chk(!stopped,
        "a reserved opcode raises an exception rather than stopping");
    chk(seq_pc === 32'h000007A0,
        "and the handler is the one at SBR + 4 x 16");
    chk(mem_word(13'h5FC) === 32'h00001000,
        "the frame's parameter word is the exception code the table gives");
    chk(mem_word(13'h5F8) === psw_before, "then the PSW as it was");
    chk(mem_word(13'h5F4) === 32'h00000410,
        "and the CURRENT PC on top: the instruction that caused it");
    chk(rf.gpr[31] === 32'h000005F4, "three words of frame");
    chk(insn_cycles === 5'd8,
        "two bus cycles for the vector and two for each word pushed");
    chk(seq_psw[PSW_EL_HI:PSW_EL_LO] === 2'b00,
        "the handler runs at execution level 0");
    step;
    chk(mem[11'h700] === 8'hE1, "and the handler runs");

    // ---- an immediate used as a destination --------------------------------
    jump(32'h00000400);
    step; step;
    jump(32'h00000420);
    step;
    chk(seq_pc === 32'h000007C0,
        "an immediate destination is the illegal addressing mode exception");
    chk(mem_word(13'h5FC) === 32'h00001300, "with its own exception code");
    chk(mem_word(13'h5F4) === 32'h00000420, "and the faulting PC");
    step;
    chk(mem[11'h700] === 8'hE3, "and that handler runs");

    // ---- a mod byte that is not printed ------------------------------------
    jump(32'h00000400);
    step; step;
    jump(32'h00000430);
    step;
    chk(seq_pc === 32'h000007B0,
        "a reserved mode is a different exception from a reserved opcode");
    chk(mem_word(13'h5FC) === 32'h00001200, "and carries a different code");
    step;
    chk(mem[11'h700] === 8'hE2, "and a different handler runs");

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
