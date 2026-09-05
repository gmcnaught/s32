//============================================================================
//  v60_top -- the clean-room uPD70616, assembled.
//
//  Until this file existed the whole processor was wired up only inside
//  verif/v60x/tb_v60_seq.sv, which is where every instantiation below was
//  lifted from.  Nothing is added; the bench's stimulus (its memory, its
//  uPD71059 stand-in, its bus-error aim) stays in the bench, and the bench's
//  two conveniences become ports:
//
//    * START_PC.  The prefetch unit starts at 0FFFFF0H out of reset
//      (databook p.3.282) and nothing in this tree changes that.  A bench that
//      wants its program elsewhere gets one redirect, on the first enabled
//      cycle after reset, to START_PC -- the same flush a control transfer
//      makes (p.3.246), issued before any byte has been decoded.
//    * pr_id / pr_wr / pr_wdata.  A bench places SBR and the interrupt stack
//      pointer before running because there is no program yet to LDPR them;
//      the bench wins while its pr_wr is high, exactly as tb_v60_seq does it.
//
//  Everything below the ports is the databook's pin list (section 1), driven
//  by v60_biu at the instants section 4 names.  ready_n, bmode, hldrq_n,
//  berr_n and rt_ep_n are inputs the board drives; on System 32 the board
//  ties BMODE, pulls BERR*/RT-EP* inactive and holds HLDRQ* off
//  (docs/v60/BUS-PINS-171-5964D.md).
//============================================================================
module v60_top
    // One import statement, not one per package: Quartus 17.0 accepts a
    // single package_import_declaration in a module header and rejects a
    // second with "expecting ;".  Same packages, same order.
    import v60_bus_pkg::*, v60_fmt_pkg::*, v60_am_pkg::*, v60_alu_pkg::*, v60_psw_pkg::*;
#(
    parameter logic [31:0] START_PC = 32'h00FF_FFF0
)(
    input  logic        clk,
    input  logic        rst,
    input  logic        ce_rise,        // the V60 clock's rising edge
    input  logic        ce_fall,        // and its falling edge
    input  logic        run,            // execute instructions while high

    // ---- databook pins ------------------------------------------------------
    output logic [23:0] a,
    output logic  [1:0] dl_o,
    output logic  [2:0] st,
    output logic        mrq_n,
    output logic        rw_n,
    output logic        ube_n,
    output logic        fas_n,
    output logic        bcy_n,
    output logic        ds_n,
    output logic        block_n,
    output logic        hldak_n,
    output logic        bus_hiz,
    output logic [15:0] d_out,
    output logic        d_oe,
    input  logic [15:0] d_in,
    input  logic        ready_n,
    input  logic        bmode,
    input  logic        hldrq_n,
    input  logic        berr_n,
    input  logic        rt_ep_n,
    input  logic        nmi_n,
    input  logic        int_req,

    // ---- observation --------------------------------------------------------
    output logic [31:0] pc,
    output logic [31:0] psw,
    output logic        retired,        // one pulse per instruction
    output logic        halted,         // HALT retired; waiting for an interrupt
    output logic        stopped,        // hit something this tree cannot execute
    output logic  [1:0] stop_reason,
    output logic  [4:0] insn_cycles,
    output bus_state_e  state,
    output logic        own_pfu,        // the arbiter's grant is the prefetch unit's

    // ---- privileged-register placement, a bench's LDPR substitute ------------
    input  logic  [4:0] pr_id,
    input  logic        pr_wr,
    input  logic [31:0] pr_wdata
);

