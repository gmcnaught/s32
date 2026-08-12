// Disabled-by-default native EPR-14084 diagnostic shadow. Unknown peripherals
// and IM0 acknowledge remain explicit external transactions; no reply is made
// locally. The existing frame-level communication HLE stays authoritative.
module s32_epr14084_shadow #(parameter ENABLE_NATIVE_SHADOW=1'b0)(
 input clk,input rst,input ce,
 input rom_we,input[14:0]rom_addr,input[7:0]rom_data,
 input host_en,input host_we,input[9:0]host_addr,input[1:0]host_be,input[15:0]host_wdata,
 output[15:0]host_rdata,input cn,input fg,input zfg,
 output io_req,output io_write,output[7:0]io_addr,output[7:0]io_wdata,
 input io_ack,input[7:0]io_rdata,input int_n,
 output dma_window,output dlc_window,output unknown_latch,
 input[15:0]authoritative_host_rdata,output ram_diverged,
 output reg first_out60,output reg[7:0]first_out60_data);
wire run_ce=ce&&ENABLE_NATIVE_SHADOW;
`ifndef SIMULATION
epr14084_lab native(.clk(clk),.ce(run_ce),.reset(rst||!ENABLE_NATIVE_SHADOW),
 .rom_we(rom_we),.rom_addr(rom_addr),.rom_data(rom_data),.host_en(host_en),.host_we(host_we),
 .host_addr(host_addr),.host_be(host_be),.host_wdata(host_wdata),.host_rdata(host_rdata),
 .cn(cn),.fg(fg),.zfg(zfg),.io_req(io_req),.io_write(io_write),.io_addr(io_addr),
 .io_wdata(io_wdata),.io_ack(io_ack),.io_rdata(io_rdata),.io_dma_window(dma_window),
 .io_dlc_window(dlc_window),.io_unknown_latch(unknown_latch),.int_n(int_n));
`else
assign host_rdata=0;assign io_req=0;assign io_write=0;assign io_addr=0;assign io_wdata=0;
assign dma_window=0;assign dlc_window=0;assign unknown_latch=0;
`endif
assign ram_diverged=ENABLE_NATIVE_SHADOW&&host_en&&!host_we&&
                    (host_rdata!=authoritative_host_rdata);
always @(posedge clk) begin
 if(rst)begin first_out60<=0;first_out60_data<=0;end
 else if(ENABLE_NATIVE_SHADOW&&io_req&&io_write&&io_addr==8'h60&&!first_out60)begin
  first_out60<=1;first_out60_data<=io_wdata;
 end
end
endmodule
