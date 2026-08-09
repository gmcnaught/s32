// Sonic name-table command boundary: decoded MOVCFU.H clear, RSR back to the
// dispatcher continuation, then the ROM's MOV.H/INC.H/DBR fill primitive.
`timescale 1ns/1ps

module tb_v60_sonic_dispatch;
reg clk = 0, rst = 1;
always #10 clk = ~clk;

wire c_req, c_we, c_ack;
wire [31:0] c_addr, c_wdata, c_rdata;
wire [1:0] c_size;
wire m_req, m_we, m_ack;
wire [23:1] m_addr;
wire [15:0] m_wdata, m_rdata;
wire [1:0] m_be;

s32_v60 #(.START_PC(32'h0000_0000)) cpu (
    .clk(clk), .ce(1'b1), .rst(rst),
    .if_req(), .if_addr(), .if_data(64'd0), .if_ack(1'b0),
    .bus_req(c_req), .bus_we(c_we), .bus_addr(c_addr), .bus_size(c_size),
    .bus_wdata(c_wdata), .bus_rdata(c_rdata), .bus_ack(c_ack),
    .irq_n(1'b1), .irq_vector(8'h00), .irq_ack(), .nmi_n(1'b1)
);
s32_v60_bus adapter (
    .clk(clk), .ce(1'b1), .rst(rst),
    .c_req(c_req), .c_we(c_we), .c_addr(c_addr), .c_size(c_size),
    .c_wdata(c_wdata), .c_rdata(c_rdata), .c_ack(c_ack),
    .m_req(m_req), .m_we(m_we), .m_addr(m_addr), .m_wdata(m_wdata),
    .m_be(m_be), .m_rdata(m_rdata), .m_ack(m_ack)
);

reg [15:0] ram [0:65535];
reg ack_r;
assign m_rdata = ram[m_addr[16:1]];
assign m_ack = ack_r;
always @(posedge clk) begin
    ack_r <= m_req & ~ack_r;
    if (m_req && m_we && !ack_r) begin
        if (m_be[0]) ram[m_addr[16:1]][7:0] <= m_wdata[7:0];
        if (m_be[1]) ram[m_addr[16:1]][15:8] <= m_wdata[15:8];
    end
end

integer ap, i, writes;
integer continuation;
task ab(input [7:0] b);
    begin
        if (ap[0]) ram[ap>>1][15:8] = b;
        else       ram[ap>>1][7:0] = b;
        ap = ap + 1;
    end
endtask
task aw32(input [31:0] w);
    begin ab(w[7:0]); ab(w[15:8]); ab(w[23:16]); ab(w[31:24]); end
endtask
task movi(input [4:0] rn, input [31:0] value);
    begin ab(8'h2d); ab(8'h20 | rn); ab(8'hf4); aw32(value); end
endtask

always @(posedge clk)
    if (m_req && m_we && !ack_r && {m_addr,1'b0} >= 24'h008000 &&
        {m_addr,1'b0} < 24'h008400)
        writes <= writes + 1;

initial begin
    for (i = 0; i < 65536; i = i + 1) ram[i] = 16'ha5a5;
    writes = 0;
    ram[16'h0100] = 16'h0900;
    ap = 0;

    movi(5'd31, 32'h0001_0000); // SP
    movi(5'd10, 32'h0000_0200); // source base
    movi(5'd11, 32'h0000_8000); // clear destination
    movi(5'd26, 32'h0000_0000); // zero-length source/fill value
    movi(5'd0,  32'h0000_0200); // 512 halfwords
    // Preload the RSR return PC through a normal V60 store.
    continuation = ap + 7 + 7 + 6 + 1;
    movi(5'd2, continuation);
    ab(8'h2d); ab(8'h02); ab(8'hf3); aw32(32'h0001_0000);

    // Exact Sonic instruction at 0x9994e and its RSR at 0x99954.
    ab(8'h5a); ab(8'h8a); ab(8'h6a); ab(8'h9a); ab(8'h6b); ab(8'h80);
    ab(8'hca);

    // Dispatcher continuation: select the same destination, then command 0x89.
    movi(5'd10, 32'h0000_0200);
    movi(5'd11, 32'h0000_8000);
    movi(5'd1, 32'h0000_0003);
    ab(8'h1b); ab(8'h60); ab(8'h8a); // mov.h [R10+],R0
    ab(8'h1b); ab(8'h40); ab(8'h8b); // mov.h R0,[R11+]
    ab(8'hdb); ab(8'h60);             // inc.h R0
    ab(8'hc6); ab(8'ha1); ab(8'hfb); ab(8'hff); // dbr R1,-5
    ab(8'h00);

    repeat (8) @(posedge clk);
    rst = 0;
    repeat (30000) @(posedge clk);

    $display("pc=%08x sp=%08x writes=%0d dst=%04x,%04x,%04x,%04x",
        cpu.pc, cpu.r[31], writes, ram[16'h4000], ram[16'h4001],
        ram[16'h4002], ram[16'h4003]);
    if (cpu.halted && cpu.r[31] == 32'h0001_0004 && writes == 515 &&
        ram[16'h4000] == 16'h0900 && ram[16'h4001] == 16'h0901 &&
        ram[16'h4002] == 16'h0902 && ram[16'h4003] == 16'h0000 &&
        ram[16'h41ff] == 16'h0000)
        $display("SONIC DISPATCH PASS");
    else
        $display("SONIC DISPATCH FAIL");
    $finish;
end
endmodule