// ---- the one redirect that places START_PC -----------------------------------
logic        start_pending;
logic        start_redirect;
always_ff @(posedge clk) begin
    if (rst) start_pending <= (START_PC != 32'h00FF_FFF0);
    else if (start_redirect) start_pending <= 1'b0;
end
assign start_redirect = start_pending && !rst;

// ---- prefetch ------------------------------------------------------------------
logic        biu_berr, biu_berr_we, nmi_pending, nmi_take, int_pending;
bus_status_e biu_berr_status;
logic [23:0] biu_berr_addr;

logic  [7:0] byte_out;
logic        byte_valid, byte_take;
logic [31:0] byte_pc;
logic        p_req, p_ack;
bus_status_e p_status;
logic [23:0] p_addr;
logic  [1:0] p_dl;
logic [15:0] biu_rdata;

logic        seq_redirect;
logic [31:0] seq_redirect_pc;

v60_pfu u_pfu (
    .clk(clk), .rst(rst),
    .byte_out(byte_out), .byte_valid(byte_valid), .byte_take(byte_take),
    .byte_pc(byte_pc),
    .redirect(start_redirect | seq_redirect),
    .redirect_pc(start_redirect ? START_PC : seq_redirect_pc),
    .bus_req(p_req), .bus_status(p_status), .bus_addr(p_addr), .bus_dl(p_dl),
    .bus_ack(p_ack), .bus_rdata(biu_rdata), .level()
);

// ---- decode --------------------------------------------------------------------
logic        idu_start, idu_done, res_op, res_mode;
insn_fmt_e   idu_fmt;
logic  [7:0] idu_op;
logic        idu_d;
logic  [4:0] idu_reg, idu_subop;
logic [31:0] idu_disp;
logic [31:0] idu_pc;
logic  [4:0] idu_len;
logic        o1_valid, o1_index, o2_valid, o2_index;
am_mode_e    o1_mode, o2_mode;
logic  [4:0] o1_rn, o1_rx, o2_rn, o2_rx;
logic [31:0] o1_disp, o1_douter, o2_disp, o2_douter;
logic [63:0] o1_imm, o2_imm;
logic  [3:0] o1_bytes, o2_bytes;
logic        o1_ext_valid, o2_ext_valid;
logic  [7:0] o1_ext, o2_ext;

v60_idu u_idu (
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

// ---- registers -------------------------------------------------------------------
logic [31:0] seq_pc, seq_psw;
logic  [4:0] rf_ra_sel, rf_rb_sel, rf_wr_sel;
logic        rf_stack_switch, rf_new_is;
logic  [1:0] rf_new_el;
logic  [1:0] seq_exc_new_el;
logic [31:0] rf_sbr;
logic [31:0] rf_ra, rf_rb, rf_wr_data;
logic [63:0] rf_ra_pair;
logic        rf_wr_en;
logic  [3:0] rf_wr_be;

logic  [4:0] seq_pr_id;
logic        seq_pr_wr;
logic [31:0] seq_pr_wdata;
logic [31:0] rf_pr_rdata;
logic        rf_pr_rd_ok, rf_pr_wr_ok;
logic  [4:0] mux_pr_id;
logic        mux_pr_wr;
logic [31:0] mux_pr_wdata;
assign mux_pr_id    = pr_wr ? pr_id    : seq_pr_id;
assign mux_pr_wr    = pr_wr | seq_pr_wr;
assign mux_pr_wdata = pr_wr ? pr_wdata : seq_pr_wdata;

v60_regfile u_rf (
    .clk(clk), .rst(rst),
    .ra_sel(rf_ra_sel), .rb_sel(rf_rb_sel), .ra(rf_ra), .rb(rf_rb),
    .ra_pair(rf_ra_pair),
    .wr_en(rf_wr_en), .wr_sel(rf_wr_sel), .wr_data(rf_wr_data), .wr_be(rf_wr_be),
    .cur_el(seq_psw[PSW_EL_HI:PSW_EL_LO]), .psw_is(seq_psw[PSW_IS]),
    .stack_switch(rf_stack_switch), .new_el(rf_new_el), .new_is(rf_new_is),
    .pr_id(mux_pr_id), .pr_wr(mux_pr_wr), .pr_wdata(mux_pr_wdata),
    .pr_rdata(rf_pr_rdata), .pr_rd_ok(rf_pr_rd_ok), .pr_wr_ok(rf_pr_wr_ok),
    .sbr(rf_sbr)
);

// ---- address unit and data unit ----------------------------------------------------
logic        ea_start, ea_index, ea_we, ea_rmw, ea_rmw_go, ea_rmw_pending;
logic        ea_addr_only, ea_io;
logic        a_io, dx_io;
logic        ea_lock, a_lock, dx_lock, d_lock, biu_lock;
am_mode_e    ea_mode;
logic [31:0] ea_disp, ea_douter, ea_rn_val, ea_rx_val, ea_pc_val, ea_ea;
logic [31:0] ea_rn1_val, ea_rn_wb_hi;
logic        ea_rn_wb_pair;
logic        ea_bit_mode;
logic  [2:0] ea_bit_resid;
logic [63:0] ea_imm, ea_wdata, ea_rmw_data, ea_rdata;
logic  [3:0] ea_opbytes, ea_cycles;
logic        ea_done, ea_rn_wb;
logic [31:0] ea_rn_wb_val;

logic        dx_req, dx_we, dx_done, dx_intack;
logic [23:0] dx_addr;
logic  [3:0] dx_nbytes, dx_cycles;
logic [63:0] dx_wdata, dx_rdata;

logic        exc_req, exc_is_int, exc_dis_ie, exc_done;
logic        exc_int_stack, exc_ack_vector, exc_intack, exc_invalid_int;
logic  [7:0] exc_int_vector;
logic  [7:0] exc_vector;
logic [31:0] exc_ret_pc, exc_psw_in, exc_sp_in, exc_sbr;
logic  [1:0] exc_nparams;
logic [15:0] exc_code;
logic [31:0] exc_param0, exc_param1;
logic [31:0] exc_sp_out, exc_psw_out, exc_handler_pc;
logic  [3:0] exc_cycles;
logic        b_req, b_we, b_done;
logic [23:0] b_addr;
logic  [3:0] b_nbytes, b_cycles;
logic [63:0] b_wdata, b_rdata;
logic        a_req, a_we, a_done;
logic [23:0] a_addr;
logic  [3:0] a_nbytes, a_cycles;
logic [63:0] a_wdata, a_rdata;
logic        dmux_overlap;

v60_ea u_ea (
    .clk(clk), .rst(rst),
    .start(ea_start), .mode(ea_mode), .has_index(ea_index),
    .disp(ea_disp), .disp_outer(ea_douter), .imm(ea_imm),
    .rn_val(ea_rn_val), .rn1_val(ea_rn1_val), .rx_val(ea_rx_val), .pc_val(ea_pc_val),
    .opbytes(ea_opbytes), .we(ea_we), .io(ea_io), .lock(ea_lock),
    .bit_mode(ea_bit_mode), .wdata(ea_wdata),
    .addr_only(ea_addr_only),
    .rmw(ea_rmw), .rmw_pending(ea_rmw_pending), .rmw_go(ea_rmw_go),
    .rmw_data(ea_rmw_data),
    .ea(ea_ea), .bit_resid(ea_bit_resid), .rdata(ea_rdata),
    .rn_wb(ea_rn_wb), .rn_wb_val(ea_rn_wb_val),
    .rn_wb_pair(ea_rn_wb_pair), .rn_wb_hi(ea_rn_wb_hi),
    .illegal(), .busy(), .done(ea_done), .bus_cycles(ea_cycles),
    .dx_req(a_req), .dx_addr(a_addr), .dx_nbytes(a_nbytes), .dx_we(a_we),
    .dx_io(a_io), .dx_lock(a_lock),
    .dx_wdata(a_wdata), .dx_rdata(a_rdata), .dx_done(a_done),
    .dx_cycles(a_cycles)
);

v60_exc u_exc (
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

v60_dmux u_dmux (
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

logic        d_req, d_we, d_ube, d_first, d_ack;
bus_status_e d_status;
logic [23:0] d_addr;
logic  [1:0] d_dl;
logic [15:0] d_wdata;

v60_dxu u_dxu (
    .clk(clk), .rst(rst),
    .req(dx_req), .addr(dx_addr), .nbytes(dx_nbytes), .we(dx_we), .io(dx_io),
    .lock(dx_lock), .intack(dx_intack),
    .wdata(dx_wdata), .rdata(dx_rdata), .busy(), .done(dx_done),
    .cycles(dx_cycles),
    .biu_lock(d_lock),
    .biu_req(d_req), .biu_status(d_status), .biu_addr(d_addr),
    .biu_we(d_we), .biu_dl(d_dl), .biu_ube(d_ube), .biu_first(d_first),
    .biu_wdata(d_wdata), .biu_ack(d_ack), .biu_rdata(biu_rdata)
);

// ---- the sequencer ---------------------------------------------------------------------
v60_seq u_seq (
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
    .rf_wr_en(rf_wr_en), .rf_wr_be(rf_wr_be), .rf_wr_sel(rf_wr_sel), .rf_wr_data(rf_wr_data),
    .ea_start(ea_start), .ea_mode(ea_mode), .ea_index(ea_index),
    .ea_disp(ea_disp), .ea_disp_outer(ea_douter), .ea_imm(ea_imm),
    .ea_rn_val(ea_rn_val), .ea_rn1_val(ea_rn1_val), .ea_rx_val(ea_rx_val), .ea_pc_val(ea_pc_val),
    .ea_opbytes(ea_opbytes), .ea_we(ea_we), .ea_io(ea_io), .ea_lock(ea_lock),
    .ea_bit_mode(ea_bit_mode), .ea_bit_resid(ea_bit_resid), .ea_wdata(ea_wdata),
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
    .pc(seq_pc), .psw(seq_psw), .retired(retired), .halted(halted),
    .insn_cycles(insn_cycles),
    .stopped(stopped), .stop_reason(stop_reason)
);

assign pc  = seq_pc;
assign psw = seq_psw;

// ---- arbiter and bus -----------------------------------------------------------------------
logic        biu_req, biu_we, biu_ube, biu_first, biu_ack, biu_busy;
bus_status_e biu_status;
logic [23:0] biu_addr;
logic  [1:0] biu_dl;
logic [15:0] biu_wdata;

v60_bus_arb u_arb (
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

v60_biu u_biu (
    .clk(clk), .rst(rst), .ce_rise(ce_rise), .ce_fall(ce_fall),
    .req(biu_req), .status(biu_status), .addr(biu_addr), .we(biu_we),
    .dl(biu_dl), .ube(biu_ube), .first(biu_first), .lock(biu_lock), .wdata(biu_wdata),
    .ack(biu_ack), .rdata(biu_rdata), .busy(biu_busy),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .block_n(block_n), .ds_n(ds_n),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .bus_hiz(bus_hiz),
    .ready_n(ready_n), .bmode(bmode), .hldrq_n(hldrq_n), .hldak_n(hldak_n),
    .berr_n(berr_n), .rt_ep_n(rt_ep_n), .nmi_n(nmi_n), .int_req(int_req),
    .berr(biu_berr), .berr_status(biu_berr_status),
    .berr_addr(biu_berr_addr), .berr_we(biu_berr_we), .berr_retry(),
    .nmi_pending(nmi_pending), .nmi_take(nmi_take), .int_pending(int_pending),
    .state(state)
);

endmodule
