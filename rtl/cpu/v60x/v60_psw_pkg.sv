//============================================================================
//  v60_psw_pkg -- the program status word, and the condition it decides.
//
//  Clean-room.  The PSW is the best-sourced object in this project: the
//  databook gives it as a table with a bit-numbered figure above it
//  (p.3.248) and the Programmer's Reference gives it as a labelled figure with
//  a prose description (S3).  Those are two independent renderings -- unlike
//  the p.3.294 mod-field figure, which is one figure printed in two books --
//  and they agree.  tb_v60_psw holds both and checks that they still do.
//
//      31    24 23    16 15     8 7      0
//      | Status | Control | Float | Integer |      -- p.3.248's four fields
//
//  The privilege rule is on the same page, and it is why there are two widths
//  of UPDPSW:
//
//    "The lower halfword is accessible to all programs and contains the
//     integer and floating point condition codes.  The upper halfword contains
//     the processor control and status fields and can only be modified by
//     programs running at execution level 0."  -- p.3.248
//
//  The condition encodings are the databook's Condition Encodings table
//  (p.3.295), cross-checked against the Programmer's Reference's Bcc page,
//  which prints the same sixteen as mnemonics with their opcode bytes: the
//  condition is the low nibble of a 6x / 7x opcode, so BGT is 6F and cc 1111.
//============================================================================
`ifndef V60_PSW_PKG_SV
`define V60_PSW_PKG_SV

package v60_psw_pkg;

// ---------------------------------------------------------------------------
// Bit positions, from the table on p.3.248.
// ---------------------------------------------------------------------------
localparam int PSW_Z     = 0;    // Z   = 1: zero integer result
localparam int PSW_S     = 1;    // S   = 1: negative integer result
localparam int PSW_OV    = 2;    // OV  = 1: integer overflow occurred
localparam int PSW_CY    = 3;    // CY  = 1: a carry (borrow) was generated
localparam int PSW_FPR   = 8;    // floating point precision fault
localparam int PSW_FUD   = 9;    // floating point underflow
localparam int PSW_FOV   = 10;   // floating point overflow
localparam int PSW_FZD   = 11;   // floating point zero divide
localparam int PSW_FIV   = 12;   // floating point invalid operand
localparam int PSW_TE    = 16;   // instruction trace enabled
localparam int PSW_AE    = 17;   // address traps enabled
localparam int PSW_IE    = 18;   // maskable interrupts enabled
localparam int PSW_EL_LO = 24;   // execution level, 24:25
localparam int PSW_EL_HI = 25;
localparam int PSW_IP    = 26;   // instruction pending
localparam int PSW_TP    = 27;   // instruction trace pending
localparam int PSW_IS    = 28;   // interrupt stack active
localparam int PSW_EM    = 29;   // V20/V30 emulation mode enabled
localparam int PSW_ATA   = 30;   // asynchronous task trap being serviced
localparam int PSW_ASA   = 31;   // asynchronous system trap being serviced

// "Reserved for future use (Must be 0)" at 4-7, 13-15 and 19-23 -- p.3.248.
localparam logic [31:0] PSW_RFU = 32'h00F8_E0F0;

// The four 8-bit fields the page draws above the table.
localparam int PSW_INTEGER_LO = 0,  PSW_INTEGER_HI = 7;
localparam int PSW_FLOAT_LO   = 8,  PSW_FLOAT_HI   = 15;
localparam int PSW_CONTROL_LO = 16, PSW_CONTROL_HI = 23;
localparam int PSW_STATUS_LO  = 24, PSW_STATUS_HI  = 31;

// "PSW 00000000H" at reset -- databook p.3.238.  Which is also EL = 0
// (privileged), interrupts disabled, and the interrupt stack not in use.
localparam logic [31:0] PSW_RESET = 32'h0000_0000;

// ---------------------------------------------------------------------------
// The integer flags, as one nibble.  It needs no order of its own: CY OV S Z
// are bits 3 2 1 0 of the PSW (p.3.248), so the flags ARE the low nibble and
// the same constants index both.
// ---------------------------------------------------------------------------
function automatic logic [3:0] psw_flags(input logic [31:0] psw);
    psw_flags = psw[3:0];
endfunction

function automatic logic [31:0] psw_set_flags(input logic [31:0] psw,
                                              input logic  [3:0] f);
    psw_set_flags = {psw[31:4], f};
endfunction

function automatic logic [1:0] psw_el(input logic [31:0] psw);
    psw_el = psw[PSW_EL_HI:PSW_EL_LO];
endfunction

// ---------------------------------------------------------------------------
// Writing it.  UPDPSW.W is the whole word and is privileged; UPDPSW.H is the
// lower halfword, which "is accessible to all programs" (p.3.248).  The
// reserved bits are dropped in both, because the page says they must be 0.
// ---------------------------------------------------------------------------
function automatic logic [31:0] psw_update_w(input logic [31:0] old,
                                             input logic [31:0] val);
    psw_update_w = val & ~PSW_RFU;
endfunction

function automatic logic [31:0] psw_update_h(input logic [31:0] old,
                                             input logic [31:0] val);
    psw_update_h = {old[31:16], val[15:0] & ~PSW_RFU[15:0]};
endfunction

// ---------------------------------------------------------------------------
// The condition, from the Condition Encodings table on p.3.295.  The four bits
// are the instruction's c3 c2 c1 c0, which for Bcc are the low nibble of the
// opcode byte (Programmer's Reference S7: BV is 6x0, BGT is 6xF).
// ---------------------------------------------------------------------------
function automatic logic cond_true(input logic [3:0] cc, input logic [3:0] f);
    logic cy, ov, sg, z, r;
    begin
        cy = f[PSW_CY];  ov = f[PSW_OV];  sg = f[PSW_S];  z = f[PSW_Z];
        case (cc)
            4'h0: r =  ov;                      // Overflow            OV = 1
            4'h1: r = !ov;                      // No overflow         OV = 0
            4'h2: r =  cy;                      // Carry / Lower       CY = 1
            4'h3: r = !cy;                      // No carry / Not lower
            4'h4: r =  z;                       // Zero / Equal        Z = 1
            4'h5: r = !z;                       // Not zero / Not equal
            4'h6: r =  (cy | z);                // Not higher   (CY v Z) = 1
            4'h7: r = !(cy | z);                // Higher       (CY v Z) = 0
            4'h8: r =  sg;                      // Sign / Negative     S = 1
            4'h9: r = !sg;                      // Not sign / Positive S = 0
            4'hA: r = 1'b1;                     // True                Always
            4'hB: r = 1'b0;                     // False               Never
            4'hC: r =  (sg ^ ov);               // Less than    (S+OV) = 1
            4'hD: r = !(sg ^ ov);               // Greater or equal
            4'hE: r =  ((sg ^ ov) | z);         // Less or equal
            default: r = !((sg ^ ov) | z);      // Greater than
        endcase
        cond_true = r;
    end
endfunction

endpackage

`endif
