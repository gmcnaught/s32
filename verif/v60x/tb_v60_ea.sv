//============================================================================
//  tb_v60_ea -- every addressing mode, resolved against a real bus.
//
//  v60_ea drives v60_dxu drives v60_biu drives the two-bank memory model from
//  tb_v60_dxu, so an address this computes is checked by what comes back from
//  the byte that is actually there.  A mode that lands one byte off reads a
//  different value; a mode that indirects when it should not reads a pointer
//  as though it were data.
//
//  Three things are asserted for every mode: the effective ADDRESS, the
//  operand VALUE that address produced, and the number of BUS CYCLES the whole
//  operand reference took -- the quantity docs/v60/v60_operand_access.csv is
//  denominated in, now measurable per mode.
//============================================================================
`timescale 1ns/1ps

module tb_v60_ea;
    import v60_bus_pkg::*;
    import v60_am_pkg::*;

localparam integer DIV = 6;

reg clk = 1'b0;
always #5 clk = ~clk;

reg rst = 1'b1;

reg [2:0] tick = 3'd0;
always @(posedge clk) if (!rst) tick <= (tick == DIV-1) ? 3'd0 : tick + 3'd1;
wire ce_rise = !rst && (tick == 3'd0);
wire ce_fall = !rst && (tick == DIV/2);

// ---- the operand under test ------------------------------------------------
reg          e_start = 1'b0, e_index = 1'b0, e_we = 1'b0;
am_mode_e    e_mode  = AM_RN;
reg   [31:0] e_disp = 32'd0, e_outer = 32'd0;
reg   [63:0] e_imm = 64'd0, e_wdata = 64'd0;
reg   [31:0] e_rn = 32'd0, e_rx = 32'd0, e_pc = 32'd0;
reg    [3:0] e_bytes = 4'd2;

wire  [31:0] e_ea, e_wb_val;
wire  [63:0] e_rdata;
wire         e_wb, e_illegal, e_busy, e_done;
wire   [3:0] e_cycles;

// ---- ea <-> dxu ------------------------------------------------------------
wire         dx_req, dx_we, dx_done;
wire  [23:0] dx_addr;
wire   [3:0] dx_nbytes, dx_cycles;
wire  [63:0] dx_wdata, dx_rdata;

v60_ea dut (
    .clk(clk), .rst(rst),
    .start(e_start), .mode(e_mode), .has_index(e_index),
    .disp(e_disp), .disp_outer(e_outer), .imm(e_imm),
    .rn_val(e_rn), .rx_val(e_rx), .pc_val(e_pc),
    .opbytes(e_bytes), .we(e_we), .io(1'b0), .lock(1'b0), .wdata(e_wdata),
    .ea(e_ea), .rdata(e_rdata), .rn_wb(e_wb), .rn_wb_val(e_wb_val),
    .illegal(e_illegal), .busy(e_busy), .done(e_done), .bus_cycles(e_cycles),
    .dx_req(dx_req), .dx_addr(dx_addr), .dx_nbytes(dx_nbytes), .dx_we(dx_we),
    .dx_io(), .dx_lock(),
    .dx_wdata(dx_wdata), .dx_rdata(dx_rdata), .dx_done(dx_done),
    .dx_cycles(dx_cycles)
);

// ---- dxu <-> biu -----------------------------------------------------------
wire         biu_req, biu_we, biu_ube, biu_first, biu_ack;
bus_status_e biu_status;
wire  [23:0] biu_addr;
wire   [1:0] biu_dl;
wire  [15:0] biu_wdata, biu_rdata;

v60_dxu dxu (
    .clk(clk), .rst(rst),
    .req(dx_req), .addr(dx_addr), .nbytes(dx_nbytes), .we(dx_we), .io(1'b0), .lock(1'b0), .intack(1'b0),
    .wdata(dx_wdata), .rdata(dx_rdata), .busy(), .done(dx_done),
    .cycles(dx_cycles),
    .biu_req(biu_req), .biu_status(biu_status), .biu_addr(biu_addr),
    .biu_we(biu_we), .biu_dl(biu_dl), .biu_ube(biu_ube), .biu_first(biu_first),
    .biu_wdata(biu_wdata), .biu_ack(biu_ack), .biu_rdata(biu_rdata)
);

wire [23:0] a;
wire  [1:0] dl_o;
wire  [2:0] st;
wire        mrq_n, rw_n, ube_n, fas_n, bcy_n, ds_n, d_oe, bus_hiz, hldak_n;
wire [15:0] d_out;
reg  [15:0] d_in;
bus_state_e state;

v60_biu biu (
    .clk(clk), .rst(rst), .ce_rise(ce_rise), .ce_fall(ce_fall),
    .req(biu_req), .status(biu_status), .addr(biu_addr), .we(biu_we),
    .dl(biu_dl), .ube(biu_ube), .first(biu_first), .lock(1'b0), .wdata(biu_wdata),
    .ack(biu_ack), .rdata(biu_rdata), .busy(),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .block_n(), .ds_n(ds_n),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .bus_hiz(bus_hiz),
    .ready_n(1'b0), .bmode(1'b1), .hldrq_n(1'b1), .hldak_n(hldak_n),
    .berr_n(1'b1), .rt_ep_n(1'b1), .nmi_n(1'b1), .int_req(1'b0),
    .berr(), .berr_status(), .berr_addr(), .berr_we(), .berr_retry(),
    .nmi_pending(), .nmi_take(1'b0), .int_pending(),
    .state(state)
);

// ---- the memory, in two byte-wide banks ------------------------------------
reg  [7:0] mem [0:1023];
wire [9:0] bank_even = {a[9:1], 1'b0};
always @(*) d_in = {mem[bank_even + 10'd1], mem[bank_even]};

integer nack = 0;
always @(posedge clk) if (!rst && biu_ack) begin
    nack = nack + 1;
    if (!rw_n) begin
        case ({ube_n, a[0]})
            2'b00: begin mem[bank_even] = d_out[7:0];
                         mem[bank_even + 10'd1] = d_out[15:8]; end
            2'b01: mem[bank_even + 10'd1] = d_out[15:8];
            2'b10: mem[bank_even] = d_out[7:0];
            default: ;
        endcase
    end
end

// The register writeback is a one-cycle pulse, so it is caught here rather
// than looked for after the fact.
reg        wb_seen = 1'b0;
reg [31:0] wb_val_r = 32'd0;
always @(posedge clk) if (!rst && e_wb) begin
    wb_seen  = 1'b1;
    wb_val_r = e_wb_val;
end

integer errors = 0;
task chk(input cond, input [8*72:1] what);
begin
    if (!cond) begin
        errors = errors + 1;
        $display("FAIL  %0s (t=%0t)", what, $time);
    end
end
endtask

task go;
begin
    @(negedge clk);
    nack    = 0;
    wb_seen = 1'b0;
    e_start = 1'b1;
    @(negedge clk);
    e_start = 1'b0;
    while (!e_done) @(negedge clk);
    @(negedge clk);
end
endtask

// Reset the description between operands, so a stale field cannot pass a test.
task setup(input [4:0] mode_in, input [3:0] nb, input w);
begin
    e_mode  = am_mode_e'(mode_in);
    e_bytes = nb;
    e_we    = w;
    e_index = 1'b0;
    e_disp  = 32'd0;
    e_outer = 32'd0;
    e_imm   = 64'd0;
    e_wdata = 64'd0;
    e_rn    = 32'd0;
    e_rx    = 32'd0;
    e_pc    = 32'd0;
end
endtask

integer i;

// A halfword of the pattern, for the checks below.
function [15:0] hw(input [9:0] addr);
    hw = {mem[addr + 10'd1], mem[addr]};
endfunction

initial begin
    for (i = 0; i < 1024; i = i + 1) mem[i] = i[7:0] + 8'h40;

    // Two pointers, four bytes apart, so that indexing the wrong side of an
    // indirection reads the other one.
    mem[10'h300] = 8'h00; mem[10'h301] = 8'h04; mem[10'h302] = 8'h00; mem[10'h303] = 8'h00;
    mem[10'h304] = 8'h00; mem[10'h305] = 8'h05; mem[10'h306] = 8'h00; mem[10'h307] = 8'h00;

    repeat (4) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);

    // =======================================================================
    // The two modes that never reach the bus.
    // =======================================================================
    setup(AM_RN, 4'd4, 1'b0); e_rn = 32'h12345678; go;
    chk(e_rdata[31:0] === 32'h12345678, "Rn: the operand is the register");
    chk(e_cycles === 4'd0 && nack == 0,  "Rn: no bus cycle at all");

    setup(AM_RN, 4'd4, 1'b1); e_rn = 32'h12345678; e_wdata = 64'h0000DEAD; go;
    chk(wb_seen === 1'b1,          "Rn write: the register is written back");
    chk(wb_val_r === 32'h0000DEAD, "Rn write: with the value the instruction supplied");
    chk(nack == 0,                 "Rn write: still no bus cycle");

    setup(AM_IMMED, 4'd2, 1'b0); e_imm = 64'hABCD; go;
    chk(e_rdata[15:0] === 16'hABCD, "immediate: the operand is in the instruction");
    chk(e_cycles === 4'd0 && nack == 0, "immediate: no bus cycle");
    chk(e_illegal === 1'b0, "immediate: reading one is legal");

    setup(AM_IMMED, 4'd2, 1'b1); e_imm = 64'hABCD; go;
    chk(e_illegal === 1'b1, "immediate: writing one is the illegal addressing mode exception");
    chk(nack == 0,          "immediate: an illegal write makes no bus cycle");

    // =======================================================================
    // The address a mode names, checked by the byte that is there.
    // =======================================================================
    setup(AM_RN_IND, 4'd2, 1'b0); e_rn = 32'h00000100; go;
    chk(e_ea === 32'h00000100,        "[Rn]: the address is the register");
    chk(e_rdata[15:0] === hw(10'h100), "[Rn]: reads what is at Rn");
    chk(e_cycles === 4'd1,            "[Rn]: an aligned halfword is one bus cycle");
    chk(wb_seen === 1'b0,             "[Rn]: nothing is written back to Rn");

    // "Disp = signed displacement" -- a negative one has to walk backwards.
    setup(AM_DISP8, 4'd2, 1'b0); e_rn = 32'h00000110; e_disp = 32'hFFFFFFF0; go;
    chk(e_ea === 32'h00000100,        "disp.8[Rn]: a negative displacement subtracts");
    chk(e_rdata[15:0] === hw(10'h100), "disp.8[Rn]: reads what is at Rn+disp");

    setup(AM_PCDISP16, 4'd2, 1'b0); e_pc = 32'h00000200; e_disp = 32'h00000100; go;
    chk(e_ea === 32'h00000300,        "disp.16[PC]: the base is the PC, not a register");

    setup(AM_ADDR, 4'd2, 1'b0); e_rn = 32'hDEADBEEF; e_disp = 32'h00000400; go;
    chk(e_ea === 32'h00000400,        "/addr: the address is in the instruction and Rn is ignored");
    chk(e_rdata[15:0] === hw(10'h400), "/addr: reads what is at that address");

    // =======================================================================
    // Indirection: the address is in memory, and reading it costs bus cycles
    // before the operand does.
    // =======================================================================
    setup(AM_DISP8_IND, 4'd2, 1'b0); e_rn = 32'h00000300; go;
    chk(e_ea === 32'h00000400,        "[disp.8[Rn]]: the address is what the pointer holds");
    chk(e_rdata[15:0] === hw(10'h400), "[disp.8[Rn]]: reads through the pointer");
    chk(e_cycles === 4'd3,            "[disp.8[Rn]]: two cycles for the pointer, one for the operand");

    setup(AM_DDISP8, 4'd2, 1'b0); e_rn = 32'h00000300; e_outer = 32'h00000004; go;
    chk(e_ea === 32'h00000404,        "disp1[disp2[Rn]]: the outer displacement is added to the pointer");
    chk(e_rdata[15:0] === hw(10'h404), "disp1[disp2[Rn]]: reads there");
    chk(e_cycles === 4'd3,            "disp1[disp2[Rn]]: pointer plus operand");

    setup(AM_ADDR_IND, 4'd2, 1'b0); e_disp = 32'h00000300; go;
    chk(e_ea === 32'h00000400,        "[/addr]: the absolute address holds the pointer");

    // =======================================================================
    // The scaled index: by the operand's size, and added LAST.
    // =======================================================================
    setup(AM_RN_IND, 4'd1, 1'b0); e_rn = 32'h00000100; e_index = 1'b1; e_rx = 32'd3; go;
    chk(e_ea === 32'h00000103, "[Rn](Rx): a byte operand scales the index by 1");
    setup(AM_RN_IND, 4'd2, 1'b0); e_rn = 32'h00000100; e_index = 1'b1; e_rx = 32'd3; go;
    chk(e_ea === 32'h00000106, "[Rn](Rx): a halfword operand scales the index by 2");
    setup(AM_RN_IND, 4'd4, 1'b0); e_rn = 32'h00000100; e_index = 1'b1; e_rx = 32'd3; go;
    chk(e_ea === 32'h0000010C, "[Rn](Rx): a word operand scales the index by 4, not by the 3 the table prints");
    setup(AM_RN_IND, 4'd8, 1'b0); e_rn = 32'h00000100; e_index = 1'b1; e_rx = 32'd3; go;
    chk(e_ea === 32'h00000118, "[Rn](Rx): a doubleword operand scales the index by 8");

    // If the index were added before the indirection, this would read the
    // pointer at 0x304 and land at 0x500.
    setup(AM_DISP8_IND, 4'd1, 1'b0); e_rn = 32'h00000300; e_index = 1'b1; e_rx = 32'd4; go;
    chk(e_ea === 32'h00000404,        "[disp[Rn]](Rx): the index is added AFTER the pointer read");
    chk(e_rdata[7:0] === mem[10'h404], "[disp[Rn]](Rx): reads there");

    // =======================================================================
    // Autoincrement and autodecrement: Rn moves by the operand's size.
    // =======================================================================
    setup(AM_RN_INC, 4'd4, 1'b0); e_rn = 32'h00000100; go;
    chk(e_ea === 32'h00000100, "[Rn+]: the address is Rn before the increment");
    chk(wb_seen === 1'b1,          "[Rn+]: Rn is written back");
    chk(wb_val_r === 32'h00000104, "[Rn+]: Rn moves on by the operand's size");
    chk(e_cycles === 4'd2,     "[Rn+]: an aligned word is two bus cycles");

    setup(AM_RN_DEC, 4'd4, 1'b0); e_rn = 32'h00000104; go;
    chk(e_ea === 32'h00000100,     "[-Rn]: the decrement happens before the access");
    chk(wb_seen === 1'b1,          "[-Rn]: Rn is written back");
    chk(wb_val_r === 32'h00000100, "[-Rn]: Rn takes the decremented value");

    setup(AM_RN_DEC, 4'd1, 1'b0); e_rn = 32'h00000104; go;
    chk(e_ea === 32'h00000103, "[-Rn]: a byte operand steps by one");

    // =======================================================================
    // Writes, and the cost of an unaligned one.
    // =======================================================================
    setup(AM_DISP8, 4'd2, 1'b1); e_rn = 32'h00000500; e_disp = 32'h00000010;
    e_wdata = 64'h1234; go;
    chk(hw(10'h510) === 16'h1234, "disp.8[Rn] write: the halfword is where the mode said");
    chk(e_cycles === 4'd1,        "an aligned halfword write is one bus cycle");

    setup(AM_DISP8, 4'd4, 1'b1); e_rn = 32'h00000520; e_disp = 32'h00000001;
    e_wdata = 64'h89ABCDEF; go;
    chk(e_ea === 32'h00000521, "a word at an odd address is a legal operand");
    chk(e_cycles === 4'd3,     "a word at an odd address costs three bus cycles");
    chk({mem[10'h524], mem[10'h523], mem[10'h522], mem[10'h521]} === 32'h89ABCDEF,
                               "an unaligned word write lands in order");

    // The whole cost of one operand reference, through a pointer, unaligned.
    mem[10'h310] = 8'h21; mem[10'h311] = 8'h05; mem[10'h312] = 8'h00; mem[10'h313] = 8'h00;
    setup(AM_DISP8_IND, 4'd4, 1'b0); e_rn = 32'h00000310; go;
    chk(e_ea === 32'h00000521, "[disp[Rn]] can name an unaligned word");
    chk(e_rdata[31:0] === 32'h89ABCDEF, "and reads back what was written there");
    chk(e_cycles === 4'd5, "two cycles for the pointer and three for an unaligned word");

    if (errors == 0) $display("V60 EA PASS");
    else             $display("V60 EA FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #6_000_000;
    $display("V60 EA FAIL (timeout)");
    $finish;
end

endmodule
