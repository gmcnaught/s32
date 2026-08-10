//============================================================================
//  Arcade: Sega System 32 / Multi 32 for MiSTer  (emu top)
//  DESIGN.md §9 — framework integration.
//============================================================================

module emu
(
    input         CLK_50M,
    input         RESET,
    inout  [45:0] HPS_BUS,

    output        CLK_VIDEO,
    output        CE_PIXEL,
    output [12:0] VIDEO_ARX,
    output [12:0] VIDEO_ARY,

    output  [7:0] VGA_R,
    output  [7:0] VGA_G,
    output  [7:0] VGA_B,
    output        VGA_HS,
    output        VGA_VS,
    output        VGA_DE,
    output        VGA_F1,
    output  [1:0] VGA_SL,
    output        VGA_SCALER,
    output        VGA_DISABLE,

    input  [11:0] HDMI_WIDTH,
    input  [11:0] HDMI_HEIGHT,
    output        HDMI_FREEZE,
    output        HDMI_BLACKOUT,
    output        HDMI_BOB_DEINT,

    output        LED_USER,
    output  [1:0] LED_POWER,
    output  [1:0] LED_DISK,

    output  [1:0] BUTTONS,

    output [15:0] AUDIO_L,
    output [15:0] AUDIO_R,
    output        AUDIO_S,
    output  [1:0] AUDIO_MIX,

    // DDR3
    output        DDRAM_CLK,
    input         DDRAM_BUSY,
    output  [7:0] DDRAM_BURSTCNT,
    output [28:0] DDRAM_ADDR,
    input  [63:0] DDRAM_DOUT,
    input         DDRAM_DOUT_READY,
    output        DDRAM_RD,
    output [63:0] DDRAM_DIN,
    output  [7:0] DDRAM_BE,
    output        DDRAM_WE,

    // SDRAM
    output        SDRAM_CLK,
    output        SDRAM_CKE,
    output [12:0] SDRAM_A,
    output  [1:0] SDRAM_BA,
    inout  [15:0] SDRAM_DQ,
    output        SDRAM_DQML,
    output        SDRAM_DQMH,
    output        SDRAM_nCS,
    output        SDRAM_nCAS,
    output        SDRAM_nRAS,
    output        SDRAM_nWE,

    input         CLK_AUDIO,   // 24.576 MHz
    inout   [3:0] ADC_BUS,

    // SD-SPI
    output        SD_SCK,
    output        SD_MOSI,
    input         SD_MISO,
    output        SD_CS,
    input         SD_CD,

    input         UART_CTS,
    output        UART_RTS,
    input         UART_RXD,
    output        UART_TXD,
    output        UART_DTR,
    input         UART_DSR,

    input   [6:0] USER_IN,
    output  [6:0] USER_OUT,

    input         OSD_STATUS
);

// unused framework peripherals
assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

import s32_pkg::*;

// Declare the descriptor before it is referenced by the clock-enable logic.
// Quartus 17 otherwise parses board_desc.multi32 as a hierarchical name.
board_desc_t board_desc;
board_desc_t active_board;

// Declare framework/HPS signals before configuration, LED, reset, and clock
// logic uses them. This keeps Quartus 17 and ModelSim 10.5 on the same parse.
wire        rom_loaded;
wire  [1:0] buttons;
wire [63:0] status;
wire        ioctl_download, ioctl_upload, ioctl_wr, ioctl_rd, ioctl_wait;
wire [15:0] ioctl_index;
wire [26:0] ioctl_addr;
wire [15:0] ioctl_dout, ioctl_din;
wire        eep_upload, eep_modified;
wire  [5:0] eep_rd_addr;
wire [15:0] eep_rd_data;
wire [31:0] joystick_0, joystick_1, joystick_2, joystick_3, joystick_4, joystick_5;
wire [15:0] joystick_l_analog_0, joystick_l_analog_1, joystick_l_analog_2;
wire [15:0] joystick_r_analog_0;
wire  [7:0] paddle_0, paddle_1;
wire [24:0] ps2_mouse;
wire        core_vs;
// The two universal RBFs have fixed profile boundaries. The standard image
// rejects V25/Multi 32 hardware; the V25 image accepts only the two protected
// System 32 boards and keeps their table selector descriptor-driven.
always @(*) begin
    active_board = board_desc;
`ifdef S32_REAL_V25
    active_board.multi32          = 1'b0;
    active_board.has_v25          = 1'b1;
    active_board.v25_table        = board_desc.v25_table;
    active_board.has_adc          = 1'b0;
    active_board.has_track        = 1'b0;
    active_board.has_ppi          = 1'b1;
    active_board.has_dsp_hle      = 1'b0;
    active_board.dual_pcb         = 1'b0;
    active_board.prot_sel         = PROT_NONE;
    active_board.sprite_bank_valid = 1'b1;
    active_board.sprite_bank_mask = 2'b11;
    active_board.flip_y           = 1'b0;
    active_board.gun_aim          = 1'b0;
    active_board.coin_swap        = 1'b0;
    active_board.analog_profile   = ANALOG_CENTERED;
    active_board.gear_toggle      = 1'b0;
    active_board.comm_link_hle    = 1'b0;
    active_board.digital_profile  = DIGITAL_GENERIC;
`elsif S32_PROFILE_STANDARD
    active_board.multi32          = 1'b0;
    // The standard image has no real V25 CPU/QIP, but retains the lightweight
    // descriptor-selected mailbox HLE for non-real-V25 board variants.
    active_board.has_v25          = board_desc.has_v25;
    active_board.v25_table        = board_desc.v25_table;
`endif
end

assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;
assign AUDIO_S = 1;
assign AUDIO_MIX = 0;
// Lit until the index-0 ROM stream has fully drained to SDRAM.
assign LED_USER = ~rom_loaded;
assign LED_POWER = 0;
assign LED_DISK = 0;
assign BUTTONS = 0;

//////////////////////////////////   CONF   ///////////////////////////////////
// BUILD_DATE is normally provided by sys/build_id.tcl -> build_id.v. Guard it
// so the core still compiles cleanly if that define is absent.
`ifndef BUILD_DATE
`define BUILD_DATE "SegaS32"
`endif

