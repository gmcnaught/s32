//============================================================================
//  tb_v60_idu -- a program, decoded instruction by instruction, off the bus.
//
//  The whole front end runs here: v60_biu fetches from a two-bank memory
//  through v60_bus_arb, v60_pfu keeps its queue filled and hands out bytes,
//  and v60_idu decodes one instruction per request -- format from the
//  generated opcode table, operands from v60_am_decode.
//
//  The program below is eight instructions covering all seven formats, a
//  two-operand instruction, an extension field and a reserved opcode.  Each is
//  checked for its format, opcode, fields, operand descriptions and LENGTH,
//  and one property is checked across all of them: each instruction's PC is
//  the previous one's PC plus its length.  Boundaries that do not chain mean a
//  byte was taken by the wrong stage, which no single-instruction check sees.
//============================================================================
`timescale 1ns/1ps

module tb_v60_idu;
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

// ---- prefetch unit ---------------------------------------------------------
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

// ---- the instruction decoder ------------------------------------------------
reg          i_start = 1'b0;
wire         i_busy, i_done, i_res_op, i_res_mode;
insn_fmt_e   i_fmt;
wire   [7:0] i_op;
wire         i_m, i_m2, i_d;
wire   [4:0] i_reg, i_subop;
wire  [31:0] i_disp, i_pc;
wire   [4:0] i_len;

wire         o1_valid, o1_index, o1_extv;
am_mode_e    o1_mode;
wire   [4:0] o1_rn, o1_rx;
wire  [31:0] o1_disp, o1_douter;
wire  [63:0] o1_imm;
wire   [7:0] o1_ext;

wire         o2_valid, o2_index, o2_extv;
am_mode_e    o2_mode;
wire   [4:0] o2_rn, o2_rx;
wire  [31:0] o2_disp, o2_douter;
wire  [63:0] o2_imm;
wire   [7:0] o2_ext;

v60_idu dut (
    .clk(clk), .rst(rst),
    .byte_in(byte_out), .byte_valid(byte_valid), .byte_pc(byte_pc),
    .byte_take(byte_take),
    .start(i_start), .busy(i_busy), .done(i_done),
    .fmt(i_fmt), .op(i_op), .m(i_m), .m2(i_m2), .d(i_d),
    .reg_field(i_reg), .subop(i_subop), .br_disp(i_disp),
    .insn_pc(i_pc), .insn_len(i_len),
    .reserved_op(i_res_op), .reserved_mode(i_res_mode),
    .op1_valid(o1_valid), .op1_mode(o1_mode), .op1_rn(o1_rn), .op1_rx(o1_rx),
    .op1_index(o1_index), .op1_disp(o1_disp), .op1_disp_outer(o1_douter),
    .op1_imm(o1_imm), .op1_ext_valid(o1_extv), .op1_ext(o1_ext), .op1_bytes(),
    .op2_valid(o2_valid), .op2_mode(o2_mode), .op2_rn(o2_rn), .op2_rx(o2_rx),
    .op2_index(o2_index), .op2_disp(o2_disp), .op2_disp_outer(o2_douter),
    .op2_imm(o2_imm), .op2_ext_valid(o2_extv), .op2_ext(o2_ext), .op2_bytes()
);

// ---- arbiter, bus and memory ------------------------------------------------
wire         biu_req, biu_we, biu_ube, biu_first, biu_ack, biu_busy, own_pfu;
bus_status_e biu_status;
wire  [23:0] biu_addr;
wire   [1:0] biu_dl;
wire  [15:0] biu_wdata;

v60_bus_arb arb (
    .clk(clk), .rst(rst),
    .d_req(1'b0), .d_status(BST_MEM_SINGLE), .d_addr(24'd0), .d_we(1'b0),
    .d_dl(DL_HALFWORD), .d_ube(1'b0), .d_first(1'b1), .d_lock(1'b0), .d_wdata(16'd0),
    .d_ack(),
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

reg  [7:0] mem [0:1023];
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

// Decode one instruction and leave its description on the outputs.
reg [31:0] expect_pc;
task decode;
begin
    @(negedge clk);
    i_start = 1'b1;
    @(negedge clk);
    i_start = 1'b0;
    while (!i_done) @(negedge clk);
    // The property that no single instruction's checks can see.
    chk(i_pc === expect_pc, "each instruction starts where the last one ended");
    expect_pc = i_pc + {27'd0, i_len};
end
endtask

integer i;

initial begin
    for (i = 0; i < 1024; i = i + 1) mem[i] = 8'h00;

    // ---- the program, at 0x100 --------------------------------------------
    // MOV.B, Format I, m=1 d=0 reg=5, operand Rn (011 Rn with m=1), Rn = 7
    mem[10'h100] = 8'h09; mem[10'h101] = 8'h45; mem[10'h102] = 8'h67;
    // NOP, Format V
    mem[10'h103] = 8'hCD;
    // MOV.B, Format II, m=0 m'=0: [Rn] and disp.16[Rn]
    mem[10'h104] = 8'h09; mem[10'h105] = 8'h80; mem[10'h106] = 8'h67;
    mem[10'h107] = 8'h27; mem[10'h108] = 8'h34; mem[10'h109] = 8'h12;
    // JMP, Format III with m = 0: [Rn]
    mem[10'h10A] = 8'hD6; mem[10'h10B] = 8'h67;
    // Bcc, Format IV, byte displacement -16
    mem[10'h10C] = 8'h60; mem[10'h10D] = 8'hF0;
    // EXTBF, Format VIIb: mod, ext, mod'
    mem[10'h10E] = 8'h5D; mem[10'h10F] = 8'hA8; mem[10'h110] = 8'h67;
    mem[10'h111] = 8'h20; mem[10'h112] = 8'h67;
    // TB, Format VI: subop 5, reg 5, disp16
    mem[10'h113] = 8'hC7; mem[10'h114] = 8'hA5; mem[10'h115] = 8'h34;
    mem[10'h116] = 8'h12;
    // MOVC, Format VIIa: mod, ext, mod', ext' -- the only format with two
    // extension fields
    mem[10'h117] = 8'h58; mem[10'h118] = 8'hA8; mem[10'h119] = 8'h67;
    mem[10'h11A] = 8'h20; mem[10'h11B] = 8'h67; mem[10'h11C] = 8'h10;
    // an opcode the instruction set does not assign
    mem[10'h11D] = 8'h06;
    // MOV.B, Format II again, this time with m = 0 and m' = 1 -- the same mod
    // byte means different things to the two operands, which is the only way
    // to see that each is decoded with its own bit.
    // 0xA0 = 1010_0000 -> bit15 = 1, m = 0, m' = 1, subop = 0
    mem[10'h11E] = 8'h09; mem[10'h11F] = 8'hA0; mem[10'h120] = 8'h67;
    mem[10'h121] = 8'h67;

    // ---- the operand data type, three ways it is specified -----------------
    // Each is `MOV`/`ADD`/`MOVF` with an IMMEDIATE source (mod byte F4) and
    // [Rn] as the destination.  immed.N's width is the operand's data type
    // (p.3.294 gives the one mode code three rows), so a wrong width changes
    // the instruction's LENGTH -- which the PC chain checks across all of them.
    // the suffix says: MOV.B, MOV.H, MOV.W
    mem[10'h122] = 8'h09; mem[10'h123] = 8'h80; mem[10'h124] = 8'hF4;
    mem[10'h125] = 8'h7F; mem[10'h126] = 8'h67;
    mem[10'h127] = 8'h1B; mem[10'h128] = 8'h80; mem[10'h129] = 8'hF4;
    mem[10'h12A] = 8'h34; mem[10'h12B] = 8'h12; mem[10'h12C] = 8'h67;
    mem[10'h12D] = 8'h2D; mem[10'h12E] = 8'h80; mem[10'h12F] = 8'hF4;
    mem[10'h130] = 8'h78; mem[10'h131] = 8'h56; mem[10'h132] = 8'h34;
    mem[10'h133] = 8'h12; mem[10'h134] = 8'h67;
    // the siz field says: ADD.b (80) and ADD.w (84)
    mem[10'h135] = 8'h80; mem[10'h136] = 8'h80; mem[10'h137] = 8'hF4;
    mem[10'h138] = 8'h55; mem[10'h139] = 8'h67;
    mem[10'h13A] = 8'h84; mem[10'h13B] = 8'h80; mem[10'h13C] = 8'hF4;
    mem[10'h13D] = 8'h11; mem[10'h13E] = 8'h22; mem[10'h13F] = 8'h33;
    mem[10'h140] = 8'h44; mem[10'h141] = 8'h67;
    // the s bit says: MOVF short real (5C) and long real (5E), subop 8
    mem[10'h142] = 8'h5C; mem[10'h143] = 8'h88; mem[10'h144] = 8'hF4;
    mem[10'h145] = 8'h01; mem[10'h146] = 8'h02; mem[10'h147] = 8'h03;
    mem[10'h148] = 8'h04; mem[10'h149] = 8'h67;
    mem[10'h14A] = 8'h5E; mem[10'h14B] = 8'h88; mem[10'h14C] = 8'hF4;
    mem[10'h14D] = 8'h01; mem[10'h14E] = 8'h02; mem[10'h14F] = 8'h03;
    mem[10'h150] = 8'h04; mem[10'h151] = 8'h05; mem[10'h152] = 8'h06;
    mem[10'h153] = 8'h07; mem[10'h154] = 8'h08; mem[10'h155] = 8'h67;

    // The conversion instructions are the ones whose two operands are
    // different widths, which is the only way to see that each operand is
    // given its OWN: MOVS.BW (0C) reads a byte and writes a word, MOVT.WB (29)
    // reads a word and writes a byte.  Both with an immediate source.
    mem[10'h156] = 8'h0C; mem[10'h157] = 8'h80; mem[10'h158] = 8'hF4;
    mem[10'h159] = 8'hAA; mem[10'h15A] = 8'h67;
    mem[10'h15B] = 8'h29; mem[10'h15C] = 8'h80; mem[10'h15D] = 8'hF4;
    mem[10'h15E] = 8'h11; mem[10'h15F] = 8'h22; mem[10'h160] = 8'h33;
    mem[10'h161] = 8'h44; mem[10'h162] = 8'h67;

    repeat (4) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);

    // Start the stream at the program.
    @(negedge clk);
    redirect_pc = 32'h00000100;
    redirect    = 1'b1;
    @(negedge clk);
    redirect = 1'b0;
    expect_pc = 32'h00000100;

    // ---- 1. MOV.B, Format I ------------------------------------------------
    decode;
    chk(i_fmt === FMT_I,      "MOV.B with bit 15 clear is Format I");
    chk(i_op === 8'h09,       "and its opcode is the first byte");
    chk(i_m === 1'b1 && i_d === 1'b0, "Format I: m and d out of the base word");
    chk(i_reg === 5'd5,       "Format I: reg is the second operand");
    chk(o1_valid === 1'b1 && o1_mode === AM_RN, "Format I: the mod field is Rn");
    chk(o1_rn === 5'd7,       "and it names r7");
    chk(o2_valid === 1'b0,    "Format I has no second mod field");
    chk(i_len === 5'd3,       "three bytes");

    // ---- 2. NOP, Format V ---------------------------------------------------
    decode;
    chk(i_fmt === FMT_V,   "NOP is Format V");
    chk(i_op === 8'hCD,    "opcode CD");
    chk(o1_valid === 1'b0, "no operands at all");
    chk(i_len === 5'd1,    "one byte");

    // ---- 3. MOV.B, Format II, two operands ---------------------------------
    decode;
    chk(i_fmt === FMT_II,     "the same opcode with bit 15 set is Format II");
    chk(i_m === 1'b0 && i_m2 === 1'b0, "m and m' both clear");
    chk(o1_valid && o1_mode === AM_RN_IND, "first operand is [Rn]");
    chk(o1_rn === 5'd7,                    "on r7");
    chk(o2_valid && o2_mode === AM_DISP16, "second operand is disp.16[Rn]");
    chk(o2_disp === 32'h00001234,          "with the displacement that follows it");
    chk(i_len === 5'd6,       "six bytes: two of base, one and three of operands");

    // ---- 4. JMP, Format III -------------------------------------------------
    decode;
    chk(i_fmt === FMT_III, "JMP is Format III");
    chk(i_m === 1'b0,      "its m is bit 0 of the opcode byte");
    chk(o1_valid && o1_mode === AM_RN_IND, "so the mod field is [Rn]");
    chk(i_len === 5'd2,    "two bytes");

    // ---- 5. Bcc, Format IV --------------------------------------------------
    decode;
    chk(i_fmt === FMT_IV,        "Bcc is Format IV");
    chk(i_disp === 32'hFFFFFFF0, "with a signed byte displacement");
    chk(o1_valid === 1'b0,       "and no operands");
    chk(i_len === 5'd2,          "two bytes");

    // ---- 6. EXTBF, Format VIIb ----------------------------------------------
    decode;
    chk(i_fmt === FMT_VIIB,  "EXTBF is Format VIIb");
    chk(i_subop === 5'd8,    "subop 8 is what made it VIIb rather than VIIc");
    chk(o1_valid && o1_mode === AM_RN_IND, "operand 1 decoded with m");
    chk(o1_extv === 1'b1,    "and the extension field was taken");
    chk(ext_is_register(o1_ext) === 1'b0 && ext_value(o1_ext) === 7'd32,
                             "which says a 32 bit operand length");
    chk(o2_valid && o2_mode === AM_RN, "operand 2 decoded with m'");
    chk(o2_extv === 1'b0,    "VIIb has no second extension field");
    chk(i_len === 5'd5,      "five bytes: base, mod, ext, mod'");

    // ---- 7. TB, Format VI ---------------------------------------------------
    decode;
    chk(i_fmt === FMT_VI,        "TB is Format VI");
    chk(i_subop === 5'd5 && i_reg === 5'd5, "subop and reg out of the base word");
    chk(i_disp === 32'h00001234, "and a halfword displacement after it");
    chk(o1_valid === 1'b0,       "no mod field");
    chk(i_len === 5'd4,          "four bytes");

    // ---- 8. MOVC, Format VIIa -----------------------------------------------
    decode;
    chk(i_fmt === FMT_VIIA,  "MOVC is Format VIIa");
    chk(o1_valid && o1_extv,  "operand 1 has an extension field");
    chk(o2_valid && o2_extv,  "and so does operand 2 -- only VIIa does");
    chk(ext_value(o1_ext) === 7'd32 && ext_value(o2_ext) === 7'd16,
                              "each extension field is its own byte");
    chk(i_len === 5'd6,       "six bytes: base, mod, ext, mod', ext'");

    // ---- 9. a reserved opcode -----------------------------------------------
    decode;
    chk(i_fmt === FMT_UNKNOWN, "0x06 is not an instruction");
    chk(i_res_op === 1'b1 && i_res_mode === 1'b0,
                               "and the decoder says which of the two it is");
    chk(i_len === 5'd1,        "consuming only the opcode byte");

    // ---- 10. one mod byte, two meanings ------------------------------------
    decode;
    chk(i_fmt === FMT_II, "Format II again");
    chk(i_m === 1'b0 && i_m2 === 1'b1, "with m = 0 and m' = 1");
    chk(o1_mode === AM_RN_IND, "the same byte is [Rn] to the first operand");
    chk(o2_mode === AM_RN,     "and Rn to the second");
    chk(i_len === 5'd4,        "four bytes");

    // ---- 11..17. the operand data type decides an immediate's width --------
    decode;
    chk(i_len === 5'd5 && o1_mode === AM_IMMED && o1_imm[7:0] === 8'h7F,
        "MOV.B takes one byte of immediate");
    decode;
    chk(i_len === 5'd6 && o1_imm[15:0] === 16'h1234,
        "MOV.H takes two");
    decode;
    chk(i_len === 5'd8 && o1_imm[31:0] === 32'h12345678,
        "MOV.W takes four");
    decode;
    chk(i_len === 5'd5 && o1_imm[7:0] === 8'h55,
        "ADD with siz = byte takes one");
    decode;
    chk(i_len === 5'd8 && o1_imm[31:0] === 32'h44332211,
        "ADD with siz = word takes four");
    decode;
    chk(i_len === 5'd8 && o1_imm[31:0] === 32'h04030201,
        "MOVF with s = short real takes four");
    decode;
    chk(i_len === 5'd12 && o1_imm === 64'h0807060504030201,
        "MOVF with s = long real takes eight");

    decode;
    chk(i_len === 5'd5 && o1_imm[7:0] === 8'hAA,
        "MOVS.BW's source is a byte even though its destination is a word");
    decode;
    chk(i_len === 5'd8 && o1_imm[31:0] === 32'h44332211,
        "MOVT.WB's source is a word even though its destination is a byte");

    if (errors == 0) $display("V60 IDU PASS");
    else             $display("V60 IDU FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #20_000_000;
    $display("V60 IDU FAIL (timeout)");
    $finish;
end

endmodule
