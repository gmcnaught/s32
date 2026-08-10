// Fast-fetch routing regression: the wide port only represents the main ROM
// windows. Code copied to work/shared RAM must continue through the ordinary
// V60 bus even when optional ROM fetch is enabled.
`timescale 1ns/1ps

module tb_v60_fetch_ram;
reg clk = 0, rst = 1;
always #10 clk = ~clk;

wire c_req, c_we, c_ack;
wire [31:0] c_addr, c_wdata, c_rdata;
wire [1:0] c_size;
wire if_req;
wire [23:0] if_addr;
wire m_req, m_we, m_ack;
wire [23:1] m_addr;
wire [15:0] m_wdata, m_rdata;
wire [1:0] m_be;

s32_v60 #(.START_PC(32'h0020_0000), .FAST_IFETCH(1'b1)) cpu (
    .clk(clk), .ce(1'b1), .rst(rst), .fast_ifetch(1'b1),
    .if_req(if_req), .if_addr(if_addr), .if_data(64'hdead_beef_bad0_cafe),
    .if_ack(if_req),
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
        if (m_be[0]) ram[m_addr[16:1]][7:0]  <= m_wdata[7:0];
        if (m_be[1]) ram[m_addr[16:1]][15:8] <= m_wdata[15:8];
    end
end

integer ap, if_starts = 0, bus_starts = 0, cycles = 0;
reg if_prev, bus_prev;
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

always @(posedge clk) begin
    cycles <= cycles + 1;
    if_prev <= if_req;
    bus_prev <= m_req;
    if (if_req && !if_prev) if_starts <= if_starts + 1;
    if (m_req && !bus_prev) bus_starts <= bus_starts + 1;
end

initial begin
    for (ap = 0; ap < 65536; ap = ap + 1) ram[ap] = 16'h0000;
    ap = 0;
    // MOVW #$12345678,R1; HALT. RAM aliases 0x200000 at model index zero.
    ab(8'h2d); ab(8'h21); ab(8'hf4); aw32(32'h1234_5678); ab(8'h00);
    if_prev = 0; bus_prev = 0; ack_r = 0;
    repeat (8) @(posedge clk);
    rst = 0;
    while (!cpu.halted && cycles < 400) @(posedge clk);
    if (!cpu.halted || cpu.r[1] !== 32'h1234_5678 || if_starts != 0 || bus_starts == 0)
        $display("V60 FETCH RAM FAIL halt=%0d r1=%08x if=%0d bus=%0d",
                 cpu.halted, cpu.r[1], if_starts, bus_starts);
    else begin
        $display("V60 FETCH RAM SUMMARY if=%0d bus=%0d", if_starts, bus_starts);
        $display("V60 FETCH RAM PASS");
    end
    $finish;
end

initial begin
    #200000;
    $display("V60 FETCH RAM FAIL timeout");
    $finish;
end
endmodule
