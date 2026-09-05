//============================================================================
//  v60_am_pkg -- the V60's addressing-mode vocabulary, from databook S5.
//
//  Clean-room.  Source: the figure "mod Field - Addressing Mode Encoding",
//  NEC_uPD70616_V60_DataBook_1986.pdf p.3.294, printed again as Appendix C of
//  the Programmer's Reference.  docs/v60/ADDRESSING-MODES.md carries the whole
//  table, the byte order, and the argument for the three cells where the
//  figure contradicts itself -- read that before changing anything here.
//
//  The mode is a FOUR bit decision: bits 7:5 of the first mod byte plus the
//  instruction word's m field (p.3.293).  Bits 4:0 of the byte are Rn.  Code
//  111 is the group that needs no register -- PC relative, absolute,
//  immediate -- and is decoded without m; see am_mode_of() for why that is the
//  page's own requirement and not a convenience.
//============================================================================
`ifndef V60_AM_PKG_SV
`define V60_AM_PKG_SV

package v60_am_pkg;

// One value per row of the figure's right-hand column.  The displacement
// width is part of the identity because it is part of the encoding: the
// figure gives disp.8, disp.16 and disp.32 three different mod codes.
typedef enum logic [4:0] {
    AM_RN            = 5'd0,   // Rn
    AM_RN_IND        = 5'd1,   // [Rn]
    AM_RN_INC        = 5'd2,   // [Rn+]
    AM_RN_DEC        = 5'd3,   // [-Rn]
    AM_DISP8         = 5'd4,   // disp.8[Rn]
    AM_DISP16        = 5'd5,   // disp.16[Rn]
    AM_DISP32        = 5'd6,   // disp.32[Rn]
    AM_DISP8_IND     = 5'd7,   // [disp.8[Rn]]
    AM_DISP16_IND    = 5'd8,   // [disp.16[Rn]]
    AM_DISP32_IND    = 5'd9,   // [disp.32[Rn]]
    AM_DDISP8        = 5'd10,  // disp1.8[disp2.8[Rn]]
    AM_DDISP16       = 5'd11,  // disp1.16[disp2.16[Rn]]
    AM_DDISP32       = 5'd12,  // disp1.32[disp2.32[Rn]]
    AM_PCDISP8       = 5'd13,  // disp.8[PC]
    AM_PCDISP16      = 5'd14,  // disp.16[PC]
    AM_PCDISP32      = 5'd15,  // disp.32[PC]
    AM_PCDISP8_IND   = 5'd16,  // [disp.8[PC]]
    AM_PCDISP16_IND  = 5'd17,  // [disp.16[PC]]
    AM_PCDISP32_IND  = 5'd18,  // [disp.32[PC]]
    AM_PCDDISP8      = 5'd19,  // disp1.8[disp2.8[PC]]
    AM_PCDDISP16     = 5'd20,  // disp1.16[disp2.16[PC]]
    AM_PCDDISP32     = 5'd21,  // disp1.32[disp2.32[PC]]
    AM_ADDR          = 5'd22,  // /addr
    AM_ADDR_IND      = 5'd23,  // [/addr]
    AM_IMMED         = 5'd24,  // immed.N -- N is the OPERAND's data length
    AM_IMMED4        = 5'd25,  // immed.4, value in bits 3:0 of the mode byte
    AM_INDEX         = 5'd26,  // 110 Rx -- an index byte, not a mode by itself
    AM_RESERVED      = 5'd27   // reserved addressing mode exception
} am_mode_e;

