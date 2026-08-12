// One physical V60 execution engine, with two complete state banks.  External
// transactions are retained and tagged here because a context may be inactive
// when its independently connected target returns the response.
module s32_v60_dualctx #(
    parameter [31:0] START_PC = 32'hfffffff0,
    parameter FAST_IFETCH = 1'b0
)(
    input clk,
    input ce0, input rst0, input fast_ifetch0,
    input irq_n0, input [7:0] irq_vector0, input nmi_n0,
    output irq_ack0,
    output if_req0, output [23:0] if_addr0, input [63:0] if_data0, input if_ack0,
    output bus_req0, output bus_we0, output [31:0] bus_addr0,
    output [1:0] bus_size0, output [31:0] bus_wdata0,
    input [31:0] bus_rdata0, input bus_ack0,

    input ce1, input rst1, input fast_ifetch1,
    input irq_n1, input [7:0] irq_vector1, input nmi_n1,
    output irq_ack1,
    output if_req1, output [23:0] if_addr1, input [63:0] if_data1, input if_ack1,
    output bus_req1, output bus_we1, output [31:0] bus_addr1,
    output [1:0] bus_size1, output [31:0] bus_wdata1,
    input [31:0] bus_rdata1, input bus_ack1,
    output active_context
);

wire core_if_req, core_bus_req, core_bus_we, core_irq_ack;
wire [23:0] core_if_addr;
wire [31:0] core_bus_addr, core_bus_wdata;
wire [1:0] core_bus_size;
reg [1:0] bus_pending = 0, bus_response = 0;
reg [1:0] if_pending = 0, if_response = 0;
reg [31:0] bus_addr_q[0:1], bus_wdata_q[0:1], bus_rdata_q[0:1];
reg [1:0] bus_size_q[0:1];
reg bus_we_q[0:1];
reg [23:0] if_addr_q[0:1];
reg [63:0] if_data_q[0:1];
assign active_context = engine.v60_active_ctx;

wire core_bus_ack = active_context ? bus_response[1] : bus_response[0];
wire core_if_ack  = active_context ? if_response[1] : if_response[0];
wire [31:0] core_bus_rdata = active_context ? bus_rdata_q[1] : bus_rdata_q[0];
wire [63:0] core_if_data = active_context ? if_data_q[1] : if_data_q[0];

assign bus_req0 = bus_pending[0]; assign bus_req1 = bus_pending[1];
assign bus_we0 = bus_we_q[0]; assign bus_we1 = bus_we_q[1];
assign bus_addr0 = bus_addr_q[0]; assign bus_addr1 = bus_addr_q[1];
assign bus_size0 = bus_size_q[0]; assign bus_size1 = bus_size_q[1];
assign bus_wdata0 = bus_wdata_q[0]; assign bus_wdata1 = bus_wdata_q[1];
assign if_req0 = if_pending[0]; assign if_req1 = if_pending[1];
assign if_addr0 = if_addr_q[0]; assign if_addr1 = if_addr_q[1];
assign irq_ack0 = core_irq_ack && !active_context;
assign irq_ack1 = core_irq_ack && active_context;

always @(posedge clk) begin
    if ((!active_context && rst0) || (active_context && rst1)) begin
        bus_pending[active_context] <= 1'b0;
        bus_response[active_context] <= 1'b0;
        if_pending[active_context] <= 1'b0;
        if_response[active_context] <= 1'b0;
    end else begin
        if (core_bus_req && !bus_pending[active_context] && !bus_response[active_context]) begin
            bus_pending[active_context] <= 1'b1;
            bus_we_q[active_context] <= core_bus_we;
            bus_addr_q[active_context] <= core_bus_addr;
            bus_size_q[active_context] <= core_bus_size;
            bus_wdata_q[active_context] <= core_bus_wdata;
        end
        if (core_if_req && !if_pending[active_context] && !if_response[active_context]) begin
            if_pending[active_context] <= 1'b1;
            if_addr_q[active_context] <= core_if_addr;
        end
        if (core_bus_ack) bus_response[active_context] <= 1'b0;
        if (core_if_ack) if_response[active_context] <= 1'b0;
    end
    // A reset dominates an ACK for that issuer even when the response arrives
    // on the same raw edge; this prevents pre-reset data entering a fresh epoch.
    if (bus_ack0 && bus_pending[0] && !rst0) begin
        bus_pending[0] <= 1'b0; bus_response[0] <= 1'b1; bus_rdata_q[0] <= bus_rdata0;
    end
    if (bus_ack1 && bus_pending[1] && !rst1) begin
        bus_pending[1] <= 1'b0; bus_response[1] <= 1'b1; bus_rdata_q[1] <= bus_rdata1;
    end
    if (if_ack0 && if_pending[0] && !rst0) begin
        if_pending[0] <= 1'b0; if_response[0] <= 1'b1; if_data_q[0] <= if_data0;
    end
    if (if_ack1 && if_pending[1] && !rst1) begin
        if_pending[1] <= 1'b0; if_response[1] <= 1'b1; if_data_q[1] <= if_data1;
    end
end

// Both contexts currently share the architectural reset vector, as do the two
// System 32 main CPUs.  Distinct program images are supplied by their buses.
s32_v60 #(.CONTEXTS(2), .START_PC(START_PC), .FAST_IFETCH(FAST_IFETCH)) engine (
    .clk(clk), .ce(active_context ? ce1 : ce0),
    .rst(active_context ? rst1 : rst0),
    .fast_ifetch(active_context ? fast_ifetch1 : fast_ifetch0),
    .if_req(core_if_req), .if_addr(core_if_addr), .if_data(core_if_data), .if_ack(core_if_ack),
    .bus_req(core_bus_req), .bus_we(core_bus_we), .bus_addr(core_bus_addr),
    .bus_size(core_bus_size), .bus_wdata(core_bus_wdata),
    .bus_rdata(core_bus_rdata), .bus_ack(core_bus_ack),
    .irq_n(active_context ? irq_n1 : irq_n0),
    .irq_vector(active_context ? irq_vector1 : irq_vector0),
    .irq_ack(core_irq_ack), .nmi_n(active_context ? nmi_n1 : nmi_n0)
);

endmodule
