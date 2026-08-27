//============================================================================
//  v60_am_decode -- decode one operand's mod field, byte by byte.
//
//  Clean-room.  Source: databook p.3.294 (the mod-field figure) and p.3.293
//  (the instruction formats, which is where the m field lives).  The whole
//  table, the byte order, and the three cells where the figure contradicts
//  itself are in docs/v60/ADDRESSING-MODES.md; the encoding itself is in
//  v60_am_pkg.
//
//  Byte by byte because that is how the field arrives: the mod field is 1 to 9
//  bytes and the instruction stream hands over one byte at a time.  Its order,
//  from the figure's ruler (bit 0 is the lowest address):
//
//      [index byte] [mode byte] [disp2 / val / addr] [disp1]
//
//  The index byte comes FIRST -- [Rn](Rx) is printed 011 Rn over 110 Rx with
//  the index byte at bits 7:0 -- and the INNER displacement of a double
//  displacement precedes the outer one.
//
//  Protocol: assert `start` together with the first mod byte (start implies
//  byte_valid).  Every output is registered, so `done` pulses on the cycle
//  AFTER the last byte is consumed and the description reads correct on that
//  same cycle.  Multi-byte fields are little endian and displacements are
//  sign extended; the figure calls them "signed displacement".
//
//  What this module does NOT do: compute an address.  Scaling an index
//  register by the operand's data type, adding the base, and reading the
//  pointer that the indirect modes need are the next stage's work.  This
//  reports WHAT the operand is, including whether that pointer read exists,
//  which is the quantity docs/v60/v60_operand_access.csv counts.
//============================================================================
`timescale 1ns/1ps

module v60_am_decode
    import v60_am_pkg::*;
(
    input               clk,
    input               rst,

    // ---- instruction stream ----------------------------------------------
    input               start,       // asserted WITH the first mod byte
    input               m,           // the instruction word's m field
    input         [3:0] opbytes,     // operand data length: 1, 2, 4 or 8.
                                     // immed.N takes its width from here --
                                     // the mod byte 11110100 does not carry it
    input               byte_valid,
    input         [7:0] byte_in,

    // ---- description ------------------------------------------------------
    output logic        busy,
    output logic        done,        // one-cycle pulse: description complete
    output am_mode_e    mode,
    output logic  [4:0] rn,          // base register
    output logic  [4:0] rx,          // index register, when has_index
    output logic        has_index,
    output logic [31:0] disp,        // displacement added to the base; for
                                     // /addr and [/addr] the address itself;
                                     // for a double displacement the INNER one
    output logic [31:0] disp_outer,  // added after the pointer read (double)
    output logic [63:0] imm,         // immediate operand
    output logic  [3:0] imm_bytes,   // immediate bytes taken from the stream
                                     // -- zero for immed.4, whose value is in
                                     // the mode byte
    output logic  [3:0] len,         // mod-field bytes consumed

    // ---- attributes of `mode`, for readers that do not want the enum ------
    output logic        base_pc,     // base is the PC, not a register
    output logic        base_none,   // no base: absolute, immediate, reserved
    output logic        reg_direct,  // operand IS the register: no bus cycle
    output logic        immediate,   // operand is in the instruction stream
    output logic        mem_operand, // operand access is a memory access
    output logic        ea_indirect, // EA calculation reads a 32-bit pointer
    output logic        autoinc,
    output logic        autodec,
    output logic        reserved     // reserved addressing mode exception
);

typedef enum logic [1:0] {
    S_MODE,     // waiting for a mode byte (the first, or one after an index)
    S_FIELD,    // collecting disp / disp2 / addr
    S_FIELD2,   // collecting disp1, the outer displacement
    S_IMM       // collecting an immediate operand
} state_e;

state_e      state;
logic        m_r;        // m for the byte being decoded; an index byte
                         // spends the m=1 slot, so the byte after one is
                         // decoded in the m=0 column (see v60_am_pkg)
logic  [3:0] cnt;        // bytes taken of the current field
logic  [3:0] width;      // bytes in the current field
logic [63:0] acc;

wire         m_eff      = start ? m : m_r;
wire         taking     = byte_valid && (start || busy);
wire         mode_phase = start || (state == S_MODE);

am_mode_e    dec;
logic  [3:0] dec_w;
logic [63:0] acc_next;

always_comb begin
    dec      = am_mode_of(m_eff, byte_in);
    dec_w    = am_disp_bytes(dec);
    acc_next = acc;
    acc_next[cnt[2:0]*8 +: 8] = byte_in;
end

// Attributes are functions of the mode, so they are decoded, not stored.
assign base_pc     = am_base_is_pc(mode);
assign base_none   = am_base_is_none(mode);
assign reg_direct  = am_is_reg_direct(mode);
assign immediate   = am_is_immediate(mode);
assign mem_operand = am_has_memory_operand(mode);
assign ea_indirect = am_is_indirect(mode);
assign autoinc     = (mode == AM_RN_INC);
assign autodec     = (mode == AM_RN_DEC);
assign reserved    = (mode == AM_RESERVED);

// Sign extension of a displacement field.  "Disp = signed displacement",
// p.3.294.  A four-byte field extends to itself, which is also what /addr
// wants -- an absolute address is not a displacement and must not be altered.
function automatic logic [31:0] sext(input logic [31:0] v, input logic [3:0] w);
    case (w)
        4'd1:    sext = {{24{v[7]}},  v[7:0]};
        4'd2:    sext = {{16{v[15]}}, v[15:0]};
        default: sext = v;
    endcase
endfunction

always_ff @(posedge clk) begin
    if (rst) begin
        state      <= S_MODE;
        busy       <= 1'b0;
        done       <= 1'b0;
        mode       <= AM_RESERVED;
        rn         <= 5'd0;
        rx         <= 5'd0;
        has_index  <= 1'b0;
        disp       <= 32'd0;
        disp_outer <= 32'd0;
        imm        <= 64'd0;
        imm_bytes  <= 4'd0;
        len        <= 4'd0;
        m_r        <= 1'b0;
        cnt        <= 4'd0;
        width      <= 4'd0;
        acc        <= 64'd0;
    end else begin
        done <= 1'b0;

        // A new operand clears the description, so nothing from the previous
        // one can be read back as though it belonged to this one.
        if (start) begin
            busy       <= 1'b1;
            m_r        <= m;
            state      <= S_MODE;
            len        <= 4'd0;
            cnt        <= 4'd0;
            has_index  <= 1'b0;
            rx         <= 5'd0;
            rn         <= 5'd0;
            disp       <= 32'd0;
            disp_outer <= 32'd0;
            imm        <= 64'd0;
            imm_bytes  <= 4'd0;
            acc        <= 64'd0;
        end

        if (taking) begin
            // `start` arrives WITH the first byte, so the clear above and this
            // count land on the same edge: take the cleared value here.
            len <= (start ? 4'd0 : len) + 4'd1;

            if (mode_phase) begin
                if (dec == AM_INDEX) begin
                    // An index byte.  It carries Rx and nothing else, and the
                    // mode byte follows it -- decoded in the m=0 column.
                    has_index <= 1'b1;
                    rx        <= byte_in[4:0];
                    m_r       <= 1'b0;
                    state     <= S_MODE;
                    busy      <= 1'b1;
                end else begin
                    mode  <= dec;
                    rn    <= byte_in[4:0];
                    acc   <= 64'd0;
                    cnt   <= 4'd0;

                    if (dec == AM_IMMED4) begin
                        // The value is in the byte: "1110 val", four bits.
                        imm       <= {60'd0, byte_in[3:0]};
                        imm_bytes <= 4'd0;
                        width     <= 4'd0;
                        busy      <= 1'b0;
                        done      <= 1'b1;
                    end else if (dec == AM_IMMED) begin
                        imm_bytes <= opbytes;
                        width     <= opbytes;
                        if (opbytes == 4'd0) begin
                            busy <= 1'b0;
                            done <= 1'b1;
                        end else begin
                            state <= S_IMM;
                            busy  <= 1'b1;
                        end
                    end else if (dec == AM_RESERVED) begin
                        // Reserved addressing mode.  Nothing follows it that
                        // this decoder could know the length of; the sequencer
                        // takes the exception.
                        width <= 4'd0;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                    end else if (dec_w == 4'd0) begin
                        // Rn, [Rn], [Rn+], [-Rn] -- one byte, complete.
                        width <= 4'd0;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                    end else begin
                        width <= dec_w;
                        state <= S_FIELD;
                        busy  <= 1'b1;
                    end
                end
            end else begin
                acc <= acc_next;
                cnt <= cnt + 4'd1;

                if (cnt + 4'd1 == width) begin
                    case (state)
                        S_FIELD: begin
                            disp <= sext(acc_next[31:0], width);
                            if (am_is_double(mode)) begin
                                acc   <= 64'd0;
                                cnt   <= 4'd0;
                                state <= S_FIELD2;
                                busy  <= 1'b1;
                            end else begin
                                busy <= 1'b0;
                                done <= 1'b1;
                            end
                        end
                        S_FIELD2: begin
                            disp_outer <= sext(acc_next[31:0], width);
                            busy       <= 1'b0;
                            done       <= 1'b1;
                        end
                        default: begin   // S_IMM
                            imm  <= acc_next;
                            busy <= 1'b0;
                            done <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end
end

// ---------------------------------------------------------------------------
// Simulation-only checks.  Both are properties of the protocol and of the
// figure, and neither can be enforced in hardware from inside this module.
// ---------------------------------------------------------------------------
// synthesis translate_off
always_ff @(posedge clk) begin
    if (!rst && done && (len > 4'd9) && !(immediate && (imm_bytes == 4'd8)))
        $display("WARN v60_am_decode: mod field of %0d bytes exceeds the 9 the databook allows (t=%0t)",
                 len, $time);
    if (!rst && start && !byte_valid)
        $display("WARN v60_am_decode: start without a byte -- start is asserted WITH the first mod byte (t=%0t)",
                 $time);
end
// synthesis translate_on

endmodule
