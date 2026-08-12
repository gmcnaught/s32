// Standalone EPR-14084 communication-board laboratory bus.
// Not included by either production profile. Memory map is evidence-backed;
// peripheral behavior is deliberately external until the devices are proven.
module epr14084_bus (
	input  wire        clk,
	input  wire        reset,
	input  wire [15:0] cpu_addr,
	input  wire  [7:0] cpu_dout,
	output reg   [7:0] cpu_din,
	input  wire        cpu_mreq_n,
	input  wire        cpu_iorq_n,
	input  wire        cpu_rd_n,
	input  wire        cpu_wr_n,
	input  wire        cpu_m1_n,
	output wire        cpu_wait_n,

	input  wire        rom_we,
	input  wire [14:0] rom_addr,
	input  wire  [7:0] rom_data,

	input  wire        host_en,
	input  wire        host_we,
	input  wire  [9:0] host_addr,
	input  wire  [1:0] host_be,
	input  wire [15:0] host_wdata,
	output reg  [15:0] host_rdata,

	input  wire        cn,
	input  wire        fg,
	input  wire        zfg,

	output wire        io_req,
	output wire        io_write,
	output wire  [7:0] io_addr,
	output wire  [7:0] io_wdata,
	input  wire        io_ack,
	input  wire  [7:0] io_rdata,
	output wire        io_dma_window,
	output wire        io_dlc_window,
	output wire        io_unknown_latch
);
	reg [7:0] rom [0:32767];
	reg [7:0] private_ram [0:8191];
	reg [7:0] shared_ram [0:2047];

	wire mem_rd = !cpu_mreq_n && !cpu_rd_n;
	wire mem_wr = !cpu_mreq_n && !cpu_wr_n;
	wire io_cycle = !cpu_iorq_n && cpu_m1_n && (!cpu_rd_n || !cpu_wr_n);

	assign io_req = io_cycle;
	assign io_write = !cpu_wr_n;
	assign io_addr = cpu_addr[7:0];
	assign io_wdata = cpu_dout;
	assign io_dma_window = io_cycle && (cpu_addr[7:4] == 4'h0);
	assign io_dlc_window = io_cycle && (cpu_addr[7:4] == 4'h2);
	assign io_unknown_latch = io_cycle && ((cpu_addr[7:0] == 8'h17) ||
		(cpu_addr[7:0] == 8'h40) || (cpu_addr[7:0] == 8'h60));
	// Interrupt acknowledge is not a peripheral read. T80 consumes DI as the
	// IM0 opcode; the external oracle must supply and acknowledge that cycle.
	wire int_ack = !cpu_iorq_n && !cpu_m1_n;
	assign cpu_wait_n = (io_cycle || int_ack) ? io_ack : 1'b1;

	always @* begin
		cpu_din = 8'hff;
		if (mem_rd) begin
			if (cpu_addr[15] == 1'b0) cpu_din = rom[cpu_addr[14:0]];
			else if (cpu_addr[15:13] == 3'b100) cpu_din = private_ram[cpu_addr[12:0]];
			else if (cpu_addr[15:11] == 5'b11000) cpu_din = shared_ram[cpu_addr[10:0]];
		end else if (io_cycle || int_ack) begin
			cpu_din = io_rdata;
		end
	end

	always @(posedge clk) begin
		if (rom_we) rom[rom_addr] <= rom_data;
		if (mem_wr && cpu_addr[15:13] == 3'b100) private_ram[cpu_addr[12:0]] <= cpu_dout;
		if (mem_wr && cpu_addr[15:11] == 5'b11000) shared_ram[cpu_addr[10:0]] <= cpu_dout;
		if (host_en && host_we && host_be[0]) shared_ram[{host_addr,1'b0}] <= host_wdata[7:0];
		if (host_en && host_we && host_be[1]) shared_ram[{host_addr,1'b1}] <= host_wdata[15:8];
		if (host_en) begin
			host_rdata[7:0] <= shared_ram[{host_addr,1'b0}];
			host_rdata[15:8] <= shared_ram[{host_addr,1'b1}];
		end
	end
endmodule
