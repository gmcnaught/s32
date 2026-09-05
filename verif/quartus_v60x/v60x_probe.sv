// Isolated synthesis wrapper for the clean-room V60 (rtl/cpu/v60x/v60_top).
//
// Every handshake and every databook pin sits at the probe boundary so
// Quartus cannot constant-fold a state away, and the observation outputs are
// kept for the same reason: a sequencer whose `retired` and `pc` go nowhere
// is a sequencer the fitter is free to delete.  Same shape as
// verif/quartus_v60/top.sv, which does this for the shipping core.
//
// START_PC is the reset default, so the one-shot redirect logic is inert and
// what is fitted is the processor as the databook boots it.
module v60x_probe (
    input             clk,
    input             rst,
    input             ce_rise,
    input             ce_fall,
    input             run,
    output     [23:0] a,
    output      [1:0] dl_o,
    output      [2:0] st,
    output            mrq_n,
    output            rw_n,
    output            ube_n,
    output            fas_n,
    output            bcy_n,
    output            ds_n,
    output            block_n,
    output            hldak_n,
    output            bus_hiz,
    output     [15:0] d_out,
    output            d_oe,
    input      [15:0] d_in,
    input             ready_n,
    input             bmode,
    input             hldrq_n,
    input             berr_n,
    input             rt_ep_n,
    input             nmi_n,
    input             int_req,
    output     [31:0] pc,
    output     [31:0] psw,
    output            retired,
    output            halted,
    output            stopped,
    output      [1:0] stop_reason,
    output      [4:0] insn_cycles,
    output      [2:0] state,
    output            own_pfu,
    input       [4:0] pr_id,
    input             pr_wr,
    input      [31:0] pr_wdata
);

v60_bus_pkg::bus_state_e state_e;
assign state = state_e[2:0];

v60_top #(.START_PC(32'h00FF_FFF0)) u_v60 (
    .clk(clk), .rst(rst), .ce_rise(ce_rise), .ce_fall(ce_fall), .run(run),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .ds_n(ds_n), .block_n(block_n),
    .hldak_n(hldak_n), .bus_hiz(bus_hiz),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in),
    .ready_n(ready_n), .bmode(bmode), .hldrq_n(hldrq_n), .berr_n(berr_n),
    .rt_ep_n(rt_ep_n), .nmi_n(nmi_n), .int_req(int_req),
    .pc(pc), .psw(psw), .retired(retired), .halted(halted),
    .stopped(stopped), .stop_reason(stop_reason), .insn_cycles(insn_cycles),
    .state(state_e), .own_pfu(own_pfu),
    .pr_id(pr_id), .pr_wr(pr_wr), .pr_wdata(pr_wdata)
);

endmodule
