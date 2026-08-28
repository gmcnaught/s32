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

// The three externally raised conditions.  NMI* and INT are driven by the
// stimulus; BERR* is aimed at an ADDRESS instead, because what a bus error
// happens to is a bus cycle and the stimulus does not know when one runs.
reg          nmi_n = 1'b1, int_req = 1'b0;
reg   [23:0] berr_target = 24'd0;
wire         biu_berr, biu_berr_we, nmi_pending, nmi_take, int_pending;
bus_status_e biu_berr_status;
wire  [23:0] biu_berr_addr;

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
// Format VII's extension bytes -- the bit field group's length operand.
wire         o1_ext_valid, o2_ext_valid;
wire   [7:0] o1_ext, o2_ext;

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
    .op1_imm(o1_imm), .op1_ext_valid(o1_ext_valid), .op1_ext(o1_ext), .op1_bytes(o1_bytes),
    .op2_valid(o2_valid), .op2_mode(o2_mode), .op2_rn(o2_rn), .op2_rx(o2_rx),
    .op2_index(o2_index), .op2_disp(o2_disp), .op2_disp_outer(o2_douter),
    .op2_imm(o2_imm), .op2_ext_valid(o2_ext_valid), .op2_ext(o2_ext), .op2_bytes(o2_bytes)
);

// ---- registers ----------------------------------------------------------------
wire [31:0] seq_pc, seq_psw;
reg   [4:0] pr_id    = 5'd0;
reg         pr_wr    = 1'b0;
reg  [31:0] pr_wdata = 32'd0;
wire  [4:0] rf_ra_sel, rf_rb_sel, rf_wr_sel;
wire        rf_stack_switch, rf_new_is;
wire  [1:0] rf_new_el;
wire  [1:0] seq_exc_new_el;
wire [31:0] rf_sbr;
wire [31:0] rf_ra, rf_rb, rf_wr_data;
wire [63:0] rf_ra_pair;
wire        rf_wr_en;

// The privileged register port has two drivers: this bench, which places SBR
// and the interrupt stack pointer during reset_and_arm because there is no
// LDPR to do it, and the sequencer, which reads TKCW for TRAPFL.  The bench
// wins while its own `pr_wr` is high, which is only during that placement.
wire  [4:0] seq_pr_id;
wire        seq_pr_wr;
wire [31:0] seq_pr_wdata;
wire [31:0] rf_pr_rdata;
wire        rf_pr_rd_ok, rf_pr_wr_ok;
wire  [4:0] mux_pr_id    = pr_wr ? pr_id    : seq_pr_id;
wire        mux_pr_wr    = pr_wr | seq_pr_wr;
wire [31:0] mux_pr_wdata = pr_wr ? pr_wdata : seq_pr_wdata;

v60_regfile rf (
    .clk(clk), .rst(rst),
    .ra_sel(rf_ra_sel), .rb_sel(rf_rb_sel), .ra(rf_ra), .rb(rf_rb),
    .ra_pair(rf_ra_pair),
    .wr_en(rf_wr_en), .wr_sel(rf_wr_sel), .wr_data(rf_wr_data),
    .psw_el(seq_psw[PSW_EL_HI:PSW_EL_LO]), .psw_is(seq_psw[PSW_IS]),
    .stack_switch(rf_stack_switch), .new_el(rf_new_el), .new_is(rf_new_is),
    .pr_id(mux_pr_id), .pr_wr(mux_pr_wr), .pr_wdata(mux_pr_wdata),
    .pr_rdata(rf_pr_rdata), .pr_rd_ok(rf_pr_rd_ok), .pr_wr_ok(rf_pr_wr_ok),
    .sbr(rf_sbr)
);

// ---- address unit and data unit ------------------------------------------------
wire        ea_start, ea_index, ea_we, ea_rmw, ea_rmw_go, ea_rmw_pending;
wire        ea_addr_only, ea_io;
wire        a_io, dx_io;
wire        ea_lock, a_lock, dx_lock, d_lock, biu_lock;
am_mode_e   ea_mode;
wire [31:0] ea_disp, ea_douter, ea_rn_val, ea_rx_val, ea_pc_val, ea_ea;
wire [31:0] ea_rn1_val, ea_rn_wb_hi;
wire        ea_rn_wb_pair;
wire        ea_bit_mode;
wire  [2:0] ea_bit_resid;
wire [63:0] ea_imm, ea_wdata, ea_rmw_data, ea_rdata;
wire  [3:0] ea_opbytes, ea_cycles;
wire        ea_done, ea_rn_wb;
wire [31:0] ea_rn_wb_val;

wire        dx_req, dx_we, dx_done, dx_intack;
wire [23:0] dx_addr;
wire  [3:0] dx_nbytes, dx_cycles;
wire [63:0] dx_wdata, dx_rdata;

wire        exc_req, exc_is_int, exc_dis_ie, exc_done;
wire        exc_int_stack, exc_ack_vector, exc_intack, exc_invalid_int;
wire  [7:0] exc_int_vector;
wire  [7:0] exc_vector;
wire [31:0] exc_ret_pc, exc_psw_in, exc_sp_in, exc_sbr;
wire  [1:0] exc_nparams;
wire [15:0] exc_code;
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
    .rn_val(ea_rn_val), .rn1_val(ea_rn1_val), .rx_val(ea_rx_val), .pc_val(ea_pc_val),
    .opbytes(ea_opbytes), .we(ea_we), .io(ea_io), .lock(ea_lock), .bit_mode(ea_bit_mode), .wdata(ea_wdata),
    .addr_only(ea_addr_only),
    .rmw(ea_rmw), .rmw_pending(ea_rmw_pending), .rmw_go(ea_rmw_go),
    .rmw_data(ea_rmw_data),
    .ea(ea_ea), .bit_resid(ea_bit_resid), .rdata(ea_rdata), .rn_wb(ea_rn_wb), .rn_wb_val(ea_rn_wb_val),
    .rn_wb_pair(ea_rn_wb_pair), .rn_wb_hi(ea_rn_wb_hi),
    .illegal(), .busy(), .done(ea_done), .bus_cycles(ea_cycles),
    .dx_req(a_req), .dx_addr(a_addr), .dx_nbytes(a_nbytes), .dx_we(a_we),
    .dx_io(a_io), .dx_lock(a_lock),
    .dx_wdata(a_wdata), .dx_rdata(a_rdata), .dx_done(a_done),
    .dx_cycles(a_cycles)
);

// ---- the exception unit, and the mux that gives it the data unit -------------
v60_exc exc (
    .clk(clk), .rst(rst),
    .req(exc_req), .vector(exc_vector), .ret_pc(exc_ret_pc),
    .psw_in(exc_psw_in), .sp_in(exc_sp_in), .sbr(exc_sbr),
    .nparams(exc_nparams), .code(exc_code),
    .param0(exc_param0), .param1(exc_param1),
    .is_interrupt(exc_is_int), .disable_ie(exc_dis_ie),
    .int_stack(exc_int_stack), .new_el(seq_exc_new_el), .ack_vector(exc_ack_vector),
    .sp_out(exc_sp_out), .psw_out(exc_psw_out), .handler_pc(exc_handler_pc),
    .busy(), .done(exc_done), .bus_cycles(exc_cycles),
    .int_vector(exc_int_vector), .invalid_int(exc_invalid_int),
    .dx_req(b_req), .dx_addr(b_addr), .dx_nbytes(b_nbytes), .dx_we(b_we),
    .dx_intack(exc_intack),
    .dx_wdata(b_wdata), .dx_rdata(b_rdata), .dx_done(b_done),
    .dx_cycles(b_cycles)
);

v60_dmux dmux (
    .a_req(a_req), .a_addr(a_addr), .a_nbytes(a_nbytes), .a_we(a_we),
    .a_wdata(a_wdata), .a_rdata(a_rdata), .a_done(a_done), .a_cycles(a_cycles),
    .b_req(b_req), .b_addr(b_addr), .b_nbytes(b_nbytes), .b_we(b_we), .b_intack(exc_intack),
    .b_wdata(b_wdata), .b_rdata(b_rdata), .b_done(b_done), .b_cycles(b_cycles),
    .a_io(a_io), .a_lock(a_lock),
    .dx_req(dx_req), .dx_addr(dx_addr), .dx_nbytes(dx_nbytes), .dx_we(dx_we),
    .dx_io(dx_io), .dx_lock(dx_lock),
    .dx_intack(dx_intack),
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
    .req(dx_req), .addr(dx_addr), .nbytes(dx_nbytes), .we(dx_we), .io(dx_io), .lock(dx_lock), .intack(dx_intack),
    .wdata(dx_wdata), .rdata(dx_rdata), .busy(), .done(dx_done),
    .cycles(dx_cycles),
    .biu_lock(d_lock),
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
    .op1_imm(o1_imm), .op1_ext_valid(o1_ext_valid), .op1_ext(o1_ext),
    .op1_bytes(o1_bytes),
    .op2_valid(o2_valid), .op2_mode(o2_mode), .op2_rn(o2_rn), .op2_rx(o2_rx),
    .op2_index(o2_index), .op2_disp(o2_disp), .op2_disp_outer(o2_douter),
    .op2_imm(o2_imm), .op2_ext_valid(o2_ext_valid), .op2_ext(o2_ext),
    .op2_bytes(o2_bytes),
    .rf_ra_sel(rf_ra_sel), .rf_rb_sel(rf_rb_sel), .rf_ra(rf_ra),
    .rf_ra_pair(rf_ra_pair), .rf_rb(rf_rb),
    .rf_wr_en(rf_wr_en), .rf_wr_sel(rf_wr_sel), .rf_wr_data(rf_wr_data),
    .ea_start(ea_start), .ea_mode(ea_mode), .ea_index(ea_index),
    .ea_disp(ea_disp), .ea_disp_outer(ea_douter), .ea_imm(ea_imm),
    .ea_rn_val(ea_rn_val), .ea_rn1_val(ea_rn1_val), .ea_rx_val(ea_rx_val), .ea_pc_val(ea_pc_val),
    .ea_opbytes(ea_opbytes), .ea_we(ea_we), .ea_io(ea_io), .ea_lock(ea_lock), .ea_bit_mode(ea_bit_mode), .ea_bit_resid(ea_bit_resid), .ea_wdata(ea_wdata),
    .ea_addr_only(ea_addr_only),
    .ea_rmw(ea_rmw), .ea_rmw_go(ea_rmw_go), .ea_rmw_data(ea_rmw_data),
    .ea_rmw_pending(ea_rmw_pending), .ea_ea(ea_ea), .ea_rdata(ea_rdata),
    .ea_rn_wb(ea_rn_wb), .ea_rn_wb_val(ea_rn_wb_val),
    .ea_rn_wb_pair(ea_rn_wb_pair), .ea_rn_wb_hi(ea_rn_wb_hi), .ea_done(ea_done),
    .ea_bus_cycles(ea_cycles),
    .rf_pr_id(seq_pr_id), .rf_pr_wr(seq_pr_wr), .rf_pr_wdata(seq_pr_wdata),
    .rf_pr_rdata(rf_pr_rdata), .rf_pr_rd_ok(rf_pr_rd_ok),
    .rf_pr_wr_ok(rf_pr_wr_ok),
    .sbr(rf_sbr),
    .exc_req(exc_req), .exc_vector(exc_vector), .exc_ret_pc(exc_ret_pc),
    .exc_psw_in(exc_psw_in), .exc_sp_in(exc_sp_in), .exc_sbr(exc_sbr),
    .exc_nparams(exc_nparams), .exc_code(exc_code), .exc_param0(exc_param0),
    .exc_param1(exc_param1), .exc_is_interrupt(exc_is_int),
    .exc_disable_ie(exc_dis_ie),
    .exc_int_stack(exc_int_stack), .exc_ack_vector(exc_ack_vector),
    .nmi_pending(nmi_pending), .nmi_take(nmi_take),
    .int_pending(int_pending),
    .berr(biu_berr), .berr_status(biu_berr_status),
    .berr_addr(biu_berr_addr), .berr_we(biu_berr_we),
    .exc_sp_out(exc_sp_out), .exc_psw_out(exc_psw_out),
    .exc_handler_pc(exc_handler_pc), .exc_done(exc_done),
    .exc_bus_cycles(exc_cycles),
    .rf_stack_switch(rf_stack_switch), .rf_new_el(rf_new_el),
    .exc_new_el(seq_exc_new_el),
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
    .d_dl(d_dl), .d_ube(d_ube), .d_first(d_first), .d_lock(d_lock),
    .d_wdata(d_wdata),
    .d_ack(d_ack),
    .p_req(p_req), .p_status(p_status), .p_addr(p_addr), .p_dl(p_dl),
    .p_ack(p_ack),
    .biu_req(biu_req), .biu_status(biu_status), .biu_addr(biu_addr),
    .biu_we(biu_we), .biu_dl(biu_dl), .biu_ube(biu_ube), .biu_first(biu_first),
    .biu_lock(biu_lock),
    .biu_wdata(biu_wdata), .biu_ack(biu_ack), .biu_busy(biu_busy),
    .own_pfu(own_pfu)
);

wire [23:0] a;
wire  [1:0] dl_o;
wire  [2:0] st;
wire        mrq_n, rw_n, ube_n, fas_n, bcy_n, ds_n, d_oe, bus_hiz, hldak_n;
wire        block_n;
wire [15:0] d_out;
reg  [15:0] d_in;
bus_state_e state;

// One cycle, at one address, fails.  RT/EP* is held at 0 throughout -- "cause
// an exception (RT/EP* = 0)" -- because the retry side is tb_v60_biu_pins's.
//
// The window is the whole of T4 and not "while BCY* is low": BCY* is negated
// at the RISING edge of T4 (p.3.283) and the pins are sampled at its falling
// one, so a stimulus gated on BCY* would release BERR* just before the instant
// that reads it.  `berr_budget` makes the arming a one-shot -- the handler
// writes to the same address the fault was aimed at.
integer n_berr_seen = 0;
integer berr_budget = 0;
always @(posedge clk) if (!rst && biu_berr) n_berr_seen = n_berr_seen + 1;

wire berr_n  = !((n_berr_seen < berr_budget) && (state === T_T4) &&
                 (a === berr_target));
wire rt_ep_n = 1'b0;

