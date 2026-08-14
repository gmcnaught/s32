
//============================================================================
//  System 32 protection hardware retained by the production profile.
//============================================================================

import s32_pkg::*;

module s32_prot_darkedge #(
    parameter ENABLE = 1'b1
) (
    input             clk,
    input             rst,
    input             enable,
    input             vblank,
    output reg        wram_req,
    output reg        wram_we,
    output reg [15:0] wram_addr,
    output reg [15:0] wram_wdata,
    output reg  [1:0] wram_be,
    input      [15:0] wram_rdata,
    input             wram_ack
);

typedef enum logic [2:0] { DKE_IDLE, DKE_W0, DKE_R0, DKE_W1, DKE_W2 } dke_state_t;
dke_state_t state;
reg [7:0] tmp;

always @(posedge clk) begin
    if (rst || !ENABLE || !enable) begin
        state      <= DKE_IDLE;
        wram_req   <= 1'b0;
        wram_we    <= 1'b0;
        wram_addr  <= 16'h0000;
        wram_wdata <= 16'h0000;
        wram_be    <= 2'b00;
        tmp        <= 8'h00;
    end
    else begin
        case (state)
        DKE_IDLE: begin
            wram_req <= 1'b0;
            if (vblank) begin
                wram_req   <= 1'b1;
                wram_we    <= 1'b1;
                wram_addr  <= 16'hF072 >> 1;
                wram_wdata <= 16'h0000;
                wram_be    <= 2'b11;
                state      <= DKE_W0;
            end
        end
        DKE_W0: if (wram_ack) begin
            wram_req   <= 1'b1;
            wram_we    <= 1'b1;
            wram_addr  <= 16'hF082 >> 1;
            wram_wdata <= 16'h0000;
            wram_be    <= 2'b11;
            state      <= DKE_R0;
        end
        DKE_R0: if (wram_ack) begin
            wram_req  <= 1'b1;
            wram_we   <= 1'b0;
            wram_addr <= 16'hA12C >> 1;
            state     <= DKE_W1;
        end
        DKE_W1: if (wram_ack) begin
            tmp <= wram_rdata[7:0];
            if (wram_rdata[7:0] != 0) begin
                wram_req   <= 1'b1;
                wram_we    <= 1'b1;
                wram_addr  <= 16'hA12C >> 1;
                wram_wdata <= {8'h00, wram_rdata[7:0] - 8'h01};
                wram_be    <= 2'b01;
                state      <= DKE_W2;
            end
            else begin
                wram_req <= 1'b0;
                state    <= DKE_IDLE;
            end
        end
        DKE_W2: if (wram_ack) begin
            if (tmp == 8'h01) begin
                wram_req   <= 1'b1;
                wram_we    <= 1'b1;
                wram_addr  <= 16'hA12E >> 1;
                wram_wdata <= 16'h0001;
                wram_be    <= 2'b01;
            end
            else begin
                wram_req <= 1'b0;
            end
            state <= DKE_IDLE;
        end
        default: begin
            wram_req <= 1'b0;
            state    <= DKE_IDLE;
        end
        endcase
    end
end

endmodule

// ---------------------------------------------------------------------------
//  s32_v25: protection MCU subsystem (§8.1) — ga2 / arabfgt
//  v1 strategy per DESIGN.md: HLE responder implementing the documented
//  wakeup/command protocol through the MB8421 dual-port RAM at 0xA00000,
//  carrying the real opcode-decrypt tables for the future full-core swap.
//  The 64KB descrambled program is loaded to BRAM by the ROM loader; a
//  full V30-family core drops in behind this interface (M-next).
// ---------------------------------------------------------------------------
module s32_v25 (
    input             clk,
    input             rst,
    input             enable,
    input             table_sel,    // 0 = ga2, 1 = arabfgt

    // program BRAM load port (from loader, descrambled)
    input             prg_wr,
    input      [15:0] prg_waddr,
    input       [7:0] prg_wdata,

    // V60-side DPRAM access (0xA00000-0xA00FFF, low byte lanes)
    input             cs,
    input             we,
    input      [11:1] addr,
    input       [7:0] wdata,
    output      [7:0] rdata
);

// The mailbox HLE does not model V25 program memory: prg_wr/prg_waddr/prg_wdata
// are accepted for interface symmetry with the real s32_v25_cpu core (which uses
// them to invalidate its decode cache) but carry no storage here.  A prior
// write-only 64 KiB array was never read anywhere in the RTL and has been
// removed so it can no longer be misread as a live program store (audit hygiene).

// MB8421 mailbox RAM.  The HLE currently owns only the V60-side port, but an
// explicit true-dual-port block preserves the physical interface for a future
// MCU core without paying 16K flip-flops in the GA2 build.
wire [7:0] dpram_q;
s32_byte_spram #(.ADDR_WIDTH(11), .NUM_WORDS(2048), .POWER_UP_UNINITIALIZED("FALSE")) dpram_mem ( // audit R20 PF-8: deterministic zero power-up
    .clock(clk),
    .address_a(addr), .data_a(wdata), .rden_a(enable && cs),
    .wren_a(enable && cs && we), .q_a(dpram_q)
);