// ---------------------------------------------------------------------------
// The mode byte.
// ---------------------------------------------------------------------------
// Two things here depart from what p.3.294 literally prints, both because the
// printed cell makes the table undecodable -- two modes sharing one encoding.
// The argument is in docs/v60/ADDRESSING-MODES.md and is drawn from the
// figure's own indexed rows; it is not taken from any other implementation.
//
//   [Rn] is printed 001 Rn with m=0, which is already disp.16[Rn].  It is
//   011 with m=0: the figure's own [Rn](Rx) row is an index byte followed by
//   base byte 011 Rn, and the byte after an index byte is decoded in the m=0
//   column.
//
//   [disp.16[Rn]](Rx) and [disp.16[PC]](Rx) are printed with the 8-bit codes
//   100 / 11111000, which the figure has already spent on the 8-bit indexed
//   indirect forms four rows above.  They are 101 / 11111001, which is what
//   the internally consistent 32-bit group below them looks like.  That
//   affects no code here -- both bytes already decode to the right mode by the
//   slot map -- and is recorded so the difference from the page is not a
//   surprise.
//
// The 111 group ignores m, and THAT ONE IS A DECISION, not a transcription.
// The figure prints every 111 row with m=0 and prints no m=1 row for the group
// at all, so what an m=1 operand whose first mod byte is 1110vvvv or 1111xxxx
// means is not on the page.  Two things argue for decoding it the same way:
// the group needs no register, so the m bit has no second interpretation to
// select; and the figure's indexed rows already decode these bytes inside an
// m=1 operand, where the m=1 slot has been spent on the index byte.  Marked
// here because a later page, or silicon, could say otherwise.
function automatic am_mode_e am_mode_of(input logic m, input logic [7:0] b);
    am_mode_e r;
    begin
        case (b[7:5])
            3'b000: if (m) r = AM_DDISP8;  else r = AM_DISP8;
            3'b001: if (m) r = AM_DDISP16; else r = AM_DISP16;
            3'b010: if (m) r = AM_DDISP32; else r = AM_DISP32;
            3'b011: if (m) r = AM_RN;      else r = AM_RN_IND;
            3'b100: if (m) r = AM_RN_INC;  else r = AM_DISP8_IND;
            3'b101: if (m) r = AM_RN_DEC;  else r = AM_DISP16_IND;
            3'b110: if (m) r = AM_INDEX;   else r = AM_DISP32_IND;
            default: begin
                if (b[4] == 1'b0) r = AM_IMMED4;        // 1110 val
                else case (b[3:0])                      // 1111 xxxx
                    4'h0: r = AM_PCDISP8;
                    4'h1: r = AM_PCDISP16;
                    4'h2: r = AM_PCDISP32;
                    4'h3: r = AM_ADDR;
                    4'h4: r = AM_IMMED;
                    4'h8: r = AM_PCDISP8_IND;
                    4'h9: r = AM_PCDISP16_IND;
                    4'hA: r = AM_PCDISP32_IND;
                    4'hB: r = AM_ADDR_IND;
                    4'hC: r = AM_PCDDISP8;
                    4'hD: r = AM_PCDDISP16;
                    4'hE: r = AM_PCDDISP32;
                    // 5, 6, 7 and F are not printed.  "These addressing mode
                    // encodings are reserved for future extensions to the
                    // addressing modes" -- Programmer's Reference S8.
                    default: r = AM_RESERVED;
                endcase
            end
        endcase
        am_mode_of = r;
    end
endfunction

// ---------------------------------------------------------------------------
// Attributes of a mode.  Each is a fact from the figure's right-hand column.
// ---------------------------------------------------------------------------

// Width of ONE displacement field, in bytes.  A double displacement has two
// fields of this width; an absolute address is four bytes and is reported
// here because it occupies the same position in the byte stream.
function automatic logic [3:0] am_disp_bytes(input am_mode_e mode);
    logic [3:0] r;
    begin
        case (mode)
            AM_DISP8,  AM_DISP8_IND,  AM_DDISP8,
            AM_PCDISP8,  AM_PCDISP8_IND,  AM_PCDDISP8:   r = 4'd1;
            AM_DISP16, AM_DISP16_IND, AM_DDISP16,
            AM_PCDISP16, AM_PCDISP16_IND, AM_PCDDISP16:  r = 4'd2;
            AM_DISP32, AM_DISP32_IND, AM_DDISP32,
            AM_PCDISP32, AM_PCDISP32_IND, AM_PCDDISP32,
            AM_ADDR,   AM_ADDR_IND:                      r = 4'd4;
            default:                                     r = 4'd0;
        endcase
        am_disp_bytes = r;
    end
endfunction

// Two displacement fields: the inner one locates a pointer, the outer one is
// added to what the pointer holds.
function automatic logic am_is_double(input am_mode_e mode);
    am_is_double = (mode == AM_DDISP8)   || (mode == AM_DDISP16)   ||
                   (mode == AM_DDISP32)  || (mode == AM_PCDDISP8)  ||
                   (mode == AM_PCDDISP16)|| (mode == AM_PCDDISP32);
endfunction

// The effective address calculation reads a 32-bit pointer from memory.  On
// System 32's 16-bit bus that is two bus cycles, before the operand's own
// access.
function automatic logic am_is_indirect(input am_mode_e mode);
    am_is_indirect = (mode == AM_DISP8_IND)   || (mode == AM_DISP16_IND)   ||
                     (mode == AM_DISP32_IND)  || (mode == AM_PCDISP8_IND)  ||
                     (mode == AM_PCDISP16_IND)|| (mode == AM_PCDISP32_IND) ||
                     (mode == AM_ADDR_IND)    || am_is_double(mode);
endfunction

// The base is the PC rather than a general register.
function automatic logic am_base_is_pc(input am_mode_e mode);
    am_base_is_pc = (mode == AM_PCDISP8)     || (mode == AM_PCDISP16)     ||
                    (mode == AM_PCDISP32)    || (mode == AM_PCDISP8_IND)  ||
                    (mode == AM_PCDISP16_IND)|| (mode == AM_PCDISP32_IND) ||
                    (mode == AM_PCDDISP8)    || (mode == AM_PCDDISP16)    ||
                    (mode == AM_PCDDISP32);
endfunction

// No base at all: the address is in the instruction, or there is no address.
function automatic logic am_base_is_none(input am_mode_e mode);
    am_base_is_none = (mode == AM_ADDR)  || (mode == AM_ADDR_IND) ||
                      (mode == AM_IMMED) || (mode == AM_IMMED4)   ||
                      (mode == AM_RESERVED);
endfunction

// The operand IS the register.  No bus cycle of any kind.
function automatic logic am_is_reg_direct(input am_mode_e mode);
    am_is_reg_direct = (mode == AM_RN);
endfunction

// The operand is in the instruction stream.  No data bus cycle -- the bytes
// arrive as part of the mod field.
function automatic logic am_is_immediate(input am_mode_e mode);
    am_is_immediate = (mode == AM_IMMED) || (mode == AM_IMMED4);
endfunction

// Number of data bus accesses the OPERAND itself makes, once the address is
// known.  Register direct and immediate make none; everything else makes one,
// whose width is the operand's data type, not the mode's.
function automatic logic am_has_memory_operand(input am_mode_e mode);
    am_has_memory_operand = !(am_is_reg_direct(mode) || am_is_immediate(mode) ||
                              (mode == AM_INDEX) || (mode == AM_RESERVED));
endfunction

endpackage

`endif
