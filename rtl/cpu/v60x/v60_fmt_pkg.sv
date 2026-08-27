//============================================================================
//  v60_fmt_pkg -- the seven instruction formats, from databook p.3.293.
//
//  Clean-room.  "The uPD70616 instruction set operation codes are described by
//  seven instruction formats" (p.3.293), and the figure on that page gives the
//  bit position of every field in each.  Transcribed here; the field layout,
//  the byte order and what this does NOT settle are in
//  docs/v60/INSTRUCTION-FORMATS.md.
//
//  Byte order is the same rule as the mod field's: the figure's bit 0 is the
//  lowest address, so `op` -- always at bits 7:0 -- is the first byte of every
//  instruction, and everything else follows it.
//============================================================================
`ifndef V60_FMT_PKG_SV
`define V60_FMT_PKG_SV

package v60_fmt_pkg;

typedef enum logic [3:0] {
    FMT_I    = 4'd0,   // [mod]        [0 m d reg] [op]
    FMT_II   = 4'd1,   // [mod'] [mod] [1 m m' subop] [op]
    FMT_III  = 4'd2,   // [mod]        [op(7) m]            -- ONE byte of base
    FMT_IV   = 4'd3,   // [disp8/disp16] [op]
    FMT_V    = 4'd4,   // [op]
    FMT_VI   = 4'd5,   // [disp16] [subop(3) reg] [op]
    FMT_VIIA = 4'd6,   // [ext'] [mod'] [ext] [mod] [1 m m' subop] [op]
    FMT_VIIB = 4'd7,   // [mod'] [ext] [mod] [1 m m' subop] [op]
    FMT_VIIC = 4'd8,   // [ext'] [mod'] [mod] [1 m m' subop] [op]

    // Two answers that are not yet a format.  The instruction-set table lists
    // most opcodes as "I, II" and the INSTRUCTION says which -- bit 15 of the
    // base word, because Format I is `0 m d reg` and Format II is
    // `1 m m' subop` in that position.  And the escape opcodes 0x58-0x5F
    // carry a subop that their format depends on.  v60_op_pkg returns these;
    // op_format() resolves them from the byte after the opcode.
    FMT_I_OR_II = 4'd9,
    FMT_ESCAPE  = 4'd10,

    FMT_UNKNOWN = 4'd15
} insn_fmt_e;

// The opcode byte is always there.  These say what else the format puts
// before its first mod field.

// The second half of the base word -- "0 m d reg", "1 m m' subop" or
// "subop reg".  Formats III, IV and V have no second half: III packs its m
// into the opcode byte and IV and V have nothing but the opcode.
// FMT_I_OR_II and FMT_ESCAPE are here because the byte that resolves them IS
// this second byte: bit 15 for the first, the subop for the second.
function automatic logic fmt_has_second_byte(input insn_fmt_e f);
    fmt_has_second_byte = (f == FMT_I) || (f == FMT_II) || (f == FMT_VI) ||
                          (f == FMT_VIIA) || (f == FMT_VIIB) || (f == FMT_VIIC) ||
                          (f == FMT_I_OR_II) || (f == FMT_ESCAPE);
endfunction

// The displacement two formats carry in the instruction itself: Format IV's
// disp8 or disp16 (the width is the caller's to know -- see
// docs/v60/INSTRUCTION-FORMATS.md) and Format VI's disp16.
function automatic logic [3:0] fmt_disp_bytes(input insn_fmt_e f,
                                              input logic [1:0] iv_disp);
    logic [3:0] r;
    begin
        case (f)
            FMT_IV:  r = {2'd0, iv_disp};
            FMT_VI:  r = 4'd2;
            default: r = 4'd0;
        endcase
        fmt_disp_bytes = r;
    end
endfunction

// Everything the format defines before its first mod field, derived from the
// two above so there is one statement of it and not three.
function automatic logic [3:0] fmt_base_bytes(input insn_fmt_e f,
                                              input logic [1:0] iv_disp);
    fmt_base_bytes = 4'd1 + {3'd0, fmt_has_second_byte(f)} +
                     fmt_disp_bytes(f, iv_disp);
endfunction

// The mod fields a format carries, in the order they appear: mod, then ext if
// the format has one, then mod', then ext'.  Format I's second operand is the
// `reg` field, not a mod field, which is why it has only one.
function automatic logic fmt_has_mod(input insn_fmt_e f);
    fmt_has_mod = (f == FMT_I) || (f == FMT_II) || (f == FMT_III) ||
                  (f == FMT_VIIA) || (f == FMT_VIIB) || (f == FMT_VIIC);
endfunction

function automatic logic fmt_has_mod2(input insn_fmt_e f);
    fmt_has_mod2 = (f == FMT_II) || (f == FMT_VIIA) || (f == FMT_VIIB) ||
                   (f == FMT_VIIC);
endfunction

function automatic logic fmt_has_ext(input insn_fmt_e f);
    fmt_has_ext = (f == FMT_VIIA) || (f == FMT_VIIB);
endfunction

function automatic logic fmt_has_ext2(input insn_fmt_e f);
    fmt_has_ext2 = (f == FMT_VIIA) || (f == FMT_VIIC);
endfunction

// ---------------------------------------------------------------------------
// The extension field, p.3.293, quoted whole because it is three lines long:
//
//   "The extension field is used to specify the length of a variable length
//    data type and is encoded as follows:
//      bit 7 (ext) = 0 ->  bits 6:0 (ext) are the operand length
//      bit 7 (ext) = 1 ->  bits 6:0 (ext) contain a pointer (register ID) to
//                          the general purpose register containing the operand
//                          length"
// ---------------------------------------------------------------------------
function automatic logic ext_is_register(input logic [7:0] e);
    ext_is_register = e[7];
endfunction

function automatic logic [6:0] ext_value(input logic [7:0] e);
    ext_value = e[6:0];
endfunction

endpackage

`endif
