//============================================================================
//  tb_v60_am_decode -- walk the whole mod-field figure through the decoder.
//
//  Every row of "mod Field - Addressing Mode Encoding" (databook p.3.294,
//  reprinted as Programmer's Reference Appendix C) appears below once, with
//  the byte string an assembler would emit for it and the length the figure
//  gives it.  Three rows are encoded as docs/v60/ADDRESSING-MODES.md argues
//  they must be rather than as the figure prints them -- they are marked
//  FIGURE-TYPO where they appear, and the printed bytes are checked too, so
//  the difference is visible rather than assumed away.
//
//  Then the things a row-by-row sweep cannot see: byte order, sign extension,
//  which displacement of a double displacement is which, and that a new
//  operand does not inherit the last one's index register.
//
//  Stimulus is driven on the negedge and the DUT is clocked on the posedge, so
//  the two simulators cannot schedule it differently.  Outputs are registered:
//  `done` is high on the negedge after the last byte was consumed, which is
//  where every check below samples.
//============================================================================
`timescale 1ns/1ps

module tb_v60_am_decode;
    import v60_am_pkg::*;

reg clk = 1'b0;
always #5 clk = ~clk;

reg         rst = 1'b1;
reg         start = 1'b0, m = 1'b0, byte_valid = 1'b0;
reg   [7:0] byte_in = 8'h00;
reg   [3:0] opbytes = 4'd1;

wire        busy, done;
am_mode_e   mode;
wire  [4:0] rn, rx;
wire        has_index, base_pc, base_none, reg_direct, immediate;
wire        mem_operand, ea_indirect, autoinc, autodec, reserved;
wire [31:0] disp, disp_outer;
wire [63:0] imm;
wire  [3:0] imm_bytes, len;

v60_am_decode dut (
    .clk(clk), .rst(rst),
    .start(start), .m(m), .opbytes(opbytes),
    .byte_valid(byte_valid), .byte_in(byte_in),
    .busy(busy), .done(done), .mode(mode), .rn(rn), .rx(rx),
    .has_index(has_index), .disp(disp), .disp_outer(disp_outer),
    .imm(imm), .imm_bytes(imm_bytes), .len(len),
    .base_pc(base_pc), .base_none(base_none), .reg_direct(reg_direct),
    .immediate(immediate), .mem_operand(mem_operand),
    .ea_indirect(ea_indirect), .autoinc(autoinc), .autodec(autodec),
    .reserved(reserved)
);

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
// A mod field, one byte per clock, `start` with the first.
// ---------------------------------------------------------------------------
reg [7:0] seq [0:9];
integer   nseq;

task clr;
begin
    nseq = 0;
end
endtask

task push(input [7:0] b);
begin
    seq[nseq] = b;
    nseq = nseq + 1;
end
endtask

task run(input m_in, input [3:0] osz);
    integer i;
begin
    @(negedge clk);
    m       = m_in;
    opbytes = osz;
    for (i = 0; i < nseq; i = i + 1) begin
        byte_in    = seq[i];
        byte_valid = 1'b1;
        start      = (i == 0);
        @(negedge clk);
    end
    byte_valid = 1'b0;
    start      = 1'b0;
    // `done` is high right now, with the description settled alongside it.
end
endtask

// One row of the figure: the encoding, the mode it names, its length.
task row(input m_in, input [3:0] osz, input [4:0] emode, input [3:0] elen,
         input [8*44:1] name);
begin
    run(m_in, osz);
    chk(done === 1'b1, {"done: ", name});
    chk(mode === am_mode_e'(emode), {"mode: ", name});
    chk(len  === elen, {"len: ", name});
end
endtask

localparam [4:0] RN = 5'd7;    // the base register every row below uses
localparam [4:0] RX = 5'd18;   // and the index register

// Mode bytes: three code bits over a five bit register field.
localparam [7:0] B_000 = {3'b000, RN};   // 0x07
localparam [7:0] B_001 = {3'b001, RN};   // 0x27
localparam [7:0] B_010 = {3'b010, RN};   // 0x47
localparam [7:0] B_011 = {3'b011, RN};   // 0x67
localparam [7:0] B_100 = {3'b100, RN};   // 0x87
localparam [7:0] B_101 = {3'b101, RN};   // 0xA7
localparam [7:0] B_110 = {3'b110, RN};   // 0xC7
localparam [7:0] B_IDX = {3'b110, RX};   // 0xD2 -- an index byte carries Rx

task push4(input [31:0] v);
begin
    push(v[7:0]); push(v[15:8]); push(v[23:16]); push(v[31:24]);
end
endtask

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);

    // =======================================================================
    // The figure, row by row.  Groups are the figure's own: mod fields of
    // one, two, three, four, five, six and nine bytes.
    // =======================================================================

    // ---- one byte ---------------------------------------------------------
    clr; push(B_011);                     row(1'b1, 4'd4, AM_RN,      4'd1, "Rn");
    clr; push(B_011);                     row(1'b0, 4'd4, AM_RN_IND,  4'd1, "[Rn] (FIGURE-TYPO: printed 001)");
    clr; push(B_100);                     row(1'b1, 4'd4, AM_RN_INC,  4'd1, "[Rn+]");
    clr; push(B_101);                     row(1'b1, 4'd4, AM_RN_DEC,  4'd1, "[-Rn]");
    clr; push(8'hE5);                     row(1'b0, 4'd4, AM_IMMED4,  4'd1, "immed.4");

    // ---- two bytes --------------------------------------------------------
    clr; push(B_000); push(8'h12);        row(1'b0, 4'd4, AM_DISP8,        4'd2, "disp.8[Rn]");
    clr; push(8'hF0); push(8'h12);        row(1'b0, 4'd4, AM_PCDISP8,      4'd2, "disp.8[PC]");
    clr; push(B_100); push(8'h12);        row(1'b0, 4'd4, AM_DISP8_IND,    4'd2, "[disp.8[Rn]]");
    clr; push(8'hF8); push(8'h12);        row(1'b0, 4'd4, AM_PCDISP8_IND,  4'd2, "[disp.8[PC]]");
    clr; push(B_IDX); push(B_011);        row(1'b1, 4'd4, AM_RN_IND,       4'd2, "[Rn](Rx)");
    clr; push(8'hF4); push(8'h5A);        row(1'b0, 4'd1, AM_IMMED,        4'd2, "immed.8");

    // ---- three bytes ------------------------------------------------------
    clr; push(B_001); push(8'h34); push(8'h12);
                                          row(1'b0, 4'd4, AM_DISP16,       4'd3, "disp.16[Rn]");
    clr; push(8'hF1); push(8'h34); push(8'h12);
                                          row(1'b0, 4'd4, AM_PCDISP16,     4'd3, "disp.16[PC]");
    clr; push(B_101); push(8'h34); push(8'h12);
                                          row(1'b0, 4'd4, AM_DISP16_IND,   4'd3, "[disp.16[Rn]]");
    clr; push(8'hF9); push(8'h34); push(8'h12);
                                          row(1'b0, 4'd4, AM_PCDISP16_IND, 4'd3, "[disp.16[PC]]");
    clr; push(8'hF4); push(8'hCD); push(8'hAB);
                                          row(1'b0, 4'd2, AM_IMMED,        4'd3, "immed.16");
    clr; push(B_000); push(8'h22); push(8'h11);
                                          row(1'b1, 4'd4, AM_DDISP8,       4'd3, "disp1.8[disp2.8[Rn]]");
    clr; push(8'hFC); push(8'h22); push(8'h11);
                                          row(1'b0, 4'd4, AM_PCDDISP8,     4'd3, "disp1.8[disp2.8[PC]]");
    clr; push(B_IDX); push(B_000); push(8'h12);
                                          row(1'b1, 4'd4, AM_DISP8,        4'd3, "disp.8[Rn](Rx)");
    clr; push(B_IDX); push(8'hF0); push(8'h12);
                                          row(1'b1, 4'd4, AM_PCDISP8,      4'd3, "disp.8[PC](Rx)");
    clr; push(B_IDX); push(B_100); push(8'h12);
                                          row(1'b1, 4'd4, AM_DISP8_IND,    4'd3, "[disp.8[Rn]](Rx)");
    clr; push(B_IDX); push(8'hF8); push(8'h12);
                                          row(1'b1, 4'd4, AM_PCDISP8_IND,  4'd3, "[disp.8[PC]](Rx)");

    // ---- four bytes -------------------------------------------------------
    clr; push(B_IDX); push(B_001); push(8'h34); push(8'h12);
                                          row(1'b1, 4'd4, AM_DISP16,       4'd4, "disp.16[Rn](Rx)");
    clr; push(B_IDX); push(8'hF1); push(8'h34); push(8'h12);
                                          row(1'b1, 4'd4, AM_PCDISP16,     4'd4, "disp.16[PC](Rx)");
    clr; push(B_IDX); push(B_101); push(8'h34); push(8'h12);
                                          row(1'b1, 4'd4, AM_DISP16_IND,   4'd4, "[disp.16[Rn]](Rx) (FIGURE-TYPO: printed 100)");
    clr; push(B_IDX); push(8'hF9); push(8'h34); push(8'h12);
                                          row(1'b1, 4'd4, AM_PCDISP16_IND, 4'd4, "[disp.16[PC]](Rx) (FIGURE-TYPO: printed 11111000)");

    // ---- five bytes -------------------------------------------------------
    clr; push(B_010); push4(32'h12345678);
                                          row(1'b0, 4'd4, AM_DISP32,       4'd5, "disp.32[Rn]");
    clr; push(8'hF2); push4(32'h12345678);
                                          row(1'b0, 4'd4, AM_PCDISP32,     4'd5, "disp.32[PC]");
    clr; push(B_110); push4(32'h12345678);
                                          row(1'b0, 4'd4, AM_DISP32_IND,   4'd5, "[disp.32[Rn]]");
    clr; push(8'hFA); push4(32'h12345678);
                                          row(1'b0, 4'd4, AM_PCDISP32_IND, 4'd5, "[disp.32[PC]]");
    clr; push(B_001); push(8'h22); push(8'h02); push(8'h11); push(8'h01);
                                          row(1'b1, 4'd4, AM_DDISP16,      4'd5, "disp1.16[disp2.16[Rn]]");
    clr; push(8'hFD); push(8'h22); push(8'h02); push(8'h11); push(8'h01);
                                          row(1'b0, 4'd4, AM_PCDDISP16,    4'd5, "disp1.16[disp2.16[PC]]");
    clr; push(8'hF3); push4(32'h00123456);
                                          row(1'b0, 4'd4, AM_ADDR,         4'd5, "/addr");
    clr; push(8'hFB); push4(32'h00123456);
                                          row(1'b0, 4'd4, AM_ADDR_IND,     4'd5, "[/addr]");
    clr; push(8'hF4); push4(32'hDEADBEEF);
                                          row(1'b0, 4'd4, AM_IMMED,        4'd5, "immed.32");

    // ---- six bytes: the 32-bit forms, indexed -----------------------------
    clr; push(B_IDX); push(B_010); push4(32'h12345678);
                                          row(1'b1, 4'd4, AM_DISP32,       4'd6, "disp.32[Rn](Rx)");
    clr; push(B_IDX); push(8'hF2); push4(32'h12345678);
                                          row(1'b1, 4'd4, AM_PCDISP32,     4'd6, "disp.32[PC](Rx)");
    clr; push(B_IDX); push(B_110); push4(32'h12345678);
                                          row(1'b1, 4'd4, AM_DISP32_IND,   4'd6, "[disp.32[Rn]](Rx)");
    clr; push(B_IDX); push(8'hFA); push4(32'h12345678);
                                          row(1'b1, 4'd4, AM_PCDISP32_IND, 4'd6, "[disp.32[PC]](Rx)");
    clr; push(B_IDX); push(8'hF3); push4(32'h00123456);
                                          row(1'b1, 4'd4, AM_ADDR,         4'd6, "/addr(Rx)");
    clr; push(B_IDX); push(8'hFB); push4(32'h00123456);
                                          row(1'b1, 4'd4, AM_ADDR_IND,     4'd6, "[/addr](Rx)");

    // ---- nine bytes: the longest mod field the figure has -----------------
    clr; push(B_010); push4(32'h22222222); push4(32'h11111111);
                                          row(1'b1, 4'd4, AM_DDISP32,      4'd9, "disp1.32[disp2.32[Rn]]");
    clr; push(8'hFE); push4(32'h22222222); push4(32'h11111111);
                                          row(1'b0, 4'd4, AM_PCDDISP32,    4'd9, "disp1.32[disp2.32[PC]]");

    // ---- the encodings the figure does not print --------------------------
    clr; push(8'hF5);                     row(1'b0, 4'd4, AM_RESERVED, 4'd1, "11110101 reserved");
    clr; push(8'hF6);                     row(1'b0, 4'd4, AM_RESERVED, 4'd1, "11110110 reserved");
    clr; push(8'hF7);                     row(1'b0, 4'd4, AM_RESERVED, 4'd1, "11110111 reserved");
    clr; push(8'hFF);                     row(1'b0, 4'd4, AM_RESERVED, 4'd1, "11111111 reserved");

    // =======================================================================
    // What the three cells the figure prints differently decode to AS PRINTED.
    // The point is not that they are wrong -- it is that as printed they
    // collide with rows the figure has already spent, which is the argument
    // in docs/v60/ADDRESSING-MODES.md.
    // =======================================================================
    // [Rn] as printed is 001 Rn with m=0.  Feed that byte and the decoder --
    // correctly, by the figure's own three-byte row -- reads disp.16[Rn] and
    // swallows the two bytes that follow it, which are the next instruction.
    clr; push(B_001); push(8'h00); push(8'h00);
                                          row(1'b0, 4'd4, AM_DISP16, 4'd3, "as printed, [Rn] eats two more bytes");

    // [disp.16[Rn]](Rx) as printed is an index byte over 100 Rn, which the
    // figure has already given to [disp.8[Rn]](Rx): three bytes, not four.
    // The fourth byte -- the displacement's high half -- would be read as an
    // opcode.
    clr; push(B_IDX); push(B_100); push(8'h34);
                                          row(1'b1, 4'd4, AM_DISP8_IND, 4'd3, "as printed, [disp.16[Rn]](Rx) is three bytes");

    // =======================================================================
    // Byte order, sign extension, and which displacement is which.
    // =======================================================================

    // Little endian, and the base register comes from the mode byte.
    clr; push(B_001); push(8'h34); push(8'h12); run(1'b0, 4'd4);
    chk(disp === 32'h00001234, "disp.16 is little endian");
    chk(rn   === RN,           "disp.16[Rn] takes Rn from the mode byte");
    chk(has_index === 1'b0,    "disp.16[Rn] has no index");

    // "Disp = signed displacement" -- p.3.294.
    clr; push(B_000); push(8'h80);              run(1'b0, 4'd4);
    chk(disp === 32'hFFFFFF80, "disp.8 is sign extended");
    clr; push(B_001); push(8'h00); push(8'h80); run(1'b0, 4'd4);
    chk(disp === 32'hFFFF8000, "disp.16 is sign extended");
    clr; push(B_010); push4(32'h80000000);      run(1'b0, 4'd4);
    chk(disp === 32'h80000000, "disp.32 is itself");

    // An absolute address is not a displacement: 32 bits, unaltered.
    clr; push(8'hF3); push4(32'hFF001234);      run(1'b0, 4'd4);
    chk(disp === 32'hFF001234, "/addr is not sign extended");
    chk(base_none === 1'b1,    "/addr has no base register");

    // Double displacement: the INNER one is nearer the mode byte.
    clr; push(B_000); push(8'h22); push(8'h11); run(1'b1, 4'd4);
    chk(disp       === 32'h00000022, "double displacement: disp2 is the inner one and comes first");
    chk(disp_outer === 32'h00000011, "double displacement: disp1 is the outer one and comes last");
    chk(ea_indirect === 1'b1,        "double displacement reads a pointer");

    // The index byte comes first and carries Rx; the mode byte after it is
    // decoded in the m=0 column, which is how [Rn](Rx) is [Rn] indexed.
    clr; push(B_IDX); push(B_011);              run(1'b1, 4'd4);
    chk(has_index === 1'b1, "[Rn](Rx) has an index");
    chk(rx === RX,          "[Rn](Rx) takes Rx from the index byte");
    chk(rn === RN,          "[Rn](Rx) takes Rn from the mode byte");
    chk(mode === AM_RN_IND, "[Rn](Rx): the byte after an index byte decodes with m=0");

    // A new operand does not inherit the last one's index register.
    clr; push(B_011);                           run(1'b0, 4'd4);
    chk(has_index === 1'b0, "a new operand clears the previous index");

    // Immediates.
    clr; push(8'hF4); push(8'hCD); push(8'hAB); run(1'b0, 4'd2);
    chk(imm[15:0]  === 16'hABCD, "immed.16 is little endian");
    chk(imm_bytes  === 4'd2,     "immed.16 takes two bytes from the stream");
    chk(immediate  === 1'b1,     "immed.16 is an immediate");
    chk(mem_operand === 1'b0,    "an immediate operand makes no data access");

    clr; push(8'hE5);                           run(1'b0, 4'd4);
    chk(imm[3:0]  === 4'd5,  "immed.4 carries its value in the mode byte");
    chk(imm_bytes === 4'd0,  "immed.4 takes no bytes from the stream");

    // The figure stops at immed.32; a long real operand is eight bytes and
    // the decoder emits what it is asked for.  See the open item in
    // docs/v60/ADDRESSING-MODES.md.
    clr; push(8'hF4); push4(32'h89ABCDEF); push4(32'h01234567);
                                                run(1'b0, 4'd8);
    chk(imm === 64'h0123456789ABCDEF, "immed.64 assembles all eight bytes");
    chk(len === 4'd9,                 "immed.64 makes a nine byte mod field");

    // =======================================================================
    // What an operand costs, which is the reason this table is worth having.
    // =======================================================================
    clr; push(B_011);                           run(1'b1, 4'd4);
    chk(reg_direct  === 1'b1, "Rn is the operand");
    chk(mem_operand === 1'b0, "Rn makes no data access");
    chk(ea_indirect === 1'b0, "Rn reads no pointer");

    clr; push(B_011);                           run(1'b0, 4'd4);
    chk(mem_operand === 1'b1, "[Rn] makes one data access");
    chk(ea_indirect === 1'b0, "[Rn] reads no pointer");

    clr; push(B_100); push(8'h12);              run(1'b0, 4'd4);
    chk(mem_operand === 1'b1, "[disp.8[Rn]] makes one data access");
    chk(ea_indirect === 1'b1, "[disp.8[Rn]] reads a pointer first");

    clr; push(8'hF9); push(8'h34); push(8'h12); run(1'b0, 4'd4);
    chk(base_pc     === 1'b1, "[disp.16[PC]] is PC relative");
    chk(ea_indirect === 1'b1, "[disp.16[PC]] reads a pointer first");

    clr; push(B_100);                           run(1'b1, 4'd4);
    chk(autoinc === 1'b1 && autodec === 1'b0, "[Rn+] increments");
    clr; push(B_101);                           run(1'b1, 4'd4);
    chk(autodec === 1'b1 && autoinc === 1'b0, "[-Rn] decrements");

    clr; push(8'hFF);                           run(1'b0, 4'd4);
    chk(reserved === 1'b1,     "an unprinted encoding is a reserved mode");
    chk(mem_operand === 1'b0,  "a reserved mode accesses nothing");

    // =======================================================================
    // The 111 group decodes the same for both values of m.  That is a
    // DECISION -- the figure prints no m=1 row for the group -- so it is
    // checked against the encoding function directly: no operand the FSM can
    // be fed reaches a 111 byte with m=1, because an index byte spends the
    // m=1 slot before the byte after it is decoded.
    chk(am_mode_of(1'b1, 8'hF0) === AM_PCDISP8,      "m=1: 11110000 is still disp.8[PC]");
    chk(am_mode_of(1'b1, 8'hF3) === AM_ADDR,         "m=1: 11110011 is still /addr");
    chk(am_mode_of(1'b1, 8'hF4) === AM_IMMED,        "m=1: 11110100 is still immed.N");
    chk(am_mode_of(1'b1, 8'hFB) === AM_ADDR_IND,     "m=1: 11111011 is still [/addr]");
    chk(am_mode_of(1'b1, 8'hFE) === AM_PCDDISP32,    "m=1: 11111110 is still the PC double displacement");
    chk(am_mode_of(1'b1, 8'hE5) === AM_IMMED4,       "m=1: 1110 val is still immed.4");
    chk(am_mode_of(1'b1, 8'hFF) === AM_RESERVED,     "m=1: 11111111 is still reserved");

    if (errors == 0) $display("V60 AM DECODE PASS");
    else             $display("V60 AM DECODE FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #2_000_000;
    $display("V60 AM DECODE FAIL (timeout)");
    $finish;
end

endmodule
