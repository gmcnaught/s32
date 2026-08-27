//============================================================================
//  tb_v60_fmt_decode -- the seven formats, field by field.
//
//  Every case below is a byte string as it would sit in memory, fed one byte
//  per clock the way v60_pfu hands them out, and checked against the figure on
//  databook p.3.293: which byte is the opcode, where m / m' / d / reg / subop
//  live, how long the base is, and which mod fields follow.
//
//  The last two cases run the real thing: v60_fmt_decode followed by
//  v60_am_decode over one byte stream, so the instruction's total length is
//  measured rather than asserted.
//============================================================================
`timescale 1ns/1ps

module tb_v60_fmt_decode;
    import v60_fmt_pkg::*;
    import v60_am_pkg::*;

reg clk = 1'b0;
always #5 clk = ~clk;

reg          rst = 1'b1;
reg          f_start = 1'b0, byte_valid = 1'b0;
reg    [7:0] byte_in = 8'h00;
insn_fmt_e   f_fmt = FMT_V;
reg    [1:0] f_ivd = 2'd1;

wire         f_busy, f_done;
wire   [7:0] f_op;
wire         f_m, f_m2, f_d;
wire   [4:0] f_reg, f_subop;
wire  [31:0] f_disp;
wire   [3:0] f_len;
wire         need_mod, need_ext, need_mod2, need_ext2, m_mod, m_mod2;

v60_fmt_decode dut (
    .clk(clk), .rst(rst),
    .start(f_start), .fmt(f_fmt), .iv_disp_bytes(f_ivd),
    .byte_valid(byte_valid), .byte_in(byte_in),
    .busy(f_busy), .done(f_done),
    .op(f_op), .m(f_m), .m2(f_m2), .d(f_d), .reg_field(f_reg),
    .subop(f_subop), .disp(f_disp), .base_len(f_len),
    .need_mod(need_mod), .need_ext(need_ext), .need_mod2(need_mod2),
    .need_ext2(need_ext2), .m_mod(m_mod), .m_mod2(m_mod2)
);

// The mod-field decoder, on the same byte stream.
reg        a_start = 1'b0, a_m = 1'b0;
reg  [3:0] a_opbytes = 4'd4;
wire       a_busy, a_done;
am_mode_e  a_mode;
wire [3:0] a_len;

v60_am_decode amd (
    .clk(clk), .rst(rst),
    .start(a_start), .m(a_m), .opbytes(a_opbytes),
    .byte_valid(byte_valid), .byte_in(byte_in),
    .busy(a_busy), .done(a_done), .mode(a_mode),
    .rn(), .rx(), .has_index(), .disp(), .disp_outer(),
    .imm(), .imm_bytes(), .len(a_len),
    .base_pc(), .base_none(), .reg_direct(), .immediate(),
    .mem_operand(), .ea_indirect(), .autoinc(), .autodec(), .reserved()
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

// ---- a byte string ---------------------------------------------------------
reg [7:0] seq [0:11];
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

// Feed the base of an instruction to the format decoder.
task base(input [3:0] fmt_in, input [1:0] ivd);
    integer i;
begin
    @(negedge clk);
    f_fmt = insn_fmt_e'(fmt_in);
    f_ivd = ivd;
    for (i = 0; i < nseq; i = i + 1) begin
        byte_in    = seq[i];
        byte_valid = 1'b1;
        f_start    = (i == 0);
        @(negedge clk);
    end
    byte_valid = 1'b0;
    f_start    = 1'b0;
    // The invariant behind every case below: the format says how long its base
    // is, so feeding exactly that many bytes must finish it.  A format left
    // waiting for a byte that is not coming would otherwise pass these checks
    // on the previous instruction's fields.
    chk(f_done === 1'b1, "the base decoder finished on the bytes the format defines");
end
endtask

// Feed one mod field to the addressing-mode decoder and return its length.
task modfield(input mm);
    integer i;
begin
    @(negedge clk);
    a_m = mm;
    for (i = 0; i < nseq; i = i + 1) begin
        byte_in    = seq[i];
        byte_valid = 1'b1;
        a_start    = (i == 0);
        @(negedge clk);
        if (a_done) i = nseq;      // it took what it needed
    end
    byte_valid = 1'b0;
    a_start    = 1'b0;
end
endtask

integer total;

initial begin
    repeat (4) @(negedge clk);
    rst = 1'b0;
    @(negedge clk);

    // =======================================================================
    // Format I:  [mod] [0 m d reg] [op]
    // 0x45 = 0100_0101 -> bit15 of the word is 0, m = 1, d = 0, reg = 5
    // =======================================================================
    clr; push(8'h09); push(8'h45); base(FMT_I, 2'd0);
    chk(f_done === 1'b1,      "Format I: the base is decoded");
    chk(f_op === 8'h09,       "Format I: the opcode is the first byte");
    chk(f_m === 1'b1,         "Format I: m is bit 14 of the word");
    chk(f_d === 1'b0,         "Format I: d is bit 13");
    chk(f_reg === 5'd5,       "Format I: reg is bits 12:8");
    chk(f_len === 4'd2,       "Format I: the base is two bytes");
    chk(need_mod === 1'b1 && need_mod2 === 1'b0,
                              "Format I: one mod field -- the other operand is reg");
    chk(m_mod === 1'b1,       "Format I: the mod field is decoded with m");
    chk(need_ext === 1'b0 && need_ext2 === 1'b0, "Format I: no extension field");

    // =======================================================================
    // Format II:  [mod'] [mod] [1 m m' subop] [op]
    // 0xA3 = 1010_0011 -> bit15 = 1, m = 0, m' = 1, subop = 3
    // =======================================================================
    clr; push(8'h09); push(8'hA3); base(FMT_II, 2'd0);
    chk(f_m === 1'b0 && f_m2 === 1'b1, "Format II: m is bit 14 and m' is bit 13");
    chk(f_subop === 5'd3,     "Format II: subop is bits 12:8");
    chk(f_len === 4'd2,       "Format II: the base is two bytes");
    chk(need_mod === 1'b1 && need_mod2 === 1'b1, "Format II: two mod fields");
    chk(m_mod === 1'b0 && m_mod2 === 1'b1,
                              "Format II: each mod field gets its own m");
    chk(need_ext === 1'b0 && need_ext2 === 1'b0, "Format II: no extension field");

    // =======================================================================
    // Format III:  [mod] [op(7:1) m]  -- one byte of base, m at the bottom
    // =======================================================================
    clr; push(8'hD7); base(FMT_III, 2'd0);
    chk(f_len === 4'd1,  "Format III: the base is ONE byte");
    chk(f_m === 1'b1,    "Format III: m is bit 0 of that byte");
    chk(m_mod === 1'b1,  "Format III: the mod field is decoded with it");
    chk(need_mod === 1'b1 && need_mod2 === 1'b0, "Format III: one mod field");
    clr; push(8'hD6); base(FMT_III, 2'd0);
    chk(f_m === 1'b0,    "Format III: and the other value of bit 0");

    // =======================================================================
    // Format IV:  [disp8/disp16] [op].  "b = 0 byte / b = 1 halfword" is in
    // the opcode for Bcc (p.3.295), so the width arrives as an input.
    // =======================================================================
    clr; push(8'h60); push(8'h80); base(FMT_IV, 2'd1);
    chk(f_len === 4'd2,           "Format IV: opcode plus a byte displacement");
    chk(f_disp === 32'hFFFFFF80,  "Format IV: disp8 is signed");
    chk(need_mod === 1'b0,        "Format IV: no mod field");
    clr; push(8'h68); push(8'h34); push(8'h12); base(FMT_IV, 2'd2);
    chk(f_len === 4'd3,           "Format IV: opcode plus a halfword displacement");
    chk(f_disp === 32'h00001234,  "Format IV: disp16 is little endian");

    // =======================================================================
    // Format V:  [op].  Nothing else at all.
    // =======================================================================
    clr; push(8'hCD); base(FMT_V, 2'd0);
    chk(f_len === 4'd1, "Format V: one byte");
    chk(f_op === 8'hCD, "Format V: and it is the opcode");
    chk(need_mod === 1'b0 && need_mod2 === 1'b0 &&
        need_ext === 1'b0 && need_ext2 === 1'b0, "Format V: nothing follows");

    // =======================================================================
    // Format VI:  [disp16] [subop reg] [op].  subop is THREE bits here.
    // 0xA5 = 1010_0101 -> subop = 101, reg = 5
    // =======================================================================
    clr; push(8'hC7); push(8'hA5); push(8'h34); push(8'h12); base(FMT_VI, 2'd0);
    chk(f_len === 4'd4,          "Format VI: opcode, fields and a halfword displacement");
    chk(f_subop === 5'd5,        "Format VI: subop is bits 15:13");
    chk(f_reg === 5'd5,          "Format VI: reg is bits 12:8");
    chk(f_disp === 32'h00001234, "Format VI: the displacement follows the word");
    chk(need_mod === 1'b0,       "Format VI: no mod field");

    // =======================================================================
    // Format VII: the three of them differ only in which extension fields
    // they carry, and the order is always mod, ext, mod', ext'.
    // =======================================================================
    clr; push(8'h58); push(8'hA0); base(FMT_VIIA, 2'd0);
    chk(need_mod && need_ext && need_mod2 && need_ext2,
        "Format VIIa: mod, ext, mod', ext'");
    clr; push(8'h5B); push(8'hA0); base(FMT_VIIB, 2'd0);
    chk(need_mod && need_ext && need_mod2 && !need_ext2,
        "Format VIIb: mod, ext, mod' -- no ext'");
    clr; push(8'h59); push(8'hA0); base(FMT_VIIC, 2'd0);
    chk(need_mod && !need_ext && need_mod2 && need_ext2,
        "Format VIIc: mod, mod', ext' -- no ext");

    // The extension field's own encoding, p.3.293.
    chk(ext_is_register(8'h80) === 1'b1, "ext bit 7 set: the length is in a register");
    chk(ext_value(8'h80) === 7'd0,       "and bits 6:0 are that register's id");
    chk(ext_is_register(8'h20) === 1'b0, "ext bit 7 clear: bits 6:0 are the length");
    chk(ext_value(8'h20) === 7'd32,      "and that length is what they say");

    // =======================================================================
    // Two whole instructions, measured rather than asserted.
    // =======================================================================
    // Format I, m = 1, one mod field of one byte: 011 Rn with m=1 is Rn.
    clr; push(8'h09); push(8'h45); base(FMT_I, 2'd0);
    total = f_len;
    clr; push(8'h67);              modfield(m_mod);
    chk(a_mode === AM_RN, "whole instruction: the mod field decodes as Rn");
    total = total + a_len;
    chk(total == 3, "whole instruction: Format I with a register operand is three bytes");

    // Format II, m = 0 and m' = 1: [Rn] and Rn, one byte each.
    // 0x80 = 1000_0000 -> bit15 = 1 (Format II), m = 0, m' = 0, subop = 0
    clr; push(8'h09); push(8'h80); base(FMT_II, 2'd0);
    total = f_len;
    chk(m_mod === 1'b0 && m_mod2 === 1'b0, "whole instruction: 0x80 is m = 0, m' = 0");
    clr; push(8'h67);              modfield(m_mod);
    chk(a_mode === AM_RN_IND, "whole instruction: the first operand is [Rn]");
    total = total + a_len;
    clr; push(8'h27); push(8'h34); push(8'h12); modfield(m_mod2);
    chk(a_mode === AM_DISP16, "whole instruction: the second operand is disp.16[Rn]");
    total = total + a_len;
    chk(total == 6, "whole instruction: Format II with [Rn] and disp.16[Rn] is six bytes");

    if (errors == 0) $display("V60 FMT PASS");
    else             $display("V60 FMT FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #2_000_000;
    $display("V60 FMT FAIL (timeout)");
    $finish;
end

endmodule
