// System-level boundary for dual-PCB composition. Stage 2 deliberately keeps
// one complete board context while moving its communications RAM outside
// s32_core. A future second context can attach to the dormant bridge port and
// share p0 through s32_sdram_mux2 without changing the board-local core.
// This module is not selected in Arcade-SegaSystem32.sv yet: board.dual_pcb is
// loaded descriptor state at runtime and therefore cannot select a generate
// branch. Runtime selection between this wrapper and the direct core would
// duplicate the complete board context. Integration must instead deliberately
// choose either an always-wrapped production profile or the full two-context
// architecture; this milestone makes neither policy-expanding choice.
import s32_pkg::*;
module s32_dual_system #(
`ifdef S32_SYSTEM32_ONLY
    parameter SYSTEM32_ONLY = 1'b1
`else
    parameter SYSTEM32_ONLY = 1'b0
`endif
) (
    input clk_sys, input clk_ram,
`ifdef S32_REAL_V25
    input clk_v25,
`endif
    input rst, input video_rst, input board_desc_t board,
    input ce_cpu, input ce_z80, input ce_fm, input ce_pcm,
    input pause, input fast_v60, input alien3_hud_blend,
    output sdr_p0_req, output sdr_p0_burst, output [24:1] sdr_p0_addr,
    input [63:0] sdr_p0_dout, input sdr_p0_ack,
    output sdr_p1_req, output [24:3] sdr_p1_addr, input [63:0] sdr_p1_dout, input sdr_p1_ack,
    output sdr_p2_req, output [24:4] sdr_p2_addr, input [127:0] sdr_p2_dout, input sdr_p2_ack,
    output sdr_p3_req, output [24:1] sdr_p3_addr, input [15:0] sdr_p3_dout, input sdr_p3_ack,
    output sdr_p4_req, output [24:1] sdr_p4_addr, input [15:0] sdr_p4_dout, input sdr_p4_ack,
    output sdr_p5_req, output [24:3] sdr_p5_addr, input [63:0] sdr_p5_dout, input sdr_p5_ack,
    output fb_wr_start, output [1:0] fb_wr_buf, output [8:0] fb_wr_x,
    output [7:0] fb_wr_y, output fb_wr_valid, output [15:0] fb_wr_pix,
    output fb_wr_end, output fb_wr_shadow, input fb_wr_busy,
    output fb_er_req, output [1:0] fb_er_buf, output [7:0] fb_er_y, input fb_er_ack,
    output fb_rd_req, output [1:0] fb_rd_buf, output [1:0] fb_rd_blend_buf,
    output fb_rd_blend, output [7:0] fb_rd_y, input fb_rd_ack,
    output [8:0] fb_rd_x, input [15:0] fb_rd_pix,
    input v25_prg_wr, input [15:0] v25_prg_waddr, input [7:0] v25_prg_wdata,
    input eep_ld_wr, input [5:0] eep_ld_addr, input [15:0] eep_ld_data,
    output [15:0] eep_rd_data, input [5:0] eep_rd_addr,
    input eep_upload, output eep_modified,
    input [7:0] in_p1a, in_p2a, in_portc, in_svc12, in_svc34,
    input [7:0] in_p1b, in_p2b, in_portc_b, in_svc12_b, in_svc34_b,
    input [7:0] adc_ch [0:7], input trk_dv [0:2],
    input signed [8:0] trk_dx [0:2], input signed [8:0] trk_dy [0:2],
    input [7:0] trk_btn [0:2], input [7:0] ppi_pa, ppi_pb, ppi_pc,
    output [23:0] rgb_a, output [23:0] rgb_b, output ce_pix,
    output hs, output vs, output hb, output vb, output mode_416_active,
    output signed [15:0] audio_l, output signed [15:0] audio_r,
    output [7:0] out_lamps
);
wire dual_enable, dual_init_ff, dual_cs_ram, dual_cs_id, dual_we;
wire [1:0] dual_be;
wire [11:1] dual_addr;
wire [15:0] dual_wdata, dual_main_rdata, dual_sub_rdata;
wire dual_collision;

s32_core #(.SYSTEM32_ONLY(SYSTEM32_ONLY), .EXTERNAL_DUAL_BRIDGE(1'b1)) main_core (
    .*, .dual_ext_enable(dual_enable), .dual_ext_init_ff(dual_init_ff),
    .dual_ext_cs_ram(dual_cs_ram), .dual_ext_cs_id(dual_cs_id),
    .dual_ext_we(dual_we), .dual_ext_be(dual_be), .dual_ext_addr(dual_addr),
    .dual_ext_wdata(dual_wdata), .dual_ext_rdata(dual_main_rdata)
);

s32_dualpcb_bridge bridge (
    .clk(clk_sys), .rst(rst), .enable(dual_enable), .init_ff(dual_init_ff),
    .main_cs_ram(dual_cs_ram), .main_cs_id(dual_cs_id), .main_we(dual_we),
    .main_be(dual_be), .main_addr(dual_addr), .main_wdata(dual_wdata),
    .main_rdata(dual_main_rdata),
    .sub_cs_ram(1'b0), .sub_cs_id(1'b0), .sub_we(1'b0), .sub_be(2'b0),
    .sub_addr(11'b0), .sub_wdata(16'b0), .sub_rdata(dual_sub_rdata),
    .collision(dual_collision)
);
endmodule
