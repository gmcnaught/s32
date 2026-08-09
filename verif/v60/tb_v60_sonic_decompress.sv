// Focused reproduction of Sonic's name-table fill primitive at 0x0998ec.
// The instruction bytes are taken directly from the parent ROM:
//   mov.h [R10+],R0; mov.h R0,[R11+]; inc.h R0; dbr R1,<store>
`timescale 1ns/1ps

module tb_v60_sonic_decompress;
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

always @(posedge clk)
    if (m_req && m_we && !ack_r && {m_addr,1'b0} >= 24'h008000)
        writes <= writes + 1;

initial begin
    for (i = 0; i < 65536; i = i + 1) ram[i] = 16'h0000;
    writes = 0;
    ram[16'h0100] = 16'h0900;
    ap = 0;

    // MOVW #$00000200,R10; MOVW #$00008000,R11; MOVW #3,R1
    ab(8'h2d); ab(8'h2a); ab(8'hf4); aw32(32'h0000_0200);
    ab(8'h2d); ab(8'h2b); ab(8'hf4); aw32(32'h0000_8000);
    ab(8'h2d); ab(8'h21); ab(8'hf4); aw32(32'h0000_0003);
    // Exact Sonic primitive; DBR displacement is relative to its opcode PC.
    ab(8'h1b); ab(8'h60); ab(8'h8a); // mov.h [R10+],R0
    ab(8'h1b); ab(8'h40); ab(8'h8b); // mov.h R0,[R11+]
    ab(8'hdb); ab(8'h60);             // inc.h R0
    ab(8'hc6); ab(8'ha1); ab(8'hfb); ab(8'hff); // dbr R1,-5
    ab(8'h00);

    repeat (8) @(posedge clk);
    rst = 0;
    repeat (4000) @(posedge clk);

    $display("r0=%08x r1=%08x r10=%08x r11=%08x writes=%0d dst=%04x,%04x,%04x",
        cpu.r[0], cpu.r[1], cpu.r[10], cpu.r[11], writes,
        ram[16'h4000], ram[16'h4001], ram[16'h4002]);
    if (cpu.halted && cpu.r[1] == 0 && cpu.r[10] == 32'h202 &&
        cpu.r[11] == 32'h8006 && writes == 3 &&
        ram[16'h4000] == 16'h0900 && ram[16'h4001] == 16'h0901 &&
        ram[16'h4002] == 16'h0902)
        $display("SONIC DECOMPRESS PASS");
    else
        $display("SONIC DECOMPRESS FAIL");
    $finish;
end
endmodule
