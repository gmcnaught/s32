// Two-client adapter for one read-only System 32 SDRAM port.
// The downstream controller accepts a rising request edge, allows one
// outstanding transaction and stretches ack until req drops. Address, burst
// and ownership are therefore latched from grant through acknowledgement.
module s32_sdram_mux2 #(
    parameter MAIN_ONLY = 1'b0
) (
    input             clk,
    input             rst,
    input             main_req,
    input             main_burst,
    input      [24:1] main_addr,
    output     [63:0] main_dout,
    output            main_ack,
    input             sub_req,
    input             sub_burst,
    input      [24:1] sub_addr,
    output     [63:0] sub_dout,
    output            sub_ack,
    output            mem_req,
    output            mem_burst,
    output     [24:1] mem_addr,
    input      [63:0] mem_dout,
    input             mem_ack
);

generate if (MAIN_ONLY) begin : g_bypass
    assign mem_req    = main_req;
    assign mem_burst  = main_burst;
    assign mem_addr   = main_addr;
    assign main_dout  = mem_dout;
    assign main_ack   = mem_ack;
    assign sub_dout   = 64'b0;
    assign sub_ack    = 1'b0;
end else begin : g_arbiter
    localparam IDLE = 2'd0, ACTIVE = 2'd1, COOLDOWN = 2'd2;
    reg [1:0] state;
    reg owner;
    reg last_owner;
    reg main_armed, sub_armed;
    reg burst_latched;
    reg [24:1] addr_latched;

    wire main_ready = main_req && main_armed;
    wire sub_ready  = sub_req  && sub_armed;
    wire choose_sub = sub_ready && (!main_ready || !last_owner);

    always @(posedge clk) begin
        if (rst) begin
            state         <= IDLE;
            owner         <= 1'b0;
            last_owner    <= 1'b1; // first simultaneous grant goes to main
            main_armed    <= 1'b1;
            sub_armed     <= 1'b1;
            burst_latched <= 1'b0;
            addr_latched  <= 24'b0;
        end else begin
            if (!main_req) main_armed <= 1'b1;
            if (!sub_req)  sub_armed  <= 1'b1;
            case (state)
                IDLE: begin
                    if (main_ready || sub_ready) begin
                        owner <= choose_sub;
                        last_owner <= choose_sub;
                        if (choose_sub) begin
                            sub_armed <= 1'b0;
                            burst_latched <= sub_burst;
                            addr_latched <= sub_addr;
                        end else begin
                            main_armed <= 1'b0;
                            burst_latched <= main_burst;
                            addr_latched <= main_addr;
                        end
                        state <= ACTIVE;
                    end
                end
                ACTIVE: if (mem_ack) state <= COOLDOWN;
                COOLDOWN: if (!mem_ack) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end

    assign mem_req   = state == ACTIVE;
    assign mem_burst = burst_latched;
    assign mem_addr  = addr_latched;
    assign main_ack  = (state == ACTIVE) && !owner && mem_ack;
    assign sub_ack   = (state == ACTIVE) &&  owner && mem_ack;
    // Data is meaningful only alongside the owning acknowledgement. Gating it
    // as well makes accidental cross-client sampling observable and benign.
    assign main_dout = ((state == ACTIVE) && !owner) ? mem_dout : 64'b0;
    assign sub_dout  = ((state == ACTIVE) &&  owner) ? mem_dout : 64'b0;
end endgenerate
endmodule
