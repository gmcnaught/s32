`timescale 1ns/1ps
module tb_dual_system_single;
import s32_pkg::*;
reg clk=0, rst=1; always #5 clk=~clk;
board_desc_t board='0;
wire [7:0] adc_ch[0:7]; wire trk_dv[0:2];
wire signed [8:0] trk_dx[0:2],trk_dy[0:2]; wire [7:0] trk_btn[0:2];
for(genvar i=0;i<8;i++)assign adc_ch[i]=8'h80;
for(genvar j=0;j<3;j++)begin assign trk_dv[j]=0;assign trk_dx[j]=0;assign trk_dy[j]=0;assign trk_btn[j]=8'hff;end
wire p0r,p0b;wire[24:1]p0a;wire[23:0]ra,rb;wire cp,hs,vs,hb,vb,m416;wire signed[15:0]al,ar;
s32_dual_system dut(
 .clk_sys(clk),.clk_ram(clk),.rst(rst),.video_rst(rst),.board(board),
 .ce_cpu('0),.ce_z80('0),.ce_fm('0),.ce_pcm('0),.pause('0),.fast_v60('0),.alien3_hud_blend('0),
 .sdr_p0_req(p0r),.sdr_p0_burst(p0b),.sdr_p0_addr(p0a),.sdr_p0_dout('0),.sdr_p0_ack('0),
 .sdr_p1_dout('0),.sdr_p1_ack('0),.sdr_p2_dout('0),.sdr_p2_ack('0),
 .sdr_p3_dout('0),.sdr_p3_ack('0),.sdr_p4_dout('0),.sdr_p4_ack('0),.sdr_p5_dout('0),.sdr_p5_ack('0),
 .fb_wr_busy('0),.fb_er_ack('0),.fb_rd_ack('0),.fb_rd_pix('0),
 .v25_prg_wr('0),.v25_prg_waddr('0),.v25_prg_wdata('0),
 .eep_ld_wr('0),.eep_ld_addr('0),.eep_ld_data('0),.eep_rd_addr('0),.eep_upload('0),
 .in_p1a(8'hff),.in_p2a(8'hff),.in_portc(8'hff),.in_svc12(8'hff),.in_svc34(8'hff),
 .in_p1b(8'hff),.in_p2b(8'hff),.in_portc_b(8'hff),.in_svc12_b(8'hff),.in_svc34_b(8'hff),
 .adc_ch(adc_ch),.trk_dv(trk_dv),.trk_dx(trk_dx),.trk_dy(trk_dy),.trk_btn(trk_btn),
 .ppi_pa(8'hff),.ppi_pb(8'hff),.ppi_pc(8'hff),.rgb_a(ra),.rgb_b(rb),.ce_pix(cp),
 .hs(hs),.vs(vs),.hb(hb),.vb(vb),.mode_416_active(m416),.audio_l(al),.audio_r(ar)
);
initial begin
 board.dual_pcb=1; repeat(4)@(posedge clk);#1;
 if(dut.main_core.EXTERNAL_DUAL_BRIDGE!==1)$fatal(1,"external bridge boundary disabled");
 if(dut.dual_enable!==1)$fatal(1,"descriptor did not enable bridge");
 if(ra!==dut.main_core.rgb_a || al!==dut.main_core.audio_l || p0r!==dut.main_core.sdr_p0_req)
   $fatal(1,"wrapper altered a forwarded board interface");
 rst=0; repeat(4)@(posedge clk);#1;
 if(dut.dual_main_rdata!==16'h0000)$fatal(1,"single-context bridge reset value changed");
 $display("DUAL SYSTEM SINGLE PASS");$finish;
end
initial begin #10000;$display("DUAL SYSTEM SINGLE FAIL timeout");$finish;end
endmodule
