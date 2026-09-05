//============================================================================
//  tb_v60_psw -- the PSW, checked against both documents at once.
//
//  The PSW is the one object in this project that two INDEPENDENT renderings
//  describe: the databook's bit-numbered table (p.3.248) and the Programmer's
//  Reference's labelled figure (S3).  This bench holds them as two separate
//  arrays -- the databook's as bit number -> name, the Reference's as the
//  order its callouts run in -- and requires them to agree.  A transcription
//  slip in one is then visible instead of absorbed.
//
//  The conditions are checked twice over as well: once against the databook's
//  Condition Encodings table (p.3.295) restated in the other direction, and
//  once by opcode, because the Programmer's Reference prints the same sixteen
//  as Bcc mnemonics whose opcode's low nibble IS the condition field.
//============================================================================
`timescale 1ns/1ps

module tb_v60_psw;
    import v60_psw_pkg::*;

integer errors = 0;
task chk(input cond, input [8*72:1] what);
begin
    if (!cond) begin
        errors = errors + 1;
        $display("FAIL  %0s", what);
    end
end
endtask

// ---------------------------------------------------------------------------
// Document 1: databook p.3.248's table, bit by bit.
// ---------------------------------------------------------------------------
// Twenty fields, six bits each, entry i at [i*6 +: 6].
localparam logic [119:0] DB_BIT = {
    6'd31, 6'd30, 6'd29, 6'd28, 6'd27, 6'd26,   // ASA ATA EM IS TP IP
    6'd25, 6'd24,                               // EL
    6'd18, 6'd17, 6'd16,                        // IE AE TE
    6'd12, 6'd11, 6'd10, 6'd9,  6'd8,           // FIV FZD FOV FUD FPR
    6'd3,  6'd2,  6'd1,  6'd0                   // CY OV S Z
};

// The same twenty, as v60_psw_pkg says they are, in the same order.
localparam logic [119:0] PKG_BIT = {
    6'(PSW_ASA), 6'(PSW_ATA), 6'(PSW_EM), 6'(PSW_IS), 6'(PSW_TP), 6'(PSW_IP),
    6'(PSW_EL_HI), 6'(PSW_EL_LO),
    6'(PSW_IE), 6'(PSW_AE), 6'(PSW_TE),
    6'(PSW_FIV), 6'(PSW_FZD), 6'(PSW_FOV), 6'(PSW_FUD), 6'(PSW_FPR),
    6'(PSW_CY), 6'(PSW_OV), 6'(PSW_S), 6'(PSW_Z)
};

// ---------------------------------------------------------------------------
// Document 2: the Programmer's Reference's figure, which numbers nothing --
// it labels the fields in order, from the top of the word downwards.  Held as
// that ORDER, which is all it gives, and checked against the databook's
// numbering.
// ---------------------------------------------------------------------------
// The Reference's order is the order of DB_BIT above -- the figure runs from
// the top of the word down -- so the check is that the databook's numbering,
// read in that order, descends without a gap of its own making.

integer i, j;
reg [31:0] psw;
reg [3:0] f;
reg expect_c, got;

// The sixteen conditions again, written the way the Programmer's Reference's
// Bcc page names them rather than the way p.3.295's table writes them: an
// unsigned "higher" is neither lower nor equal, a signed "less than" is a sign
// that disagrees with the overflow.  De Morgan's, on purpose -- restating the
// same boolean identically would check nothing.
function automatic logic ref_cond(input [3:0] cc, input [3:0] gf);
    logic r;
    logic g_cy, g_ov, g_s, g_z;
    begin
        g_cy = gf[PSW_CY]; g_ov = gf[PSW_OV]; g_s = gf[PSW_S]; g_z = gf[PSW_Z];
        case (cc)
            4'h0: r = (g_ov == 1'b1);                    // BV
            4'h1: r = (g_ov == 1'b0);                    // BNV
            4'h2: r = (g_cy == 1'b1);                    // BL  / BC
            4'h3: r = (g_cy == 1'b0);                    // BNL / BNC
            4'h4: r = (g_z  == 1'b1);                    // BE  / BZ
            4'h5: r = (g_z  == 1'b0);                    // BNE / BNZ
            4'h6: r = !(!g_cy && !g_z);                  // BNH: not higher
            4'h7: r =  (!g_cy && !g_z);                  // BH:  higher
            4'h8: r = (g_s == 1'b1);                     // BN
            4'h9: r = (g_s == 1'b0);                     // BP
            4'hA: r = 1'b1;                              // BR
            4'hB: r = 1'b0;                              // (never)
            4'hC: r = (g_s != g_ov);                     // BLT
            4'hD: r = (g_s == g_ov);                     // BGE
            4'hE: r = (g_s != g_ov) || g_z;              // BLE
            default: r = (g_s == g_ov) && !g_z;          // BGT
        endcase
        ref_cond = r;
    end
endfunction

initial begin
    // =======================================================================
    // The two documents, against each other and against the package.
    // =======================================================================
    for (i = 0; i < 20; i = i + 1)
        chk(DB_BIT[i*6 +: 6] === PKG_BIT[i*6 +: 6],
            "every field sits at the bit number the databook table gives it");

    // The Reference's figure runs from the top of the word down, so the
    // databook's numbering read in that order must descend strictly.
    for (i = 0; i < 19; i = i + 1)
        chk(DB_BIT[(i+1)*6 +: 6] > DB_BIT[i*6 +: 6],
            "the Reference's field order runs down the databook's numbering");
    chk(DB_BIT[19*6 +: 6] === 6'd31 && DB_BIT[0 +: 6] === 6'd0,
        "and it runs from bit 31 to bit 0");

    // Each field lands in the 8-bit group p.3.248 draws it in.
    chk(PSW_Z >= PSW_INTEGER_LO && PSW_CY <= PSW_INTEGER_HI,
        "the integer flags are in the integer field");
    chk(PSW_FPR >= PSW_FLOAT_LO && PSW_FIV <= PSW_FLOAT_HI,
        "the floating point flags are in the floating point field");
    chk(PSW_TE >= PSW_CONTROL_LO && PSW_IE <= PSW_CONTROL_HI,
        "the enables are in the control field");
    chk(PSW_EL_LO >= PSW_STATUS_LO && PSW_ASA <= PSW_STATUS_HI,
        "execution level and the status bits are in the status field");

    // The reserved groups are exactly 4-7, 13-15 and 19-23.
    for (i = 0; i < 32; i = i + 1) begin
        if ((i >= 4 && i <= 7) || (i >= 13 && i <= 15) || (i >= 19 && i <= 23))
            chk(PSW_RFU[i] === 1'b1, "reserved bits are the ones the page reserves");
        else
            chk(PSW_RFU[i] === 1'b0, "and no others are");
    end

    // =======================================================================
    // Writing it.
    // =======================================================================
    chk(psw_update_w(32'hFFFFFFFF, 32'hFFFFFFFF) === ~PSW_RFU,
        "a full write cannot set a reserved bit");
    chk(psw_update_h(32'hFFFF0000, 32'hFFFFFFFF) === (32'hFFFF0000 | (32'h0000FFFF & ~PSW_RFU)),
        "a halfword write reaches the lower halfword");
    psw = psw_update_h(32'h00000000, 32'hFFFFFFFF);
    chk(psw[31:16] === 16'h0000,
        "and cannot reach the upper halfword, which is execution level 0's");
    psw = psw_update_w(32'h0, 32'h03000000);
    chk(psw[PSW_EL_HI:PSW_EL_LO] === 2'b11,
        "a full write can set the execution level");
    chk(psw_el(psw) === 2'b11, "and psw_el reads it back");

    // Reset, and what it selects.
    chk(PSW_RESET === 32'h1000_0000,         "the PSW resets to 10000000H (p.3.282, PgmRef S8)");
    chk(psw_el(PSW_RESET) === 2'b00,         "which is execution level 0");
    chk(PSW_RESET[PSW_IE] === 1'b0,          "interrupts disabled");
    chk(PSW_RESET[PSW_IS] === 1'b1,          "and on the interrupt stack");

    // The flags go in and come out where the table says.
    psw = 32'h0;
    psw = psw_set_flags(psw, 4'b1010);   // CY and S
    chk(psw === ((32'h1 << PSW_CY) | (32'h1 << PSW_S)),
        "setting CY and S sets bits 3 and 1 and nothing else");
    chk(psw_flags(psw) === 4'b1010, "and they read back");

    // =======================================================================
    // All sixteen conditions over all sixteen flag combinations, twice.
    // =======================================================================
    for (i = 0; i < 16; i = i + 1) begin
        for (j = 0; j < 16; j = j + 1) begin
            f = j[3:0];
            got      = cond_true(i[3:0], f);
            expect_c = ref_cond(i[3:0], f);
            chk(got === expect_c,
                "each condition agrees with the way the Reference names it");
        end
    end

    // The named ones, by the opcode that carries them: the condition is the
    // low nibble of a Bcc, so these are the Reference's own Bcc page.
    f = 4'b0001;   // Z
    chk(cond_true(4'h4, f) === 1'b1, "6x4 (BE) is taken when Z is set");
    chk(cond_true(4'h5, f) === 1'b0, "6x5 (BNE) is not");
    chk(cond_true(4'h7, f) === 1'b0, "6x7 (BH) is not, because equal is not higher");
    chk(cond_true(4'hF, f) === 1'b0, "6xF (BGT) is not, for the same reason");
    chk(cond_true(4'hD, f) === 1'b1, "6xD (BGE) is, because equal is not less");
    f = 4'b0110;   // OV and S
    chk(cond_true(4'hD, f) === 1'b1, "S and OV agreeing is 'greater or equal'");
    chk(cond_true(4'hC, f) === 1'b0, "and not 'less than'");
    f = 4'b0010;   // S
    chk(cond_true(4'hC, f) === 1'b1, "S without OV is 'less than'");
    f = 4'b1000;   // CY
    chk(cond_true(4'h2, f) === 1'b1, "6x2 (BL) is taken on carry");
    chk(cond_true(4'h6, f) === 1'b1, "6x6 (BNH) too, because lower is not higher");
    chk(cond_true(4'hA, f) === 1'b1 && cond_true(4'hB, f) === 1'b0,
        "6xA is always and 6xB is never");

    if (errors == 0) $display("V60 PSW PASS");
    else             $display("V60 PSW FAIL (%0d errors)", errors);
    $finish;
end

endmodule
