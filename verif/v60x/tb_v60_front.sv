//============================================================================
//  tb_v60_front -- an instruction fetched, decoded, and its operands read.
//
//  Everything built so far, on one bus:
//
//      v60_biu  <- v60_bus_arb <- v60_pfu   (instruction fetch)
//                              <- v60_dxu <- v60_ea   (operand access)
//      v60_pfu  -> v60_idu -> v60_fmt_decode, v60_am_decode
//
//  The point of this bench is the JOIN.  v60_idu describes operands in the
//  shape v60_ea takes; nothing in the tree had ever passed one to the other,
//  so nothing had shown that an instruction's operands can actually be
//  resolved and read.  Here they are, off real memory, with the instruction
//  fetch still running underneath.
//
//  What it does NOT claim: the arbiter's priority rule, which tb_v60_pfu tests
//  deliberately, and the length of a Format VIIa instruction, which tb_v60_idu
//  does.  This bench only shows that the two halves fit and that the stream
//  survives the data cycles.
//
//  Register values come from the bench: v60_ea takes Rn, Rx and the PC as
//  values, and the register file belongs to the execution stage that does not
//  exist yet.
//============================================================================
`timescale 1ns/1ps

module tb_v60_front;
    import v60_bus_pkg::*;
    import v60_fmt_pkg::*;
    import v60_am_pkg::*;

localparam integer DIV = 6;

reg clk = 1'b0;
always #5 clk = ~clk;

reg rst = 1'b1;

reg [2:0] tick = 3'd0;
always @(posedge clk) if (!rst) tick <= (tick == DIV-1) ? 3'd0 : tick + 3'd1;
wire ce_rise = !rst && (tick == 3'd0);
wire ce_fall = !rst && (tick == DIV/2);

// ---- instruction fetch ------------------------------------------------------
reg          redirect = 1'b0;
reg   [31:0] redirect_pc = 32'd0;

wire   [7:0] byte_out;
wire         byte_valid, byte_take;
wire  [31:0] byte_pc;
wire         p_req, p_ack;
bus_status_e p_status;
wire  [23:0] p_addr;
wire   [1:0] p_dl;
wire  [15:0] biu_rdata;

v60_pfu pfu (
    .clk(clk), .rst(rst),
    .byte_out(byte_out), .byte_valid(byte_valid), .byte_take(byte_take),
    .byte_pc(byte_pc),
    .redirect(redirect), .redirect_pc(redirect_pc),
    .bus_req(p_req), .bus_status(p_status), .bus_addr(p_addr), .bus_dl(p_dl),
    .bus_ack(p_ack), .bus_rdata(biu_rdata),
    .level()
);

// ---- decode -----------------------------------------------------------------
reg          i_start = 1'b0;
wire         i_done;
insn_fmt_e   i_fmt;
wire   [4:0] i_len;
wire  [31:0] i_pc;
wire         o1_valid, o1_index, o2_valid, o2_index;
am_mode_e    o1_mode, o2_mode;
wire   [4:0] o1_rn, o1_rx, o2_rn, o2_rx;
wire  [31:0] o1_disp, o1_douter, o2_disp, o2_douter;
wire  [63:0] o1_imm, o2_imm;
wire   [3:0] o1_bytes, o2_bytes;

v60_idu idu (
    .clk(clk), .rst(rst),
    .byte_in(byte_out), .byte_valid(byte_valid), .byte_pc(byte_pc),
    .byte_take(byte_take),
    .start(i_start), .busy(), .done(i_done),
    .fmt(i_fmt), .op(), .m(), .m2(), .d(), .reg_field(), .subop(),
    .br_disp(), .insn_pc(i_pc), .insn_len(i_len),
    .reserved_op(), .reserved_mode(),
    .op1_valid(o1_valid), .op1_mode(o1_mode), .op1_rn(o1_rn), .op1_rx(o1_rx),
    .op1_index(o1_index), .op1_disp(o1_disp), .op1_disp_outer(o1_douter),
    .op1_imm(o1_imm), .op1_ext_valid(), .op1_ext(), .op1_bytes(o1_bytes),
    .op2_valid(o2_valid), .op2_mode(o2_mode), .op2_rn(o2_rn), .op2_rx(o2_rx),
    .op2_index(o2_index), .op2_disp(o2_disp), .op2_disp_outer(o2_douter),
    .op2_imm(o2_imm), .op2_ext_valid(), .op2_ext(), .op2_bytes(o2_bytes)
);

// ---- the operand, resolved --------------------------------------------------
// Driven from the IDU's description, with register values from the bench.
reg          e_start = 1'b0, e_we = 1'b0, e_index = 1'b0;
am_mode_e    e_mode = AM_RN;
reg   [31:0] e_disp = 32'd0, e_outer = 32'd0;
reg   [63:0] e_imm = 64'd0, e_wdata = 64'd0;
reg   [31:0] e_rn = 32'd0, e_rx = 32'd0, e_pc = 32'd0;
reg    [3:0] e_bytes = 4'd1;

wire  [31:0] e_ea;
wire  [63:0] e_rdata;
wire         e_done;
wire   [3:0] e_cycles;

wire         dx_req, dx_we, dx_done;
wire  [23:0] dx_addr;
wire   [3:0] dx_nbytes, dx_cycles;
wire  [63:0] dx_wdata, dx_rdata;

v60_ea ea (
    .clk(clk), .rst(rst),
    .start(e_start), .mode(e_mode), .has_index(e_index),
    .disp(e_disp), .disp_outer(e_outer), .imm(e_imm),
    .rn_val(e_rn), .rn1_val(32'd0), .rx_val(e_rx), .pc_val(e_pc),
    .opbytes(e_bytes), .we(e_we), .io(1'b0), .lock(1'b0), .wdata(e_wdata),
    .ea(e_ea), .rdata(e_rdata), .rn_wb(), .rn_wb_val(),
    .illegal(), .busy(), .done(e_done), .bus_cycles(e_cycles),
    .dx_req(dx_req), .dx_addr(dx_addr), .dx_nbytes(dx_nbytes), .dx_we(dx_we),
    .dx_io(), .dx_lock(),
    .dx_wdata(dx_wdata), .dx_rdata(dx_rdata), .dx_done(dx_done),
    .dx_cycles(dx_cycles)
);

wire         d_req, d_we, d_ube, d_first, d_ack;
bus_status_e d_status;
wire  [23:0] d_addr;
wire   [1:0] d_dl;
wire  [15:0] d_wdata;

v60_dxu dxu (
    .clk(clk), .rst(rst),
    .req(dx_req), .addr(dx_addr), .nbytes(dx_nbytes), .we(dx_we), .io(1'b0), .lock(1'b0), .intack(1'b0),
    .wdata(dx_wdata), .rdata(dx_rdata), .busy(), .done(dx_done),
    .cycles(dx_cycles),
    .biu_req(d_req), .biu_status(d_status), .biu_addr(d_addr),
    .biu_we(d_we), .biu_dl(d_dl), .biu_ube(d_ube), .biu_first(d_first),
    .biu_wdata(d_wdata), .biu_ack(d_ack), .biu_rdata(biu_rdata)
);

// ---- arbiter, bus, memory ----------------------------------------------------
wire         biu_req, biu_we, biu_ube, biu_first, biu_ack, biu_busy, own_pfu;
bus_status_e biu_status;
wire  [23:0] biu_addr;
wire   [1:0] biu_dl;
wire  [15:0] biu_wdata;

v60_bus_arb arb (
    .clk(clk), .rst(rst),
    .d_req(d_req), .d_status(d_status), .d_addr(d_addr), .d_we(d_we),
    .d_dl(d_dl), .d_ube(d_ube), .d_first(d_first), .d_lock(1'b0), .d_wdata(d_wdata),
    .d_ack(d_ack),
    .p_req(p_req), .p_status(p_status), .p_addr(p_addr), .p_dl(p_dl),
    .p_ack(p_ack),
    .biu_req(biu_req), .biu_status(biu_status), .biu_addr(biu_addr),
    .biu_we(biu_we), .biu_dl(biu_dl), .biu_ube(biu_ube), .biu_first(biu_first),
    .biu_lock(), .biu_wdata(biu_wdata), .biu_ack(biu_ack), .biu_busy(biu_busy),
    .own_pfu(own_pfu)
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
    .ack(biu_ack), .rdata(biu_rdata), .busy(biu_busy),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .block_n(), .ds_n(ds_n),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .bus_hiz(bus_hiz),
    .ready_n(1'b0), .bmode(1'b1), .hldrq_n(1'b1), .hldak_n(hldak_n),
    .berr_n(1'b1), .rt_ep_n(1'b1), .nmi_n(1'b1), .int_req(1'b0),
    .berr(), .berr_status(), .berr_addr(), .berr_we(), .berr_retry(),
    .nmi_pending(), .nmi_take(1'b0), .int_pending(),
    .state(state)
);

reg  [7:0] mem [0:2047];
wire [10:0] bank_even = {a[10:1], 1'b0};
always @(*) d_in = {mem[bank_even + 11'd1], mem[bank_even]};

// Writes, through the same three lanes the databook gives.
always @(posedge clk) if (!rst && biu_ack && !rw_n) begin
    case ({ube_n, a[0]})
        2'b00: begin mem[bank_even] = d_out[7:0];
                     mem[bank_even + 11'd1] = d_out[15:8]; end
        2'b01: mem[bank_even + 11'd1] = d_out[15:8];
        2'b10: mem[bank_even] = d_out[7:0];
        default: ;
    endcase
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

task decode;
begin
    @(negedge clk);
    i_start = 1'b1;
    @(negedge clk);
    i_start = 1'b0;
    while (!i_done) @(negedge clk);
end
endtask

// Hand operand 1 or operand 2 of the decoded instruction to v60_ea.
task resolve(input second, input [31:0] rn_val, input [3:0] nbytes, input w,
             input [63:0] wdata);
begin
    @(negedge clk);
    if (!second) begin
        e_mode = o1_mode; e_index = o1_index; e_disp = o1_disp;
        e_outer = o1_douter; e_imm = o1_imm; e_rx = {27'd0, o1_rx};
    end else begin
        e_mode = o2_mode; e_index = o2_index; e_disp = o2_disp;
        e_outer = o2_douter; e_imm = o2_imm; e_rx = {27'd0, o2_rx};
    end
    e_rn    = rn_val;
    e_bytes = nbytes;
    e_we    = w;
    e_wdata = wdata;
    e_start = 1'b1;
    @(negedge clk);
    e_start = 1'b0;
    while (!e_done) @(negedge clk);
end
endtask

integer i;

initial begin
    for (i = 0; i < 2048; i = i + 1) mem[i] = 8'h00;

    // MOV.B, Format II, m = 0 and m' = 0: source [Rn], destination
    // disp.16[Rn] with disp = 0x0100.
    mem[11'h100] = 8'h09; mem[11'h101] = 8'h80; mem[11'h102] = 8'h67;
    mem[11'h103] = 8'h27; mem[11'h104] = 8'h00; mem[11'h105] = 8'h01;

    // The data the instruction moves.
    mem[11'h300] = 8'h5A;

    repeat (4) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);

    @(negedge clk);
    redirect_pc = 32'h00000100;
    redirect    = 1'b1;
    @(negedge clk);
    redirect = 1'b0;

    // ---- decode it ----------------------------------------------------------
    decode;
    chk(i_fmt === FMT_II,  "the instruction decoded as Format II");
    chk(i_pc === 32'h00000100 && i_len === 5'd6, "six bytes at 0x100");
    chk(o1_valid && o1_mode === AM_RN_IND,  "source is [Rn]");
    chk(o2_valid && o2_mode === AM_DISP16,  "destination is disp.16[Rn]");
    chk(o2_disp === 32'h00000100,           "with the displacement from the stream");

    // ---- read the source operand -------------------------------------------
    // r7 = 0x300, so [Rn] names 0x300 and the byte there is 0x5A.
    resolve(1'b0, 32'h00000300, 4'd1, 1'b0, 64'd0);
    chk(e_ea === 32'h00000300,   "the source operand's address came from the description");
    chk(e_rdata[7:0] === 8'h5A,  "and the byte at it was read off the bus");
    chk(e_cycles === 4'd1,       "one bus cycle for a byte");

    // ---- write the destination operand --------------------------------------
    // disp.16[Rn] with Rn = 0x300 and disp = 0x100 names 0x400.
    resolve(1'b1, 32'h00000300, 4'd1, 1'b1, {56'd0, e_rdata[7:0]});
    chk(e_ea === 32'h00000400, "the destination's address is Rn plus the displacement");
    chk(mem[11'h400] === 8'h5A, "and the operand landed there");

    // ---- the instruction stream survived the data cycles --------------------
    // The prefetch unit shares the bus with all of that, at lower priority.
    decode;
    chk(i_pc === 32'h00000106,
        "the next instruction is still where the last one ended");

    if (errors == 0) $display("V60 FRONT PASS");
    else             $display("V60 FRONT FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #20_000_000;
    $display("V60 FRONT FAIL (timeout)");
    $finish;
end

endmodule