localparam CONF_STR = {
    "S32;;",
    "-;",
    "O[2:1],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
    "O[5:3],Scandoubler Fx,None,CRT 25%,CRT 50%,CRT 75%;",
    "-;",
`ifndef S32_SYSTEM32_ONLY
    "O[6],Screen (Multi32),A,B;",
`endif
    "O[7],Service Mode,Off,On;",
    // h0 hides this line unless menumask[0] identifies Alien 3.
    "h0O[8],Alien 3 Flicker Blend,Off,On;",
    "-;",
    "O[28:27],Scale,Normal,V-Integer,HV-Integer;",
    "O[9],CRT Adjust,Off,On;",
    "H1O[14:10],CRT H-Size,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
    "H1O[21:15],CRT H-Position,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,+16,+17,+18,+19,+20,+21,+22,+23,+24,+25,+26,+27,+28,+29,+30,+31,+32,+33,+34,+35,+36,+37,+38,+39,+40,+41,+42,+43,+44,+45,+46,+47,+48,-48,-47,-46,-45,-44,-43,-42,-41,-40,-39,-38,-37,-36,-35,-34,-33,-32,-31,-30,-29,-28,-27,-26,-25,-24,-23,-22,-21,-20,-19,-18,-17,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
    "H1O[26:22],CRT V-Shift,0,+1,+2,+3,+4,+5,+6,+7,+8,+9,+10,+11,+12,+13,+14,+15,-16,-15,-14,-13,-12,-11,-10,-9,-8,-7,-6,-5,-4,-3,-2,-1;",
    "-;",
    "R[0],Reset;",
    "J1,B1,B2,B3,B4,B5,B6,Start,Coin,Test,Service;",
    "V,v",`BUILD_DATE
};

////////////////////////////   CLOCKS/PLL   ///////////////////////////////////
wire clk_sys, clk_ram, clk_v25, pll_locked;
wire sdram_ready;
reg  sdram_ready_meta, sdram_ready_sys;
pll pll (
    .refclk_clk(CLK_50M),
    .reset_reset(1'b0),
    .outclk0_clk(clk_ram),    // 96.634615 MHz
    .outclk1_clk(clk_sys),    // 48.317307 MHz
    .outclk2_clk(SDRAM_CLK),  // 96.634615 MHz, 180 deg: centred SDRAM interface
    .outclk3_clk(clk_v25),    // 24.158653 MHz (clk_sys/2): s80x86 compute domain
    .locked_export(pll_locked)
);
assign DDRAM_CLK = clk_ram;
assign CLK_VIDEO = clk_sys;

// Keep every game subsystem reset until a complete index-0 ROM transfer has
// drained into SDRAM. The loader itself is reset only by PLL startup so soft
// reset and NVRAM transfers do not forget that ROM is already resident.
wire video_reset = RESET | status[0] | buttons[1] | ~pll_locked;
wire reset = video_reset | ioctl_download | ~rom_loaded | ~sdram_ready_sys;

// Synchronise the controller-ready level from clk_ram before it gates the
// loader and the game logic in clk_sys.
always @(posedge clk_sys) begin
    if (!pll_locked) begin
        sdram_ready_meta <= 1'b0;
        sdram_ready_sys  <= 1'b0;
    end
    else begin
        sdram_ready_meta <= sdram_ready;
        sdram_ready_sys  <= sdram_ready_meta;
    end
end

// fractional clock enables (DESIGN.md §3.3)
reg ce_cpu, ce_z80, ce_fm, ce_pcm;
reg [15:0] acc_cpu, acc_z80, acc_fm, acc_pcm;
wire is_multi32 = active_board.multi32;
// CPU Turbo is retired in the single merged profile: s32.sdc's V60 register-
// to-register multicycle relaxation now applies unconditionally, and that
// relaxation is only sound with fixed, single-cycle-safe CE spacing (no
// back-to-back clk_sys edges) for every game, not just the two V25 titles --
// see s32.sdc's s32_game_fixed_ce comment. Every board therefore runs at a
// fixed per-board cadence: arabfgt/ga2 keep the exact measured constants
// carried over from the dedicated V25 profile this replaces (real-hardware
// timing, including Arabian Fight's clk_sys/2 cadence for its 12.49
// clocks/instruction non-pipelined V60 attract-loop overrun); every other
// board keeps its existing base rate with the multiplier locked at 1x.
wire [15:0] cpu_ce_inc = active_board.has_v25
                         ? (active_board.v25_table ? 16'd32768 : 16'd21848)
                         : (is_multi32 ? 16'd27127 : 16'd21848);
always @(posedge clk_sys) begin
    logic [16:0] s;
    if (reset) begin
        ce_cpu <= 1'b0; ce_z80 <= 1'b0; ce_pcm <= 1'b0;
        acc_cpu <= 16'd0; acc_z80 <= 16'd0; acc_pcm <= 16'd0;
    end
    else begin
        // cpu: 16.10795/48.317307 (V60); 20/48.317307 (V70)
        s = acc_cpu + {1'b0, cpu_ce_inc};  // base increment * turbo mult (capped)
        ce_cpu <= s[16];
        acc_cpu <= s[15:0];
        // Z80/YM3438: 32.2159 MHz / 4 on the standard board.
        s = acc_z80 + (is_multi32 ? 16'd10851 : PCB_Z80_CE_INC);
        ce_z80 <= s[16];
        acc_z80 <= s[15:0];
        // RF5C68-family PCM: separate 50 MHz source / 4 = 12.5 MHz.
        s = acc_pcm + (is_multi32 ? 16'd13564 : PCB_PCM_CE_INC);
        ce_pcm <= s[16];
        acc_pcm <= s[15:0];
    end
end

// JT12's resettable operator/envelope rings advance only on its enabled
// clock.  Keep the FM chip clock running throughout board/ROM-load reset;
// tying it to the halted Z80 CE leaves those rings unreset and can poison the
// stereo mixer with unknown/random startup state.  PLL unlock is the only
// condition that stops and rephases this NCO.
always @(posedge clk_sys) begin
    logic [16:0] s;
    if (!pll_locked) begin
        ce_fm <= 1'b0;
        acc_fm <= 16'd0;
    end
    else begin
        s = acc_fm + (is_multi32 ? 16'd10851 : PCB_Z80_CE_INC);
        ce_fm <= s[16];
        acc_fm <= s[15:0];
    end
end

///////////////////////////////   HPS IO   ////////////////////////////////////

hps_io #(.CONF_STR(CONF_STR), .WIDE(1)) hps_io (
    .clk_sys(clk_sys),
    .HPS_BUS(HPS_BUS),

    .buttons(buttons),
    .status(status),
    .status_menumask({14'd0, ~status[9], active_board.gun_aim && active_board.coin_swap}),

    .ioctl_download(ioctl_download),
    .ioctl_upload(ioctl_upload),
    .ioctl_upload_req(eep_modified),
    .ioctl_upload_index(8'd3),
    .ioctl_wr(ioctl_wr),
    .ioctl_rd(ioctl_rd),
    .ioctl_addr(ioctl_addr),
    .ioctl_dout(ioctl_dout),
    .ioctl_din(ioctl_din),
    .ioctl_index(ioctl_index),
    .ioctl_wait(ioctl_wait),

    .joystick_0(joystick_0),
    .joystick_1(joystick_1),
    .joystick_2(joystick_2),
    .joystick_3(joystick_3),
    .joystick_4(joystick_4),
    .joystick_5(joystick_5),
    .joystick_l_analog_0(joystick_l_analog_0),
    .joystick_l_analog_1(joystick_l_analog_1),
    .joystick_l_analog_2(joystick_l_analog_2),
    .joystick_r_analog_0(joystick_r_analog_0),
    .paddle_0(paddle_0),
    .paddle_1(paddle_1),
    .ps2_mouse(ps2_mouse)
);

// MiSTer MRA NVRAM is a byte stream at index 3. Convert the EEPROM's
// 64x16 little-endian shadow into that stream for save uploads.
s32_eeprom_nvram_if #(.WIDE(1)) eep_nvram_if (
    .ioctl_upload(ioctl_upload), .ioctl_index(ioctl_index),
    .ioctl_addr(ioctl_addr), .eep_rd_data(eep_rd_data),
    .eep_upload(eep_upload), .eep_rd_addr(eep_rd_addr),
    .ioctl_din(ioctl_din)
);

////////////////////////////   ROM LOADING   //////////////////////////////////
wire        sw_req, sw_ack;
wire [24:1] sw_addr;
wire [15:0] sw_din;
wire  [1:0] sw_be;
wire        v25_wr;
wire [15:0] v25_waddr;
wire  [7:0] v25_wdata;
wire        eep_wr;
wire  [5:0] eep_waddr;
wire [15:0] eep_wdata;

s32_rom_loader #(.WIDE(1)) loader (
    .clk(clk_sys), .rst(~pll_locked),
    .mem_ready(sdram_ready_sys),
    .ioctl_download(ioctl_download), .ioctl_index(ioctl_index[7:0]),
    .ioctl_wr(ioctl_wr), .ioctl_addr(ioctl_addr), .ioctl_dout(ioctl_dout),
    .ioctl_wait(ioctl_wait),
    .board_desc(board_desc),
    .sdr_wr_req(sw_req), .sdr_wr_addr(sw_addr), .sdr_wr_din(sw_din),
    .sdr_wr_be(sw_be), .sdr_wr_ack(sw_ack),
    .v25_wr(v25_wr), .v25_waddr(v25_waddr), .v25_wdata(v25_wdata),
    .eep_wr(eep_wr), .eep_waddr(eep_waddr), .eep_wdata(eep_wdata),
    .eep_loaded(), .rom_loaded(rom_loaded)
);

/////////////////////////////////   SDRAM   ///////////////////////////////////
wire        p0_req, p0_ack, p1_req, p1_ack, p2_req, p2_ack, p3_req, p3_ack, p4_req, p4_ack, p5_req, p5_ack;
wire        core_p1_req, core_p2_req;
wire [24:1] p0_addr, p3_addr, p4_addr;
wire [24:3] p1_addr, p5_addr;
wire [24:4] p2_addr;
wire [24:3] core_p1_addr;
wire [24:4] core_p2_addr;
wire [15:0] p0_dout, p3_dout, p4_dout;
wire [63:0] p1_dout, p5_dout;
wire[127:0] p2_dout;

assign p1_req  = core_p1_req;
assign p1_addr = core_p1_addr;
assign p2_req  = core_p2_req;
assign p2_addr = core_p2_addr;
sdram sdram (
    .clk(clk_ram), .init(~pll_locked), .ready(sdram_ready),
    .SDRAM_DQ(SDRAM_DQ), .SDRAM_A(SDRAM_A), .SDRAM_BA(SDRAM_BA),
    .SDRAM_DQML(SDRAM_DQML), .SDRAM_DQMH(SDRAM_DQMH),
    .SDRAM_nCS(SDRAM_nCS), .SDRAM_nCAS(SDRAM_nCAS),
    .SDRAM_nRAS(SDRAM_nRAS), .SDRAM_nWE(SDRAM_nWE), .SDRAM_CKE(SDRAM_CKE),
    .wr_req(sw_req), .wr_addr(sw_addr), .wr_din(sw_din), .wr_be(sw_be), .wr_ack(sw_ack),
    .p0_req(p0_req), .p0_addr(p0_addr), .p0_dout(p0_dout), .p0_ack(p0_ack),
    .p1_req(p1_req), .p1_addr(p1_addr), .p1_dout(p1_dout), .p1_ack(p1_ack),
    .p2_req(p2_req), .p2_addr(p2_addr), .p2_dout(p2_dout), .p2_ack(p2_ack),
    .p3_req(p3_req), .p3_addr(p3_addr), .p3_dout(p3_dout), .p3_ack(p3_ack),
    .p4_req(p4_req), .p4_addr(p4_addr), .p4_dout(p4_dout), .p4_ack(p4_ack),
    .p5_req(p5_req), .p5_addr(p5_addr), .p5_dout(p5_dout), .p5_ack(p5_ack)
);

////////////////////////////   FRAMEBUFFER   //////////////////////////////////
wire        fbw_start, fbw_valid, fbw_end, fbw_shadow, fbw_busy;
wire        fbe_req, fbe_ack, fbr_req, fbr_ack, fbr_blend;
wire  [1:0] fbw_buf, fbe_buf, fbr_buf, fbr_blend_buf;
wire  [8:0] fbw_x, fbr_x;
wire  [7:0] fbw_y, fbe_y, fbr_y;
wire [15:0] fbw_pix, fbr_pix;

s32_fb_if fb (
    .clk(clk_ram), .rst(reset),
    .DDRAM_BUSY(DDRAM_BUSY), .DDRAM_BURSTCNT(DDRAM_BURSTCNT),
    .DDRAM_ADDR(DDRAM_ADDR), .DDRAM_DOUT(DDRAM_DOUT),
    .DDRAM_DOUT_READY(DDRAM_DOUT_READY), .DDRAM_RD(DDRAM_RD),
    .DDRAM_DIN(DDRAM_DIN), .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .wr_start(fbw_start), .wr_buf(fbw_buf), .wr_x(fbw_x), .wr_y(fbw_y),
    .wr_valid(fbw_valid), .wr_pix(fbw_pix), .wr_end(fbw_end),
    .wr_shadow(fbw_shadow), .wr_busy(fbw_busy),
    .er_req(fbe_req), .er_buf(fbe_buf), .er_y(fbe_y), .er_ack(fbe_ack),
    .rd_req(fbr_req), .rd_buf(fbr_buf), .rd_blend_buf(fbr_blend_buf),
    .rd_blend(fbr_blend), .rd_y(fbr_y), .rd_ack(fbr_ack),
    .rd_x(fbr_x), .rd_pix(fbr_pix)
);

//////////////////////////////   INPUTS   /////////////////////////////////////
// MiSTer logical joystick bits are directions [3:0], six arcade buttons
// [9:4], Start [10], Coin [11].  GA2's 315-5296 player ports follow MAME:
// {left,right,up,down,unused,button3,button2,button1}, active low.
function automatic [7:0] p_dig(input [31:0] j);
    p_dig = ~{j[1], j[0], j[3], j[2], 1'b0, j[6], j[5], j[4]};
endfunction
wire [7:0] p1a_dig = p_dig(joystick_0);
wire [7:0] radm_p1a = {p1a_dig[7:3], ~joystick_0[5],
                        ~joystick_0[4], 1'b1};
// SegaSonic action buttons: P1=P1_A[0], P2=P2_A[0], P3=P1_A[2].
// Every other player-port bit is physically unused on the trackball cabinet.
wire [7:0] sonic_p1a = {5'b11111, ~joystick_2[4], 1'b1, ~joystick_0[4]};
wire [7:0] p2a_dig = p_dig(joystick_1);
wire [7:0] sonic_p2a = {7'b1111111, ~joystick_1[4]};
`ifdef S32_REAL_V25
// The V25 release has exactly two supported boards (GA2 and Arabian Fight).
// Neither has a gun, trackball, ADC or alternate standard-profile cabinet
// wiring. Keep these ports explicitly driven for the shared core interface,
// but compile out the corresponding input conditioners and their state.
wire sonic_controls = 1'b0;
wire [7:0] core_p1a = p1a_dig;
wire [7:0] core_p2a = p2a_dig;
wire [7:0] adc_ch [0:7];
assign adc_ch[0] = 8'h80;
assign adc_ch[1] = 8'h80;
assign adc_ch[2] = 8'h80;
assign adc_ch[3] = 8'h80;
assign adc_ch[4] = 8'h80;
assign adc_ch[5] = 8'h80;
assign adc_ch[6] = 8'h80;
assign adc_ch[7] = 8'h80;
wire trk_dv_a [0:2];
wire signed [8:0] trk_dx_a [0:2];
wire signed [8:0] trk_dy_a [0:2];
wire [7:0] trk_btn [0:2];
assign trk_dv_a[0] = 1'b0; assign trk_dv_a[1] = 1'b0; assign trk_dv_a[2] = 1'b0;
assign trk_dx_a[0] = 9'sd0; assign trk_dx_a[1] = 9'sd0; assign trk_dx_a[2] = 9'sd0;
assign trk_dy_a[0] = 9'sd0; assign trk_dy_a[1] = 9'sd0; assign trk_dy_a[2] = 9'sd0;
assign trk_btn[0] = 8'h00; assign trk_btn[1] = 8'h00; assign trk_btn[2] = 8'h00;
`else
wire sonic_controls = active_board.has_track;
// Rad Rally and Slip Stream expose a single cabinet Gear Change toggle, not a
// momentary switch or four-position encoding.  Keep this semantic independent
// from Rad Rally's separate EPR-14084 communication-board selector.
reg radr_gear = 1'b0;
reg radr_gear_btn_d = 1'b0;
always @(posedge clk_sys) begin
    if (reset || !active_board.gear_toggle) begin
        radr_gear <= 1'b0;
        radr_gear_btn_d <= joystick_0[6];
    end
    else begin
        radr_gear_btn_d <= joystick_0[6];
        if (joystick_0[6] && !radr_gear_btn_d)
            radr_gear <= ~radr_gear;
    end
end
wire [7:0] gear_toggle_p1a = {p1a_dig[7:1], ~radr_gear};
// Dark Edge leaves raw player-port bit 0 unused and places its first two
// buttons on bits 1/2.  Adapt MiSTer's logical B1/B2 here; the remaining
// three buttons are on the PPI below.  Select from the existing descriptor so
// this remains a shared Standard-profile implementation, not a game build.
wire [7:0] darkedge_p1a = {p1a_dig[7:4], 1'b1,
                           ~joystick_0[5], ~joystick_0[4], 1'b1};
`ifdef S32_REAL_V25
// The real-V25 profile has no positional gun. The standard profile retains
// one shared conditioner for descriptor-selected Jurassic Park and Alien3;
// both games therefore use exactly the same sticks, inversion, curve,
// deadzones, saturation, smoothing and four ADC-channel assignments.
// active_board.gun_aim is loaded from runtime descriptor data, so Quartus
// cannot prove it constant on its own and would otherwise always pay for
// the full curve-LUT/divider FSM in s32_gun_aim below regardless of which
// games a profile ships. Force a real compile-time constant so that module
// is provably prunable.
wire gun_aim_active = 1'b0;
`else
wire gun_aim_active = active_board.gun_aim;
`endif
wire alien3_controls = active_board.gun_aim && active_board.coin_swap;
// Alien 3 has no cabinet Start inputs.  MAME's alien3 port map leaves
// SERVICE12 bit 5 unused and repurposes generic Start 1 (bit 4) as Service 2;
// starting a side is done with its gun trigger.  Keep MiSTer's Start buttons
// as convenient trigger aliases without asserting either service-credit line.
wire [7:0] alien3_p1a = p1a_dig & {7'h7f, ~joystick_0[10]};
wire [7:0] alien3_p2a = p2a_dig & {7'h7f, ~joystick_1[10]};
wire [7:0] core_p1a = sonic_controls ? sonic_p1a :
                       alien3_controls ? alien3_p1a :
                       (active_board.prot_sel == PROT_DARKEDGE) ? darkedge_p1a :
                       active_board.gear_toggle ? gear_toggle_p1a :
                       (active_board.digital_profile == DIGITAL_RADM) ? radm_p1a :
                       p1a_dig;
wire [7:0] darkedge_p2a = {p2a_dig[7:4], 1'b1,
                           ~joystick_1[5], ~joystick_1[4], 1'b1};
wire [7:0] core_p2a = sonic_controls ? sonic_p2a :
                       alien3_controls ? alien3_p2a :
                       (active_board.prot_sel == PROT_DARKEDGE) ? darkedge_p2a :
                       p2a_dig;

// --- Analog-stick positional-gun aiming ------------------------------------
// The gun channels are MAME IPT_AD_STICK_X/Y: absolute, offset-binary, resting
// at 0x80 (full left/up=0x00, full right/down=0xff).  MiSTer's left analog
// stick feeds them directly (P1 = stick 0, P2 = stick 1). Positional-gun
// inputs use a radial inner deadzone, 95%-throw outer saturation, progressive
// response, and error-sensitive smoothing in s32_gun_aim. Other analog titles
// retain the proven per-axis conditioning below. Alien 3 and Jurassic Park
// use natural stick directions: left/up decrease the cabinet ADC coordinate,
// while right/down increase it.
wire aim_inv_x = 1'b0;
wire aim_inv_y = 1'b0;
localparam signed [8:0] AIM_DZ = 9'sd6;

// signed stick -> offset binary (center 0x80), with centred optional inversion
function automatic [7:0] aim_axis(input [7:0] raw, input inv);
    logic [7:0] v;
    v = raw ^ 8'h80;
    aim_axis = inv ? (8'h00 - v) : v;     // mirror about 0x80 (0x80 stays 0x80)
endfunction

// continuous (subtractive) deadzone about center 0x80
function automatic [7:0] aim_deadzone(input [7:0] v);
    logic signed [8:0] d;
    d = $signed({1'b0, v}) - 9'sd128;
    if (d <= AIM_DZ && d >= -AIM_DZ) aim_deadzone = 8'h80;
    else if (d > 0)                  aim_deadzone = 8'd128 + (d - AIM_DZ);
    else                             aim_deadzone = 8'd128 + (d + AIM_DZ);
endfunction

wire [7:0] aim_in [0:3];
assign aim_in[0] = aim_axis(joystick_l_analog_0[7:0],  aim_inv_x); // P1 gun X
assign aim_in[1] = aim_axis(joystick_l_analog_0[15:8], aim_inv_y); // P1 gun Y
assign aim_in[2] = aim_axis(joystick_l_analog_1[7:0],  aim_inv_x); // P2 gun X
assign aim_in[3] = aim_axis(joystick_l_analog_1[15:8], aim_inv_y); // P2 gun Y

wire [7:0] gun_aim_x [0:1];
wire [7:0] gun_aim_y [0:1];
s32_gun_aim gun_aim_conditioner (
    .clk(clk_sys), .rst(reset), .enable(gun_aim_active),
    .p1_raw_x(joystick_l_analog_0[7:0]),
    .p1_raw_y(joystick_l_analog_0[15:8]),
    .p2_raw_x(joystick_l_analog_1[7:0]),
    .p2_raw_y(joystick_l_analog_1[15:8]),
    .invert_x(aim_inv_x), .invert_y(aim_inv_y),
    .p1_aim_x(gun_aim_x[0]), .p1_aim_y(gun_aim_y[0]),
    .p2_aim_x(gun_aim_x[1]), .p2_aim_y(gun_aim_y[1])
);

// ~1 kHz IIR smoothing tick (48.317307 MHz / 2^16 ~ 737 Hz)
reg  [7:0] aim_sm [0:3];
reg [15:0] aim_div = 16'd0;
wire       aim_tick = (aim_div == 16'd0);
integer    aim_i;
always @(posedge clk_sys) begin
    aim_div <= aim_div + 1'b1;
    for (aim_i = 0; aim_i < 4; aim_i = aim_i + 1) begin
        logic [7:0]        tgt;
        logic signed [9:0] err;
        tgt = aim_deadzone(aim_in[aim_i]);
        if (reset)          aim_sm[aim_i] <= 8'h80;
        else if (aim_tick) begin
            err = $signed({2'b00, tgt}) - $signed({2'b00, aim_sm[aim_i]});
            // Snap the final few LSB to the target. A plain err>>>2 floors on
            // negative errors, so approaching from a deflected value stalls a
            // few codes short and the aim never re-centres exactly on 0x80.
            if (err >= -10'sd3 && err <= 10'sd3) aim_sm[aim_i] <= tgt;
            else                                 aim_sm[aim_i] <= aim_sm[aim_i] + (err >>> 2);
        end
    end
end

wire [7:0] adc_ch [0:7];
wire driving_analog = (active_board.analog_profile == ANALOG_DRIVING);
wire pulled_up_adc  = (active_board.analog_profile == ANALOG_ALL_FF);
// MiSTer reports each analog-stick axis as signed -128..+127. Split the right
// stick's vertical axis into independent, released-at-zero pedals: up is
// accelerator and down is brake. Saturating magnitude 127/128 to 255 lets
// both directions reach the cabinet ADC endpoint without a multiplier.
wire [7:0] driving_accel;
wire [7:0] driving_brake;
s32_driving_controls driving_controls (
    .right_analog(joystick_r_analog_0),
    .digital_accel(joystick_0[4]),
    .digital_brake(joystick_0[5]),
    .accel(driving_accel),
    .brake(driving_brake)
);
// Driving cabinets wire the wheel, accelerator, and brake to the first three
// MSM6253 channels. MiSTer's left-stick X is the wheel; right-stick up/down
// are the analog pedals, with A/B as full-scale digital fallbacks.
assign adc_ch[0] = pulled_up_adc ? 8'hff :
                   gun_aim_active ? gun_aim_x[0] : aim_sm[0]; // ANALOG1
assign adc_ch[1] = pulled_up_adc ? 8'hff :
                   driving_analog ? driving_accel :
                   gun_aim_active ? gun_aim_y[0] : aim_sm[1]; // ANALOG2
assign adc_ch[2] = pulled_up_adc ? 8'hff :
                   driving_analog ? driving_brake :
                   gun_aim_active ? gun_aim_x[1] : aim_sm[2]; // ANALOG3
assign adc_ch[3] = pulled_up_adc ? 8'hff :
                   driving_analog ? 8'hff :
                   gun_aim_active ? gun_aim_y[1] : aim_sm[3]; // ANALOG4
assign adc_ch[4] = pulled_up_adc ? 8'hff : driving_analog ? 8'h80 : paddle_0;
assign adc_ch[5] = pulled_up_adc ? 8'hff : driving_analog ? 8'h80 : paddle_1;
assign adc_ch[6] = pulled_up_adc ? 8'hff : 8'h80;
assign adc_ch[7] = pulled_up_adc ? 8'hff : 8'h80;

// Each controller's left stick is trackball velocity, not position. One
// signed delta is injected per video frame. The shared VS edge detector
// replaces the former 16-bit timer; the three converters are combinational
// deadzone/subtract/shift logic with no RAM, DSP, multiplier or divider.
reg core_vs_d = 1'b0;
always @(posedge clk_sys) begin
    if (reset) core_vs_d <= 1'b0;
    else       core_vs_d <= core_vs;
end
wire trk_tick = core_vs & ~core_vs_d;

wire [7:0] trk_btn [0:2];
assign trk_btn[0] = {4'b0, ~joystick_0[4], 3'b0};
assign trk_btn[1] = {4'b0, ~joystick_1[4], 3'b0};
assign trk_btn[2] = {4'b0, ~joystick_2[4], 3'b0};

wire signed [8:0] trk_velx [0:2];
wire signed [8:0] trk_vely [0:2];
s32_trackball_stick trk_stick0 (
    .analog(joystick_l_analog_0), .dx(trk_velx[0]), .dy(trk_vely[0])
);
s32_trackball_stick trk_stick1 (
    .analog(joystick_l_analog_1), .dx(trk_velx[1]), .dy(trk_vely[1])
);
s32_trackball_stick trk_stick2 (
    .analog(joystick_l_analog_2), .dx(trk_velx[2]), .dy(trk_vely[2])
);

wire trk_dv_a [0:2];
assign trk_dv_a[0] = sonic_controls & trk_tick &
                     ((trk_velx[0] != 9'sd0) | (trk_vely[0] != 9'sd0));
assign trk_dv_a[1] = sonic_controls & trk_tick &
                     ((trk_velx[1] != 9'sd0) | (trk_vely[1] != 9'sd0));
assign trk_dv_a[2] = sonic_controls & trk_tick &
                     ((trk_velx[2] != 9'sd0) | (trk_vely[2] != 9'sd0));
wire signed [8:0] trk_dx_a [0:2];
wire signed [8:0] trk_dy_a [0:2];
assign trk_dx_a[0] = trk_velx[0];
assign trk_dy_a[0] = trk_vely[0];
assign trk_dx_a[1] = trk_velx[1];
assign trk_dy_a[1] = trk_vely[1];
assign trk_dx_a[2] = trk_velx[2];
assign trk_dy_a[2] = trk_vely[2];
`endif

// MAME system32_generic: port C is unused; port E/SERVICE12 is
// {unknown[7:6], start2, start1, coin2, coin1, test, service}, active low.
// Test = the OSD "Service Mode" toggle OR the mappable Test button (j12);
// Service (coin-service credit) = the mappable Service button (j13).
wire [7:0] portc = 8'hff;
wire test_btn = status[7] | joystick_0[12] | joystick_1[12];
wire svc_btn  = joystick_0[13] | joystick_1[13];
// SegaSonic maps Coin 3 and Start 3 to the upper service bits.  Keep them on
// the third MiSTer player: mirroring P1 here would assert Start1+Start3 and
// Coin1+Coin3 together.
wire [7:0] svc12_generic = ~{
                     sonic_controls ? joystick_2[10] : 1'b0,
                     sonic_controls ? joystick_2[11] : 1'b0,
                     joystick_1[10], joystick_0[10],
                     joystick_1[11], joystick_0[11], test_btn, svc_btn};
// Alien 3 swaps the two coin assignments relative to system32_generic:
// bit3=Coin 1, bit2=Coin 2.  Bits 5/4 must remain released so Start cannot
// become the game's right-side service credit.
wire [7:0] svc12_alien3 = ~{2'b00, 2'b00, joystick_0[11],
                             joystick_1[11], test_btn, svc_btn};
wire [7:0] svc12 = alien3_controls ? svc12_alien3 : svc12_generic;
// Port F/SERVICE34: bits 3:0 = DIP SW1:1-4 (Off), bit4 = PCB Push SW1
// (Service), bit5 = PCB Push SW2 (Test), bit6 unknown; bit7 is replaced by the
// EEPROM DO line inside s32_core.  Some games poll the PCB push switches
// rather than the cabinet Test line, so drive them from the same buttons —
// physically equivalent to pressing the matching switch on the board.
wire [7:0] svc34 = ~{2'b00, test_btn, svc_btn, 4'b0000};
// GA2's 4-player i8255 port C is MAME EXTRA3 (ppi.in_pc_callback -> "EXTRA3").
// Base sets: bit0=Start3, bit1=Start4, bits[7:2] unused. The US sets (ga2u,
// spidmanu, arabfgtu) instead read COIN1 on bit3 (0x08) and COIN2 on bit2
// (0x04) here (PORT_MODIFY EXTRA3). IO-11/12: additively drive those two bits
// from the same P1/P2 coin buttons that feed SERVICE12 coin1/coin2, so US sets
// register their primary coins. Safe for every non-US set because they mark
// EXTRA3 bits 2/3 IPT_UNUSED. NOTE (unverified on hardware): on a US set the
// coin button now also pulses SERVICE12 (read there as COIN3/COIN4), so if that
// game credits COIN3/4 as well as COIN1/2 a single press could double-count;
// eliminating that needs a board-descriptor US flag, deferred by choice.
wire [7:0] ga2_ppi_pc = ~{4'b0, joystick_0[11], joystick_1[11],
                          joystick_3[10], joystick_2[10]};
// Burning Rival and Dark Edge use the same physical i8255 differently from
// GA2: A/C are pulled high and B carries the upper action buttons.  This costs
// only descriptor-selected wiring and preserves the single Standard image.
wire [7:0] brival_ppi_pb = {~joystick_0[9], 1'b1,
                            ~joystick_0[7], ~joystick_0[8], 1'b1,
                            ~joystick_1[9], ~joystick_1[8], ~joystick_1[7]};
wire [7:0] darkedge_ppi_pb = {~joystick_0[8], 1'b1,
                              ~joystick_0[6], ~joystick_0[7], 1'b1,
                              ~joystick_1[8], ~joystick_1[7], ~joystick_1[6]};
wire brival_inputs = active_board.prot_sel == PROT_BRIVAL;
wire darkedge_inputs = active_board.prot_sel == PROT_DARKEDGE;
wire [7:0] core_ppi_pa = (brival_inputs || darkedge_inputs) ? 8'hff :
                          p_dig(joystick_2);
wire [7:0] core_ppi_pb = brival_inputs ? brival_ppi_pb :
                          darkedge_inputs ? darkedge_ppi_pb : p_dig(joystick_3);
wire [7:0] core_ppi_pc = (brival_inputs || darkedge_inputs) ? 8'hff :
                          ga2_ppi_pc;

//////////////////////////////   CORE   ///////////////////////////////////////
wire [23:0] rgb_a, rgb_b;
wire ce_pix_core, core_hs, core_hb, core_vb, mode_416_active;
wire signed [15:0] aud_l, aud_r;

s32_core core (
    .clk_sys(clk_sys), .clk_ram(clk_ram),
`ifdef S32_REAL_V25
    .clk_v25(clk_v25),
`endif
    .rst(reset), .video_rst(video_reset),
    .board(active_board),
    .ce_cpu(ce_cpu), .ce_z80(ce_z80), .ce_fm(ce_fm), .ce_pcm(ce_pcm),
    // Production profiles have no debug/screenshot pause control. Keep the
    // core port constant so standalone verification benches can still test
    // V25 pause semantics without carrying the menu logic into an RBF.
    .pause(1'b0), .alien3_hud_blend(alien3_controls && status[8]),
    .sdr_p0_req(p0_req), .sdr_p0_addr(p0_addr), .sdr_p0_dout(p0_dout), .sdr_p0_ack(p0_ack),
    .sdr_p1_req(core_p1_req), .sdr_p1_addr(core_p1_addr), .sdr_p1_dout(p1_dout),
    .sdr_p1_ack(p1_ack),
    .sdr_p2_req(core_p2_req), .sdr_p2_addr(core_p2_addr), .sdr_p2_dout(p2_dout),
    .sdr_p2_ack(p2_ack),
    .sdr_p3_req(p3_req), .sdr_p3_addr(p3_addr), .sdr_p3_dout(p3_dout), .sdr_p3_ack(p3_ack),
    .sdr_p4_req(p4_req), .sdr_p4_addr(p4_addr), .sdr_p4_dout(p4_dout), .sdr_p4_ack(p4_ack),
    .sdr_p5_req(p5_req), .sdr_p5_addr(p5_addr), .sdr_p5_dout(p5_dout), .sdr_p5_ack(p5_ack),
    .fb_wr_start(fbw_start), .fb_wr_buf(fbw_buf), .fb_wr_x(fbw_x), .fb_wr_y(fbw_y),
    .fb_wr_valid(fbw_valid), .fb_wr_pix(fbw_pix), .fb_wr_end(fbw_end),
    .fb_wr_shadow(fbw_shadow), .fb_wr_busy(fbw_busy),
    .fb_er_req(fbe_req), .fb_er_buf(fbe_buf), .fb_er_y(fbe_y), .fb_er_ack(fbe_ack),
    .fb_rd_req(fbr_req), .fb_rd_buf(fbr_buf),
    .fb_rd_blend_buf(fbr_blend_buf), .fb_rd_blend(fbr_blend),
    .fb_rd_y(fbr_y), .fb_rd_ack(fbr_ack),
    .fb_rd_x(fbr_x), .fb_rd_pix(fbr_pix),
    .v25_prg_wr(v25_wr), .v25_prg_waddr(v25_waddr), .v25_prg_wdata(v25_wdata),
    .eep_ld_wr(eep_wr), .eep_ld_addr(eep_waddr), .eep_ld_data(eep_wdata),
    .eep_rd_data(eep_rd_data), .eep_rd_addr(eep_rd_addr),
    .eep_upload(eep_upload), .eep_modified(eep_modified),
    .in_p1a(core_p1a), .in_p2a(core_p2a),
    .in_portc(portc), .in_svc12(svc12), .in_svc34(svc34),
    .in_p1b(p_dig(joystick_2)), .in_p2b(p_dig(joystick_3)),
    .in_portc_b(8'hff), .in_svc12_b(8'hff), .in_svc34_b(8'hff),
    .adc_ch(adc_ch),
    .trk_dv(trk_dv_a), .trk_dx(trk_dx_a), .trk_dy(trk_dy_a), .trk_btn(trk_btn),
    .ppi_pa(core_ppi_pa), .ppi_pb(core_ppi_pb), .ppi_pc(core_ppi_pc),
    .rgb_a(rgb_a), .rgb_b(rgb_b),
    .ce_pix(ce_pix_core),
    .hs(core_hs), .vs(core_vs), .hb(core_hb), .vb(core_vb),
    .mode_416_active(mode_416_active),
    .audio_l(aud_l), .audio_r(aud_r),
    .out_lamps()
);

assign AUDIO_L = aud_l;
assign AUDIO_R = aud_r;

//////////////////////////////   VIDEO   //////////////////////////////////////
`ifdef S32_SYSTEM32_ONLY
wire [23:0] game_rgb = rgb_a;
`else
wire [23:0] game_rgb = status[6] ? rgb_b : rgb_a;
`endif
wire [2:0] scandoubler_fx = status[5:3];
// Scandoubler Fx is a 3-bit field (None/CRT 25/50/75). VGA_SL takes the two
// low bits directly so None=0 and CRT 25/50/75 map to 1/2/3.
wire [2:0] scanline_level = scandoubler_fx;   // None=0, CRT 25/50/75 = 1/2/3
assign VGA_SL = scanline_level[1:0];

// Original = the 4:3 arcade monitor (MAME's default for both 320- and 416-wide
// System 32 modes); the old 13:7 square-pixel ratio stretched holo's 320 mode.
// Full Screen fills; [ARC1]/[ARC2] emit the framework custom-aspect encoding
// (ARY=0, ARX = menu index) instead of acting as 16:9 (audit R20 PF-2).
wire [1:0] aspect = status[2:1];
wire [11:0] aspect_arx = (aspect == 0) ? 12'd4 : {10'd0, (aspect - 1'd1)};
wire [11:0] aspect_ary = (aspect == 0) ? 12'd3 : 12'd0;

// Reuse the framework's existing integer-scaling engine. This adds no frame
// buffer: video_freak only computes the requested HDMI target size and the
// existing sys/ascal scaler performs the actual resize. A direct-video mode
// reports HDMI_WIDTH/HEIGHT as zero, so keep the engine in its cheap bypass
// mode there instead of asking its divider to divide by zero.
wire [2:0] scale_mode = (HDMI_WIDTH != 12'd0 && HDMI_HEIGHT != 12'd0)
                      ? {1'b0, status[28:27]} : 3'd0;
wire scale_de_unused;
video_freak s32_video_freak (
    .CLK_VIDEO (clk_sys),
    .CE_PIXEL  (ce_pix_core),
    .VGA_VS    (core_vs),
    .HDMI_WIDTH(HDMI_WIDTH),
    .HDMI_HEIGHT(HDMI_HEIGHT),
    .VGA_DE    (scale_de_unused),
    .VIDEO_ARX (VIDEO_ARX),
    .VIDEO_ARY (VIDEO_ARY),
    .VGA_DE_IN(~(core_hb | core_vb)),
    .ARX       (aspect_arx),
    .ARY       (aspect_ary),
    .CROP_SIZE (12'd0),
    .CROP_OFF  (5'd0),
    .SCALE     (scale_mode)
);

//////////////////////////// CRT ADJUST /////////////////////////////////////
// The upstream core-side CRT Adjust module uses one ping-pong RGB line buffer
// and keeps the native sync reference. AW includes the ping-pong bank bit, so
// two complete 512-sample lines require the generic 1024-entry AW=10 buffer.
// Use the hps_io status bits directly; they already live in clk_sys and this
// avoids duplicating 19 control registers solely to sample them on pixel CE.
wire              crt_on     = status[9];
wire signed [4:0] crt_hsize  = $signed(status[14:10]);
wire        [6:0] crt_hpos    = status[21:15];
wire signed [5:0] crt_vshift = $signed(status[26:22]);

// CRT Adjust operates on the native 15 kHz stream. The framework's
// scandoubler changes the pixel-CE ratio, so leave the line buffer in bypass
// while a CRT 25/50/75% effect is selected.
wire crt_adjust_active = crt_on && (scandoubler_fx == 3'd0);

// HSync-shift mode is the safe choice here because the System 32 active window
// is line-anchored at x=0 rather than centered inside the total line. The
// module is sized for the 416-wide mode; for 320-wide mode compensate negative
// positions by the 512-410 total-line difference before passing the offset in.
wire signed [8:0] crt_hpos_native = (crt_hpos <= 7'd48)
    ? $signed({2'b00, crt_hpos})
    : $signed({2'b00, crt_hpos}) - 9'sd128;
wire signed [8:0] crt_hpos_module = (!mode_416_active && crt_hpos_native[8])
    ? crt_hpos_native - 9'sd102 : crt_hpos_native;

wire [7:0] crt_r, crt_g, crt_b;
wire crt_hs, crt_vs, crt_hb, crt_vb, crt_hs_ref;

// clk_sys/pixel is 6 clocks (24 quarter-cycles) in 416 mode and 7.5 clocks
// (30 quarter-cycles on average) in 320 mode. CRT Adjust steps the read period
// in quarter-cycles; this preserves its native width in both modes without a
// divider or a second timing generator.
reg [7:0] crt_rd_acc;
reg crt_hs_ref_d;
wire [7:0] crt_base_period = mode_416_active ? 8'd24 : 8'd30;
wire [7:0] crt_rd_period = crt_base_period + {{3{crt_hsize[4]}}, crt_hsize};
wire crt_rd_tick = (crt_rd_acc + 8'd4) >= {1'b0, crt_rd_period};
wire crt_hs_ref_rise = crt_hs_ref & ~crt_hs_ref_d;
always @(posedge clk_sys) begin
    if (video_reset) begin
        crt_rd_acc   <= 8'd0;
        crt_hs_ref_d <= 1'b0;
    end
    else begin
        crt_hs_ref_d <= crt_hs_ref;
        if (crt_hs_ref_rise)
            crt_rd_acc <= 8'd0;
        else if (crt_rd_tick)
            crt_rd_acc <= crt_rd_acc + 8'd4 - {1'b0, crt_rd_period};
        else
            crt_rd_acc <= crt_rd_acc + 8'd4;
    end
end
wire crt_rd_ce = crt_adjust_active ? crt_rd_tick : ce_pix_core;

crt_adjust #(
    .VTOTAL   (262),
    .HTOTAL   (512),
    .HPOS_MODE(0),
    .AW        (10)
) u_crt_adjust (
    .clk       (clk_sys),
    .pxl_cen   (ce_pix_core),
    .pxl2_cen  (crt_rd_ce),
    .active    (crt_adjust_active),
    .hsize     (crt_hsize),
    .hoffset   (crt_hpos_module),
    .voffset   (crt_vshift),
    .r_in      (game_rgb[23:16]),
    .g_in      (game_rgb[15:8]),
    .b_in      (game_rgb[7:0]),
    .hs_in     (core_hs),
    .vs_in     (core_vs),
    .hb_in     (core_hb | core_vb),
    .vb_in     (core_vb),
    .r_out     (crt_r),
    .g_out     (crt_g),
    .b_out     (crt_b),
    .hs_out    (crt_hs),
    .vs_out    (crt_vs),
    .hb_out    (crt_hb),
    .vb_out    (crt_vb),
    .hs_ref_out(crt_hs_ref)
);

// Keep the framework OSD centered on the native active window. H-Position and
// H-Size alter the analog image window, but this separate DE edge keeps the
// downstream OSD from following that adjustment.
reg crt_hs_in_d, crt_native_active_d, crt_str_active_d;
reg crt_vblank_1l, crt_de_osd;
wire crt_hs_in_rise = core_hs & ~crt_hs_in_d;
wire crt_native_active = ~(core_hb | crt_vblank_1l);
wire crt_native_rise = crt_native_active & ~crt_native_active_d;
wire crt_str_active = ~crt_hb;
wire crt_str_fall = crt_str_active_d & ~crt_str_active;
always @(posedge clk_sys) begin
    if (video_reset) begin
        crt_hs_in_d         <= 1'b0;
        crt_native_active_d <= 1'b0;
        crt_str_active_d    <= 1'b0;
        crt_vblank_1l       <= 1'b0;
        crt_de_osd           <= 1'b0;
    end
    else begin
        crt_hs_in_d <= core_hs;
        if (crt_hs_in_rise)
            crt_vblank_1l <= core_vb;
        if (ce_pix_core)
            crt_native_active_d <= crt_native_active;
        if (crt_rd_ce)
            crt_str_active_d <= crt_str_active;
        if (crt_native_rise)
            crt_de_osd <= 1'b1;
        else if (crt_str_fall)
            crt_de_osd <= 1'b0;
    end
end

assign CE_PIXEL = crt_adjust_active ? crt_rd_ce : ce_pix_core;
assign VGA_R  = crt_adjust_active ? crt_r : game_rgb[23:16];
assign VGA_G  = crt_adjust_active ? crt_g : game_rgb[15:8];
assign VGA_B  = crt_adjust_active ? crt_b : game_rgb[7:0];
assign VGA_HS = crt_adjust_active ? crt_hs : core_hs;
assign VGA_VS = crt_adjust_active ? crt_vs : core_vs;
assign VGA_DE = crt_adjust_active ? crt_de_osd : ~(core_hb | core_vb);

endmodule
