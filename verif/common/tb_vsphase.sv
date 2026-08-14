`timescale 1ns/1ps
module tb_vsphase;
reg clk=0, rst=1;
reg [1:0] vs_phase=0;
wire ce_pix, mode_active, hblank, vblank, hsync, vsync, vbs, vbe;
wire [8:0] hcnt, vcnt;
s32_video dut(.clk(clk), .rst(rst), .mode_416(1'b0), .vs_phase(vs_phase),
  .ce_pix(ce_pix), .mode_active(mode_active), .hcnt(hcnt), .vcnt(vcnt),
  .hblank(hblank), .vblank(vblank), .hsync(hsync), .vsync(vsync),
  .vblank_start(vbs), .vblank_end(vbe));
always #10.35 clk=~clk;
integer f; reg pvs=0; realtime tvs=0, pvst=0;
reg [8:0] vs_line_on=0, vs_line_off=0; reg pv=0;
initial begin
  repeat(20) @(posedge clk); rst=0;
  for (f=0; f<9; f=f+1) begin
    if (f==3) vs_phase=2'd1;
    if (f==6) vs_phase=2'd2;
    // wait one full frame: vblank_end pulse
    @(posedge clk); while(!vbe) @(posedge clk);
    // record vsync lines within this frame
    pv=0;
    forever begin
      @(posedge clk);
      if (vsync && !pv) vs_line_on = vcnt;
      if (!vsync && pv) begin vs_line_off = vcnt; end
      pv = vsync;
      if (vbe) break;
    end
    $display("frame %0d phase=%0d vs_on_line=%0d vs_off_line=%0d", f, vs_phase, vs_line_on, vs_line_off);
  end
  // frame period check at phase=2
  @(posedge clk); while(!vbe) @(posedge clk); pvst=$realtime;
  @(posedge clk); while(!vbe) @(posedge clk); tvs=$realtime;
  $display("frame_period_ns=%0.1f (expect 805650 clk * 20.7ns = 16676955)", tvs-pvst);
  $finish;
end
endmodule
