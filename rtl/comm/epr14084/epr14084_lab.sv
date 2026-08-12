// EPR-14084 native-firmware execution lab. This is intentionally absent from
// files.qip and the production profile manifests.
module epr14084_lab (
	input wire clk, input wire ce, input wire reset,
	input wire rom_we, input wire [14:0] rom_addr, input wire [7:0] rom_data,
	input wire host_en, input wire host_we, input wire [9:0] host_addr,
	input wire [1:0] host_be, input wire [15:0] host_wdata, output wire [15:0] host_rdata,
	input wire cn, input wire fg, input wire zfg,
	output wire io_req, output wire io_write, output wire [7:0] io_addr,
	output wire [7:0] io_wdata, input wire io_ack, input wire [7:0] io_rdata,
	output wire io_dma_window, output wire io_dlc_window,
	output wire io_unknown_latch,
	input wire int_n
);
	wire [15:0] a; wire [7:0] di, dout;
	wire m1_n, mreq_n, iorq_n, rd_n, wr_n, wait_n;
	T80s cpu(.RESET_n(!reset), .CLK(clk), .CEN(ce), .WAIT_n(wait_n),
		.INT_n(int_n), .NMI_n(1'b1), .BUSRQ_n(1'b1), .M1_n(m1_n),
		.MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n),
		.RFSH_n(), .HALT_n(), .BUSAK_n(), .OUT0(1'b0), .A(a), .DI(di),
		.DO(dout), .REG(), .DIRSet(1'b0), .DIR(230'd0), .ISet_out());
	epr14084_bus bus(.clk(clk), .reset(reset), .cpu_addr(a), .cpu_dout(dout),
		.cpu_din(di), .cpu_mreq_n(mreq_n), .cpu_iorq_n(iorq_n),
		.cpu_rd_n(rd_n), .cpu_wr_n(wr_n), .cpu_m1_n(m1_n), .cpu_wait_n(wait_n),
		.rom_we(rom_we), .rom_addr(rom_addr), .rom_data(rom_data),
		.host_en(host_en), .host_we(host_we), .host_addr(host_addr),
		.host_be(host_be), .host_wdata(host_wdata), .host_rdata(host_rdata), .cn(cn), .fg(fg),
		.zfg(zfg), .io_req(io_req), .io_write(io_write), .io_addr(io_addr),
		.io_wdata(io_wdata), .io_ack(io_ack), .io_rdata(io_rdata),
		.io_dma_window(io_dma_window), .io_dlc_window(io_dlc_window),
		.io_unknown_latch(io_unknown_latch));
endmodule