v60_biu biu (
    .clk(clk), .rst(rst), .ce_rise(ce_rise), .ce_fall(ce_fall),
    .req(biu_req), .status(biu_status), .addr(biu_addr), .we(biu_we),
    .dl(biu_dl), .ube(biu_ube), .first(biu_first), .lock(biu_lock), .wdata(biu_wdata),
    .ack(biu_ack), .rdata(biu_rdata), .busy(biu_busy),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .block_n(block_n), .ds_n(ds_n),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .bus_hiz(bus_hiz),
    .ready_n(1'b0), .bmode(1'b1), .hldrq_n(1'b1), .hldak_n(hldak_n),
    .berr_n(berr_n), .rt_ep_n(rt_ep_n), .nmi_n(nmi_n), .int_req(int_req),
    .berr(biu_berr), .berr_status(biu_berr_status),
    .berr_addr(biu_berr_addr), .berr_we(biu_berr_we), .berr_retry(),
    .nmi_pending(nmi_pending), .nmi_take(nmi_take), .int_pending(int_pending),
    .state(state)
);

reg  [7:0] mem [0:2047];
wire [10:0] bank_even = {a[10:1], 1'b0};

// A stand-in for the uPD71059.  "On the second interrupt acknowledge cycle, an
// 8-bit interrupt vector is read" (p.3.237), so the two cycles of the pair
// answer differently and a machine that kept the first one's byte fails.
wire       is_iack = ({mrq_n, st} === 4'b1110);
reg  [7:0] iack_first  = 8'hFF;
reg  [7:0] iack_second = 8'd96;
integer    iack_n = 0;
always @(posedge clk) if (!rst && biu_ack && is_iack) iack_n = iack_n + 1;

always @(*) d_in = is_iack ? {8'h00, (iack_n == 0) ? iack_first : iack_second}
                           : {mem[bank_even + 11'd1], mem[bank_even]};

integer n_writes = 0;
always @(posedge clk) if (!rst && biu_ack && !rw_n) n_writes = n_writes + 1;
// TEMP: catch whoever writes the CHLVL program
always @(posedge clk) if (!rst && biu_ack && !rw_n && (bank_even == 11'h730))
    $display("DBG CLOBBER a=%06x d=%04x t=%0t", a, d_out, $time);

// The I/O address space, watched at the PINS.  "MRQ*,ST2-ST0 = 1011" is a
// single mode I/O access (p.3.233), and MRQ is the bit that says I/O at all --
// so this is the pin pattern and not a decode of anything internal.  Nothing
// but IN and OUT can produce it.
// BLOCK*, and the invariant it exists to make true.  The pin only ANNOUNCES
// -- "It is used by external logic to guarantee the integrity of the bus
// cycle" (databook p.3.236) -- so the enforcement has to be somewhere else,
// and it is v60_bus_arb's hold-off.  This holds the two to each other: while
// the bus is locked, no prefetch cycle may be acknowledged.  Checked every
// cycle rather than at a moment, because it is an invariant and not an event.
integer n_block = 0;
always @(posedge clk) if (!rst && biu_ack && !block_n) n_block = n_block + 1;
always @(posedge clk) if (!rst && biu_ack && own_pfu && !block_n)
    chk(1'b0, "a prefetch cycle was acknowledged inside a locked operation");

// And BLOCK* must not be RELEASED inside the operation.  Counting asserted
// cycles cannot see this: the pin is raised at T1 of every bus cycle, so a
// version that drops it at TI still looks asserted at each acknowledge.  What
// distinguishes them is the gap BETWEEN the two cycles, which is the only part
// "indivisible" is about.
reg block_armed = 1'b0;
always @(posedge clk) if (!rst) begin
    if (!block_n)          block_armed <= 1'b1;
    else if (!biu_lock)    block_armed <= 1'b0;
end
always @(posedge clk) if (!rst && biu_lock && block_armed)
    chk(block_n === 1'b0, "BLOCK* was released inside an indivisible operation");

// And the other half, which is the one the tranche-two audit found missing.
// Asserting BLOCK* is a CLAIM to other bus masters -- "an indivisible
// read-modify-write bus cycle (TASI, CAXI instructions) is taking place" -- so
// it must be false on every access that is neither.  Every earlier check here
// was about the pin being asserted when it should be; nothing said it was
// clear when it should be, which is exactly the half a leaked `ea_lock` falls
// in.
always @(posedge clk) if (!rst && biu_ack && !block_n && !is_iack)
    chk(seq.is_lockop === 1'b1,
        "BLOCK* was asserted on an access that is not interlocked");

wire       is_io      = ({mrq_n, st} === 4'b1011);
wire       is_mem_sgl = ({mrq_n, st} === 4'b0011);
integer    n_io = 0, n_io_wr = 0, n_mem_sgl = 0;
always @(posedge clk) if (!rst && biu_ack && is_io)      n_io      = n_io + 1;
always @(posedge clk) if (!rst && biu_ack && is_io && !rw_n)
                                                          n_io_wr   = n_io_wr + 1;
always @(posedge clk) if (!rst && biu_ack && is_mem_sgl) n_mem_sgl = n_mem_sgl + 1;

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

// Reset, then place the two privileged registers this stage cannot load for
// itself: the system base register, and the interrupt stack pointer that every
// externally raised condition's frame goes on.  Both through the register
// file's privileged port, the way the PC is placed through the prefetch unit's
// redirect -- there is no LDPR here.
task reset_and_arm;
begin
    @(negedge clk);
    rst = 1'b1;
    repeat (4) @(negedge clk);
    rst = 1'b0;
    repeat (2) @(negedge clk);
    pr_id = 5'd5; pr_wdata = 32'h0000_0000; pr_wr = 1'b1;   // PR_SBR
    @(negedge clk);
    pr_id = 5'd0; pr_wdata = 32'h0000_0680;                 // PR_ISP
    @(negedge clk);
    pr_wr = 1'b0;
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

task put_word(input [12:0] addr, input [31:0] val);
begin
    mem[addr]         = val[7:0];
    mem[addr + 13'd1] = val[15:8];
    mem[addr + 13'd2] = val[23:16];
    mem[addr + 13'd3] = val[31:24];
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
    mem[11'h128] = 8'hA9; mem[11'h129] = 8'hA0; mem[11'h12A] = 8'hF4;
    mem[11'h12B] = 8'h01; mem[11'h12C] = 8'h68;
    // SHL.w #4, R9          AD A0 F4 04 69
    //   The count is a BYTE and the destination is a WORD: the two operands of
    //   one instruction at different widths, which nothing else in these
    //   programs does.  The immediate is one byte long because the count is,
    //   so an implementation that took the widths the other way round would
    //   read four and every following instruction would decode from the wrong
    //   place -- which the PC below would show.
    mem[11'h12D] = 8'hAD; mem[11'h12E] = 8'hA0; mem[11'h12F] = 8'hF4;
    mem[11'h130] = 8'h04; mem[11'h131] = 8'h69;
    // MUL.b #2, R8          81 A0 F4 02 68
    //   R8 holds 0xB6 by now, which is -74 as a signed byte, so the product is
    //   -148: it does not fit a signed byte and OV is set, and the byte that
    //   is stored is the low one.
    mem[11'h132] = 8'h81; mem[11'h133] = 8'hA0; mem[11'h134] = 8'hF4;
    mem[11'h135] = 8'h02; mem[11'h136] = 8'h68;
    // MULX #2, R8           86 A0 F4 02 00 00 00 68
    //   The X form, whose destination is a DOUBLEWORD -- "a register pair, low
    //   register first" -- so this writes R8 AND R9.  Its source is a word, so
    //   its immediate is four bytes where MUL.b's was one.
    mem[11'h137] = 8'h86; mem[11'h138] = 8'hA0; mem[11'h139] = 8'hF4;
    mem[11'h13A] = 8'h02; mem[11'h13B] = 8'h00; mem[11'h13C] = 8'h00;
    mem[11'h13D] = 8'h00; mem[11'h13E] = 8'h68;

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
    // The conversions, whose two operands are at different widths by
    // definition: "the source and destination operand lengths differ in this
    // instruction".
    // MOVS.BW #0x80, R9     0C A0 F4 80 69   a byte immediate into a word
    mem[11'h21B] = 8'h0C; mem[11'h21C] = 8'hA0; mem[11'h21D] = 8'hF4;
    mem[11'h21E] = 8'h80; mem[11'h21F] = 8'h69;
    // MOVZ.BW #0x80, R10    0D A0 F4 80 6A   the same bits, not extended
    mem[11'h220] = 8'h0D; mem[11'h221] = 8'hA0; mem[11'h222] = 8'hF4;
    mem[11'h223] = 8'h80; mem[11'h224] = 8'h6A;
    // MOVT.WB R9, [R8]      29 C0 69 68      a word truncated to a byte
    mem[11'h225] = 8'h29; mem[11'h226] = 8'hC0; mem[11'h227] = 8'h69;
    mem[11'h228] = 8'h68;
    // MOVT.WB R10, [R8]     29 C0 6A 68      the same byte, from a value whose
    //                                        dropped bits do not match its sign
    mem[11'h229] = 8'h29; mem[11'h22A] = 8'hC0; mem[11'h22B] = 8'h6A;
    mem[11'h22C] = 8'h68;

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

    // ---- a fifth program, at 0x500: the externally raised conditions ---------
    // Four stores that leave a different byte at 0x700, so which of them ran
    // and which was interrupted is readable out of memory.  The system base
    // table is still at SBR = 0.
    // SBT entry 2,  Non-Maskable Interrupt  (Figure 8-2's +8)  -> 0x7D0
    mem[11'h008] = 8'hD0; mem[11'h009] = 8'h07;
    // SBT entry 3,  Serious System Fault    (Figure 8-2's +12) -> 0x7E0
    mem[11'h00C] = 8'hE0; mem[11'h00D] = 8'h07;
    // SBT entry 96, a maskable interrupt    (4 x 96 = 0x180)   -> 0x7F0
    mem[11'h180] = 8'hF0; mem[11'h181] = 8'h07;
    // MOV.W #0x600, R31   the level 0 stack
    mem[11'h500] = 8'h2D; mem[11'h501] = 8'hA0; mem[11'h502] = 8'hF4;
    mem[11'h503] = 8'h00; mem[11'h504] = 8'h06; mem[11'h505] = 8'h00;
    mem[11'h506] = 8'h00; mem[11'h507] = 8'h7F;
    // MOV.W #0x700, R8    where every store below goes
    mem[11'h508] = 8'h2D; mem[11'h509] = 8'hA0; mem[11'h50A] = 8'hF4;
    mem[11'h50B] = 8'h00; mem[11'h50C] = 8'h07; mem[11'h50D] = 8'h00;
    mem[11'h50E] = 8'h00; mem[11'h50F] = 8'h68;
    // MOV.B #1, [R8]
    mem[11'h510] = 8'h09; mem[11'h511] = 8'h80; mem[11'h512] = 8'hF4;
    mem[11'h513] = 8'h01; mem[11'h514] = 8'h68;
    // MOV.B #2, [R8]
    mem[11'h515] = 8'h09; mem[11'h516] = 8'h80; mem[11'h517] = 8'hF4;
    mem[11'h518] = 8'h02; mem[11'h519] = 8'h68;
    // MOV.B #3, [R8]
    mem[11'h51A] = 8'h09; mem[11'h51B] = 8'h80; mem[11'h51C] = 8'hF4;
    mem[11'h51D] = 8'h03; mem[11'h51E] = 8'h68;
    // handler 2:  MOV.B #0xA1, [R8] ; RETIS #0
    //   RETIS is Format III, so its m rides in bit 0 of the opcode (FA/FB) and
    //   one mod field follows.  E0 is immediate quick with the value in its
    //   low nibble: "when the immediate quick addressing mode is specified,
    //   the data is zero extended to 16-bit length and used as the count".
    //   An interrupt's frame is the PSW and the PC and nothing else, so there
    //   is nothing above them to discard and the count is zero.
    mem[11'h7D0] = 8'h09; mem[11'h7D1] = 8'h80; mem[11'h7D2] = 8'hF4;
    mem[11'h7D3] = 8'hA1; mem[11'h7D4] = 8'h68;
    mem[11'h7D5] = 8'hFA; mem[11'h7D6] = 8'hE0;
    // handler 3:  MOV.W #0x6B0, R9 ; MOV.B #0xA2, [R8] ; RETIS [R9]
    //   The count is read from MEMORY rather than from an immediate, and the
    //   word there is FFFF0008: a halfword count of 8, with the upper half set
    //   to something an implementation that read four bytes could not survive.
    //   "retis count.h.r" -- the operand is a halfword.
    //   8 is what this frame has above the PC and PSW: Figure 8-5's Bus Fault
    //   prints a parameter count of 8, and that is what §8 means by "the
    //   number of bytes to discard from the stack following the processing of
    //   the exception".  The handler reads it and passes it here.
    mem[11'h7E0] = 8'h2D; mem[11'h7E1] = 8'hA0; mem[11'h7E2] = 8'hF4;
    mem[11'h7E3] = 8'hB0; mem[11'h7E4] = 8'h06; mem[11'h7E5] = 8'h00;
    mem[11'h7E6] = 8'h00; mem[11'h7E7] = 8'h69;
    mem[11'h7E8] = 8'h09; mem[11'h7E9] = 8'h80; mem[11'h7EA] = 8'hF4;
    mem[11'h7EB] = 8'hA2; mem[11'h7EC] = 8'h68;
    mem[11'h7ED] = 8'hFA; mem[11'h7EE] = 8'h69;
    // handler 96: MOV.B #0xA3, [R8] ; RETIS #0
    mem[11'h7F0] = 8'h09; mem[11'h7F1] = 8'h80; mem[11'h7F2] = 8'hF4;
    mem[11'h7F3] = 8'hA3; mem[11'h7F4] = 8'h68;
    mem[11'h7F5] = 8'hFA; mem[11'h7F6] = 8'hE0;

    // ---- a sixth program, at 0x540: the two return pairs --------------------
    // SBT entry 17, Privileged Instruction   (Figure 8-2's +68) -> 0x780
    mem[11'h044] = 8'h80; mem[11'h045] = 8'h07;
    // SBT entry 20, Illegal Data Field       (Figure 8-2's +80) -> 0x790
    mem[11'h050] = 8'h90; mem[11'h051] = 8'h07;
    // handler 17: MOV.B #0xB1, [R8]
    mem[11'h780] = 8'h09; mem[11'h781] = 8'h80; mem[11'h782] = 8'hF4;
    mem[11'h783] = 8'hB1; mem[11'h784] = 8'h68;
    // handler 20: MOV.B #0xB2, [R8]
    mem[11'h790] = 8'h09; mem[11'h791] = 8'h80; mem[11'h792] = 8'hF4;
    mem[11'h793] = 8'hB2; mem[11'h794] = 8'h68;

    // MOV.W #0x600, R31
    mem[11'h540] = 8'h2D; mem[11'h541] = 8'hA0; mem[11'h542] = 8'hF4;
    mem[11'h543] = 8'h00; mem[11'h544] = 8'h06; mem[11'h545] = 8'h00;
    mem[11'h546] = 8'h00; mem[11'h547] = 8'h7F;
    // MOV.W #0x700, R8
    mem[11'h548] = 8'h2D; mem[11'h549] = 8'hA0; mem[11'h54A] = 8'hF4;
    mem[11'h54B] = 8'h00; mem[11'h54C] = 8'h07; mem[11'h54D] = 8'h00;
    mem[11'h54E] = 8'h00; mem[11'h54F] = 8'h68;
    // MOV.W #0x5A5A, R29   the caller's argument pointer, which CALL saves
    mem[11'h550] = 8'h2D; mem[11'h551] = 8'hA0; mem[11'h552] = 8'hF4;
    mem[11'h553] = 8'h5A; mem[11'h554] = 8'h5A; mem[11'h555] = 8'h00;
    mem[11'h556] = 8'h00; mem[11'h557] = 8'h7D;
    // MOV.W #0x6A0, R9     the argument list.  Loaded BEFORE R10 on purpose:
    //                      the last immediate an instruction read before the
    //                      CALL must not be the argument list's address, or an
    //                      implementation that passed a stale operand instead
    //                      of the effective address would pass.
    mem[11'h558] = 8'h2D; mem[11'h559] = 8'hA0; mem[11'h55A] = 8'hF4;
    mem[11'h55B] = 8'hA0; mem[11'h55C] = 8'h06; mem[11'h55D] = 8'h00;
    mem[11'h55E] = 8'h00; mem[11'h55F] = 8'h69;
    // MOV.W #0x590, R10    the first procedure
    mem[11'h560] = 8'h2D; mem[11'h561] = 8'hA0; mem[11'h562] = 8'hF4;
    mem[11'h563] = 8'h90; mem[11'h564] = 8'h05; mem[11'h565] = 8'h00;
    mem[11'h566] = 8'h00; mem[11'h567] = 8'h6A;
    // CALL [R10], [R9]     49 80 6A 69   Format II, m = m' = 0 so both mod
    //                                    fields are register indirect.  CALL
    //                                    takes their ADDRESSES, so what is at
    //                                    0x590 and 0x6A0 is never read as an
    //                                    operand -- and 0x6A0 is left at zero.
    mem[11'h568] = 8'h49; mem[11'h569] = 8'h80; mem[11'h56A] = 8'h6A;
    mem[11'h56B] = 8'h69;
    // MOV.B #0x0C, [R8]    where the first RET comes back to
    mem[11'h56C] = 8'h09; mem[11'h56D] = 8'h80; mem[11'h56E] = 8'hF4;
    mem[11'h56F] = 8'h0C; mem[11'h570] = 8'h68;
    // MOV.W #0x5B0, R10    the second procedure
    mem[11'h571] = 8'h2D; mem[11'h572] = 8'hA0; mem[11'h573] = 8'hF4;
    mem[11'h574] = 8'hB0; mem[11'h575] = 8'h05; mem[11'h576] = 8'h00;
    mem[11'h577] = 8'h00; mem[11'h578] = 8'h6A;
    // CALL [R10], [R9]
    mem[11'h579] = 8'h49; mem[11'h57A] = 8'h80; mem[11'h57B] = 8'h6A;
    mem[11'h57C] = 8'h69;
    // MOV.B #0x0E, [R8]
    mem[11'h57D] = 8'h09; mem[11'h57E] = 8'h80; mem[11'h57F] = 8'hF4;
    mem[11'h580] = 8'h0E; mem[11'h581] = 8'h68;

    // procedure 1, at 0x590: MOV.B #0x0B, [R8] ; RET #0
    //   E2 is RET with m = 0, and E0 is immediate quick with the value in its
    //   low nibble.  Nothing was pushed above the frame, so nothing is
    //   discarded.
    mem[11'h590] = 8'h09; mem[11'h591] = 8'h80; mem[11'h592] = 8'hF4;
    mem[11'h593] = 8'h0B; mem[11'h594] = 8'h68;
    mem[11'h595] = 8'hE2; mem[11'h596] = 8'hE0;
    // procedure 2, at 0x5B0: MOV.B #0x0D, [R8] ; RET #4
    //   "the optional number operand is used to automatically discard any
    //   input parameters from the stack", so this one leaves the stack pointer
    //   four bytes ABOVE where the caller had it.
    mem[11'h5B0] = 8'h09; mem[11'h5B1] = 8'h80; mem[11'h5B2] = 8'hF4;
    mem[11'h5B3] = 8'h0D; mem[11'h5B4] = 8'h68;
    mem[11'h5B5] = 8'hE2; mem[11'h5B6] = 8'hE4;
    // the privilege pair, each on its own so a raise cannot run the other
    // RETIS #0   FA E0   -- privileged, so at execution level 3 it raises
    mem[11'h5C0] = 8'hFA; mem[11'h5C1] = 8'hE0;
    // RETIU #0   EA E0   -- not privileged, so at execution level 3 it runs
    mem[11'h5C8] = 8'hEA; mem[11'h5C9] = 8'hE0;

    // ---- a seventh program, at 0x440: the multiplies and divides ------------
    // SBT entry 21, Integer Arithmetic Exception (Figure 8-2's +84) -> 0x1C0.
    // BRKV's page confirms the vector independently: "PC <- [ Exception
    // Vector 21 ]", and 84 = 4 x 21.
    mem[11'h054] = 8'hC0; mem[11'h055] = 8'h01;
    // handler 21: MOV.B #0xC1, [R8] ; RETIS #8
    //   Four words of frame -- the Current PC above the code word, then the
    //   PSW, then the Next PC -- so eight bytes are left to discard after the
    //   PC and PSW are popped, which is the count Figure 8-5 prints for it.
    mem[11'h1C0] = 8'h09; mem[11'h1C1] = 8'h80; mem[11'h1C2] = 8'hF4;
    mem[11'h1C3] = 8'hC1; mem[11'h1C4] = 8'h68;
    mem[11'h1C5] = 8'hFA; mem[11'h1C6] = 8'hE8;
    // MOV.W #0x600, R31
    mem[11'h440] = 8'h2D; mem[11'h441] = 8'hA0; mem[11'h442] = 8'hF4;
    mem[11'h443] = 8'h00; mem[11'h444] = 8'h06; mem[11'h445] = 8'h00;
    mem[11'h446] = 8'h00; mem[11'h447] = 8'h7F;
    // MOV.W #0x700, R8
    mem[11'h448] = 8'h2D; mem[11'h449] = 8'hA0; mem[11'h44A] = 8'hF4;
    mem[11'h44B] = 8'h00; mem[11'h44C] = 8'h07; mem[11'h44D] = 8'h00;
    mem[11'h44E] = 8'h00; mem[11'h44F] = 8'h68;
    // MOV.W #100, R9
    mem[11'h450] = 8'h2D; mem[11'h451] = 8'hA0; mem[11'h452] = 8'hF4;
    mem[11'h453] = 8'h64; mem[11'h454] = 8'h00; mem[11'h455] = 8'h00;
    mem[11'h456] = 8'h00; mem[11'h457] = 8'h69;
    // MUL.w #7, R9        85 A0 F4 07 00 00 00 69   -> 700
    mem[11'h458] = 8'h85; mem[11'h459] = 8'hA0; mem[11'h45A] = 8'hF4;
    mem[11'h45B] = 8'h07; mem[11'h45C] = 8'h00; mem[11'h45D] = 8'h00;
    mem[11'h45E] = 8'h00; mem[11'h45F] = 8'h69;
    // DIV.w #3, R9        A5 ...                    -> 233
    mem[11'h460] = 8'hA5; mem[11'h461] = 8'hA0; mem[11'h462] = 8'hF4;
    mem[11'h463] = 8'h03; mem[11'h464] = 8'h00; mem[11'h465] = 8'h00;
    mem[11'h466] = 8'h00; mem[11'h467] = 8'h69;
    // REM.w #3, R9        54 ...                    -> 233 % 3 = 2
    mem[11'h468] = 8'h54; mem[11'h469] = 8'hA0; mem[11'h46A] = 8'hF4;
    mem[11'h46B] = 8'h03; mem[11'h46C] = 8'h00; mem[11'h46D] = 8'h00;
    mem[11'h46E] = 8'h00; mem[11'h46F] = 8'h69;
    // DIV.w #0, R9        A5 ...                    -> the Zero Divide exception
    mem[11'h470] = 8'hA5; mem[11'h471] = 8'hA0; mem[11'h472] = 8'hF4;
    mem[11'h473] = 8'h00; mem[11'h474] = 8'h00; mem[11'h475] = 8'h00;
    mem[11'h476] = 8'h00; mem[11'h477] = 8'h69;
    // MOV.B #0x21, [R8]   where the handler returns to: the NEXT instruction
    mem[11'h478] = 8'h09; mem[11'h479] = 8'h80; mem[11'h47A] = 8'hF4;
    mem[11'h47B] = 8'h21; mem[11'h47C] = 8'h68;

    // ---- an eighth program, at 0x4A0: RVBIT, RVBYT and SETF -----------------
    // Three that write their destination without reading it, and leave every
    // flag alone.  The bus-cycle count is what proves the first half.
    // MOV.W #0x700, R8
    mem[11'h4A0] = 8'h2D; mem[11'h4A1] = 8'hA0; mem[11'h4A2] = 8'hF4;
    mem[11'h4A3] = 8'h00; mem[11'h4A4] = 8'h07; mem[11'h4A5] = 8'h00;
    mem[11'h4A6] = 8'h00; mem[11'h4A7] = 8'h68;
    // CMP.b #0, R8   B8 A0 E0 68   -- sets the flags to a known state: R8 is
    //                                 0x700, so its byte 00 equals 0 and Z is
    //                                 set, CY clear.
    mem[11'h4A8] = 8'hB8; mem[11'h4A9] = 8'hA0; mem[11'h4AA] = 8'hE0;
    mem[11'h4AB] = 8'h68;
    // RVBIT #1, R9   08 A0 E1 69   -- immediate quick 1, into a register.
    //   "the immediate data is zero extended to byte length before the bit
    //   reversal takes place", so this reverses 0000_0001 and gives 80.
    mem[11'h4AC] = 8'h08; mem[11'h4AD] = 8'hA0; mem[11'h4AE] = 8'hE1;
    mem[11'h4AF] = 8'h69;
    // RVBYT #0x11223344, R10   2C A0 F4 44 33 22 11 6A
    mem[11'h4B0] = 8'h2C; mem[11'h4B1] = 8'hA0; mem[11'h4B2] = 8'hF4;
    mem[11'h4B3] = 8'h44; mem[11'h4B4] = 8'h33; mem[11'h4B5] = 8'h22;
    mem[11'h4B6] = 8'h11; mem[11'h4B7] = 8'h6A;
    // SETF #4, [R8]  47 80 E4 68   -- condition 4 is Zero/Equal, and the CMP
    //   above left Z set, so this stores 01H.  The destination is MEMORY, so
    //   its bus cycles are countable: one write, and no read.
    mem[11'h4B8] = 8'h47; mem[11'h4B9] = 8'h80; mem[11'h4BA] = 8'hE4;
    mem[11'h4BB] = 8'h68;
    // SETF #5, [R8]  47 80 E5 68   -- condition 5 is Not zero / Not equal.
    mem[11'h4BC] = 8'h47; mem[11'h4BD] = 8'h80; mem[11'h4BE] = 8'hE5;
    mem[11'h4BF] = 8'h68;
    // RVBIT #1, [R8] 08 80 E1 68   -- the byte reversal, into memory
    mem[11'h4C0] = 8'h08; mem[11'h4C1] = 8'h80; mem[11'h4C2] = 8'hE1;
    mem[11'h4C3] = 8'h68;

    // TEST.b through MEMORY, at 0x480.  The register form below exercises the
    // sequencer's own register path; this one exercises v60_ea's, and it is
    // the only place Format III's operand has to reach val1 through ea_rdata.
    // MOV.W #0x700, R8
    mem[11'h480] = 8'h2D; mem[11'h481] = 8'hA0; mem[11'h482] = 8'hF4;
    mem[11'h483] = 8'h00; mem[11'h484] = 8'h07; mem[11'h485] = 8'h00;
    mem[11'h486] = 8'h00; mem[11'h487] = 8'h68;
    // TEST.b [R8]   F0 68   -- m = 0, register indirect
    mem[11'h488] = 8'hF0; mem[11'h489] = 8'h68;
    // CMP.b #0x80, [R8]   B8 80 F4 80 68
    //   Its second operand is "src2.b.r" -- the page does not call it a
    //   destination -- so it must be read and never written back.
    mem[11'h48A] = 8'hB8; mem[11'h48B] = 8'h80; mem[11'h48C] = 8'hF4;
    mem[11'h48D] = 8'h80; mem[11'h48E] = 8'h68;

    // ---- a tenth program, at 0x1D0: NOP, MOVEA, and the addr_only leak -----
    // MOV.W #0x700, R8
    mem[11'h1D0] = 8'h2D; mem[11'h1D1] = 8'hA0; mem[11'h1D2] = 8'hF4;
    mem[11'h1D3] = 8'h00; mem[11'h1D4] = 8'h07; mem[11'h1D5] = 8'h00;
    mem[11'h1D6] = 8'h00; mem[11'h1D7] = 8'h68;
    // MOV.B #0x5A, [R8]     -- the byte the load after the JMP must see
    mem[11'h1D8] = 8'h09; mem[11'h1D9] = 8'h80; mem[11'h1DA] = 8'hF4;
    mem[11'h1DB] = 8'h5A; mem[11'h1DC] = 8'h68;
    // NOP                   -- one byte, Format V
    mem[11'h1DD] = 8'hCD;
    // MOVEA.b [R8], R9      40 A0 68 69
    //   The source is "src.b.n": its ADDRESS is taken and no bus cycle is
    //   issued for it, so R9 gets 0x700 and not 0x5A.
    mem[11'h1DE] = 8'h40; mem[11'h1DF] = 8'hA0; mem[11'h1E0] = 8'h68;
    mem[11'h1E1] = 8'h69;
    // MOV.W #0x1F0, R10     -- where the JMP goes
    mem[11'h1E2] = 8'h2D; mem[11'h1E3] = 8'hA0; mem[11'h1E4] = 8'hF4;
    mem[11'h1E5] = 8'hF0; mem[11'h1E6] = 8'h01; mem[11'h1E7] = 8'h00;
    mem[11'h1E8] = 8'h00; mem[11'h1E9] = 8'h6A;
    // JMP [R10]             D6 6A   -- sets ea_addr_only on its way out
    mem[11'h1EA] = 8'hD6; mem[11'h1EB] = 8'h6A;
    // 0x1F0: MOV.B [R8], R11   09 A0 68 6B
    //   A MEMORY source in the instruction immediately after a control
    //   transfer.  This is the case the addr_only leak broke: R11 must get the
    //   BYTE at 0x700, not the address 0x700 and not stale data.
    mem[11'h1F0] = 8'h09; mem[11'h1F1] = 8'hA0; mem[11'h1F2] = 8'h68;
    mem[11'h1F3] = 8'h6B;
    // MOVEA.b [R8+], R9   40 E0 88 69
    //   An AUTOINCREMENT source, which is the only way MOVEA's size field is
    //   observable: nothing is read, but "separate instructions are provided
    //   for byte, halfword and word operands to permit correct computation of
    //   effective addresses using the autoincrement, autodecrement and scaled
    //   index addressing modes".  The .b form steps R8 by ONE.
    mem[11'h1F4] = 8'h40; mem[11'h1F5] = 8'hE0; mem[11'h1F6] = 8'h88;
    mem[11'h1F7] = 8'h69;
    // MOVEA.w [R9], [R9]   44 80 69 69
    //   A MEMORY destination, which is "dst.w.w" -- written and not read.  A
    //   MOVEA left out of dst_write_only reads it first, which costs two extra
    //   bus cycles and puts a READ on the pins the page does not describe.
    //   R9 is 0x700 by now, so both the address taken and the place it is
    //   stored are that, and the destination is word aligned.
    mem[11'h1F8] = 8'h44; mem[11'h1F9] = 8'h80; mem[11'h1FA] = 8'h69;
    mem[11'h1FB] = 8'h69;

    // ---- an eleventh program, at 0x200 is taken; use 0x230 -----------------
    // GETPSW and the UPDPSW pair.  The .h form's operands are WORDS, like the
    // .w form's -- the `.h` names which half of the PSW it may touch.
    // UPDPSW.H #0x0000000F, #0x0000000F   4A 80 F4 0F 00 00 00 F4 0F 00 00 00
    //   newPSW = 0x0F, mask = 0x0F: set all four integer condition codes.
    mem[11'h230] = 8'h4A; mem[11'h231] = 8'h80; mem[11'h232] = 8'hF4;
    mem[11'h233] = 8'h0F; mem[11'h234] = 8'h00; mem[11'h235] = 8'h00;
    mem[11'h236] = 8'h00; mem[11'h237] = 8'hF4; mem[11'h238] = 8'h0F;
    mem[11'h239] = 8'h00; mem[11'h23A] = 8'h00; mem[11'h23B] = 8'h00;
    // GETPSW R9    F7 69   -- Format III, one write-only operand
    mem[11'h23C] = 8'hF7; mem[11'h23D] = 8'h69;
    // UPDPSW.H #0x00010005, #0x0001000F
    //   One instruction carrying three distinct questions:
    //     * mask bit 16 is PSW.TE, OUTSIDE the condition codes, and newPSW has
    //       it SET -- so an unrestricted .h form would turn TE on;
    //     * newPSW's low nibble is 0101 and the mask's is 1111, which differ,
    //       so an implementation that swapped the two operands would leave the
    //       codes at 1111 instead of 0101;
    //     * the codes start at 1111 from the instruction above, so the merge
    //       has to CLEAR two of them rather than only set bits.
    mem[11'h23E] = 8'h4A; mem[11'h23F] = 8'h80; mem[11'h240] = 8'hF4;
    mem[11'h241] = 8'h05; mem[11'h242] = 8'h00; mem[11'h243] = 8'h01;
    mem[11'h244] = 8'h00; mem[11'h245] = 8'hF4; mem[11'h246] = 8'h0F;
    mem[11'h247] = 8'h00; mem[11'h248] = 8'h01; mem[11'h249] = 8'h00;
    // UPDPSW.W #0x00010000, #0x00010000   13 80 ...  -- the privileged form
    //   CAN set PSW.TE.
    mem[11'h24A] = 8'h13; mem[11'h24B] = 8'h80; mem[11'h24C] = 8'hF4;
    mem[11'h24D] = 8'h00; mem[11'h24E] = 8'h00; mem[11'h24F] = 8'h01;
    mem[11'h250] = 8'h00; mem[11'h251] = 8'hF4; mem[11'h252] = 8'h00;
    mem[11'h253] = 8'h00; mem[11'h254] = 8'h01; mem[11'h255] = 8'h00;
    // SBT entry 13, Instruction Breakpoint (Figure 8-2's +52) -> 0x1A0
    mem[11'h034] = 8'hA0; mem[11'h035] = 8'h01;
    // handler 13: MOV.B #0xB9, [R8]
    mem[11'h1A0] = 8'h09; mem[11'h1A1] = 8'h80; mem[11'h1A2] = 8'hF4;
    mem[11'h1A3] = 8'hB9; mem[11'h1A4] = 8'h68;
    // BRK at 0x27C -- C8, Format V, one byte
    mem[11'h27C] = 8'hC8;

    // TRAP.  Format III, so the same shape as INC and TEST above: the mod
    // field in the register column with m = 1, and F8/F9 one instruction.
    //
    // SBT entry 53 -- Software Trap 5, at 4 x 53 = +212 = 0xD4 -- points at a
    // handler that writes a byte, so a trap that vectors ANYWHERE else is
    // visible in two ways rather than one.
    mem[11'h0D4] = 8'hB0; mem[11'h0D5] = 8'h01;
    // handler for trap 5: MOV.B #0xC7, [R8]
    mem[11'h1B0] = 8'h09; mem[11'h1B1] = 8'h80; mem[11'h1B2] = 8'hF4;
    mem[11'h1B3] = 8'hC7; mem[11'h1B4] = 8'h68;
    // TRAP R9    F9 69
    mem[11'h2A0] = 8'hF9; mem[11'h2A1] = 8'h69;
    // MOV.B #0x5C, [R8]   -- reached only when the TRAP above falls through
    mem[11'h2A2] = 8'h09; mem[11'h2A3] = 8'h80; mem[11'h2A4] = 8'hF4;
    mem[11'h2A5] = 8'h5C; mem[11'h2A6] = 8'h68;

    // TRAPFL.  SBT entry 22 -- Floating Point Arithmetic Exception, at
    // 4 x 22 = +88 = 0x58 -- gets its own handler rather than sharing vector
    // 21's, so a TRAPFL that reached the integer arithmetic vector instead is
    // visible in the byte the handler writes as well as in the PC.
    mem[11'h058] = 8'hC0; mem[11'h059] = 8'h02;
    // handler for vector 22: MOV.B #0xD3, [R8]
    mem[11'h2C0] = 8'h09; mem[11'h2C1] = 8'h80; mem[11'h2C2] = 8'hF4;
    mem[11'h2C3] = 8'hD3; mem[11'h2C4] = 8'h68;
    // The privileged register pair, Format II throughout: an immediate source
    // and a register second operand, the same shape as MOV.B #0x77, R9 above.
    //
    // STPR #8, R9      02 A0 F4 08 00 00 00 69   -- TKCW into R9
    mem[11'h2D0] = 8'h02; mem[11'h2D1] = 8'hA0; mem[11'h2D2] = 8'hF4;
    mem[11'h2D3] = 8'h08; mem[11'h2D4] = 8'h00; mem[11'h2D5] = 8'h00;
    mem[11'h2D6] = 8'h00; mem[11'h2D7] = 8'h69;
    // STPR #40, R9     02 A0 F4 28 00 00 00 69   -- an id above 31
    mem[11'h2E0] = 8'h02; mem[11'h2E1] = 8'hA0; mem[11'h2E2] = 8'hF4;
    mem[11'h2E3] = 8'h28; mem[11'h2E4] = 8'h00; mem[11'h2E5] = 8'h00;
    mem[11'h2E6] = 8'h00; mem[11'h2E7] = 8'h69;
    // STPR #7, R10     02 A0 F4 07 00 00 00 6A   -- a DIFFERENT id, so that an
    //   implementation reading a fixed privileged register cannot pass
    mem[11'h2D8] = 8'h02; mem[11'h2D9] = 8'hA0; mem[11'h2DA] = 8'hF4;
    mem[11'h2DB] = 8'h07; mem[11'h2DC] = 8'h00; mem[11'h2DD] = 8'h00;
    mem[11'h2DE] = 8'h00; mem[11'h2DF] = 8'h6A;
    // LDPR #0x5EED1234, [R8]   12 80 F4 34 12 ED 5E 68
    //   The id in MEMORY, which is the only way to see that LDPR READS its
    //   second operand and never writes it: a read-modify-write would put a
    //   bus WRITE on a location the instruction only ever consults.
    mem[11'h3A0] = 8'h12; mem[11'h3A1] = 8'h80; mem[11'h3A2] = 8'hF4;
    mem[11'h3A3] = 8'h34; mem[11'h3A4] = 8'h12; mem[11'h3A5] = 8'hED;
    mem[11'h3A6] = 8'h5E; mem[11'h3A7] = 8'h68;
    // LDPR #0xCAFEF00D, R9   12 A0 F4 0D F0 FE CA 69
    //   R9 carries the ID and is READ, not written -- which is the whole
    //   question its ".w.w" syntax line raises.
    mem[11'h2F0] = 8'h12; mem[11'h2F1] = 8'hA0; mem[11'h2F2] = 8'hF4;
    mem[11'h2F3] = 8'h0D; mem[11'h2F4] = 8'hF0; mem[11'h2F5] = 8'hFE;
    mem[11'h2F6] = 8'hCA; mem[11'h2F7] = 8'h69;

    // HALT at 0x3B0 -- 00, Format V, one byte -- and an instruction after it
    // that must NOT run until an interrupt has been through.
    mem[11'h3B0] = 8'h00;
    mem[11'h3B1] = 8'h09; mem[11'h3B2] = 8'h80; mem[11'h3B3] = 8'hF4;
    mem[11'h3B4] = 8'h4D; mem[11'h3B5] = 8'h68;

    // The four bit instructions, Format II throughout.
    // SET1 #5, R9      97 A0 F4 05 00 00 00 69   -- a REGISTER base
    mem[11'h3C0] = 8'h97; mem[11'h3C1] = 8'hA0; mem[11'h3C2] = 8'hF4;
    mem[11'h3C3] = 8'h05; mem[11'h3C4] = 8'h00; mem[11'h3C5] = 8'h00;
    mem[11'h3C6] = 8'h00; mem[11'h3C7] = 8'h69;
    // SET1 #32, R9     97 A0 F4 20 00 00 00 69   -- one past the top of the range
    mem[11'h3C8] = 8'h97; mem[11'h3C9] = 8'hA0; mem[11'h3CA] = 8'hF4;
    mem[11'h3CB] = 8'h20; mem[11'h3CC] = 8'h00; mem[11'h3CD] = 8'h00;
    mem[11'h3CE] = 8'h00; mem[11'h3CF] = 8'h69;
    // TEST1 #9, [R8]   87 80 F4 09 00 00 00 68   -- a MEMORY base, read only
    mem[11'h3D0] = 8'h87; mem[11'h3D1] = 8'h80; mem[11'h3D2] = 8'hF4;
    mem[11'h3D3] = 8'h09; mem[11'h3D4] = 8'h00; mem[11'h3D5] = 8'h00;
    mem[11'h3D6] = 8'h00; mem[11'h3D7] = 8'h68;
    // CLR1 #9, [R8]    A7 80 F4 09 00 00 00 68
    mem[11'h3D8] = 8'hA7; mem[11'h3D9] = 8'h80; mem[11'h3DA] = 8'hF4;
    mem[11'h3DB] = 8'h09; mem[11'h3DC] = 8'h00; mem[11'h3DD] = 8'h00;
    mem[11'h3DE] = 8'h00; mem[11'h3DF] = 8'h68;
    // NOT1 #3, [R8+]   B7 A0 F4 03 00 00 00 88   -- the base is WORD data, so
    //   the autoincrement steps R8 by FOUR and not by one.  The A0 prefix puts
    //   m = 1 on the SECOND operand, which is what makes 88 autoincrement
    //   rather than 8-bit displacement indirect.
    mem[11'h3E0] = 8'hB7; mem[11'h3E1] = 8'hA0; mem[11'h3E2] = 8'hF4;
    mem[11'h3E3] = 8'h03; mem[11'h3E4] = 8'h00; mem[11'h3E5] = 8'h00;
    mem[11'h3E6] = 8'h00; mem[11'h3E7] = 8'h88;

    // The I/O pair, Format II.  R10 holds the port address.
    // IN.b [R10], R9    20 A0 6A 69   -- the port on the SOURCE side
    mem[11'h3F0] = 8'h20; mem[11'h3F1] = 8'hA0; mem[11'h3F2] = 8'h6A;
    mem[11'h3F3] = 8'h69;
    // OUT.b R9, [R10]   21 C0 69 6A   -- the port on the DESTINATION side.
    //   The C0 prefix is m = 1 on the first operand (R9 direct) and m = 0 on
    //   the second, which is what makes 6A the INDIRECT [R10] a port needs.
    mem[11'h3F4] = 8'h21; mem[11'h3F5] = 8'hC0; mem[11'h3F6] = 8'h69;
    mem[11'h3F7] = 8'h6A;
    // MOVEA's illegal source modes.  Its Addressing Modes table marks Rn,
    // Immediate and Immediate.Quick as X for the src column: "movea.b
    // src.b.n, dst.w.w" asks for an ADDRESS, and none of the three has one.
    // MOVEA.w R10, R9   44 E0 6A 69
    mem[11'h490] = 8'h44; mem[11'h491] = 8'hE0; mem[11'h492] = 8'h6A;
    mem[11'h493] = 8'h69;
    // MOVEA.w #5, R9    44 A0 F4 05 00 00 00 69
    mem[11'h494] = 8'h44; mem[11'h495] = 8'hA0; mem[11'h496] = 8'hF4;
    mem[11'h497] = 8'h05; mem[11'h498] = 8'h00; mem[11'h499] = 8'h00;
    mem[11'h49A] = 8'h00; mem[11'h49B] = 8'h69;

    // PUSH and POP, Format III -- one encoded operand and an implicit stack.
    // PUSH R9    EF 69   (m = 1, so the mod field is the register column)
    mem[11'h620] = 8'hEF; mem[11'h621] = 8'h69;
    // POP R10    E7 6A
    mem[11'h622] = 8'hE7; mem[11'h623] = 8'h6A;
    // PUSH [R8+] EF 88   -- an AUTOINCREMENT operand, so the instruction has
    //   TWO register writebacks: R8 from the addressing mode and R31 from the
    //   stack.  The stack access uses AM_RN_IND with a pointer this sequencer
    //   computes, so v60_ea raises only one of them and the pair coexists.
    mem[11'h624] = 8'hEF; mem[11'h625] = 8'h88;

    // PREPARE #16   DE F4 10 00 00 00   -- Format III with an immediate `num`
    mem[11'h626] = 8'hDE; mem[11'h627] = 8'hF4; mem[11'h628] = 8'h10;
    mem[11'h629] = 8'h00; mem[11'h62A] = 8'h00; mem[11'h62B] = 8'h00;
    // DISPOSE       CC   -- Format V, one byte
    mem[11'h62C] = 8'hCC;

    // XCH, Format II.  dst1 must be a general purpose register; the same
    // column raises two DIFFERENT exceptions for the two ways it can not be.
    // XCH.w R9, R10    45 E0 69 6A
    mem[11'h630] = 8'h45; mem[11'h631] = 8'hE0; mem[11'h632] = 8'h69;
    mem[11'h633] = 8'h6A;
    // XCH.w R9, [R8]   45 C0 69 68   -- the legal memory case: dst2, not dst1
    mem[11'h634] = 8'h45; mem[11'h635] = 8'hC0; mem[11'h636] = 8'h69;
    mem[11'h637] = 8'h68;
    // XCH.w [R8], R9   45 A0 68 69   -- dst1 in MEMORY: `A`, Reserved
    mem[11'h638] = 8'h45; mem[11'h639] = 8'hA0; mem[11'h63A] = 8'h68;
    mem[11'h63B] = 8'h69;
    // XCH.w #5, R9     45 A0 F4 05 00 00 00 69   -- dst1 IMMEDIATE: `X`, Illegal
    mem[11'h63C] = 8'h45; mem[11'h63D] = 8'hA0; mem[11'h63E] = 8'hF4;
    mem[11'h63F] = 8'h05; mem[11'h640] = 8'h00; mem[11'h641] = 8'h00;
    mem[11'h642] = 8'h00; mem[11'h643] = 8'h69;

    // PUSHM / POPM #0x80000E00 -- R9, R10, R11 and the PSW (bit 31).
    //   The three registers are consecutive so the ORDER they land in is
    //   visible, and the PSW is at the far end of the mask from them so the
    //   scan direction is visible too.
    mem[11'h644] = 8'hEC; mem[11'h645] = 8'hF4; mem[11'h646] = 8'h00;
    mem[11'h647] = 8'h0E; mem[11'h648] = 8'h00; mem[11'h649] = 8'h80;
    mem[11'h64A] = 8'hE4; mem[11'h64B] = 8'hF4; mem[11'h64C] = 8'h00;
    mem[11'h64D] = 8'h0E; mem[11'h64E] = 8'h00; mem[11'h64F] = 8'h80;

    // CHLVL, Format II, two BYTE immediates.
    // SBT entry 24, Change to Execution Level 0 (Figure 8-2's +96) -> 0x2E8
    mem[11'h060] = 8'hE8; mem[11'h061] = 8'h02;
    // handler 24: MOV.B #0xC5, [R8]
    mem[11'h2E8] = 8'h09; mem[11'h2E9] = 8'h80; mem[11'h2EA] = 8'hF4;
    mem[11'h2EB] = 8'hC5; mem[11'h2EC] = 8'h68;
    // CHLVL #0, #0x5A   4B 80 F4 00 F4 5A   -- calling UP to level 0
    mem[11'h730] = 8'h4B; mem[11'h731] = 8'h80; mem[11'h732] = 8'hF4;
    mem[11'h733] = 8'h00; mem[11'h734] = 8'hF4; mem[11'h735] = 8'h5A;
    // CHLVL #2, #0x5A   -- from level 0, asking for a LESS privileged level
    mem[11'h736] = 8'h4B; mem[11'h737] = 8'h80; mem[11'h738] = 8'hF4;
    mem[11'h739] = 8'h02; mem[11'h73A] = 8'hF4; mem[11'h73B] = 8'h5A;
    // CHLVL #5, #0x5A   -- a level that does not exist
    mem[11'h73C] = 8'h4B; mem[11'h73D] = 8'h80; mem[11'h73E] = 8'hF4;
    mem[11'h73F] = 8'h05; mem[11'h740] = 8'hF4; mem[11'h741] = 8'h5A;
    // CHLVL #4, #0x5A   -- out of range, and chosen so that the RANGE check is
    //   the only thing that can catch it: 4's low two bits are 00, so the
    //   privilege comparison against a level 0 caller passes.
    mem[11'h742] = 8'h4B; mem[11'h743] = 8'h80; mem[11'h744] = 8'hF4;
    mem[11'h745] = 8'h04; mem[11'h746] = 8'hF4; mem[11'h747] = 8'h5A;
    // CHLVL #2, #0x77   -- a SUCCESSFUL call to a non-zero level, which is the
    //   only case where "24 + level", the second-nibble code, the target
    //   level's stack and the handler's PSW.EL are each distinguishable.
    mem[11'h748] = 8'h4B; mem[11'h749] = 8'h80; mem[11'h74A] = 8'hF4;
    mem[11'h74B] = 8'h02; mem[11'h74C] = 8'hF4; mem[11'h74D] = 8'h77;
    // SBT entry 26, Change to Execution Level 2 (Figure 8-2's +104) -> 0x150
    mem[11'h068] = 8'h50; mem[11'h069] = 8'h01;
    // handler 26: MOV.B #0xE2, [R8]
    mem[11'h150] = 8'h09; mem[11'h151] = 8'h80; mem[11'h152] = 8'hF4;
    mem[11'h153] = 8'hE2; mem[11'h154] = 8'h68;

    // The X forms end to end, Format II.
    // MULX #0x10000, R9    86 A0 F4 00 00 01 00 69
    //   R9/R10 is the destination PAIR -- and it is an ODD low register on
    //   purpose: neither page puts an evenness constraint on the pair, and an
    //   implementation that masked the low bit to "align" it would be wrong on
    //   every odd n.
    mem[11'h158] = 8'h86; mem[11'h159] = 8'hA0; mem[11'h15A] = 8'hF4;
    mem[11'h15B] = 8'h00; mem[11'h15C] = 8'h00; mem[11'h15D] = 8'h01;
    mem[11'h15E] = 8'h00; mem[11'h15F] = 8'h69;
    // DIVX #10, [R8]       A6 80 F4 0A 00 00 00 68
    //   A MEMORY doubleword: eight bytes at R8, quotient at [R8] and remainder
    //   at [R8+4].
    mem[11'h160] = 8'hA6; mem[11'h161] = 8'h80; mem[11'h162] = 8'hF4;
    mem[11'h163] = 8'h0A; mem[11'h164] = 8'h00; mem[11'h165] = 8'h00;
    mem[11'h166] = 8'h00; mem[11'h167] = 8'h68;
    // DIVX #0, [R8]        A6 80 F4 00 00 00 00 68   -- the zero divide
    mem[11'h168] = 8'hA6; mem[11'h169] = 8'h80; mem[11'h16A] = 8'hF4;
    mem[11'h16B] = 8'h00; mem[11'h16C] = 8'h00; mem[11'h16D] = 8'h00;
    mem[11'h16E] = 8'h00; mem[11'h16F] = 8'h68;

    // DIVX #0x10000, R9    A6 A0 F4 00 00 01 00 69
    //   A REGISTER-PAIR dividend whose value genuinely needs its high word --
    //   the only shape that can tell "reads the pair" from "reads Rn twice"
    //   or from "reads only Rn".  MULX cannot: it reads the low word by
    //   design, so its high word could be anything.
    mem[11'h170] = 8'hA6; mem[11'h171] = 8'hA0; mem[11'h172] = 8'hF4;
    mem[11'h173] = 8'h00; mem[11'h174] = 8'h00; mem[11'h175] = 8'h01;
    mem[11'h176] = 8'h00; mem[11'h177] = 8'h69;

    // DIVX R12, R9    A6 4C 69   -- Format I: m = 1 (bit 6), d = 0 (bit 5),
    //   reg = 12.  With d = 0 the register field is the SOURCE and the mod
    //   field is the destination, so the destination pair R9/R10 is reached
    //   through v60_ea's register-direct path rather than the sequencer's own
    //   -- which is the only way that path's pair read and pair writeback are
    //   exercised at all.
    mem[11'h178] = 8'hA6; mem[11'h179] = 8'h4C; mem[11'h17A] = 8'h69;

    // MOV.W [R8], R9   2D A0 68 69   -- a MEMORY SOURCE, whose read runs
    //   through S_OP1S.  That path is reached BEFORE S_OP2 gets a chance to
    //   set the lock, so it is the only shape in which a leaked ea_lock is
    //   visible at all: an immediate source makes no bus access, and by the
    //   destination S_OP2 has already cleared it.
    mem[11'h724] = 8'h2D; mem[11'h725] = 8'hA0; mem[11'h726] = 8'h68;
    mem[11'h727] = 8'h69;
    // CALL [R10], [R9]  49 80 6A 69   -- the stack ENGINE's own accesses
    mem[11'h728] = 8'h49; mem[11'h729] = 8'h80; mem[11'h72A] = 8'h6A;
    mem[11'h72B] = 8'h69;
    // BSR +2            48 02 00      -- the control transfer's push
    mem[11'h72C] = 8'h48; mem[11'h72D] = 8'h02; mem[11'h72E] = 8'h00;
    mem[11'h72F] = 8'hCD;              // NOP, where both of the above land

    // The bit field group.  Format VII's base word is `1 m m' subop` over the
    // opcode, so byte 1 is 0x80 | m<<6 | m'<<5 | subop -- and the sub-op's low
    // two bits are the variant (00 signed, 01 unsigned, 10 left justified).
    //
    // A DISPLACEMENT mode is used for the bit-addressed operand on purpose:
    // "the displacement field is interpreted as the bit offset from the base
    // address", so 3[R8] gives a residual of 3, where [R8] would give 0 and
    // the shift could not be seen.
    //
    // EXTBFZ 3[R8], #5, R9    5D A9 08 03 05 69
    mem[11'h6B4] = 8'h5D; mem[11'h6B5] = 8'hA9; mem[11'h6B6] = 8'h08;
    mem[11'h6B7] = 8'h03; mem[11'h6B8] = 8'h05; mem[11'h6B9] = 8'h69;
    // EXTBFS 3[R8], #5, R9    5D A8 08 03 05 69   -- the signed variant
    mem[11'h6BA] = 8'h5D; mem[11'h6BB] = 8'hA8; mem[11'h6BC] = 8'h08;
    mem[11'h6BD] = 8'h03; mem[11'h6BE] = 8'h05; mem[11'h6BF] = 8'h69;
    // CMPBFZ 3[R8], #5, R9    5D A1 08 03 05 69   -- three reads, no write
    mem[11'h6C0] = 8'h5D; mem[11'h6C1] = 8'hA1; mem[11'h6C2] = 8'h08;
    mem[11'h6C3] = 8'h03; mem[11'h6C4] = 8'h05; mem[11'h6C5] = 8'h69;
    // INSBFR R9, 3[R8], #5    5D D8 69 08 03 05   -- Format VIIc: the length
    //   is LAST, and the bit-addressed operand is the DESTINATION.
    mem[11'h6C6] = 8'h5D; mem[11'h6C7] = 8'hD8; mem[11'h6C8] = 8'h69;
    mem[11'h6C9] = 8'h08; mem[11'h6CA] = 8'h03; mem[11'h6CB] = 8'h05;
    // EXTBFZ 3[R8], #31, R9   5D A9 08 03 1F 69   -- 3 + 31 = 34 > 32, so the
    //   Illegal Data Field exception, which is the only thing these can raise.
    mem[11'h6CC] = 8'h5D; mem[11'h6CD] = 8'hA9; mem[11'h6CE] = 8'h08;
    mem[11'h6CF] = 8'h03; mem[11'h6D0] = 8'h1F; mem[11'h6D1] = 8'h69;
    // EXTBFZ 3[R8], R7, R9    5D A9 08 03 87 69   -- the length in a REGISTER,
    //   which bit 7 of the ext byte selects.
    mem[11'h6D2] = 8'h5D; mem[11'h6D3] = 8'hA9; mem[11'h6D4] = 8'h08;
    mem[11'h6D5] = 8'h03; mem[11'h6D6] = 8'h87; mem[11'h6D7] = 8'h69;

    // EXTBFZ -8[R8], #5, R9   5D A9 08 F8 05 69   -- a NEGATIVE bit offset.
    //   "the 32-bit bit offset is SIGN extended to 35-bit length", so this
    //   addresses bits BELOW the base byte.  Zero extension would land 4 GB
    //   away instead, which is the only way to tell the two apart.
    mem[11'h6D8] = 8'h5D; mem[11'h6D9] = 8'hA9; mem[11'h6DA] = 8'h08;
    mem[11'h6DB] = 8'hF8; mem[11'h6DC] = 8'h05; mem[11'h6DD] = 8'h69;
    // INSBFR 8[R10], 3[R8], #5   5D 98 0A 08 08 03 05   -- a memory source
    //   WITH A DISPLACEMENT.  Without one the two readings agree: a bit
    //   address with a zero offset divides back to the same byte, so treating
    //   this operand as bit-addressed would be invisible.  With +8 they differ
    //   -- 0x710+8 byte-addressed against ((0x710<<3)+8)>>3 = 0x711.
    mem[11'h6DE] = 8'h5D; mem[11'h6DF] = 8'h98; mem[11'h6E0] = 8'h0A;
    mem[11'h6E1] = 8'h08; mem[11'h6E2] = 8'h08; mem[11'h6E3] = 8'h03;
    mem[11'h6E4] = 8'h05;
    // EXTBFZ 0[R8], #40, R9   5D A9 08 00 28 69   -- a length above 32 with a
    //   residual of ZERO, so only the length can make the sum exceed it.
    mem[11'h6E5] = 8'h5D; mem[11'h6E6] = 8'hA9; mem[11'h6E7] = 8'h08;
    mem[11'h6E8] = 8'h00; mem[11'h6E9] = 8'h28; mem[11'h6EA] = 8'h69;
    // EXTBFZ 3[R8], #40, R9   5D A9 08 03 28 69   -- the SAME over-long length
    //   at a NON-ZERO residual, which is the only shape in which the sum's
    //   width matters: an over-long length is stored as 63, and 3 + 63 is 66,
    //   which is 2 in six bits and passes a six-bit check.
    mem[11'h6EB] = 8'h5D; mem[11'h6EC] = 8'hA9; mem[11'h6ED] = 8'h08;
    mem[11'h6EE] = 8'h03; mem[11'h6EF] = 8'h28; mem[11'h6F0] = 8'h69;
    // EXTBFZ 0[R8], #96, R9   5D A9 08 00 60 69   -- an ext byte whose LOW SIX
    //   BITS look legal.  96 is 0x60, and 0x60 & 0x3F is exactly 32, which
    //   passes every check; the length field is seven bits and only the full
    //   seven say it is out of range.
    mem[11'h6F1] = 8'h5D; mem[11'h6F2] = 8'hA9; mem[11'h6F3] = 8'h08;
    mem[11'h6F4] = 8'h00; mem[11'h6F5] = 8'h60; mem[11'h6F6] = 8'h69;

    // The decimal group.  Format VIIc, three operands, the third being the
    // extension byte -- carrying a PATTERN here where INSBF's carries a length.
    // ADDDC [R10], [R8], #0   59 00 6A 68 00
    mem[11'h6F7] = 8'h59; mem[11'h6F8] = 8'h00; mem[11'h6F9] = 8'h6A;
    mem[11'h6FA] = 8'h68; mem[11'h6FB] = 8'h00;
    // CVTD.PZ [R10], [R8], #0x30   59 10 6A 68 30   -- a byte source into a
    //   HALFWORD destination, with the pattern supplying the zone by OR.
    mem[11'h184] = 8'h59; mem[11'h185] = 8'h10; mem[11'h186] = 8'h6A;
    mem[11'h187] = 8'h68; mem[11'h188] = 8'h30;
    // CVTD.ZP [R10], [R8], #0x30   59 18 6A 68 30   -- the inverse, and the
    //   only one of the five that raises for something that is not a bad digit.
    mem[11'h189] = 8'h59; mem[11'h18A] = 8'h18; mem[11'h18B] = 8'h6A;
    mem[11'h18C] = 8'h68; mem[11'h18D] = 8'h30;

    // EXTBFZ [4[R10]], #8, R9   5D A9 8A 04 08 69   -- an INDIRECT bit-addressed
    //   operand.  Six of p.3.261's sixteen bit addressing modes are indirect and
    //   none was exercised until now, which is how the address unit came to do
    //   no bit arithmetic at all on that path.
    mem[11'h764] = 8'h5D; mem[11'h765] = 8'hA9; mem[11'h766] = 8'h8A;
    mem[11'h767] = 8'h04; mem[11'h768] = 8'h08; mem[11'h769] = 8'h69;

    // The floating point three.  Format II, opcode 5C short / 5E long, sub-op
    // in the second byte -- 08 MOVF, 09 NEGF, 0A ABSF.
    // NEGF.s [R10], R9    5C A9 6A 69
    mem[11'h76A] = 8'h5C; mem[11'h76B] = 8'hA9; mem[11'h76C] = 8'h6A;
    mem[11'h76D] = 8'h69;
    // POP 0[R31]   E6 1F 00   -- Format III, m = 0, mode byte 0x1F is
    //   AM_DISP8 on R31 with a displacement of 0.  The destination's ADDRESS
    //   depends on the stack pointer, which is the case that makes POP's
    //   "the stack pointer is THEN incremented" observable.
    mem[11'h772] = 8'hE6; mem[11'h773] = 8'h1F; mem[11'h774] = 8'h00;

    // MOVF.s [R10], R9    5C A8 6A 69   -- a NaN through this raises
    mem[11'h76E] = 8'h5C; mem[11'h76F] = 8'hA8; mem[11'h770] = 8'h6A;
    mem[11'h771] = 8'h69;

    // SBT entry 23, Decimal Arithmetic (Figure 8-2's +92) -> 0x1C0, which is
    // vector 21's handler -- the two share a frame and this reuses it.
    mem[11'h05C] = 8'hC0; mem[11'h05D] = 8'h01;

    // CHLVL R5, R6    4B E0 65 66   -- both operands in REGISTERS, which is the
    //   only way a byte operand arrives unmasked: a memory source is
    //   zero-extended by the address unit and a register source is not.
    mem[11'h17B] = 8'h4B; mem[11'h17C] = 8'hE0; mem[11'h17D] = 8'h65;
    mem[11'h17E] = 8'h66;

    // CAXI R9, [R8]   4C 09 68   -- Format I, d = 0 (the page requires it),
    //   so the register field is Rn and the mod field is the destination.
    mem[11'h721] = 8'h4C; mem[11'h722] = 8'h09; mem[11'h723] = 8'h68;

    // TASI [R8]   E0 68   -- Format III, m = 0, a byte through a pointer
    mem[11'h650] = 8'hE0; mem[11'h651] = 8'h68;

    // IN.b [0[R10]], R9   20 A0 8A 00 69   -- an INDIRECT port.  The pointer
    //   at [R10] is read from MEMORY and only the operand it names is an I/O
    //   access: an addressing mode's own accesses are not the instruction's.
    mem[11'h280] = 8'h20; mem[11'h281] = 8'hA0; mem[11'h282] = 8'h8A;
    mem[11'h283] = 8'h00; mem[11'h284] = 8'h69;
    // IN.b R10, R9      20 E0 6A 69   -- the port names a REGISTER: illegal
    mem[11'h3F8] = 8'h20; mem[11'h3F9] = 8'hE0; mem[11'h3FA] = 8'h6A;
    mem[11'h3FB] = 8'h69;

    // TRAPFL at 0x2B0 -- CB, Format V, one byte
    mem[11'h2B0] = 8'hCB;
    // MOV.B #0x6E, [R8]   -- reached only when the TRAPFL above falls through
    mem[11'h2B1] = 8'h09; mem[11'h2B2] = 8'h80; mem[11'h2B3] = 8'hF4;
    mem[11'h2B4] = 8'h6E; mem[11'h2B5] = 8'h68;

    // BRKV at 0x270, twice: once with OV clear and once with it set.
    // BRKV is C9, Format V, one byte.
    mem[11'h270] = 8'hC9;
    // MOV.B #0x31, [R8]   -- reached only when the BRKV above does nothing
    mem[11'h271] = 8'h09; mem[11'h272] = 8'h80; mem[11'h273] = 8'hF4;
    mem[11'h274] = 8'h31; mem[11'h275] = 8'h68;
    // BRKV again
    mem[11'h276] = 8'hC9;

    // UPDPSW.H #0x00000F00, #0x00000F00 at 0x290, twelve bytes.
    //   Bits 8-11 are FPR, FUD, FOV and FZD -- four of the five FLOATING POINT
    //   condition codes, which §3 says UPDPSW.H may modify along with the
    //   integer ones.  A mask restricted to 0x10FF instead of 0x1F0F writes
    //   nothing here, and no test using only the integer codes or PSW.TE can
    //   tell the two apart.
    mem[11'h290] = 8'h4A; mem[11'h291] = 8'h80; mem[11'h292] = 8'hF4;
    mem[11'h293] = 8'h00; mem[11'h294] = 8'h0F; mem[11'h295] = 8'h00;
    mem[11'h296] = 8'h00; mem[11'h297] = 8'hF4; mem[11'h298] = 8'h00;
    mem[11'h299] = 8'h0F; mem[11'h29A] = 8'h00; mem[11'h29B] = 8'h00;

    // UPDPSW.W again, at 0x260, for the privilege test
    mem[11'h260] = 8'h13; mem[11'h261] = 8'h80; mem[11'h262] = 8'hF4;
    mem[11'h263] = 8'h00; mem[11'h264] = 8'h00; mem[11'h265] = 8'h01;
    mem[11'h266] = 8'h00; mem[11'h267] = 8'hF4; mem[11'h268] = 8'h00;
    mem[11'h269] = 8'h00; mem[11'h26A] = 8'h01; mem[11'h26B] = 8'h00;

    // ---- a ninth program, at 0x4D0: Format III -----------------------------
    // INC, DEC and TEST: one mod field, no `reg` field, and the m bit riding
    // in bit 0 of the opcode.  Their pages define INC and DEC as "add #1, dst"
    // and "sub #1, dst", so the boundaries below are ADD's and SUB's.
    // MOV.W #0x7F, R9
    mem[11'h4D0] = 8'h2D; mem[11'h4D1] = 8'hA0; mem[11'h4D2] = 8'hF4;
    mem[11'h4D3] = 8'h7F; mem[11'h4D4] = 8'h00; mem[11'h4D5] = 8'h00;
    mem[11'h4D6] = 8'h00; mem[11'h4D7] = 8'h69;
    // INC.b R9    D9 69   -- m = 1 puts the mod field in the register column
    mem[11'h4D8] = 8'hD9; mem[11'h4D9] = 8'h69;
    // MOV.W #0xFF, R9
    mem[11'h4DA] = 8'h2D; mem[11'h4DB] = 8'hA0; mem[11'h4DC] = 8'hF4;
    mem[11'h4DD] = 8'hFF; mem[11'h4DE] = 8'h00; mem[11'h4DF] = 8'h00;
    mem[11'h4E0] = 8'h00; mem[11'h4E1] = 8'h69;
    // INC.b R9
    mem[11'h4E2] = 8'hD9; mem[11'h4E3] = 8'h69;
    // MOV.W #0, R9
    mem[11'h4E4] = 8'h2D; mem[11'h4E5] = 8'hA0; mem[11'h4E6] = 8'hF4;
    mem[11'h4E7] = 8'h00; mem[11'h4E8] = 8'h00; mem[11'h4E9] = 8'h00;
    mem[11'h4EA] = 8'h00; mem[11'h4EB] = 8'h69;
    // DEC.b R9    D1 69
    mem[11'h4EC] = 8'hD1; mem[11'h4ED] = 8'h69;
    // TEST.b R9   F1 69   -- reads and writes nothing
    mem[11'h4EE] = 8'hF1; mem[11'h4EF] = 8'h69;
    // MOV.W #0x700, R8
    mem[11'h4F0] = 8'h2D; mem[11'h4F1] = 8'hA0; mem[11'h4F2] = 8'hF4;
    mem[11'h4F3] = 8'h00; mem[11'h4F4] = 8'h07; mem[11'h4F5] = 8'h00;
    mem[11'h4F6] = 8'h00; mem[11'h4F7] = 8'h68;
    // INC.b [R8]  D8 68   -- m = 0, so the mod field is register indirect
    mem[11'h4F8] = 8'hD8; mem[11'h4F9] = 8'h68;

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

    // ---- 8. a shift, whose two operands are different widths ---------------------
    step;
    chk(rf.gpr[8] === 32'h0000_00B6, "SHL.b shifted the register left one bit");
    chk(seq_psw[PSW_CY] === 1'b0,
        "and 0x5B's bit 7 was clear, so no bit was shifted out set");
    chk(seq_psw[PSW_S] === 1'b1,   "the result's MSB is set at byte width");
    chk(seq_psw[PSW_OV] === 1'b0,  "and a logical shift clears OV");
    chk(seq_pc === 32'h0000012D,   "the count operand's immediate is one byte");
    step;
    chk(rf.gpr[9] === 32'h0000_6100, "SHL.w shifted a WORD by a BYTE count");
    chk(seq_pc === 32'h00000132,
        "and its immediate is one byte too, because the COUNT is the byte");

    // ---- 9. a multiply, which is not one cycle of combinational logic ----------
    step;
    chk(!stopped,                    "MUL.b executes");
    chk(rf.gpr[8] === 32'h0000_006C, "-74 x 2 stores the low byte of -148");
    chk(seq_psw[PSW_OV] === 1'b1,
        "and OV is set, because -148 does not fit within a signed byte");
    chk(seq_psw[PSW_S] === 1'b0,     "the stored byte's MSB is clear");
    chk(seq_psw[PSW_Z] === 1'b0,     "and it is not zero");
    chk(seq_pc === 32'h00000137,     "the PC advances by the instruction's length");

    // ---- 10. the X form, whose destination is a register PAIR ------------------
    step;
    chk(!stopped, "the X form executes");
    chk(rf.gpr[8] === 32'h0000_00D8,
        "MULX put the product's low word in Rn");
    chk(rf.gpr[9] === 32'h0000_0000,
        "and its high word in Rn+1 -- the pair, low register first");
    chk(seq_psw[PSW_OV] === 1'b0,
        "with OV cleared: a 32x32 product always fits 64 bits, so an X multiply cannot overflow");

    // ---- 10. a format whose semantics are not documented -------------------------
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

    // ---- the conversions, whose operands are at different widths ------------
    step;
    chk(rf.gpr[9] === 32'hFFFF_FF80,
        "MOVS.BW sign extended a byte immediate into a word register");
    chk(seq_pc === 32'h00000220,
        "and its immediate was one byte, because the SOURCE is the byte");
    step;
    chk(rf.gpr[10] === 32'h0000_0080,
        "MOVZ.BW put the same bits in without extending them");
    step;
    chk(mem[11'h600] === 8'h80,   "MOVT.WB stored the low byte of the word");
    chk(seq_psw[PSW_OV] === 1'b0,
        "and the bits it dropped all matched the result's sign");
    step;
    chk(mem[11'h600] === 8'h80,
        "the other truncation stores the same byte");
    chk(seq_psw[PSW_OV] === 1'b1,
        "and overflows, because the bits it dropped do NOT match that sign");

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
    chk(mem_word(13'h5FC) === 32'h10000004,
        "the frame word is the exception code beside the parameter count");
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
    chk(mem_word(13'h5FC) === 32'h13000004, "with its own exception code");
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
    chk(mem_word(13'h5FC) === 32'h12000004, "and carries a different code");
    step;
    chk(mem[11'h700] === 8'hE2, "and a different handler runs");

    // =======================================================================
    // The externally raised conditions.  Each is recognised where an
    // instruction exception is -- between instructions -- and each puts its
    // frame on the INTERRUPT stack, which is why PR_ISP is loaded above and
    // why the frames below are found at 0x680 downward and not at R31's 0x600.
    // =======================================================================

    // The record byte is the same one the control-flow program used.
    mem[11'h700] = 8'h00;

    // ---- NMI: an event, taken at the completion of the current instruction --
    reset_and_arm;
    jump(32'h00000500);
    step; step;                                  // the stack and the pointer
    chk(seq_pc === 32'h00000510, "the setup ran and the PC is at the first store");
    chk(mem[11'h700] === 8'h00,  "and nothing has been stored yet");

    // A pulse, gone long before the instruction boundary: v60_biu latches it.
    @(negedge clk); nmi_n = 1'b0;
    repeat (3) @(negedge clk); nmi_n = 1'b1;
    psw_before = seq_psw;
    step;
    chk(!stopped,               "an NMI is taken rather than stopping");
    chk(seq_pc === 32'h000007D0,
        "and the handler is SBT entry 2's, which is Figure 8-2's +8");
    chk(mem[11'h700] === 8'h00,
        "the instruction it interrupted did not run");
    chk(rf.gpr[31] === 32'h00000678,
        "the frame went on the INTERRUPT stack, not on R31's own");
    chk(mem_word(13'h67C) === psw_before, "which holds the PSW");
    chk(mem_word(13'h678) === 32'h00000510,
        "and the NEXT PC: the instruction that has not run yet");
    chk(seq_psw[PSW_IS] === 1'b1,  "the handler runs on the interrupt stack");
    chk(seq_psw[PSW_IE] === 1'b0,  "with maskable interrupts disabled");
    step;
    chk(mem[11'h700] === 8'hA1,    "and the handler runs");

    // RETIS: "PC <- [SP+] ; PSW <- [SP+] ; SP <- SP + count", and the count is
    // an OPERAND, not something read out of the frame.
    step;
    chk(seq_pc === 32'h00000510,
        "RETIS returned to the instruction the NMI interrupted");
    chk(seq_psw === psw_before,
        "with the PSW it was pushed with, flags and all: 'CY OV S Z Restored'");
    chk(seq_psw[PSW_IS] === 1'b0,
        "so PSW.IS is back off, and the level stack is current again");
    chk(rf.gpr[31] === 32'h00000600,
        "and R31 is the LEVEL stack pointer again, back where it started");
    chk(rf.pr[0] === 32'h00000680,
        "with the interrupt stack pointer restored to its own entry");
    step;
    chk(mem[11'h700] === 8'h01,
        "and the interrupted instruction runs, at last");

    // ---- INT: a level, and PSW.IE decides ----------------------------------
    reset_and_arm;
    jump(32'h00000500);
    step; step;
    @(negedge clk);
    int_req = 1'b1;                    // and it stays asserted, as the pin must
    repeat (4) @(negedge clk);
    chk(seq_psw[PSW_IE] === 1'b0, "PSW.IE is clear out of reset");
    step;
    chk(seq_pc === 32'h00000515,
        "with PSW.IE clear the request is held pending and the program runs");
    chk(mem[11'h700] === 8'h01,  "the first store happened");
    step;
    chk(mem[11'h700] === 8'h02,  "and so did the second");

    // Set PSW.IE the way the instruction this tree does not have would.  There
    // is no LDPSW or UPDPSW in v60_seq -- op_alu reports ALU_NONE for them --
    // so the bit is placed directly, which is the same liberty the bench takes
    // with the PC and the privileged registers.
    @(negedge clk);
    seq.psw[PSW_IE] = 1'b1;
    repeat (2) @(negedge clk);
    psw_before = seq_psw;
    step;
    chk(seq_pc === 32'h000007F0,
        "unmasked, the interrupt is taken at the next instruction boundary");
    chk(exc_int_vector === 8'd96,
        "and its vector came off the second interrupt acknowledge cycle");
    chk(!exc_invalid_int, "96 is one of the 192 vectors an application owns");
    chk(mem[11'h700] === 8'h02,  "the instruction it interrupted did not run");
    chk(mem_word(13'h67C) === psw_before, "the frame is the PSW");
    chk(mem_word(13'h678) === 32'h0000051A, "and the Next PC");
    chk(rf.gpr[31] === 32'h00000678, "two words, on the interrupt stack");
    chk(seq_psw[PSW_IE] === 1'b0,
        "and taking it disables further maskable interrupts");
    step;
    chk(mem[11'h700] === 8'hA3,  "and the handler runs");
    @(negedge clk); int_req = 1'b0;
    repeat (4) @(negedge clk);
    step;
    chk(seq_pc === 32'h0000051A,
        "and RETIS returns from a maskable interrupt the same way");
    chk(rf.gpr[31] === 32'h00000600, "with the stack pointer back");
    chk(seq_psw[PSW_IE] === 1'b1,
        "and PSW.IE restored, because the whole PSW comes back");

    // ---- BERR*: the bus fault, which aborts the instruction ----------------
    reset_and_arm;
    jump(32'h00000500);
    step; step;
    berr_target = 24'h000700;          // the store's own destination
    berr_budget = n_berr_seen + 1;     // exactly one failed cycle
    psw_before  = seq_psw;
    step;
    chk(!stopped,  "a bus error raises rather than stopping");
    chk(seq_pc === 32'h000007E0,
        "the handler is SBT entry 3's, the Serious System Fault at +12");
    chk(seq_pc !== 32'h00000515,
        "so the faulting instruction did not retire");
    chk(mem_word(13'h67C) === 32'h00000700,
        "the frame's deepest word is the Exception Address: a physical address");
    chk(mem_word(13'h678) === 32'h03030008,
        "then the code -- a fixed length data WRITE bus error -- beside a count of 8");
    chk(mem_word(13'h674) === psw_before, "then the PSW");
    chk(mem_word(13'h670) === 32'h00000510,
        "and the PC of the instruction whose cycle failed");
    chk(rf.gpr[31] === 32'h00000670,
        "four words, on the interrupt stack this group also uses");
    chk(seq_psw[PSW_IE] === 1'b0,
        "and a bus error disables maskable interrupts, by Note 2");
    put_word(13'h6B0, 32'hFFFF_0008);   // a halfword count with a poisoned top
    step; step;
    chk(mem[11'h700] === 8'hA2,  "the bus fault handler runs");
    step;
    chk(seq_pc === 32'h00000510,
        "and RETIS returns to the instruction whose bus cycle failed");
    chk(rf.gpr[31] === 32'h00000600,
        "with the level stack current again");
    chk(rf.pr[0] === 32'h00000680,
        "the interrupt stack pointer is back where the frame started");
    chk(insn_cycles === 5'd5,
        "and the count cost ONE bus cycle, not two: it is a halfword operand");
    step;
    chk(mem[11'h700] === 8'h01,
        "and the instruction completes, because the fault was aimed once");

    // =======================================================================
    // CALL and RET, the other return pair.  CALL passes the argument pointer;
    // RET restores it and discards what the caller pushed.
    // =======================================================================
    reset_and_arm;
    mem[11'h700] = 8'h00;
    // Something at the argument list's address, so that "CALL took the
    // ADDRESS" is distinguishable from "CALL read what was there".
    put_word(13'h6A0, 32'hDEAD_BEEF);
    jump(32'h00000540);
    step; step; step; step; step;          // R31, R8, R29, R10, R9
    chk(seq_pc === 32'h00000568,   "the setup ran");
    chk(rf.gpr[29] === 32'h00005A5A, "with an argument pointer to save");

    step;
    chk(seq_pc === 32'h00000590,
        "CALL transferred to the effective ADDRESS of its target operand");
    chk(rf.gpr[29] === 32'h000006A0,
        "and AP is the argument list's ADDRESS, not the word at it");
    chk(mem_word(13'h5FC) === 32'h00005A5A,
        "the caller's AP went down first: '[-SP] <- AP'");
    chk(mem_word(13'h5F8) === 32'h0000056C,
        "then the Next PC, so the return address is on top");
    chk(rf.gpr[31] === 32'h000005F8, "two words of frame");
    chk(insn_cycles === 5'd4,
        "which is two bus cycles each on a sixteen bit bus, and no operand read");
    step;
    chk(mem[11'h700] === 8'h0B,   "the procedure ran");

    step;
    chk(seq_pc === 32'h0000056C,  "RET returned to the instruction after CALL");
    chk(rf.gpr[29] === 32'h00005A5A,
        "and restored the caller's argument pointer: 'AP <- [SP+]'");
    chk(rf.gpr[31] === 32'h00000600,
        "with the stack pointer back where it started: the frame is gone");
    step;
    chk(mem[11'h700] === 8'h0C,   "and the caller continues");

    // A RET that discards, which is what the `num` operand is for.
    step;                                  // point R10 at the second procedure
    step;
    chk(seq_pc === 32'h000005B0,  "the second call");
    chk(rf.gpr[31] === 32'h000005F8, "pushes the same two words");
    step;
    chk(mem[11'h700] === 8'h0D,   "the second procedure ran");
    step;
    chk(seq_pc === 32'h0000057D,  "and RET #4 returned");
    chk(rf.gpr[31] === 32'h00000604,
        "leaving the stack pointer four bytes ABOVE the caller's: 'SP <- SP + tmp1'");
    step;
    chk(mem[11'h700] === 8'h0E,   "and the caller continues from there too");

    // =======================================================================
    // RETIS is privileged and RETIU is not, which is the whole documented
    // difference between them: RETIS's Exceptions list begins "Privileged
    // Instruction" and RETIU's does not.
    // =======================================================================
    reset_and_arm;
    mem[11'h700] = 8'h00;
    pr_id = 5'd1; pr_wdata = 32'h0000_0660; pr_wr = 1'b1;  // PR_L0SP
    @(negedge clk); pr_wr = 1'b0; @(negedge clk);
    jump(32'h00000540);
    step; step;                            // R31 = 0x600, R8 = 0x700
    // Execution level 3, the way the CHLVL this tree does not have would set
    // it.  R31 is now read as the level 3 stack pointer, which is what it
    // holds.
    @(negedge clk);
    seq.psw[PSW_EL_HI:PSW_EL_LO] = 2'b11;
    repeat (2) @(negedge clk);
    jump(32'h000005C0);
    step;
    chk(seq_pc === 32'h00000780,
        "RETIS at execution level 3 is the Privileged Instruction exception");
    chk(mem_word(13'h65C) === 32'h11000004,
        "with vector 17's code, and its frame on the level 0 stack");
    step;
    chk(mem[11'h700] === 8'hB1, "and that handler runs");

    // RETIU at the same level runs, because it is the user half of the pair.
    reset_and_arm;
    mem[11'h700] = 8'h00;
    pr_id = 5'd1; pr_wdata = 32'h0000_0660; pr_wr = 1'b1;
    @(negedge clk); pr_wr = 1'b0; @(negedge clk);
    jump(32'h00000540);
    step; step;
    // A frame to pop: the PC on top, the PSW under it -- the order v60_exc
    // leaves them in -- and a PSW that stays at level 3.
    put_word(13'h600, 32'h0000_056C);
    put_word(13'h604, 32'h0300_0000);
    @(negedge clk);
    seq.psw[PSW_EL_HI:PSW_EL_LO] = 2'b11;
    repeat (2) @(negedge clk);
    jump(32'h000005C8);
    step;
    chk(seq_pc === 32'h0000056C,
        "RETIU at execution level 3 is not privileged, and returns");
    chk(rf.gpr[31] === 32'h00000608,
        "having popped two words and discarded a count of zero");
    chk(seq_psw[PSW_EL_HI:PSW_EL_LO] === 2'b11,
        "with the execution level the popped PSW carried");

    // And the same instruction returning to a MORE privileged level is the
    // Illegal Data Field exception: "levels are numbered from 0 to 3 with
    // level 0 being the most privileged".
    reset_and_arm;
    mem[11'h700] = 8'h00;
    pr_id = 5'd1; pr_wdata = 32'h0000_0660; pr_wr = 1'b1;
    @(negedge clk); pr_wr = 1'b0; @(negedge clk);
    jump(32'h00000540);
    step; step;
    put_word(13'h600, 32'h0000_056C);
    put_word(13'h604, 32'h0000_0000);      // execution level 0
    @(negedge clk);
    seq.psw[PSW_EL_HI:PSW_EL_LO] = 2'b11;
    repeat (2) @(negedge clk);
    jump(32'h000005C8);
    step;
    chk(seq_pc === 32'h00000790,
        "returning to a more privileged level raises Illegal Data Field");
    chk(mem_word(13'h65C) === 32'h14000004, "which is vector 20, code 1400");
    step;
    chk(mem[11'h700] === 8'hB2, "and that handler runs");

    // A read that fails carries a different code from a write that does: the
    // 0300-031E group is one code per KIND of cycle.
    reset_and_arm;
    jump(32'h00000500);
    step; step; step;                  // let the first store put 1 at 0x700
    berr_target = 24'h000700;
    berr_budget = n_berr_seen + 1;
    // ADD.b #1, [R8] at 0x325 reads its destination first, so aim at that
    // program instead: jump there with R8 already pointing at 0x700.
    jump(32'h00000325);
    step;
    chk(seq_pc === 32'h000007E0,   "a failed READ raises the same vector");
    chk(mem_word(13'h678) === 32'h03130008,
        "with the fixed length data READ code instead");

    // =======================================================================
    // The multiplies and divides, off the bus, and the exception one of them
    // raises.  The arithmetic is tb_v60_muldiv's; what is here is that the
    // sequencer waits for a unit that is not combinational, and that a divide
    // by zero reaches its handler.
    // =======================================================================
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step; step;                      // R31, R8, R9 = 100
    chk(rf.gpr[9] === 32'd100,  "the setup ran");
    step;
    chk(rf.gpr[9] === 32'd700,  "MUL.w multiplied, and the sequencer waited for it");
    chk(seq_psw[PSW_OV] === 1'b0, "700 fits a word");
    chk(seq_pc === 32'h00000460, "and the PC advanced by the instruction's length");
    step;
    chk(rf.gpr[9] === 32'd233,  "DIV.w divided, truncating toward zero");
    chk(seq_psw[PSW_OV] === 1'b0, "and did not overflow");
    step;
    chk(rf.gpr[9] === 32'd2,    "REM.w left 233 % 3");
    chk(seq_psw[PSW_OV] === 1'b0, "with OV cleared, which its page prints outright");

    psw_before = seq_psw;
    step;
    chk(!stopped, "a divide by zero raises rather than stopping");
    chk(seq_pc === 32'h000001C0,
        "and the handler is SBT entry 21's, which BRKV's page names independently");
    chk(rf.gpr[9] === 32'd2,
        "the destination operand remains unchanged");
    // Figure 8-5's Arithmetic Exceptions frame: "+12 PC (Current PC) /
    // +8 Exception Code | 8 / +4 PSW / PC (Next PC)".
    chk(mem_word(13'h5FC) === 32'h00000470,
        "the Current PC is a PARAMETER above the code word, not the return PC");
    chk(mem_word(13'h5F8) === 32'h15000008,
        "the code is 1500, integer zero divide, beside a parameter count of 8");
    chk(mem_word(13'h5F4) === psw_before, "then the PSW");
    chk(mem_word(13'h5F0) === 32'h00000478,
        "and the NEXT PC on top, so the handler returns past the divide");
    chk(rf.gpr[31] === 32'h000005F0, "four words of frame");
    chk(seq_psw[PSW_IS] === 1'b0,
        "an arithmetic exception is not an interrupt: it stays on the level stack");
    step;
    chk(mem[11'h700] === 8'hC1, "the handler runs");
    step;
    chk(seq_pc === 32'h00000478, "and RETIS #8 returns past the divide");
    chk(rf.gpr[31] === 32'h00000600,
        "with the count discarding the code word and the parameter above it");
    step;
    chk(mem[11'h700] === 8'h21, "and the program continues");

    // =======================================================================
    // RVBIT, RVBYT and SETF, off the bus.
    // =======================================================================
    reset_and_arm;
    mem[11'h700] = 8'hFF;
    jump(32'h000004A0);
    step;                                    // R8 = 0x700
    step;                                    // CMP.b #0, R8 -> Z set
    chk(seq_psw[PSW_Z] === 1'b1, "the compare left Z set");
    psw_before = seq_psw;

    step;
    chk(rf.gpr[9] === 32'h0000_0080,
        "RVBIT reversed the byte 01 into 80");
    chk(seq_psw === psw_before,
        "and touched none of the four flags");

    step;
    chk(rf.gpr[10] === 32'h4433_2211, "RVBYT swapped all four bytes");
    chk(seq_psw === psw_before,        "and touched none of them either");

    step;
    chk(mem[11'h700] === 8'h01,
        "SETF stored 01H, because Z was set and the condition is Zero/Equal");
    chk(insn_cycles === 5'd1,
        "in ONE bus cycle: a write-only destination is not read first");
    chk(seq_psw === psw_before, "SETF sets a byte, not a flag");

    step;
    chk(mem[11'h700] === 8'h00,
        "and the opposite condition stored 00H");

    step;
    chk(mem[11'h700] === 8'h80,
        "RVBIT into memory reversed 01 to 80 there too");
    chk(insn_cycles === 5'd1,
        "also in one cycle, which is what a dst.b.w syntax line means");

    // =======================================================================
    // Format III: one operand, which is both what is read and what is written.
    // =======================================================================
    reset_and_arm;
    mem[11'h700] = 8'h41;
    jump(32'h000004D0);
    step;
    step;
    chk(!stopped,                     "a Format III instruction executes");
    chk(rf.gpr[9] === 32'h0000_0080,  "INC.b 0x7F gives 0x80");
    chk(seq_psw[PSW_OV] === 1'b1,     "which overflows a signed byte");
    chk(seq_psw[PSW_S]  === 1'b1,     "and is negative at byte width");
    chk(seq_psw[PSW_CY] === 1'b0,     "with no carry out of the byte");
    chk(seq_psw[PSW_Z]  === 1'b0,     "and is not zero");
    chk(seq_pc === 32'h000004DA,      "and it is TWO bytes long");

    step; step;
    chk(rf.gpr[9] === 32'h0000_0000,  "INC.b 0xFF wraps to 0x00");
    chk(seq_psw[PSW_CY] === 1'b1,     "carrying out of the byte");
    chk(seq_psw[PSW_Z]  === 1'b1,     "with a zero result");
    chk(seq_psw[PSW_OV] === 1'b0,     "and no signed overflow");

    step; step;
    chk(rf.gpr[9] === 32'h0000_00FF,  "DEC.b 0x00 gives 0xFF");
    chk(seq_psw[PSW_CY] === 1'b1,     "borrowing, which is what CY means here");
    chk(seq_psw[PSW_S]  === 1'b1,     "and the result is negative");
    chk(seq_psw[PSW_OV] === 1'b0,     "without overflowing");

    // TEST's one operand is what v60_alu reads as `x`, where INC's and DEC's
    // is `y` -- the sequencer gives Format III's operand to both.
    step;
    chk(rf.gpr[9] === 32'h0000_00FF,  "TEST writes nothing");
    chk(seq_psw[PSW_S]  === 1'b1,     "but sets S from the operand");
    chk(seq_psw[PSW_Z]  === 1'b0,     "and Z");
    chk(seq_psw[PSW_CY] === 1'b0,     "and clears CY");
    chk(seq_psw[PSW_OV] === 1'b0,     "and OV");

    step; step;
    chk(mem[11'h700] === 8'h42,
        "INC.b through a register-indirect mod field incremented memory");
    chk(insn_cycles === 5'd2,
        "in two bus cycles: a dst.rw operand is read and written");

    // TEST with a MEMORY operand.  Its one operand is what v60_alu reads as
    // `x`, and on this path it arrives through ea_rdata rather than through
    // the register file -- so this is what proves Format III mirrors its
    // operand into val1 at all.
    reset_and_arm;
    mem[11'h700] = 8'h80;
    jump(32'h00000480);
    step;
    step;
    chk(mem[11'h700] === 8'h80,   "TEST left memory alone");
    chk(seq_psw[PSW_S] === 1'b1,
        "and set S from the byte it read: 0x80 is negative at byte width");
    chk(seq_psw[PSW_Z] === 1'b0,  "and cleared Z");
    chk(insn_cycles === 5'd1,
        "in ONE bus cycle: it reads its operand and writes nothing");

    // CMP's second operand is read-only too -- "cmp.b src1.b.r, src2.b.r".
    // A read-modify-write here would cost a second cycle AND put a write on
    // the bus against a location the page marks read only.
    n_writes = 0;
    step;
    chk(seq_psw[PSW_Z] === 1'b1,
        "CMP.b of 0x80 against the byte at [R8] compares equal");
    chk(insn_cycles === 5'd1,
        "and costs ONE bus cycle: src2 is read, not read-modify-written");
    chk(n_writes == 0,
        "and puts no write on the bus at all against a read-only operand");

    // =======================================================================
    // NOP, MOVEA, and the instruction after a control transfer.
    // =======================================================================
    reset_and_arm;
    jump(32'h000001D0);
    step; step;
    chk(mem[11'h700] === 8'h5A, "the byte is in place");
    psw_before = seq_psw;

    step;
    chk(!stopped,                "NOP executes");
    chk(seq_pc === 32'h000001DE, "and is ONE byte long");
    chk(insn_cycles === 5'd0,    "and makes no bus cycle");
    chk(seq_psw === psw_before,  "and moves no flag");

    step;
    chk(rf.gpr[9] === 32'h0000_0700,
        "MOVEA took the source's ADDRESS, not the byte at it");
    chk(insn_cycles === 5'd0,
        "and issued no bus cycle for it: the access type is .n");
    chk(seq_psw === psw_before,  "and moved no flag either");

    step; step;
    chk(seq_pc === 32'h000001F0, "the JMP transferred");

    // The instruction after a control transfer, with a MEMORY source.  Before
    // ea_addr_only was cleared in S_OP1 this read nothing and val1 was stale.
    step;
    chk(rf.gpr[11] === 32'h0000_005A,
        "a memory source is READ in the instruction after a JMP");
    chk(insn_cycles === 5'd1,
        "which costs the one bus cycle a byte read costs");

    step;
    chk(rf.gpr[9] === 32'h0000_0700, "MOVEA.b through [R8+] took the address");
    chk(rf.gpr[8] === 32'h0000_0701,
        "and stepped the pointer by ONE, which is what its .b size field is for");
    chk(insn_cycles === 5'd0, "still without a bus cycle");

    // A MEMORY destination.  MOVEA's is "dst.w.w", so it is written and never
    // read -- an aligned word write is two bus cycles, and a read-modify-write
    // would be four.
    n_writes = 0;
    step;
    chk(mem_word(13'h700) === 32'h0000_0700,
        "MOVEA stored the source's address into memory");
    chk(insn_cycles === 5'd2,
        "in TWO bus cycles: the destination is written, not read first");

    // =======================================================================
    // GETPSW and the UPDPSW pair.
    // =======================================================================
    reset_and_arm;
    pr_id = 5'd1; pr_wdata = 32'h0000_0660; pr_wr = 1'b1;  // PR_L0SP
    @(negedge clk); pr_wr = 1'b0; @(negedge clk);
    jump(32'h00000230);

    step;
    chk(seq_psw[3:0] === 4'b1111,
        "UPDPSW.H set all four integer condition codes through its mask");
    chk(seq_pc === 32'h0000023C,
        "and BOTH its operands were words: the .h names the PSW half, not the size");

    step;
    chk(rf.gpr[9] === seq_psw,
        "GETPSW copied the whole PSW to its write-only operand");

    step;
    chk(seq_psw[PSW_TE] === 1'b0,
        "UPDPSW.H may not touch PSW.TE: it is restricted to the condition codes");
    chk(seq_psw[3:0] === 4'b0101,
        "and merged the codes it may touch: newPSW under mask, not the reverse");

    step;
    chk(seq_psw[PSW_TE] === 1'b1,
        "UPDPSW.W, which is privileged, can set it");

    // The FLOATING POINT condition codes, which §3 permits UPDPSW.H to modify
    // alongside the integer ones.  Nothing else in this bench touches bits
    // 8-11, and a mask that excluded them would write nothing here.
    jump(32'h00000290);
    step;
    chk(seq_psw[11:8] === 4'b1111,
        "UPDPSW.H may modify the FLOATING POINT condition codes too");

    // And at a non-zero execution level it raises instead.
    @(negedge clk);
    seq.psw[PSW_EL_HI:PSW_EL_LO] = 2'b11;
    repeat (2) @(negedge clk);
    jump(32'h00000260);
    step;
    chk(seq_pc === 32'h00000780,
        "UPDPSW.W at execution level 3 is the Privileged Instruction exception");
    chk(mem_word(13'h65C) === 32'h11000004, "with vector 17's code");

    // =======================================================================
    // BRKV: conditional on PSW.OV, and the Arithmetic Exceptions frame.
    // =======================================================================
    reset_and_arm;
    mem[11'h700] = 8'h00;
    // The handler for vector 21 is the one program seven installed at 0x1C0,
    // and reset_and_arm has left SBR at 0 -- so entry 21 at +84 still points
    // there.  R31 is the level 0 stack; R8 is where the handler writes.
    jump(32'h00000440);
    step; step;                            // R31 = 0x600, R8 = 0x700

    // OV is clear, so BRKV is a one-byte no-op.
    @(negedge clk);
    seq.psw[PSW_OV] = 1'b0;
    repeat (2) @(negedge clk);
    jump(32'h00000270);
    step;
    chk(seq_pc === 32'h00000271,
        "with OV clear, BRKV does nothing and advances by its one byte");
    chk(rf.gpr[31] === 32'h00000600, "pushing nothing");
    step;
    chk(mem[11'h700] === 8'h31, "and the instruction after it runs");

    // Now with OV set.
    @(negedge clk);
    seq.psw[PSW_OV] = 1'b1;
    repeat (2) @(negedge clk);
    psw_before = seq_psw;
    step;
    chk(seq_pc === 32'h000001C0,
        "with OV set, BRKV raises vector 21 -- the same handler a zero divide reaches");
    chk(mem_word(13'h5FC) === 32'h00000276,
        "its frame carries the CURRENT PC as a parameter");
    chk(mem_word(13'h5F8) === 32'h15010008,
        "with the integer overflow code beside a parameter count of 8");
    chk(mem_word(13'h5F4) === psw_before, "then the PSW");
    chk(mem_word(13'h5F0) === 32'h00000277,
        "and the NEXT PC on top, so a handler returns past the BRKV");
    chk(rf.gpr[31] === 32'h000005F0, "four words of frame");

    // =======================================================================
    // BRK: vector 13, unconditionally, and the CURRENT PC.
    // =======================================================================
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    psw_before = seq_psw;
    jump(32'h0000027C);
    step;
    chk(seq_pc === 32'h000001A0,
        "BRK vectors through SBT entry 13");
    chk(mem_word(13'h5FC) === 32'h0D000004,
        "with the instruction breakpoint code beside a parameter count of 4");
    chk(mem_word(13'h5F8) === psw_before, "then the PSW");
    chk(mem_word(13'h5F4) === 32'h0000027C,
        "and the CURRENT PC: the address of the BRK itself, not the next byte");
    chk(rf.gpr[31] === 32'h000005F4, "three words of frame, no parameter");
    step;
    chk(mem[11'h700] === 8'hB9, "and the breakpoint handler runs");

    // =======================================================================
    // TRAP: Format III, the condition in the UPPER nibble, and vector 48 + n.
    //
    // Both operands below are chosen so that reading the two nibbles the other
    // way round changes whether the trap is taken at all -- which is the one
    // mistake this instruction invites, because SETF's condition is in the LOW
    // nibble and the two share a condition evaluator.
    // =======================================================================
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700

    // Condition FALSE, so nothing happens at all.
    //   Operand 0xB2: the upper nibble B is "False / Never" and the lower
    //   nibble 2 is vector offset 2.  Read the other way round the condition
    //   would be 2, "Carry", which the CY = 1 below satisfies -- so a swap
    //   takes a trap here where this falls through.
    @(negedge clk);
    rf.gpr[9]       = 32'hFFFF_FFB2;
    seq.psw[PSW_CY] = 1'b1;
    seq.psw[PSW_Z]  = 1'b1;
    repeat (2) @(negedge clk);
    jump(32'h000002A0);
    step;
    chk(seq_pc === 32'h000002A2,
        "with its condition false TRAP advances past its two bytes and does nothing");
    chk(rf.gpr[31] === 32'h00000600, "pushing nothing");
    step;
    chk(mem[11'h700] === 8'h5C, "and the instruction after it runs");

    // Condition TRUE, and everything about the frame.
    //   Operand 0x45: the upper nibble 4 is "Zero", satisfied by Z = 1, and
    //   the lower nibble 5 is vector offset 5 -- SBT entry 53.  Swapped, the
    //   condition would be 5, "Not zero", which Z = 1 makes FALSE.  The high
    //   bytes are junk: the operand is `.b`, so only the low byte is read.
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[9]       = 32'h1234_5645;
    seq.psw[PSW_CY] = 1'b1;
    seq.psw[PSW_Z]  = 1'b1;
    repeat (2) @(negedge clk);
    psw_before = seq_psw;
    jump(32'h000002A0);
    step;
    chk(seq_pc === 32'h000001B0,
        "TRAP with vector offset 5 vectors through SBT entry 53 -- 48 + n, not n");
    chk(mem_word(13'h5FC) === 32'h35000004,
        "its code puts the trap number in bits 11:8, beside a parameter count of 4");
    chk(mem_word(13'h5F8) === psw_before, "then the PSW");
    chk(mem_word(13'h5F4) === 32'h000002A2,
        "and the NEXT PC, so a handler returns PAST the trap -- unlike BRK");
    chk(rf.gpr[31] === 32'h000005F4, "three words of frame, no parameter");
    chk(seq_psw[PSW_IE] === psw_before[PSW_IE],
        "and an exception leaves PSW.IE alone -- only an interrupt clears it");
    step;
    chk(mem[11'h700] === 8'hC7, "and the trap handler runs");

    // =======================================================================
    // TRAPFL: "if ( TKCW[8:4] AND PSW[12:8] ) != 0 then Floating Point
    // Operation Exception".  No floating point datapath is touched -- it never
    // reads an FP operand, never rounds and never writes a result -- so it is
    // implementable in full here, and it is NOT a no-op: software arms it by
    // hand, which is exactly what this does.
    //
    // The three cases are chosen so that the AND has to be an AND of the RIGHT
    // two five-bit fields.  In every one of them BOTH sides are non-zero, so
    // an implementation that tested either side alone, or that ORed them, or
    // that lined the fields up without the shift of four, gets a different
    // answer than the page does.
    // =======================================================================

    // Case one: the flag that is set is not the flag that is enabled.
    //   TKCW = 0x40 enables FOT (bit 6, overflow) and nothing else; the PSW
    //   has FZD set (bit 11, zero divide) and nothing else.  Both fields are
    //   non-zero and their AND is zero, so nothing happens.
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    pr_id = 5'd8; pr_wdata = 32'h0000_0040; pr_wr = 1'b1;   // PR_TKCW
    @(negedge clk);
    pr_wr = 1'b0;
    seq.psw[PSW_FZD] = 1'b1;
    repeat (2) @(negedge clk);
    jump(32'h000002B0);
    step;
    chk(seq_pc === 32'h000002B1,
        "an enabled trap for a flag that is clear leaves TRAPFL a one-byte no-op");
    chk(rf.gpr[31] === 32'h00000600, "pushing nothing");
    step;
    chk(mem[11'h700] === 8'h6E, "and the instruction after it runs");

    // Case two: one pair lines up, and only that one is reported.
    //   TKCW = 0xA0 enables FZT (bit 7, zero divide) and FUT (bit 5,
    //   underflow); the PSW has FZD (bit 11) and FOV (bit 10) set.  Only the
    //   zero divide is both set and enabled, so the code is 1608 alone --
    //   the overflow is set but not enabled and must not appear.
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    pr_id = 5'd8; pr_wdata = 32'h0000_00A0; pr_wr = 1'b1;
    @(negedge clk);
    pr_wr = 1'b0;
    seq.psw[PSW_FZD] = 1'b1;
    seq.psw[PSW_FOV] = 1'b1;
    repeat (2) @(negedge clk);
    psw_before = seq_psw;
    jump(32'h000002B0);
    step;
    chk(seq_pc === 32'h000002C0,
        "TRAPFL reaches vector 22 -- the floating point one, not vector 21");
    chk(mem_word(13'h5FC) === 32'h000002B0,
        "its frame carries the CURRENT PC as a parameter");
    chk(mem_word(13'h5F8) === 32'h16080008,
        "and reports only the condition that is BOTH set and enabled");
    chk(mem_word(13'h5F4) === psw_before, "then the PSW");
    chk(mem_word(13'h5F0) === 32'h000002B1,
        "and the NEXT PC on top, so a handler returns past the trapfl");
    chk(rf.gpr[31] === 32'h000005F0, "four words of frame, count 8");
    chk(seq_psw[PSW_FZD] === 1'b1 && seq_psw[PSW_FOV] === 1'b1,
        "and the floating point flags stay sticky -- all nine are Unchanged");
    step;
    chk(mem[11'h700] === 8'hD3, "and the floating point handler runs");

    // Case three: two conditions at once, which is why the codes are one-hot.
    //   TKCW = 0xE0 now enables FOT as well, so both the zero divide and the
    //   overflow are live.  p.3.272 braces 1601/1602/1604/1608/1610 with
    //   "these exception codes can combine in the case of simultaneous
    //   exceptions", and 1608 | 1604 is 160C.
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    pr_id = 5'd8; pr_wdata = 32'h0000_00E0; pr_wr = 1'b1;
    @(negedge clk);
    pr_wr = 1'b0;
    seq.psw[PSW_FZD] = 1'b1;
    seq.psw[PSW_FOV] = 1'b1;
    repeat (2) @(negedge clk);
    jump(32'h000002B0);
    step;
    chk(seq_pc === 32'h000002C0, "with two conditions live TRAPFL still reaches vector 22");
    chk(mem_word(13'h5F8) === 32'h160C0008,
        "and ORs both codes into one word, which is what the one-hot low byte is for");

    // =======================================================================
    // LDPR and STPR.  Both privileged, both Format II, and between them they
    // are the only instructions whose operand names a register rather than
    // being one.
    // =======================================================================

    // STPR reads the privileged register its FIRST operand names.
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    pr_id = 5'd8; pr_wdata = 32'hDEAD_BEEF; pr_wr = 1'b1;   // PR_TKCW
    @(negedge clk);
    pr_id = 5'd7; pr_wdata = 32'h0BAD_F00D;                 // PR_SYCW
    @(negedge clk);
    pr_wr = 1'b0;
    rf.gpr[9]  = 32'h0000_0000;
    rf.gpr[10] = 32'h0000_0000;
    repeat (2) @(negedge clk);
    jump(32'h000002D0);
    step;
    chk(rf.gpr[9] === 32'hDEAD_BEEF,
        "STPR copied privileged register 8 -- TKCW -- into its destination");
    chk(seq_pc === 32'h000002D8, "and advanced past its eight bytes");
    step;
    chk(rf.gpr[10] === 32'h0BAD_F00D,
        "and a second STPR reads the DIFFERENT register its own operand names");

    // LDPR writes the privileged register its SECOND operand names, which
    // means that operand is READ.  Its syntax line is "ldpr src.w.r,
    // regID.w.w", so the ".w" names the privileged register that is written
    // and not the operand -- an operand that were genuinely write-only could
    // not tell the instruction which register to load.  R9 holds 7, SYCW.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[9] = 32'h0000_0007;
    repeat (2) @(negedge clk);
    jump(32'h000002F0);
    step;
    chk(rf.pr[7] === 32'hCAFE_F00D,
        "LDPR loaded the privileged register its second operand NAMED");
    chk(rf.gpr[9] === 32'h0000_0007,
        "leaving that operand alone -- it was read for its value, not written");
    chk(seq_pc === 32'h000002F8, "and advanced past its eight bytes");

    // The same, with the id in MEMORY: LDPR reads that operand, so nothing may
    // go out on the bus as a write.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h700, 32'h0000_0007);        // the id, SYCW, at [R8]
    repeat (2) @(negedge clk);
    n_writes = 0;
    jump(32'h000003A0);
    step;
    chk(rf.pr[7] === 32'h5EED_1234,
        "LDPR through a memory operand loaded the register that operand named");
    chk(n_writes == 0,
        "and put no write on the bus: its second operand is read for an id, never written");
    chk(insn_cycles === 5'd2,
        "in TWO bus cycles -- one word read on a 16-bit bus, not a read AND a write back");
    chk(mem_word(13'h700) === 32'h0000_0007, "and the id in memory is unchanged");

    // An id above 31 is the one bad-id case the pages make a rule.  STPR's
    // page: "An Illegal Data Field exception will occur if the register ID
    // field is not in the range of [0] to 31."
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[9] = 32'h1234_5678;
    repeat (2) @(negedge clk);
    jump(32'h000002E0);
    step;
    chk(seq_pc === 32'h00000790,
        "STPR with an id of 40 raises the Illegal Data Field exception");
    chk(mem_word(13'h5FC) === 32'h14000004, "with vector 20's code");
    chk(mem_word(13'h5F4) === 32'h000002E0,
        "and the CURRENT PC, so the handler restarts the instruction");
    chk(rf.gpr[9] === 32'h1234_5678,
        "having written nothing -- an instruction that will be restarted must not have");

    // The same rule on LDPR, whose page states only the unpredictable half but
    // still lists Illegal Data Field in its Exceptions block.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[9] = 32'h0000_0020;               // 32, one past the top
    repeat (2) @(negedge clk);
    jump(32'h000002F0);
    step;
    chk(seq_pc === 32'h00000790,
        "LDPR with an id of 32 raises it too -- one past the top of the range");
    chk(rf.pr[0] === 32'h0000_0680,
        "and the id's low five bits did NOT reach a register: ISP is untouched");

    // And both are privileged.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    pr_id = 5'd1; pr_wdata = 32'h0000_0680; pr_wr = 1'b1;   // PR_L0SP
    @(negedge clk);
    pr_wr = 1'b0;
    seq.psw[PSW_EL_HI:PSW_EL_LO] = 2'b11;
    repeat (2) @(negedge clk);
    jump(32'h000002D0);
    step;
    chk(seq_pc === 32'h00000780,
        "STPR at execution level 3 is the Privileged Instruction exception");
    chk(mem_word(13'h67C) === 32'h11000004, "with vector 17's code");
    chk(mem_word(13'h674) === 32'h000002D0,
        "and the CURRENT PC -- the exception is for ATTEMPTING it");

    // =======================================================================
    // HALT.  "The processor halts and waits for an interrupt.  Following the
    // execution of the interrupt handler, program execution will continue with
    // the instruction following the HALT instruction."
    // =======================================================================
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    jump(32'h000003B0);
    step;
    chk(seq_pc === 32'h000003B1,
        "HALT retires and advances past itself -- the resume point is HALT + 1");
    chk(!stopped, "and it is a wait, not a stop");

    // Now let it run with nothing asserted.  Nothing may retire and the
    // instruction after the HALT may not run.
    run = 1'b1;
    repeat (80) @(negedge clk);
    chk(!retired, "and then waits: nothing retires while it is halted");
    chk(mem[11'h700] === 8'h00,
        "and the instruction after the HALT has not run");
    chk(seq_pc === 32'h000003B1, "the PC has not moved either");

    // An NMI ends the wait.
    @(negedge clk); nmi_n = 1'b0;
    repeat (3) @(negedge clk); nmi_n = 1'b1;
    while (!retired && !stopped) @(negedge clk);
    run = 1'b0;
    @(negedge clk);
    chk(seq_pc === 32'h000007D0, "an interrupt ends the wait and is taken");
    chk(mem_word(13'h678) === 32'h000003B1,
        "and the frame carries HALT + 1, so the handler returns PAST the halt");
    step;
    chk(mem[11'h700] === 8'hA1, "the handler runs");

    // And after it returns, the instruction after the HALT finally does -- the
    // processor does not re-halt.
    step;                                    // RETIS
    chk(seq_pc === 32'h000003B1, "RETIS returns to the instruction after the HALT");
    step;
    chk(mem[11'h700] === 8'h4D,
        "which now runs: the wait was ended, not resumed");

    // HALT is privileged.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    pr_id = 5'd1; pr_wdata = 32'h0000_0680; pr_wr = 1'b1;   // PR_L0SP
    @(negedge clk);
    pr_wr = 1'b0;
    seq.psw[PSW_EL_HI:PSW_EL_LO] = 2'b11;
    repeat (2) @(negedge clk);
    jump(32'h000003B0);
    step;
    chk(seq_pc === 32'h00000780,
        "HALT at execution level 3 is the Privileged Instruction exception");
    chk(seq.halted_r === 1'b0, "and it did not halt on the way");

    // =======================================================================
    // The four bit instructions, end to end: the base's two natures, the
    // offset's one exception, and the autoincrement that steps by four.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700

    // A REGISTER base: "If the register addressing mode is used for the base
    // operand, the designated bit is located within a general purpose register
    // at the specified bit offset."
    @(negedge clk);
    rf.gpr[9] = 32'h0000_0000;
    repeat (2) @(negedge clk);
    jump(32'h000003C0);
    step;
    chk(rf.gpr[9] === 32'h0000_0020, "SET1 #5 set bit 5 inside the register base");
    chk(seq_psw[PSW_CY] === 1'b0 && seq_psw[PSW_Z] === 1'b1,
        "reporting the bit as it was BEFORE: clear");
    jump(32'h000003C0);
    step;
    chk(rf.gpr[9] === 32'h0000_0020, "a second SET1 of the same bit changes nothing");
    chk(seq_psw[PSW_CY] === 1'b1 && seq_psw[PSW_Z] === 1'b0,
        "and now reports it set -- CY and Z are the bit, not the result");

    // A MEMORY base, read only.  "For any other addressing mode, the
    // designated bit is at the specified bit offset from the base address" --
    // and with the offset capped at 31 that is one word, which is why the two
    // bases are the same datapath.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h700, 32'h0000_0200);        // bit 9 set
    repeat (2) @(negedge clk);
    n_writes = 0;
    jump(32'h000003D0);
    step;
    chk(seq_psw[PSW_CY] === 1'b1 && seq_psw[PSW_Z] === 1'b0,
        "TEST1 #9 through a memory base found bit 9 set");
    chk(n_writes == 0,
        "and put no write on the bus: test1's base is .r, not .rw");
    chk(mem_word(13'h700) === 32'h0000_0200, "the word is untouched");

    // CLR1 on the same bit, which DOES write back.
    step;
    chk(mem_word(13'h700) === 32'h0000_0000, "CLR1 #9 cleared it in memory");
    chk(seq_psw[PSW_CY] === 1'b1 && seq_psw[PSW_Z] === 1'b0,
        "still reporting the bit as it was before");

    // The autoincrement, which steps by FOUR: "If the autoincrement or
    // autodecrement addressing mode is specified for the base operand, the
    // base operand is treated as word data and is incremented or decremented
    // by four."
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h700, 32'h0000_0000);
    repeat (2) @(negedge clk);
    jump(32'h000003E0);
    step;
    chk(mem_word(13'h700) === 32'h0000_0008, "NOT1 #3 complemented bit 3 in memory");
    chk(rf.gpr[8] === 32'h00000704,
        "and the autoincrement stepped the base by FOUR -- it is word data");

    // The offset's one exception: "An Illegal Data Field exception occurs if
    // the bit offset is outside the range 0 to 31."
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[9] = 32'h1234_5678;
    repeat (2) @(negedge clk);
    jump(32'h000003C8);
    step;
    chk(seq_pc === 32'h00000790,
        "an offset of 32 raises the Illegal Data Field exception");
    chk(mem_word(13'h5FC) === 32'h14000004, "with vector 20's code");
    chk(mem_word(13'h5F4) === 32'h000003C8,
        "and the CURRENT PC, so the handler restarts it");
    chk(rf.gpr[9] === 32'h1234_5678,
        "having touched nothing: the base was never even addressed");

    // =======================================================================
    // IN and OUT.  The only instructions that put an I/O bus cycle on the
    // pins, and the only reason v60_bus_pkg's three-TI recovery rule is
    // reachable at all.
    //
    // Their asymmetry is the thing to get right: "in.b port.b.r, dst.b.w" puts
    // the port on the SOURCE and "out.b src.b.r, port.b.w" on the DESTINATION,
    // so one wire cannot drive both.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    rf.gpr[10] = 32'h0000_0710;              // the port address
    rf.gpr[9]  = 32'h0000_0000;
    mem[11'h710] = 8'h5B;
    repeat (2) @(negedge clk);
    n_io = 0; n_io_wr = 0; n_mem_sgl = 0;
    jump(32'h000003F0);
    step;
    chk(rf.gpr[9] === 32'h0000_005B, "IN.b read the port into its destination");
    chk(n_io == 1, "in exactly one I/O bus cycle");
    chk(n_io_wr == 0, "which was a READ");
    chk(n_mem_sgl == 0,
        "and no single-mode MEMORY cycle: its destination is a register");

    // OUT, whose port is the other operand.
    @(negedge clk);
    rf.gpr[9] = 32'h0000_00C4;
    repeat (2) @(negedge clk);
    n_io = 0; n_io_wr = 0;
    jump(32'h000003F4);
    step;
    chk(mem[11'h710] === 8'hC4, "OUT.b wrote its source to the port");
    chk(n_io == 1 && n_io_wr == 1,
        "in one I/O cycle, and this time a WRITE -- the port is the DESTINATION");

    // The pointer chase, which is the distinction worth proving: an indirect
    // addressing mode reads its pointer from MEMORY even when the operand it
    // finally reaches is a port.  Only the last access is I/O.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[10] = 32'h0000_0710;
    rf.gpr[9]  = 32'h0000_0000;
    put_word(13'h710, 32'h0000_0720);        // the pointer, in memory
    mem[11'h720] = 8'h9E;                    // the port, behind it
    repeat (2) @(negedge clk);
    n_io = 0; n_io_wr = 0; n_mem_sgl = 0;
    jump(32'h00000280);
    step;
    chk(rf.gpr[9] === 32'h0000_009E,
        "IN through an indirect port read the byte the pointer named");
    chk(n_io == 1, "in exactly ONE I/O cycle -- the operand access");
    chk(n_mem_sgl == 2,
        "while the pointer itself was read from MEMORY, in two cycles on a 16-bit bus");

    // A register port is Illegal.  "Rn" is marked X in the Addressing Modes
    // column of both pages, because the I/O address is the port operand's
    // effective address and a register has none.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[10] = 32'h0000_0710;
    repeat (2) @(negedge clk);
    n_io = 0;
    jump(32'h000003F8);
    step;
    chk(seq_pc === 32'h000007C0,
        "IN with a register port is the Illegal Addressing Mode exception");
    chk(mem_word(13'h5FC) === 32'h13000004, "with vector 19's code");
    chk(n_io == 0, "and no I/O cycle was issued");

    // Both are privileged: "I/O space accesses are always generated by the
    // execution of the privileged IN and OUT instructions."
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    pr_id = 5'd1; pr_wdata = 32'h0000_0680; pr_wr = 1'b1;   // PR_L0SP
    @(negedge clk);
    pr_wr = 1'b0;
    rf.gpr[10] = 32'h0000_0710;
    seq.psw[PSW_EL_HI:PSW_EL_LO] = 2'b11;
    repeat (2) @(negedge clk);
    n_io = 0;
    jump(32'h000003F0);
    step;
    chk(seq_pc === 32'h00000780,
        "IN at execution level 3 is the Privileged Instruction exception");
    chk(n_io == 0, "raised before any I/O cycle went out");

    // =======================================================================
    // MOVEA's illegal source modes -- audit item M1.  Rn, Immediate and
    // Immediate.Quick are all marked X in its src column, and nothing raised
    // it: v60_ea's reg-direct and immediate branches both set ea <= 0 without
    // consulting addr_only, and `illegal` is driven from `we`, which a source
    // never is.  So both quietly wrote ZERO, which is a plausible-looking
    // answer and the reason this went unnoticed.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[9]  = 32'h1234_5678;
    rf.gpr[10] = 32'h0000_0710;
    repeat (2) @(negedge clk);
    jump(32'h00000490);
    step;
    chk(seq_pc === 32'h000007C0,
        "MOVEA from a REGISTER source is the Illegal Addressing Mode exception");
    chk(mem_word(13'h5FC) === 32'h13000004, "with vector 19's code");
    chk(rf.gpr[9] === 32'h1234_5678,
        "and the destination is untouched -- it used to be quietly written with 0");

    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[9] = 32'h1234_5678;
    repeat (2) @(negedge clk);
    jump(32'h00000494);
    step;
    chk(seq_pc === 32'h000007C0,
        "and from an IMMEDIATE source it is the same exception");
    chk(rf.gpr[9] === 32'h1234_5678, "with the destination again untouched");

    // =======================================================================
    // PUSH and POP.  "The PUSH instruction is a shorter encoding of the more
    // general instruction mov.w src, [ -sp ]", and POP of "mov.w [ sp+ ], dst"
    // -- so whatever [-Rn] and [Rn+] do on R31 with a word operand, these do.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    rf.gpr[9]  = 32'hDEAD_BEEF;
    rf.gpr[10] = 32'h0000_0000;
    put_word(13'h5FC, 32'h0000_0000);
    repeat (2) @(negedge clk);
    psw_before = seq_psw;
    jump(32'h00000620);
    step;
    chk(rf.gpr[31] === 32'h000005FC,
        "PUSH decremented the stack pointer by four");
    chk(mem_word(13'h5FC) === 32'hDEAD_BEEF, "and wrote its source there");
    chk(seq_psw === psw_before, "leaving every flag alone");

    // POP takes it straight back, which is the property the pair exists for.
    step;
    chk(rf.gpr[10] === 32'hDEAD_BEEF, "POP read the word back into its destination");
    chk(rf.gpr[31] === 32'h00000600,
        "and incremented the stack pointer, so the pair round-trips");

    // An autoincrement operand: TWO register writebacks in one instruction,
    // R8 from the addressing mode and R31 from the stack.  This sequencer
    // stops on two addressing-mode writebacks, so the stack access must not
    // look like one.
    @(negedge clk);
    put_word(13'h700, 32'h1234_5678);
    repeat (2) @(negedge clk);
    step;
    chk(!stopped, "PUSH through an autoincrement operand does not stop the sequencer");
    chk(mem_word(13'h5FC) === 32'h1234_5678,
        "it pushed the word its operand pointed at");
    chk(rf.gpr[8] === 32'h00000704,
        "the addressing mode stepped R8");
    chk(rf.gpr[31] === 32'h000005FC,
        "and the stack pointer moved too -- both writebacks landed");

    // =======================================================================
    // PREPARE and DISPOSE.  Between them they touch R30 and R31 and nothing
    // else -- NOT R29, which §3 gives to CALL and RET.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    rf.gpr[30] = 32'h0000_05A0;              // the caller's frame pointer
    rf.gpr[29] = 32'hA9A9_A9A9;              // the argument pointer, untouched
    put_word(13'h5EC, 32'hBAD0_BAD0);        // where SP will end up: NOT the
                                             //   place DISPOSE reads
    repeat (2) @(negedge clk);
    jump(32'h00000626);
    step;
    chk(mem_word(13'h5FC) === 32'h0000_05A0,
        "PREPARE saved the old frame pointer on the stack");
    chk(rf.gpr[30] === 32'h000005FC,
        "and FP took the UPDATED SP -- it points at the slot holding the old FP");
    chk(rf.gpr[31] === 32'h000005EC,
        "then SP dropped by `num` BYTES: 0x5FC - 16, not 0x5FC - 64");
    chk(rf.gpr[29] === 32'hA9A9_A9A9,
        "and R29, the argument pointer, is not this instruction's business");

    // DISPOSE undoes it, and does not need to know what `num` was.
    step;
    chk(rf.gpr[31] === 32'h00000600,
        "DISPOSE put SP back above the frame, whatever size the frame was");
    chk(rf.gpr[30] === 32'h0000_05A0,
        "and restored the old frame pointer -- read at FP, not at SP");

    // =======================================================================
    // XCH.  "dst1 <-> dst2", both operands ".rw" -- the syntax line names
    // neither a source, which is the page's way of saying the roles are
    // symmetric.  What is NOT symmetric is where dst1 may live.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    rf.gpr[9]  = 32'hAAAA_1111;
    rf.gpr[10] = 32'hBBBB_2222;
    repeat (2) @(negedge clk);
    psw_before = seq_psw;
    jump(32'h00000630);
    step;
    chk(rf.gpr[9] === 32'hBBBB_2222 && rf.gpr[10] === 32'hAAAA_1111,
        "XCH exchanged two registers -- BOTH writes landed");
    chk(seq_psw === psw_before, "with every flag Unchanged");

    // The legal memory case: dst2 may be anywhere, and the two halves are
    // written through different paths -- one a bus cycle, one the register
    // file.
    @(negedge clk);
    rf.gpr[9] = 32'hAAAA_1111;
    put_word(13'h700, 32'hCCCC_3333);
    repeat (2) @(negedge clk);
    jump(32'h00000634);
    step;
    chk(rf.gpr[9] === 32'hCCCC_3333,
        "XCH with a memory dst2 put the memory word into the register");
    chk(mem_word(13'h700) === 32'hAAAA_1111,
        "and the register's old contents into memory");

    // dst1 in memory: `A` in the table, and the page's own sentence.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[9] = 32'h1234_5678;
    put_word(13'h700, 32'hCCCC_3333);
    repeat (2) @(negedge clk);
    jump(32'h00000638);
    step;
    chk(seq_pc === 32'h000007B0,
        "XCH with dst1 in memory is the RESERVED Addressing Mode exception");
    chk(mem_word(13'h5FC) === 32'h12000004, "with vector 18's code");
    chk(rf.gpr[9] === 32'h1234_5678 && mem_word(13'h700) === 32'hCCCC_3333,
        "and nothing was exchanged");

    // dst1 immediate: `X` in the same column, and a DIFFERENT exception.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[9] = 32'h1234_5678;
    repeat (2) @(negedge clk);
    jump(32'h0000063C);
    step;
    chk(seq_pc === 32'h000007C0,
        "but with dst1 IMMEDIATE it is the ILLEGAL Addressing Mode exception");
    chk(mem_word(13'h5FC) === 32'h13000004,
        "vector 19 -- the same operand column, two different complaints");

    // =======================================================================
    // PUSHM and POPM.  Bit n is Rn for n = 0..30, bit 31 is the PSW, and R31
    // has no bit -- "The SP (R31) is not saved".  The two scan in OPPOSITE
    // directions, which is the property that makes them round-trip.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    rf.gpr[9]  = 32'h1111_1111;
    rf.gpr[10] = 32'h2222_2222;
    rf.gpr[11] = 32'h3333_3333;
    seq.psw[PSW_Z] = 1'b1;
    seq.psw[PSW_S] = 1'b1;
    repeat (2) @(negedge clk);
    psw_before = seq_psw;
    jump(32'h00000644);
    step;

    // "searched sequentially from the MSB (PSW) to the LSB (R0)", each push
    // pre-decrementing -- so the PSW lands HIGHEST and R9 lowest.  Scanned the
    // other way the four words would come out in the opposite order.
    chk(mem_word(13'h5FC) === psw_before,
        "PUSHM pushed the PSW first, so it is at the highest address");
    chk(mem_word(13'h5F8) === 32'h3333_3333, "then R11");
    chk(mem_word(13'h5F4) === 32'h2222_2222, "then R10");
    chk(mem_word(13'h5F0) === 32'h1111_1111, "then R9, at the lowest");
    chk(rf.gpr[31] === 32'h000005F0,
        "and SP points at the last register pushed");

    // Clobber everything, and set a HIGH-halfword PSW bit that the stacked
    // copy does not have.
    @(negedge clk);
    rf.gpr[9]  = 32'hDEAD_0009;
    rf.gpr[10] = 32'hDEAD_0010;
    rf.gpr[11] = 32'hDEAD_0011;
    seq.psw[PSW_Z]  = 1'b0;
    seq.psw[PSW_S]  = 1'b0;
    seq.psw[PSW_TE] = 1'b1;
    repeat (2) @(negedge clk);
    step;

    chk(rf.gpr[9]  === 32'h1111_1111 &&
        rf.gpr[10] === 32'h2222_2222 &&
        rf.gpr[11] === 32'h3333_3333,
        "POPM restored all three from the slots PUSHM wrote -- the pair round-trips");
    chk(rf.gpr[31] === 32'h00000600,
        "and SP came back to where the PUSHM began");
    chk(seq_psw[PSW_Z] === 1'b1 && seq_psw[PSW_S] === 1'b1,
        "the PSW's condition codes were restored from the stack");
    chk(seq_psw[PSW_TE] === 1'b1,
        "but PSW.TE was NOT -- only the lower halfword is modified");
    chk(seq_psw[PSW_EL_HI:PSW_EL_LO] === 2'b00 && seq_psw[PSW_IS] === 1'b0,
        "so EL and IS are out of reach, and POPM is not a privilege escalation");

    // =======================================================================
    // TASI.  "lock ; flags <- dst - 0FFH ; dst <- 0FFH ; unlock" -- so Z is
    // set exactly when the byte was ALREADY 0FFH, which is to say when the
    // lock was already held.  That is the whole of test-and-set.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    mem[11'h700] = 8'h00;                    // the lock is free
    repeat (2) @(negedge clk);
    n_block = 0;
    jump(32'h00000650);
    step;
    chk(mem[11'h700] === 8'hFF,
        "TASI stored 0FFH into its destination");
    chk(seq_psw[PSW_Z] === 1'b0,
        "and Z is CLEAR, because the byte was not already 0FFH -- the lock was free");
    chk(seq_psw[PSW_CY] === 1'b1,
        "with CY set: 0x00 - 0xFF borrows, and the codes are a SUBTRACT's");
    chk(n_block == 2,
        "and BLOCK* was asserted for both bus cycles of the indivisible pair");

    // Again, on a byte that is now already set.  Same instruction, opposite
    // answer -- and it still writes 0FFH, unconditionally.
    @(negedge clk);
    repeat (2) @(negedge clk);
    jump(32'h00000650);
    step;
    chk(seq_psw[PSW_Z] === 1'b1,
        "a second TASI reports Z SET: the lock was already held");
    chk(seq_psw[PSW_CY] === 1'b0, "and no borrow, 0xFF - 0xFF being zero");
    chk(mem[11'h700] === 8'hFF,
        "the store happens either way -- TASI is not conditional");

    // And the lock must not outlive the instruction.  BLOCK* is a CLAIM to
    // other bus masters -- "an indivisible read-modify-write bus cycle (TASI,
    // CAXI instructions) is taking place" -- so an ordinary access after one
    // must not still be making it.
    //
    // Both shapes are needed and neither is obvious.  A MEMORY SOURCE reaches
    // the bus at S_OP1S, before the destination state that clears the lock; an
    // immediate source makes no access at all and would pass whatever the RTL
    // did.  And PUSH's stack access is described in a state of its own that
    // shares nothing with either.
    // Four shapes, because there are four places an access is described and a
    // leak in any of them is invisible from the others.  Each runs IMMEDIATELY
    // after a TASI: the first instruction to reach S_OP2 clears the lock, so a
    // test that puts anything in between proves nothing.
    @(negedge clk);
    put_word(13'h700, 32'h1234_5678);
    rf.gpr[10] = 32'h0000_072F;
    rf.gpr[9]  = 32'h0000_0700;
    repeat (2) @(negedge clk);

    n_block = 0;
    jump(32'h00000724);                      // MOV.W [R8], R9 -- a memory SOURCE
    step;
    chk(rf.gpr[9] === 32'h1234_5678, "the instruction after a TASI runs");
    chk(n_block == 0,
        "and its memory SOURCE read is not interlocked -- the lock did not leak");

    jump(32'h00000650); step;                // TASI again
    n_block = 0;
    jump(32'h00000620);                      // PUSH R9
    step;
    chk(n_block == 0,
        "nor is a PUSH's stack access, described in a state of its own");

    jump(32'h00000650); step;
    @(negedge clk);
    rf.gpr[10] = 32'h0000_072F;
    rf.gpr[9]  = 32'h0000_0700;
    repeat (2) @(negedge clk);
    n_block = 0;
    jump(32'h00000728);                      // CALL -- the stack ENGINE
    step;
    chk(n_block == 0,
        "nor the stack engine's, which CALL and RET share");

    jump(32'h00000650); step;
    n_block = 0;
    jump(32'h0000072C);                      // BSR -- a control transfer's push
    step;
    chk(n_block == 0,
        "nor a control transfer's push");

    // =======================================================================
    // CHLVL.  "This instruction provides a protected method of accessing more
    // privileged execution levels" -- the only exception in this tree whose
    // handler does not run at level 0, and the only one whose frame goes
    // somewhere other than L0SP or the interrupt stack.
    // =======================================================================
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    pr_id = 5'd1; pr_wdata = 32'h0000_0680; pr_wr = 1'b1;   // PR_L0SP
    @(negedge clk);
    pr_wr = 1'b0;
    // Drop to level 3 with a stack of its own, the way a user program runs.
    rf.gpr[31] = 32'h0000_05A0;
    seq.psw[PSW_EL_HI:PSW_EL_LO] = 2'b11;
    repeat (2) @(negedge clk);
    psw_before = seq_psw;
    jump(32'h00000730);
    step;

    chk(seq_pc === 32'h000002E8,
        "CHLVL #0 from level 3 vectors through SBT entry 24 -- 24 + level");
    chk(seq_psw[PSW_EL_HI:PSW_EL_LO] === 2'b00,
        "and the handler runs at the TARGET level, not at the caller's");
    chk(rf.gpr[31] === 32'h00000670,
        "its frame went on the target level's stack -- L0SP, not the level 3 one");
    chk(mem_word(13'h67C) === 32'h0000_005A,
        "the byte argument, zero extended, is the frame's parameter");
    chk(mem_word(13'h678) === 32'h18000008,
        "with code 0x1800 for level 0 and a parameter count of 8");
    chk(mem_word(13'h674) === psw_before, "then the caller's PSW");
    chk(mem_word(13'h670) === 32'h00000736,
        "and the NEXT PC, so the handler returns past the CHLVL");
    step;
    chk(mem[11'h700] === 8'hC5, "and the level 0 handler runs");

    // Asking for a LESS privileged level than the caller already has.  "the
    // current execution level is less than the level operand" -- level 0 is
    // the most privileged, so this instruction only ever goes one way.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    jump(32'h00000736);
    step;
    chk(seq_pc === 32'h00000790,
        "CHLVL #2 from level 0 is the Illegal Data Field exception");
    chk(mem_word(13'h5FC) === 32'h14000004,
        "vector 20's code -- not a Privileged Instruction exception, and not a no-op");

    // And a level that is not a level at all.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    jump(32'h0000073C);
    step;
    chk(seq_pc === 32'h00000790,
        "and a level operand of 5 raises it too: the range is 0 to 3");

    // A level of 4, which the PRIVILEGE test cannot catch -- its low two bits
    // are 00, so a caller at level 0 passes "EL < level".  Only the range
    // check sees this one.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    jump(32'h00000742);
    step;
    chk(seq_pc === 32'h00000790,
        "a level operand of 4 is caught by the RANGE check, which nothing else can do");

    // A SUCCESSFUL call to a non-zero level.  Everything about CHLVL that is
    // indistinguishable at level 0 -- the vector's base, the code's second
    // nibble, whose stack the frame lands on and what PSW.EL the handler runs
    // with -- is distinguishable here and nowhere else.
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    pr_id = 5'd3; pr_wdata = 32'h0000_0760; pr_wr = 1'b1;   // PR_L2SP
    @(negedge clk);
    pr_wr = 1'b0;
    rf.gpr[31] = 32'h0000_05A0;
    seq.psw[PSW_EL_HI:PSW_EL_LO] = 2'b11;                   // a level 3 caller
    repeat (2) @(negedge clk);
    psw_before = seq_psw;
    jump(32'h00000748);
    step;
    chk(seq_pc === 32'h00000150,
        "CHLVL #2 from level 3 vectors through SBT entry 26 -- 24 + level, not 24");
    chk(seq_psw[PSW_EL_HI:PSW_EL_LO] === 2'b10,
        "and the handler runs at level TWO: PSW.EL is the target, not zero");
    chk(rf.gpr[31] === 32'h00000750,
        "its frame went on L2SP -- the TARGET level's stack");
    chk(mem_word(13'h75C) === 32'h0000_0077, "the argument is the parameter");
    chk(mem_word(13'h758) === 32'h1A000008,
        "and the code is 0x1A00 -- the level is the SECOND NIBBLE, not an addend");
    chk(mem_word(13'h754) === psw_before, "then the caller's PSW");
    chk(mem_word(13'h750) === 32'h0000074E, "and the Next PC");
    step;
    chk(mem[11'h700] === 8'hE2, "and the level 2 handler runs");

    // A REGISTER source, whose upper bytes are not the operand.  `level` is a
    // byte, so 0x00000102 is level 2 -- and an implementation that
    // range-checked the whole register would raise Illegal Data Field on a
    // level the page permits.
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    pr_id = 5'd3; pr_wdata = 32'h0000_0760; pr_wr = 1'b1;   // PR_L2SP
    @(negedge clk);
    pr_wr = 1'b0;
    rf.gpr[5]  = 32'h0000_0102;              // level 2, with rubbish above it
    rf.gpr[6]  = 32'h0000_0077;              // the argument
    rf.gpr[31] = 32'h0000_05A0;
    seq.psw[PSW_EL_HI:PSW_EL_LO] = 2'b11;
    repeat (2) @(negedge clk);
    jump(32'h0000017B);
    step;
    chk(seq_pc === 32'h00000150,
        "CHLVL with a register level operand reads it as a BYTE and is permitted");
    chk(mem_word(13'h75C) === 32'h0000_0077,
        "and the argument is the byte too, not the register");

    // And the NEXT exception must go back to level 0.  CHLVL is the only
    // instruction that sets a non-zero target, so the target has to be cleared
    // again -- otherwise every exception after a CHLVL inherits its level and
    // lands on the wrong stack.  A BRK is the cheapest thing that raises.
    @(negedge clk);
    pr_id = 5'd1; pr_wdata = 32'h0000_0680; pr_wr = 1'b1;   // PR_L0SP
    @(negedge clk);
    pr_wr = 1'b0;
    repeat (2) @(negedge clk);
    jump(32'h0000027C);
    step;
    chk(seq_pc === 32'h000001A0, "a BRK after a CHLVL reaches its own handler");
    chk(seq_psw[PSW_EL_HI:PSW_EL_LO] === 2'b00,
        "at level 0 -- CHLVL's target level did not leak into the next exception");
    chk(rf.gpr[31] === 32'h00000674,
        "and its frame went on L0SP, not on the level 2 stack");

    // =======================================================================
    // CAXI -- compare and swap, and "a more general form of the TASI
    // instruction".  R28 is an IMPLICIT third operand: the new value comes
    // from it and it appears nowhere in the syntax line.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    rf.gpr[9]  = 32'h1234_5678;              // Rn, the comparand
    rf.gpr[28] = 32'h5EED_C0DE;              // the value to install
    put_word(13'h700, 32'h1234_5678);        // the destination MATCHES
    repeat (2) @(negedge clk);
    n_block = 0;
    jump(32'h00000721);
    step;
    chk(seq_psw[PSW_Z] === 1'b1,
        "CAXI on a matching destination sets Z -- the comparison is dst - Rn");
    chk(mem_word(13'h700) === 32'h5EED_C0DE,
        "and installs R28, which the syntax line never mentions");
    chk(rf.gpr[9] === 32'h1234_5678, "leaving Rn alone on a match");
    chk(n_block == 4,
        "with BLOCK* over all four cycles: a word read and a word write, interlocked");


    // Now the destination no longer matches -- which is the case a retry loop
    // is built on.  The word there is a THIRD value, equal to neither R28 nor
    // Rn: with R28's value still sitting in memory, "Rn takes what was there"
    // and "Rn takes R28" cannot be told apart.
    @(negedge clk);
    put_word(13'h700, 32'hFACE_0FF1);
    repeat (2) @(negedge clk);
    jump(32'h00000721);
    step;
    chk(seq_psw[PSW_Z] === 1'b0, "a second CAXI does not match, and clears Z");
    chk(rf.gpr[9] === 32'hFACE_0FF1,
        "so Rn receives what was ACTUALLY there -- the retry value, without a second read");
    chk(mem_word(13'h700) === 32'hFACE_0FF1,
        "and the destination keeps its own contents");

    // =======================================================================
    // The X forms end to end.  A doubleword operand is "a register pair, low
    // register first" (§3) or eight contiguous bytes "identified by the
    // address of the low order byte" (§2) -- the same little-endian statement
    // in the two media.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    rf.gpr[9]  = 32'h0001_0000;              // the multiplicand: the LOW word
    rf.gpr[10] = 32'hDEAD_BEEF;              // the high word, which MULX never reads
    repeat (2) @(negedge clk);
    jump(32'h00000158);
    step;
    chk(rf.gpr[9] === 32'h0000_0000,
        "MULX 0x10000 x 0x10000 leaves the product's low word in R9");
    chk(rf.gpr[10] === 32'h0000_0001,
        "and its high word in R10 -- an ODD low register, which the pages allow");
    chk(seq_psw[PSW_Z] === 1'b0,
        "Z is clear: it tests all sixty-four bits, and the low word alone is zero");
    chk(seq_psw[PSW_OV] === 1'b0, "and OV is cleared, always, on an X multiply");

    // A register-pair DIVIDEND, which is the only case that proves the pair is
    // read rather than the low register twice.  0x1_0000_0005 / 0x10000.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[9]  = 32'h0000_0005;              // the dividend's LOW word
    rf.gpr[10] = 32'h0000_0001;              //   and its HIGH word
    repeat (2) @(negedge clk);
    jump(32'h00000170);
    step;
    chk(rf.gpr[9] === 32'h0001_0000,
        "DIVX read the whole PAIR as its dividend: the quotient needs the high word");
    chk(rf.gpr[10] === 32'h0000_0005,
        "and the remainder replaced it -- quotient low, remainder high");

    // The same dividend through the ADDRESS UNIT's register-direct path, which
    // Format I with d = 0 is the only way to reach.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[9]  = 32'h0000_0005;
    rf.gpr[10] = 32'h0000_0001;
    rf.gpr[12] = 32'h0001_0000;              // the divisor
    repeat (2) @(negedge clk);
    jump(32'h00000178);
    step;
    chk(rf.gpr[9] === 32'h0001_0000 && rf.gpr[10] === 32'h0000_0005,
        "a doubleword pair reached through the address unit reads and writes BOTH registers");

    // A MEMORY doubleword, where the two halves of the destination carry two
    // different quantities.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h700, 32'd12345);            // the dividend, low word
    put_word(13'h704, 32'd0);                //   and high
    repeat (2) @(negedge clk);
    jump(32'h00000160);
    step;
    chk(mem_word(13'h700) === 32'd1234,
        "DIVX through memory put the QUOTIENT at the operand's own address");
    chk(mem_word(13'h704) === 32'd5,
        "and the REMAINDER four bytes above it -- two different quantities, one operand");

    // A zero divide still raises, and the destination survives it.
    reset_and_arm;
    mem[11'h700] = 8'h00;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h700, 32'd12345);
    put_word(13'h704, 32'd99);
    repeat (2) @(negedge clk);
    jump(32'h00000168);
    step;
    chk(seq_pc === 32'h000001C0,
        "an X divide by zero reaches the Integer Arithmetic handler");
    chk(mem_word(13'h700) === 32'd12345 && mem_word(13'h704) === 32'd99,
        "and NEITHER half of the destination changed");

    // =======================================================================
    // The bit field group, end to end.  Format VII has never been executed
    // here -- v60_idu has produced its ext bytes all along and nothing
    // consumed them.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    put_word(13'h700, 32'h0000_0098);        // the word holding the field
    rf.gpr[9] = 32'hDEAD_BEEF;
    repeat (2) @(negedge clk);
    psw_before = seq_psw;
    jump(32'h000006B4);
    step;
    chk(rf.gpr[9] === 32'h0000_0013,
        "EXTBFZ took the five bits at bit offset 3 -- the displacement IS the bit offset");
    chk(seq_psw === psw_before, "with every flag Unchanged");
    chk(seq_pc === 32'h000006BA, "and six bytes consumed: op, base word, mod, disp, ext, mod'");

    // The signed variant of the same field, whose top bit is set.
    step;
    chk(rf.gpr[9] === 32'hFFFF_FFF3,
        "EXTBFS sign extends the same field from ITS top bit, not from bit 31");

    // CMPBF reads three operands and writes none.
    @(negedge clk);
    rf.gpr[9] = 32'h0000_0013;               // equal to the field
    repeat (2) @(negedge clk);
    n_writes = 0;
    jump(32'h000006C0);
    step;
    chk(seq_psw[PSW_Z] === 1'b1, "CMPBF against an equal source sets Z");
    chk(rf.gpr[9] === 32'h0000_0013, "leaving its source alone");
    chk(n_writes == 0, "and putting no write on the bus at all");

    // INSBF, whose bit-addressed operand is the destination and whose length
    // is the LAST field rather than the middle one.
    @(negedge clk);
    put_word(13'h700, 32'hFFFF_FFFF);
    rf.gpr[9] = 32'h0000_0002;
    repeat (2) @(negedge clk);
    jump(32'h000006C6);
    step;
    chk(mem_word(13'h700) === 32'hFFFF_FF17,
        "INSBFR replaced the five bits at offset 3 and left every neighbour");

    // "The sum of the bit offset and the bit field length must not exceed
    // thirty-two, otherwise an Illegal Data Field exception will occur."
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h700, 32'h0000_0098);
    rf.gpr[9] = 32'hDEAD_BEEF;
    repeat (2) @(negedge clk);
    n_writes = 0;
    jump(32'h000006CC);
    step;
    chk(seq_pc === 32'h00000790,
        "3 + 31 exceeds thirty-two, and that is the Illegal Data Field exception");
    chk(mem_word(13'h5FC) === 32'h14000004, "vector 20's code");
    chk(rf.gpr[9] === 32'hDEAD_BEEF,
        "with the destination untouched -- the handler restarts the instruction");
    chk(seq.bf_len_r === 6'd31,
        "the length was taken, so the check is on the SUM and not on the length alone");

    // The length in a register, which bit 7 of the ext byte selects.  The word
    // is chosen so that the register's 5 and the ext byte's own low bits -- 7,
    // from 0x87 -- give DIFFERENT fields: 0x398 >> 3 is 0x73, which is 0x13 at
    // five bits and 0x73 at seven.  With 0x98 the two agree and the register
    // form cannot be told from the immediate one.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h700, 32'h0000_0398);
    rf.gpr[7] = 32'h0000_0005;
    rf.gpr[9] = 32'hDEAD_BEEF;
    repeat (2) @(negedge clk);
    jump(32'h000006D2);
    step;
    chk(rf.gpr[9] === 32'h0000_0013,
        "an ext byte with bit 7 set names a REGISTER holding the length");

    // A NEGATIVE bit offset, which the sign extension is there for.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h6FC, 32'h0000_0000);
    put_word(13'h700, 32'h0000_0000);
    mem[11'h6FF] = 8'hAA;                    // one byte below R8
    rf.gpr[9] = 32'hDEAD_BEEF;
    repeat (2) @(negedge clk);
    jump(32'h000006D8);
    step;
    chk(rf.gpr[9] === 32'h0000_000A,
        "an offset of -8 bits addresses the byte BELOW the base: the offset is signed");

    // INSBF with a memory source, so that which operand is bit-addressed is
    // observable rather than hidden by a register operand having no address.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h700, 32'hFFFF_FFFF);        // the destination
    put_word(13'h718, 32'h0000_0002);        // the source, at 8[R10]
    rf.gpr[10] = 32'h0000_0710;
    repeat (2) @(negedge clk);
    jump(32'h000006DE);
    step;
    chk(mem_word(13'h700) === 32'hFFFF_FF17,
        "INSBF's bit-addressed operand is its DESTINATION, and its source is an ordinary read");

    // A length above 32 at residual zero, where only the length can fail the
    // sum -- and where a six-bit sum would have wrapped and let it through.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h700, 32'h0000_0098);
    rf.gpr[9] = 32'hDEAD_BEEF;
    repeat (2) @(negedge clk);
    jump(32'h000006E5);
    step;
    chk(seq_pc === 32'h00000790,
        "a length of 40 raises Illegal Data Field even with a residual of zero");
    chk(rf.gpr[9] === 32'hDEAD_BEEF, "leaving the destination alone");

    // And the same length at a non-zero residual, where the sum's WIDTH is
    // what decides: 3 + 63 is 66, which wraps to 2 in six bits.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h700, 32'h0000_0098);
    rf.gpr[9] = 32'hDEAD_BEEF;
    repeat (2) @(negedge clk);
    jump(32'h000006EB);
    step;
    chk(seq_pc === 32'h00000790,
        "an over-long length at residual 3 raises too -- the sum must not wrap");
    chk(rf.gpr[9] === 32'hDEAD_BEEF, "with the destination untouched");

    // An ext byte of 96, whose low six bits are exactly 32 and therefore look
    // legal.  The length field is SEVEN bits and only the whole of it says so.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h700, 32'h0000_0098);
    rf.gpr[9] = 32'hDEAD_BEEF;
    repeat (2) @(negedge clk);
    jump(32'h000006F1);
    step;
    chk(seq_pc === 32'h00000790,
        "a length of 96 raises, though its low six bits are a legal 32");

    // =======================================================================
    // The decimal group, end to end.  The same Format VIIc the bit field group
    // uses, and the same extension byte -- carrying a mask PATTERN here rather
    // than a length, which only the opcode distinguishes.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    mem[11'h700] = 8'h59;                    // the destination byte
    mem[11'h710] = 8'h59;                    // the source
    rf.gpr[10] = 32'h0000_0710;
    seq.psw[PSW_CY] = 1'b0;
    seq.psw[PSW_Z]  = 1'b1;                  // preset, to watch it survive
    repeat (2) @(negedge clk);
    jump(32'h000006F7);
    step;
    chk(mem[11'h700] === 8'h18,
        "ADDDC 59 + 59 stored 18: the carry is DECIMAL, not bit 8 of a binary sum");
    chk(seq_psw[PSW_CY] === 1'b1, "and set CY out of the top digit");
    chk(seq_psw[PSW_Z] === 1'b0, "clearing the preset Z, the result being non-zero");
    chk(seq_pc === 32'h000006FC, "five bytes: op, base word, mod, mod', ext'");

    // The carry threads the next byte, which is the whole point of the group.
    @(negedge clk);
    mem[11'h700] = 8'h00;
    mem[11'h710] = 8'h00;
    repeat (2) @(negedge clk);
    jump(32'h000006F7);
    step;
    chk(mem[11'h700] === 8'h01,
        "the next byte up takes the carry in: 00 + 00 + 1 is 01");

    // Z is sticky across the chain: a zero byte with no carry leaves it.
    @(negedge clk);
    mem[11'h700] = 8'h00;
    mem[11'h710] = 8'h00;
    seq.psw[PSW_CY] = 1'b0;
    seq.psw[PSW_Z]  = 1'b1;
    repeat (2) @(negedge clk);
    jump(32'h000006F7);
    step;
    chk(mem[11'h700] === 8'h00 && seq_psw[PSW_Z] === 1'b1,
        "a zero byte with no carry LEAVES Z: it accumulates across the whole number");

    // The two conversions, where the pattern byte is actually READ -- the
    // arithmetic three never look at it, so nothing above can tell whether it
    // was captured at all.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    mem[11'h710] = 8'h59;                    // the packed source
    put_word(13'h700, 32'h0000_0000);
    rf.gpr[10] = 32'h0000_0710;
    repeat (2) @(negedge clk);
    jump(32'h00000184);
    step;
    chk(mem[11'h700] === 8'h35 && mem[11'h701] === 8'h39,
        "CVTD.PZ wrote '5' then '9' -- the digits cross, and the PATTERN supplied the zone");

    // And back, which raises when a zone does not match the pattern.  This is
    // the only Decimal Format exception in the group that is not a bad digit:
    // §3 says "There is no restriction on the contents of the zone field", so
    // the restriction comes from the INSTRUCTION.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    mem[11'h710] = 8'h35; mem[11'h711] = 8'h39;
    mem[11'h700] = 8'hCC;                    // the destination, to stay put
    rf.gpr[10] = 32'h0000_0710;
    repeat (2) @(negedge clk);
    jump(32'h00000189);
    step;
    chk(mem[11'h700] === 8'h59, "CVTD.ZP converts back exactly");

    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    mem[11'h710] = 8'h45; mem[11'h711] = 8'h39;   // a zone of 4, not 3
    mem[11'h700] = 8'hCC;
    rf.gpr[10] = 32'h0000_0710;
    repeat (2) @(negedge clk);
    jump(32'h00000189);
    step;
    chk(seq_pc === 32'h000001C0,
        "a zone that does not match the pattern raises the Decimal Format exception");
    chk(mem_word(13'h5F8) === 32'h17800008,
        "with code 0x1780 beside a parameter count of 8 -- the Arithmetic frame");
    chk(mem[11'h700] === 8'hCC,
        "and the destination remains unchanged, which every one of the five promises");

    // An INDIRECT bit-addressed operand, which nothing exercised before.  The
    // pointer is at 4[R10] and the operand at the pointer, so the bit address
    // must be built from the POINTER -- and the residual with it.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    rf.gpr[10] = 32'h0000_0710;
    put_word(13'h714, 32'h0000_0700);        // the pointer
    put_word(13'h700, 32'h0000_0098);        // the field's word
    rf.gpr[9] = 32'hDEAD_BEEF;
    repeat (2) @(negedge clk);
    // Run a DIRECT bit-field instruction first, whose residual is 3.  Without
    // it the previous residual happens to be 0, which is also the right answer
    // here -- so "the indirect path recomputes the residual" and "the indirect
    // path leaves the last one alone" would agree, and the test would prove
    // nothing.
    jump(32'h000006B4);                      // EXTBFZ 3[R8], #5, R9
    step;
    chk(seq.bf_resid_r === 3'd3, "the direct instruction leaves a residual of 3 behind");
    @(negedge clk);
    rf.gpr[9] = 32'hDEAD_BEEF;
    repeat (2) @(negedge clk);
    jump(32'h00000764);
    step;
    chk(rf.gpr[9] === 32'h0000_0098,
        "an indirect bit operand reads at the POINTER, with a residual taken from it");
    chk(seq.bf_resid_r === 3'd0,
        "and the residual is RECOMPUTED from the pointer, not left at the last one");

    // =======================================================================
    // The floating point three that contain no arithmetic -- and the first
    // thing in this tree that writes the FLOATING POINT condition codes,
    // PSW[12:8].  Nothing had, which is why docs/v60/BREAK-AND-TRAP.md could
    // only record TRAPFL as armable by hand.
    // =======================================================================
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600, R8 = 0x700
    @(negedge clk);
    put_word(13'h710, 32'h3F80_0000);        // 1.0f
    rf.gpr[10] = 32'h0000_0710;
    rf.gpr[9]  = 32'hDEAD_BEEF;
    repeat (2) @(negedge clk);
    jump(32'h0000076A);
    step;
    chk(rf.gpr[9] === 32'hBF80_0000, "NEGF.s of 1.0 stored -1.0");
    chk(seq_psw[PSW_S] === 1'b1 && seq_psw[PSW_CY] === 1'b1,
        "with S and CY from the result");

    // A NaN raises Reserved Floating Point Operand, and "the flags and
    // destination will remain unchanged".
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h710, 32'h7FC0_0000);        // a quiet NaN
    rf.gpr[10] = 32'h0000_0710;
    rf.gpr[9]  = 32'h1234_5678;
    seq.psw[PSW_Z] = 1'b1;
    repeat (2) @(negedge clk);
    psw_before = seq_psw;
    jump(32'h0000076E);
    step;
    chk(seq_pc === 32'h000002C0,
        "a NaN source raises the FLOATING POINT exception, vector 22 -- not the integer one");
    chk(mem_word(13'h5F8) === 32'h16800008,
        "with code 0x1680 -- Reserved Floating Point Operand");
    chk(rf.gpr[9] === 32'h1234_5678, "the destination remains unchanged");
    chk(mem_word(13'h5F4) === psw_before,
        "and the FLAGS remain unchanged too, which the page says in the same breath");

    // And a clean value DOES write the floating point condition codes, which
    // is what finally lets TRAPFL fire from an FP result rather than by hand.
    reset_and_arm;
    jump(32'h00000440);
    step; step;
    @(negedge clk);
    put_word(13'h710, 32'h0000_0001);        // a denormal
    rf.gpr[10] = 32'h0000_0710;
    repeat (2) @(negedge clk);
    jump(32'h0000076A);
    step;
    chk(seq_psw[PSW_FUD] === 1'b1,
        "a denormal result sets PSW.FUD -- the first FP condition code this tree writes");

    // POP's ordering, which its page states with the word "then": "The word
    // data located on the top of the stack is copied to the destination
    // operand.  The stack pointer (R31) is THEN incremented by four."
    //
    // A destination whose ADDRESS depends on R31 is what makes it visible --
    // `pop sp` is the famous case but this is the general one.
    reset_and_arm;
    jump(32'h00000440);
    step; step;                              // R31 = 0x600
    @(negedge clk);
    put_word(13'h600, 32'hC0DE_C0DE);        // the word on the stack
    put_word(13'h604, 32'h0000_0000);
    repeat (2) @(negedge clk);
    jump(32'h00000772);
    step;
    chk(mem_word(13'h600) === 32'hC0DE_C0DE,
        "POP wrote its destination at the OLD stack pointer: the copy comes first");
    chk(mem_word(13'h604) === 32'h0000_0000,
        "and not four bytes up, which incrementing first would have done");
    chk(rf.gpr[31] === 32'h00000604, "with the stack pointer incremented after");

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
