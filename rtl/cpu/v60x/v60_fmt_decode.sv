//============================================================================
//  v60_fmt_decode -- everything in an instruction that is not a mod field.
//
//  Clean-room.  Source: the instruction-format figure on databook p.3.293.
//  Takes the instruction stream a byte at a time -- the interface v60_pfu
//  hands out -- consumes the opcode byte, the second half of the base word
//  where the format has one, and the displacement that formats IV and VI
//  carry.  It then says what follows: which mod fields the format has, in
//  which order, and which `m` bit applies to each.  The mod fields themselves
//  belong to v60_am_decode, which is why this stops at them.
//
//  Fields, from the figure:
//
//    I     [mod]              [0 m d reg]     [op]     bit15=0
//    II    [mod'] [mod]       [1 m m' subop]  [op]     bit15=1
//    III   [mod]                              [op(7:1) m]   -- ONE byte
//    IV    [disp8/disp16]                     [op]
//    V                                        [op]
//    VI    [disp16]           [subop reg]     [op]
//    VIIa  [ext'] [mod'] [ext] [mod] [1 m m' subop] [op]
//    VIIb         [mod'] [ext] [mod] [1 m m' subop] [op]
//    VIIc  [ext'] [mod']       [mod] [1 m m' subop] [op]
//
//  Two things this deliberately does not decide, both in
//  docs/v60/INSTRUCTION-FORMATS.md:
//
//    * WHICH FORMAT an opcode is.  That is the instruction-set table on
//      pp.3.296-3.301 and it is a separate job -- for the escape opcodes the
//      format depends on the SUBOP as well, so it is not an 8-bit lookup.
//      `fmt` is an input here.
//    * How wide Format IV's displacement is.  For Bcc the `b` bit in the
//      opcode says (p.3.295: "b = 0 byte, b = 1 halfword"), but Format IV is
//      not only Bcc.  `iv_disp_bytes` is an input.
//============================================================================
`timescale 1ns/1ps

module v60_fmt_decode
    import v60_fmt_pkg::*;
(
    input               clk,
    input               rst,

    input               start,          // asserted WITH the opcode byte
    input  insn_fmt_e   fmt,
    input         [1:0] iv_disp_bytes,  // Format IV only: 1 or 2

    input               byte_valid,
    input         [7:0] byte_in,

    output logic        busy,
    output logic        done,           // base decoded; the plan below is set

    // ---- fields -----------------------------------------------------------
    output logic  [7:0] op,             // the first byte, whole and unaltered
    output logic        m,              // operand 1's addressing-mode bit
    output logic        m2,             // operand 2's (m' in the figure)
    output logic        d,              // Format I direction bit
    output logic  [4:0] reg_field,      // Format I, Format VI
    output logic  [4:0] subop,          // Format II, VII (5 bits), VI (3)
    output logic [31:0] disp,           // Format IV and VI, sign extended
    output logic  [3:0] base_len,       // bytes consumed here

    // ---- what follows, in this order: mod, ext, mod', ext' ----------------
    output logic        need_mod,
    output logic        need_ext,
    output logic        need_mod2,
    output logic        need_ext2,
    output logic        m_mod,          // the m to decode mod with
    output logic        m_mod2          // ... and mod'
);

typedef enum logic [1:0] { S_OP, S_SECOND, S_DISP } state_e;

state_e      state;
insn_fmt_e   fmt_r;
logic  [1:0] ivd_r;
logic  [3:0] cnt, want;
logic [31:0] acc;

wire taking = byte_valid && (start || busy);

// Sign extension of the Format IV / VI displacement.  "disp: signed
// displacement" -- p.3.294's legend, and the branch displacement table on
// p.3.295 gives the two widths.
function automatic logic [31:0] sext(input logic [31:0] v, input logic [3:0] w);
    case (w)
        4'd1:    sext = {{24{v[7]}},  v[7:0]};
        4'd2:    sext = {{16{v[15]}}, v[15:0]};
        default: sext = v;
    endcase
endfunction

always_ff @(posedge clk) begin
    if (rst) begin
        state     <= S_OP;
        busy      <= 1'b0;
        done      <= 1'b0;
        op        <= 8'd0;
        m         <= 1'b0;
        m2        <= 1'b0;
        d         <= 1'b0;
        reg_field <= 5'd0;
        subop     <= 5'd0;
        disp      <= 32'd0;
        base_len  <= 4'd0;
        need_mod  <= 1'b0;
        need_ext  <= 1'b0;
        need_mod2 <= 1'b0;
        need_ext2 <= 1'b0;
        m_mod     <= 1'b0;
        m_mod2    <= 1'b0;
        fmt_r     <= FMT_UNKNOWN;
        ivd_r     <= 2'd0;
        cnt       <= 4'd0;
        want      <= 4'd0;
        acc       <= 32'd0;
    end else begin
        done <= 1'b0;

        if (start) begin
            busy      <= 1'b1;
            state     <= S_OP;
            fmt_r     <= fmt;
            ivd_r     <= iv_disp_bytes;
            base_len  <= 4'd0;
            cnt       <= 4'd0;
            acc       <= 32'd0;
            disp      <= 32'd0;
            m         <= 1'b0;
            m2        <= 1'b0;
            d         <= 1'b0;
            reg_field <= 5'd0;
            subop     <= 5'd0;
            // The plan is the package's statement about the format, not this
            // module's: one place says which mod fields a format carries.
            need_mod  <= fmt_has_mod(fmt);
            need_ext  <= fmt_has_ext(fmt);
            need_mod2 <= fmt_has_mod2(fmt);
            need_ext2 <= fmt_has_ext2(fmt);
        end

        if (taking) begin
            base_len <= (start ? 4'd0 : base_len) + 4'd1;

            if (start || (state == S_OP)) begin
                op <= byte_in;

                // Format III is the one format whose m rides in the opcode
                // byte: "op(7:1) m", p.3.293.
                if (fmt == FMT_III) begin
                    m     <= byte_in[0];
                    m_mod <= byte_in[0];
                end

                if (fmt_has_second_byte(fmt)) begin
                    state <= S_SECOND;
                    busy  <= 1'b1;
                end else if (fmt_disp_bytes(fmt, iv_disp_bytes) != 4'd0) begin
                    state <= S_DISP;
                    want  <= fmt_disp_bytes(fmt, iv_disp_bytes);
                    cnt   <= 4'd0;
                    busy  <= 1'b1;
                end else begin
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end else if (state == S_SECOND) begin
                case (fmt_r)
                    // "0 m d reg" -- bit 15 is 0 and identifies Format I.
                    FMT_I: begin
                        m         <= byte_in[6];
                        d         <= byte_in[5];
                        reg_field <= byte_in[4:0];
                        m_mod     <= byte_in[6];
                        busy      <= 1'b0;
                        done      <= 1'b1;
                    end
                    // "subop reg" over the displacement that follows.
                    FMT_VI: begin
                        subop     <= {2'b00, byte_in[7:5]};
                        reg_field <= byte_in[4:0];
                        state     <= S_DISP;
                        want      <= fmt_disp_bytes(fmt_r, ivd_r);
                        cnt       <= 4'd0;
                        busy      <= 1'b1;
                    end
                    // "1 m m' subop" -- Format II and all three of VII.
                    default: begin
                        m         <= byte_in[6];
                        m2        <= byte_in[5];
                        subop     <= byte_in[4:0];
                        m_mod     <= byte_in[6];
                        m_mod2    <= byte_in[5];
                        busy      <= 1'b0;
                        done      <= 1'b1;
                    end
                endcase
            end else begin   // S_DISP
                acc[cnt[1:0]*8 +: 8] <= byte_in;
                cnt <= cnt + 4'd1;
                if (cnt + 4'd1 == want) begin
                    disp <= sext(acc | ({24'd0, byte_in} << (cnt[1:0]*8)), want);
                    busy <= 1'b0;
                    done <= 1'b1;
                end
            end
        end
    end
end

// synthesis translate_off
always_ff @(posedge clk) begin
    if (!rst && start && (fmt == FMT_UNKNOWN))
        $display("WARN v60_fmt_decode: started on an opcode with no format -- the instruction-set table has to say (t=%0t)",
                 $time);
    if (!rst && start && (fmt == FMT_IV) &&
        !((iv_disp_bytes == 2'd1) || (iv_disp_bytes == 2'd2)))
        $display("WARN v60_fmt_decode: Format IV takes disp8 or disp16, not %0d bytes (t=%0t)",
                 iv_disp_bytes, $time);
end
// synthesis translate_on

endmodule
