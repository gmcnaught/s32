//============================================================================
//  tb_v60_dxu -- a logical access, and the bus cycles it is allowed to become.
//
//  v60_dxu drives a real v60_biu here, into a memory model built the way the
//  databook describes the memory: "a pair of byte-wide banks ... addressed by
//  A23-A1", the even bank selected by A0 low and the odd bank by UBE*
//  (p.3.235-6).  So the model can only be read or written through the same
//  three lane encodings the silicon has, and an access that picks the wrong
//  lane moves the wrong byte rather than merely looking wrong on a waveform.
//
//  Every access below is checked three ways: the DATA that moved, the SHAPE of
//  each bus cycle it took ({UBE*, A0}, DL1-DL0, FAS*), and the COUNT.  The
//  count is the quantity docs/v60/v60_operand_access.csv is denominated in.
//
//  Stimulus on the negedge, DUT on the posedge, as in the other benches.
//============================================================================
`timescale 1ns/1ps

module tb_v60_dxu;
    import v60_bus_pkg::*;

localparam integer DIV = 6;         // clk_ram ticks per V60 clock (System 32)

reg clk = 1'b0;
always #5 clk = ~clk;

reg rst = 1'b1;

reg [2:0] tick = 3'd0;
always @(posedge clk) if (!rst) tick <= (tick == DIV-1) ? 3'd0 : tick + 3'd1;
wire ce_rise = !rst && (tick == 3'd0);
wire ce_fall = !rst && (tick == DIV/2);

// ---- the logical access ----------------------------------------------------
reg         dreq = 1'b0, dwe = 1'b0, dio = 1'b0;
reg  [23:0] daddr = 24'h0;
reg   [3:0] dn = 4'd1;
reg  [63:0] dwdata = 64'd0;
wire [63:0] drdata;
wire        dbusy, ddone;
wire  [3:0] dcycles;

// ---- dxu <-> biu -----------------------------------------------------------
wire         biu_req, biu_we, biu_ube, biu_first, biu_ack;
bus_status_e biu_status;
wire  [23:0] biu_addr;
wire   [1:0] biu_dl;
wire  [15:0] biu_wdata, biu_rdata;

v60_dxu dut (
    .clk(clk), .rst(rst),
    .req(dreq), .addr(daddr), .nbytes(dn), .we(dwe), .io(dio), .wdata(dwdata),
    .rdata(drdata), .busy(dbusy), .done(ddone), .cycles(dcycles),
    .biu_req(biu_req), .biu_status(biu_status), .biu_addr(biu_addr),
    .biu_we(biu_we), .biu_dl(biu_dl), .biu_ube(biu_ube), .biu_first(biu_first),
    .biu_wdata(biu_wdata), .biu_ack(biu_ack), .biu_rdata(biu_rdata)
);

// ---- pins ------------------------------------------------------------------
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
    .dl(biu_dl), .ube(biu_ube), .first(biu_first), .wdata(biu_wdata),
    .ack(biu_ack), .rdata(biu_rdata), .busy(),
    .a(a), .dl_o(dl_o), .st(st), .mrq_n(mrq_n), .rw_n(rw_n), .ube_n(ube_n),
    .fas_n(fas_n), .bcy_n(bcy_n), .ds_n(ds_n),
    .d_out(d_out), .d_oe(d_oe), .d_in(d_in), .bus_hiz(bus_hiz),
    .ready_n(1'b0), .bmode(1'b1), .hldrq_n(1'b1), .hldak_n(hldak_n),
    .state(state)
);

// ---------------------------------------------------------------------------
// The memory: two byte-wide banks, addressed by A23-A1.
// ---------------------------------------------------------------------------
reg [7:0] mem [0:1023];
wire [9:0] bank_even = {a[9:1], 1'b0};

always @(*) d_in = {mem[bank_even + 10'd1], mem[bank_even]};

integer errors = 0;

task chk(input cond, input [8*72:1] what);
begin
    if (!cond) begin
        errors = errors + 1;
        $display("FAIL  %0s (t=%0t)", what, $time);
    end
end
endtask

// ---------------------------------------------------------------------------
// The recorder: one entry per bus cycle, taken at the ack.
// ---------------------------------------------------------------------------
reg [23:0] rec_a   [0:15];
reg  [1:0] rec_lane[0:15];   // {UBE*, A0}
reg  [1:0] rec_dl  [0:15];
reg        rec_fas [0:15];
reg  [3:0] rec_st  [0:15];
integer    ncyc = 0;

always @(posedge clk) if (!rst && biu_ack) begin
    // A cycle that presents {UBE*, A0} = 11 is asking for the reserved access
    // type on p.3.236.  There is no such bus cycle.
    if ({ube_n, a[0]} === 2'b11) begin
        errors = errors + 1;
        $display("FAIL  a bus cycle presented the reserved lane encoding (a=%h t=%0t)", a, $time);
    end
    if (ncyc < 16) begin
        rec_a[ncyc]    = a;
        rec_lane[ncyc] = {ube_n, a[0]};
        rec_dl[ncyc]   = dl_o;
        rec_fas[ncyc]  = fas_n;
        rec_st[ncyc]   = {mrq_n, st};
    end
    ncyc = ncyc + 1;

    // The write side of the memory model, through the same three lanes.
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

task access(input [23:0] a_in, input [3:0] n, input w, input i_o, input [63:0] wd);
begin
    @(negedge clk);
    daddr = a_in; dn = n; dwe = w; dio = i_o; dwdata = wd;
    ncyc = 0;
    dreq = 1'b1;
    @(negedge clk);
    while (!ddone) @(negedge clk);
    dreq = 1'b0;
    @(negedge clk);
end
endtask

integer i;

initial begin
    for (i = 0; i < 1024; i = i + 1) mem[i] = i[7:0] + 8'h40;

    repeat (4) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);

    // =======================================================================
    // Reads.  One byte lands on the lane its address selects, and lands at the
    // operand's own offset regardless of which lane that was.
    // =======================================================================
    access(24'h000100, 4'd1, 1'b0, 1'b0, 64'd0);
    chk(dcycles === 4'd1,               "byte at an even address is one bus cycle");
    chk(drdata[7:0] === mem[10'h100],   "byte at an even address comes off the lower lane");
    chk(rec_lane[0] === 2'b10,          "byte at an even address is a lower byte access");
    chk(rec_dl[0] === DL_BYTE,          "a byte access drives DL = byte");
    chk(rec_fas[0] === 1'b0,            "the first bus cycle asserts FAS*");

    access(24'h000101, 4'd1, 1'b0, 1'b0, 64'd0);
    chk(dcycles === 4'd1,               "byte at an odd address is one bus cycle");
    chk(drdata[7:0] === mem[10'h101],   "byte at an odd address comes off the upper lane");
    chk(rec_lane[0] === 2'b01,          "byte at an odd address is an upper byte access");

    access(24'h000100, 4'd2, 1'b0, 1'b0, 64'd0);
    chk(dcycles === 4'd1,               "aligned halfword is one bus cycle");
    chk(drdata[15:0] === {mem[10'h101], mem[10'h100]}, "aligned halfword is little endian");
    chk(rec_lane[0] === 2'b00,          "aligned halfword is a halfword access");
    chk(rec_dl[0] === DL_HALFWORD,      "a halfword access drives DL = halfword");

    // {UBE*, A0} has no halfword-at-an-odd-address encoding, so this is two
    // byte cycles -- and the operand is still little endian across them.
    access(24'h000101, 4'd2, 1'b0, 1'b0, 64'd0);
    chk(dcycles === 4'd2,               "unaligned halfword is two bus cycles");
    chk(drdata[15:0] === {mem[10'h102], mem[10'h101]}, "unaligned halfword is assembled in order");
    chk(rec_a[0] === 24'h000101 && rec_lane[0] === 2'b01, "unaligned halfword starts with the upper byte at A");
    chk(rec_a[1] === 24'h000102 && rec_lane[1] === 2'b10, "unaligned halfword ends with the lower byte at A+1");
    chk(rec_dl[0] === DL_HALFWORD && rec_dl[1] === DL_HALFWORD,
                                        "DL is the logical length on every cycle of the access");
    chk(rec_fas[0] === 1'b0 && rec_fas[1] === 1'b1,
                                        "FAS* marks the first cycle and only the first");

    access(24'h000100, 4'd4, 1'b0, 1'b0, 64'd0);
    chk(dcycles === 4'd2,               "aligned word is two bus cycles");
    chk(drdata[31:0] === {mem[10'h103], mem[10'h102], mem[10'h101], mem[10'h100]},
                                        "aligned word is little endian");
    chk(rec_lane[0] === 2'b00 && rec_lane[1] === 2'b00, "aligned word is two halfword accesses");
    chk(rec_a[1] === 24'h000102,        "the second halfword is at A+2");
    chk(rec_dl[0] === DL_WORD,          "a word access drives DL = word");

    // Odd address: the split has to fall back to a byte, then realign.
    access(24'h000101, 4'd4, 1'b0, 1'b0, 64'd0);
    chk(dcycles === 4'd3,               "word at an odd address is three bus cycles");
    chk(drdata[31:0] === {mem[10'h104], mem[10'h103], mem[10'h102], mem[10'h101]},
                                        "word at an odd address is assembled in order");
    chk(rec_a[0] === 24'h000101 && rec_lane[0] === 2'b01, "odd word: upper byte first");
    chk(rec_a[1] === 24'h000102 && rec_lane[1] === 2'b00, "odd word: then a halfword, now aligned");
    chk(rec_a[2] === 24'h000104 && rec_lane[2] === 2'b10, "odd word: then the last lower byte");

    access(24'h000110, 4'd8, 1'b0, 1'b0, 64'd0);
    chk(dcycles === 4'd4,               "aligned doubleword is four bus cycles");
    chk(drdata === {mem[10'h117], mem[10'h116], mem[10'h115], mem[10'h114],
                    mem[10'h113], mem[10'h112], mem[10'h111], mem[10'h110]},
                                        "aligned doubleword is little endian");
    chk(rec_dl[0] === DL_WORD,          "DL has no doubleword code, so a doubleword drives word");
    chk(rec_fas[0] === 1'b0 && rec_fas[1] === 1'b1 &&
        rec_fas[2] === 1'b0 && rec_fas[3] === 1'b1,
                                        "a doubleword is two word accesses as far as FAS* is concerned");

    access(24'h000111, 4'd8, 1'b0, 1'b0, 64'd0);
    chk(dcycles === 4'd5,               "doubleword at an odd address is five bus cycles");

    // =======================================================================
    // Writes.  The memory model can only be written through a lane, so a write
    // that picks the wrong one lands in the wrong byte.
    // =======================================================================
    access(24'h000201, 4'd1, 1'b1, 1'b0, 64'h11);
    chk(mem[10'h201] === 8'h11, "byte write at an odd address lands at A");
    chk(mem[10'h200] === 8'h40 && mem[10'h202] === 8'h42, "byte write disturbs neither neighbour");

    access(24'h000210, 4'd2, 1'b1, 1'b0, 64'h2233);
    chk(mem[10'h210] === 8'h33 && mem[10'h211] === 8'h22, "aligned halfword write is little endian");

    access(24'h000221, 4'd2, 1'b1, 1'b0, 64'h4455);
    chk(mem[10'h221] === 8'h55 && mem[10'h222] === 8'h44, "unaligned halfword write splits into two bytes");
    chk(mem[10'h220] === 8'h60 && mem[10'h223] === 8'h63, "unaligned halfword write disturbs no neighbour");

    access(24'h000230, 4'd4, 1'b1, 1'b0, 64'h89ABCDEF);
    chk(mem[10'h230] === 8'hEF && mem[10'h231] === 8'hCD &&
        mem[10'h232] === 8'hAB && mem[10'h233] === 8'h89, "aligned word write is little endian");

    access(24'h000241, 4'd4, 1'b1, 1'b0, 64'h01234567);
    chk(dcycles === 4'd3, "word write at an odd address is three bus cycles");
    chk(mem[10'h241] === 8'h67 && mem[10'h242] === 8'h45 &&
        mem[10'h243] === 8'h23 && mem[10'h244] === 8'h01, "word write at an odd address lands in order");
    chk(mem[10'h240] === 8'h80 && mem[10'h245] === 8'h85, "word write at an odd address disturbs no neighbour");

    // Read back what was written, through a different split than it went out.
    access(24'h000241, 4'd4, 1'b0, 1'b0, 64'd0);
    chk(drdata[31:0] === 32'h01234567, "a word written unaligned reads back unaligned");

    // =======================================================================
    // Address space.  The status code is the only thing that says which one.
    // =======================================================================
    access(24'h000300, 4'd2, 1'b0, 1'b1, 64'd0);
    chk(rec_st[0] === BST_IO_SINGLE, "an I/O access drives single mode I/O status");
    access(24'h000300, 4'd2, 1'b0, 1'b0, 64'd0);
    chk(rec_st[0] === BST_MEM_SINGLE, "a memory access drives single mode memory status");

    if (errors == 0) $display("V60 DXU PASS");
    else             $display("V60 DXU FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #4_000_000;
    $display("V60 DXU FAIL (timeout)");
    $finish;
end

endmodule