// HLE: wakeup string + echo protocol (MAME simulation fallback)
//   ga2:  "wake up! GOLDEN AXE The Revenge of Death-Adder! "
//   arf:  "wake up! ARF!                                   "
// The V25 firmware fills DPRAM offset 0 with the string, then serves
// command/response tables. v1 provides the string + the ga2 sprite
// expansion results table (prot[16] from MAME).
function automatic [7:0] wake_ga2(input [5:0] i);
    case (i)
        6'd0:  wake_ga2 = "w"; 6'd1:  wake_ga2 = "a"; 6'd2:  wake_ga2 = "k";
        6'd3:  wake_ga2 = "e"; 6'd4:  wake_ga2 = " "; 6'd5:  wake_ga2 = "u";
        6'd6:  wake_ga2 = "p"; 6'd7:  wake_ga2 = "!"; 6'd8:  wake_ga2 = " ";
        6'd9:  wake_ga2 = "G"; 6'd10: wake_ga2 = "O"; 6'd11: wake_ga2 = "L";
        6'd12: wake_ga2 = "D"; 6'd13: wake_ga2 = "E"; 6'd14: wake_ga2 = "N";
        6'd15: wake_ga2 = " "; 6'd16: wake_ga2 = "A"; 6'd17: wake_ga2 = "X";
        6'd18: wake_ga2 = "E"; 6'd19: wake_ga2 = " "; 6'd20: wake_ga2 = "T";
        6'd21: wake_ga2 = "h"; 6'd22: wake_ga2 = "e"; 6'd23: wake_ga2 = " ";
        6'd24: wake_ga2 = "R"; 6'd25: wake_ga2 = "e"; 6'd26: wake_ga2 = "v";
        6'd27: wake_ga2 = "e"; 6'd28: wake_ga2 = "n"; 6'd29: wake_ga2 = "g";
        6'd30: wake_ga2 = "e"; 6'd31: wake_ga2 = " "; 6'd32: wake_ga2 = "o";
        6'd33: wake_ga2 = "f"; 6'd34: wake_ga2 = " "; 6'd35: wake_ga2 = "D";
        6'd36: wake_ga2 = "e"; 6'd37: wake_ga2 = "a"; 6'd38: wake_ga2 = "t";
        6'd39: wake_ga2 = "h"; 6'd40: wake_ga2 = "-"; 6'd41: wake_ga2 = "A";
        6'd42: wake_ga2 = "d"; 6'd43: wake_ga2 = "d"; 6'd44: wake_ga2 = "e";
        6'd45: wake_ga2 = "r"; 6'd46: wake_ga2 = "!"; 6'd47: wake_ga2 = " ";
        default: wake_ga2 = " ";
    endcase
endfunction
function automatic [7:0] wake_arf(input [5:0] i);
    case (i)
        6'd0: wake_arf = "w"; 6'd1: wake_arf = "a"; 6'd2: wake_arf = "k";
        6'd3: wake_arf = "e"; 6'd4: wake_arf = " "; 6'd5: wake_arf = "u";
        6'd6: wake_arf = "p"; 6'd7: wake_arf = "!"; 6'd8: wake_arf = " ";
        6'd9: wake_arf = "A"; 6'd10: wake_arf = "R"; 6'd11: wake_arf = "F";
        6'd12: wake_arf = "!";
        default: wake_arf = " ";
    endcase
endfunction

// ga2 sprite-expansion result table (MAME prot[16])
function automatic [7:0] ga2_prot(input [3:0] i);
    case (i)
        4'd0:  ga2_prot = 8'h0a; 4'd2:  ga2_prot = 8'hc5;
        4'd4:  ga2_prot = 8'h11; 4'd6:  ga2_prot = 8'h11;
        4'd8:  ga2_prot = 8'h18; 4'd10: ga2_prot = 8'h18;
        4'd12: ga2_prot = 8'h1f; 4'd14: ga2_prot = 8'hc6;
        default: ga2_prot = 8'h00;
    endcase
endfunction

// Capture the address on the same edge as the RAM read.  The wrapper q and
// this selector then become visible together, preserving the original single
// synchronous-read cycle without adding a second output register.
reg [11:1] rd_addr;
reg        rd_table_sel;
always @(posedge clk) begin
    if (enable && cs) begin
        rd_addr      <= addr;
        rd_table_sel <= table_sel;
    end
end

// Window layout proven from the ga2 V60 boot code (loop at 0x1009ce):
// the game polls byte 0xA00100 for 'w' then string-compares 0x30 bytes
// against its ROM copy at 0x1009FF, so the wakeup string is byte window
// 0x100-0x15F (word index 0x80-0xAF); the sprite-expansion results table is
// byte window 0x000-0x01F.  rd_addr retains the input's [11:1] naming, so
// rd_addr[6:1] is the six-bit character offset.
assign rdata = (rd_addr >= 11'h80 && rd_addr < 11'hB0)
             ? (rd_table_sel ? wake_arf(rd_addr[6:1])
                             : wake_ga2(rd_addr[6:1]))
             : (!rd_table_sel && rd_addr < 11'h10)
             ? ga2_prot(rd_addr[4:1])
             : dpram_q;

endmodule
