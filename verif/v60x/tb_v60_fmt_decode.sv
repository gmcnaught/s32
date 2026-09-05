//============================================================================
//  tb_v60_fmt_decode -- the seven formats, field by field, from real opcodes.
//
//  Every case below is a byte string as it would sit in memory, fed one byte
//  per clock the way v60_pfu hands them out.  The format is NOT told to the
//  decoder: it looks the opcode up in v60_op_pkg, which is generated from the
//  instruction-set table (tools/v60x/insn_table.py), so these cases exercise
//  the table as well as the field extraction.
//
//  Checked against the figure on databook p.3.293: which byte is the opcode,
//  where m / m' / d / reg / subop live, how long the base is, and which mod
//  fields follow.  The last two cases run v60_fmt_decode and v60_am_decode
//  over one byte stream, so an instruction's total length is measured.
//============================================================================
`timescale 1ns/1ps

module tb_v60_fmt_decode;
    import v60_fmt_pkg::*;
    import v60_op_pkg::*;
    import v60_am_pkg::*;

reg clk = 1'b0;
always #5 clk = ~clk;

reg          rst = 1'b1;
reg          f_start = 1'b0, byte_valid = 1'b0;
reg    [7:0] byte_in = 8'h00;

wire         f_busy, f_done;
insn_fmt_e   f_fmt;
wire   [7:0] f_op;
wire         f_m, f_m2, f_d;
wire   [4:0] f_reg, f_subop;
wire  [31:0] f_disp;
wire   [3:0] f_len;
wire         need_mod, need_ext, need_mod2, need_ext2, m_mod, m_mod2;

v60_fmt_decode dut (
    .clk(clk), .rst(rst),
    .start(f_start),
    .byte_valid(byte_valid), .byte_in(byte_in),
    .busy(f_busy), .done(f_done), .fmt_out(f_fmt),
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

// Feed the base of an instruction.  The opcode is seq[0]; nothing tells the
// decoder what format to expect.
task base;
    integer i;
begin
    @(negedge clk);
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

// Feed one mod field to the addressing-mode decoder.
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
        if (a_done) i = nseq;
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
    // Format I and Format II are the SAME opcode.  MOV.B is 0x09, which the
    // instruction-set table lists as "I, II"; bit 15 of the base word decides.
    // 0x45 = 0100_0101 -> bit15 = 0, m = 1, d = 0, reg = 5
    // =======================================================================
    clr; push(8'h09); push(8'h45); base;
    chk(f_fmt === FMT_I,      "MOV.B with bit 15 clear is Format I");
    chk(f_op === 8'h09,       "Format I: the opcode is the first byte");
    chk(f_m === 1'b1,         "Format I: m is bit 14 of the word");
    chk(f_d === 1'b0,         "Format I: d is bit 13");
    chk(f_reg === 5'd5,       "Format I: reg is bits 12:8");
    chk(f_len === 4'd2,       "Format I: the base is two bytes");
    chk(need_mod === 1'b1 && need_mod2 === 1'b0,
                              "Format I: one mod field -- the other operand is reg");
    chk(m_mod === 1'b1,       "Format I: the mod field is decoded with m");
    chk(need_ext === 1'b0 && need_ext2 === 1'b0, "Format I: no extension field");

    // 0xA3 = 1010_0011 -> bit15 = 1, m = 0, m' = 1, subop = 3
    clr; push(8'h09); push(8'hA3); base;
    chk(f_fmt === FMT_II,     "the same opcode with bit 15 set is Format II");
    chk(f_m === 1'b0 && f_m2 === 1'b1, "Format II: m is bit 14 and m' is bit 13");
    chk(f_subop === 5'd3,     "Format II: subop is bits 12:8");
    chk(f_len === 4'd2,       "Format II: the base is two bytes");
    chk(need_mod === 1'b1 && need_mod2 === 1'b1, "Format II: two mod fields");
    chk(m_mod === 1'b0 && m_mod2 === 1'b1,
                              "Format II: each mod field gets its own m");

    // =======================================================================
    // Format III: JMP is 1101011-, one byte of base, m at the bottom of it.
    // =======================================================================
    clr; push(8'hD7); base;
    chk(f_fmt === FMT_III, "JMP is Format III");
    chk(f_len === 4'd1,    "Format III: the base is ONE byte");
    chk(f_m === 1'b1,      "Format III: m is bit 0 of that byte");
    chk(m_mod === 1'b1,    "Format III: the mod field is decoded with it");
    chk(need_mod === 1'b1 && need_mod2 === 1'b0, "Format III: one mod field");
    clr; push(8'hD6); base;
    chk(f_fmt === FMT_III, "JMP's other byte value is the same instruction");
    chk(f_m === 1'b0,      "Format III: and the other value of bit 0");

    // =======================================================================
    // Format IV: Bcc is 011 b cccc, and the width is in the opcode -- 6x is a
    // byte displacement and 7x a halfword (Programmer's Reference S7), which
    // is the same b bit as p.3.295.  Nothing outside has to say.
    // =======================================================================
    clr; push(8'h60); push(8'h80); base;
    chk(f_fmt === FMT_IV,         "Bcc is Format IV");
    chk(f_len === 4'd2,           "Format IV: opcode plus a byte displacement");
    chk(f_disp === 32'hFFFFFF80,  "Format IV: disp8 is signed");
    chk(need_mod === 1'b0,        "Format IV: no mod field");
    clr; push(8'h70); push(8'h34); push(8'h12); base;
    chk(f_len === 4'd3,           "Format IV: opcode plus a halfword displacement");
    chk(f_disp === 32'h00001234,  "Format IV: disp16 is little endian");

    // =======================================================================
    // Format V: NOP is 0xCD, and nothing follows it at all.
    // =======================================================================
    clr; push(8'hCD); base;
    chk(f_fmt === FMT_V, "NOP is Format V");
    chk(f_len === 4'd1,  "Format V: one byte");
    chk(need_mod === 1'b0 && need_mod2 === 1'b0 &&
        need_ext === 1'b0 && need_ext2 === 1'b0, "Format V: nothing follows");

    // =======================================================================
    // Format VI: TB is 0xC7.  subop is THREE bits here.
    // 0xA5 = 1010_0101 -> subop = 101, reg = 5
    // =======================================================================
    clr; push(8'hC7); push(8'hA5); push(8'h34); push(8'h12); base;
    chk(f_fmt === FMT_VI,        "TB is Format VI");
    chk(f_len === 4'd4,          "Format VI: opcode, fields and a halfword displacement");
    chk(f_subop === 5'd5,        "Format VI: subop is bits 15:13");
    chk(f_reg === 5'd5,          "Format VI: reg is bits 12:8");
    chk(f_disp === 32'h00001234, "Format VI: the displacement follows the word");
    chk(need_mod === 1'b0,       "Format VI: no mod field");

    // =======================================================================
    // The escape opcodes: 0x58-0x5F carry a subop and their format depends on
    // it.  The second byte is `1 m m' subop`, so 0xA8 is m=0, m'=1, subop=8.
    // =======================================================================
    clr; push(8'h58); push(8'hA8); base;   // MOVC
    chk(f_fmt === FMT_VIIA, "MOVC is Format VIIa");
    chk(need_mod && need_ext && need_mod2 && need_ext2,
        "Format VIIa: mod, ext, mod', ext'");

    clr; push(8'h5B); push(8'hA8); base;   // MOVBS
    chk(f_fmt === FMT_VIIB, "MOVBS is Format VIIb");
    chk(need_mod && need_ext && need_mod2 && !need_ext2,
        "Format VIIb: mod, ext, mod' -- no ext'");

    clr; push(8'h59); push(8'hA0); base;   // ADDDC
    chk(f_fmt === FMT_VIIC, "ADDDC is Format VIIc");
    chk(need_mod && !need_ext && need_mod2 && need_ext2,
        "Format VIIc: mod, mod', ext' -- no ext");

    // The headline reason the table is not an 8-bit lookup: one opcode byte,
    // two formats, told apart by the subop.
    clr; push(8'h5D); push(8'hA8); base;   // EXTBF, subop 8
    chk(f_fmt === FMT_VIIB, "0x5D with subop 8 is EXTBF: Format VIIb");
    clr; push(8'h5D); push(8'hB8); base;   // INSBF, subop 0x18
    chk(f_fmt === FMT_VIIC, "0x5D with subop 0x18 is INSBF: Format VIIc");

    // An opcode the instruction set does not assign.  Nothing can be said
    // about its length either, so the decoder stops at the opcode byte and the
    // sequencer takes the reserved-opcode exception.
    clr; push(8'h06); base;
    chk(f_fmt === FMT_UNKNOWN, "0x06 is not an instruction: reserved opcode");
    chk(f_len === 4'd1,        "a reserved opcode consumes only itself");

    // The extension field's own encoding, p.3.293.
    chk(ext_is_register(8'h80) === 1'b1, "ext bit 7 set: the length is in a register");
    chk(ext_value(8'h80) === 7'd0,       "and bits 6:0 are that register's id");
    chk(ext_is_register(8'h20) === 1'b0, "ext bit 7 clear: bits 6:0 are the length");
    chk(ext_value(8'h20) === 7'd32,      "and that length is what they say");

    // =======================================================================
    // Two whole instructions, measured rather than asserted.
    // =======================================================================
    // MOV.B as Format I, m = 1: one mod field of one byte (011 Rn with m=1).
    clr; push(8'h09); push(8'h45); base;
    total = f_len;
    clr; push(8'h67);              modfield(m_mod);
    chk(a_mode === AM_RN, "whole instruction: the mod field decodes as Rn");
    total = total + a_len;
    chk(total == 3, "whole instruction: Format I with a register operand is three bytes");

    // MOV.B as Format II, m = 0 and m' = 0: [Rn] and disp.16[Rn].
    // 0x80 = 1000_0000 -> bit15 = 1, m = 0, m' = 0, subop = 0
    clr; push(8'h09); push(8'h80); base;
    total = f_len;
    chk(f_fmt === FMT_II, "whole instruction: 0x80 makes it Format II");
    chk(m_mod === 1'b0 && m_mod2 === 1'b0, "whole instruction: m = 0, m' = 0");
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
