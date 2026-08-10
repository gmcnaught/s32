//============================================================================
// Sprite vblank/frame-boundary regression.
//
// On hardware the sprite engine runs on clk_ram (96.634615 MHz) while its vblank
// input is the end-of-vblank pulse from s32_video, which is one clk_sys
// (48.317307 MHz) wide — i.e. TWO consecutive clk_ram samples. Treat that
// pulse as one frame event. If another vblank arrives during a long render,
// drop it: consuming it when the FSM eventually returns to idle would swap the
// displayed A/B buffer partway through the visible raster.
//
// This bench covers realistic 2-cycle pulses, the legacy 1-cycle pulse, and
// an overrun whose next swap must wait for a new physical frame boundary.
//============================================================================
`timescale 1ns/1ps

module tb_sprite_vblank;

reg clk = 0;
always #5 clk = ~clk;
reg rst = 1;

// Sprite-list RAM: every word 0xC000 => word0 command bits[15:14]=11 = END, so
// the list terminates on entry 0 and each render pass is minimal.
reg [15:0] sram [0:16383];
wire [15:0] slist_addr;
reg  [15:0] slist_q;
always @(posedge clk) slist_q <= sram[slist_addr[13:0]];

// Sprite ROM: unused (list ends immediately) but keep the handshake alive.
wire        srom_req;
wire [23:4] srom_addr;
reg         srom_ack = 0;
reg [127:0] srom_data = 128'h0;
always @(posedge clk) srom_ack <= srom_req;

// Sprite -> framebuffer ports.
wire        fbw_start, fbw_valid, fbw_end, fbw_shadow, fbw_busy;
wire [1:0]  fbw_buf;
wire [8:0]  fbw_x;
wire [7:0]  fbw_y;
wire [15:0] fbw_pix;
wire        fbe_req, fbe_ack;
wire [1:0]  fbe_buf;
wire [7:0]  fbe_y;
wire [1:0]  disp_buf;
wire        rendering;

reg vblank = 0;
reg [7:0] ctl_addr = 0;
reg [7:0] ctl_wdata = 0;
reg       ctl_we = 0;

// Small post-vblank delay keeps the sim short; behaviour is delay-independent.
s32_sprite #(.POST_VBLANK_CYCLES(8)) sprite (
    .clk(clk), .rst(rst), .is_multi32(1'b0),
    .verify_srom(1'b0),
    .srom_bank_mask(2'b11),
    .vblank(vblank),
    .ctl_we(ctl_we), .ctl_addr(ctl_addr[2:0]), .ctl_wdata(ctl_wdata),
    .ctl_rdata(), .ctl_raddr(3'd0),
    .slist_addr(slist_addr), .slist_data(slist_q),
    .srom_req(srom_req), .srom_addr(srom_addr),
    .srom_data(srom_data), .srom_ack(srom_ack),
    .fb_wr_start(fbw_start), .fb_wr_buf(fbw_buf),
    .fb_wr_x(fbw_x), .fb_wr_y(fbw_y), .fb_wr_valid(fbw_valid),
    .fb_wr_pix(fbw_pix), .fb_wr_end(fbw_end),
    .fb_wr_shadow(fbw_shadow), .fb_busy(fbw_busy),
    .fb_er_req(fbe_req), .fb_er_buf(fbe_buf), .fb_er_y(fbe_y),
    .fb_er_ack(fbe_ack), .disp_buf(disp_buf)
);
assign rendering = sprite.rs != 0;

// Non-backpressured DDR so passes complete quickly.
wire        dd_busy;
wire [7:0]  dd_burst;
wire [28:0] dd_addr;
reg  [63:0] dd_dout = 0;
reg         dd_ready = 0;
wire        dd_rd, dd_we;
wire [63:0] dd_din;
wire [7:0]  dd_be;
assign dd_busy = 1'b0;

s32_fb_if #(.FB_BASE(32'h3000_0000)) fb (
    .clk(clk), .rst(rst),
    .DDRAM_BUSY(dd_busy), .DDRAM_BURSTCNT(dd_burst),
    .DDRAM_ADDR(dd_addr), .DDRAM_DOUT(dd_dout),
    .DDRAM_DOUT_READY(dd_ready), .DDRAM_RD(dd_rd),
    .DDRAM_DIN(dd_din), .DDRAM_BE(dd_be), .DDRAM_WE(dd_we),
    .wr_start(fbw_start), .wr_buf(fbw_buf), .wr_x(fbw_x), .wr_y(fbw_y),
    .wr_valid(fbw_valid), .wr_pix(fbw_pix), .wr_end(fbw_end),
    .wr_shadow(fbw_shadow), .wr_busy(fbw_busy),
    .er_req(fbe_req), .er_buf(fbe_buf), .er_y(fbe_y), .er_ack(fbe_ack),
    .rd_req(1'b0), .rd_buf(2'd0), .rd_blend_buf(2'd0), .rd_blend(1'b0),
    .rd_y(8'd0), .rd_ack(),
    .rd_x(9'd0), .rd_pix()
);

// Count logical controller swaps globally and prove System 32 uses only its
// ordinary A/B pair; the removed Alien 3 experiment allocated buffer 2 here.
integer render_edges = 0;
integer swap_edges = 0;
integer errors = 0;
reg rendering_d = 0;
reg [1:0] disp_buf_d = 0;
always @(posedge clk) begin
    rendering_d <= rendering;
    disp_buf_d  <= disp_buf;
    if (!rst && rendering && !rendering_d) render_edges = render_edges + 1;
    if (!rst && disp_buf !== disp_buf_d)   swap_edges   = swap_edges + 1;
    if (!rst && (fbe_req || fbw_start) &&
        (fbe_req ? fbe_buf[1] : fbw_buf[1])) begin
        errors = errors + 1;
        $display("  FAIL System 32 used removed extra framebuffer %0d",
                 fbe_req ? fbe_buf : fbw_buf);
    end
end

task write_ctl(input [2:0] a, input [7:0] d);
    @(posedge clk); ctl_we <= 1'b1; ctl_addr <= {5'd0, a}; ctl_wdata <= d;
    @(posedge clk); ctl_we <= 1'b0;
endtask

// Drive one vblank pulse `width` clk cycles wide, then let the pass settle.
task pulse_frame(input integer width);
    integer i;
    @(posedge clk); vblank <= 1'b1;
    for (i = 0; i < width; i = i + 1) @(posedge clk);
    vblank <= 1'b0;
endtask

task pulse_and_settle(input integer width);
    pulse_frame(width);
    // wait for the pass to run and the framebuffer to drain
    wait (rendering === 1'b1);
    wait (rendering === 1'b0);
    wait (fbw_busy === 1'b0);
    repeat (40) @(posedge clk);
endtask

integer si;
integer base_render, base_swap;
initial begin
    for (si = 0; si < 16384; si = si + 1) sram[si] = 16'hc000; // all END

    repeat (6) @(posedge clk);
    rst <= 1'b0;
    repeat (6) @(posedge clk);

    // Automatic every-frame mode: ctl[3] bit1=0, bit0=0 => command forced 2'b11.
    write_ctl(3'd3, 8'h00);
    repeat (8) @(posedge clk);

    // ---- Realistic 2-cycle (clk_ram) wide pulse: must produce ONE pass. ----
    base_render = render_edges;
    base_swap   = swap_edges;
    pulse_and_settle(2);
    if (render_edges - base_render !== 1) begin
        errors = errors + 1;
        $display("  FAIL 2-wide vblank produced %0d render passes (want 1)",
                 render_edges - base_render);
    end
    if (swap_edges - base_swap !== 1) begin
        errors = errors + 1;
        $display("  FAIL 2-wide vblank produced %0d buffer swaps (want 1)",
                 swap_edges - base_swap);
    end
    // ---- Three more 2-wide frames: strictly one pass + one swap each. ----
    for (si = 0; si < 3; si = si + 1) begin
        base_render = render_edges;
        base_swap   = swap_edges;
        pulse_and_settle(2);
        if (render_edges - base_render !== 1) begin
            errors = errors + 1;
            $display("  FAIL frame %0d: %0d render passes (want 1)",
                     si, render_edges - base_render);
        end
        if (swap_edges - base_swap !== 1) begin
            errors = errors + 1;
            $display("  FAIL frame %0d: %0d swaps (want 1)",
                     si, swap_edges - base_swap);
        end
    end

    // ---- 1-cycle pulse must still yield exactly one pass (no regression). ----
    base_render = render_edges;
    base_swap   = swap_edges;
    pulse_and_settle(1);
    if (render_edges - base_render !== 1) begin
        errors = errors + 1;
        $display("  FAIL 1-wide vblank produced %0d render passes (want 1)",
                 render_edges - base_render);
    end
    if (swap_edges - base_swap !== 1) begin
        errors = errors + 1;
        $display("  FAIL 1-wide vblank produced %0d buffer swaps (want 1)",
                 swap_edges - base_swap);
    end
    // ---- Overrun path: a frame event while erase/render is busy is dropped. ----
    // It must not be replayed on return to idle because that would swap buffers
    // in the middle of the visible raster. The next real vblank starts the next
    // pass at a safe frame boundary.
    base_render = render_edges;
    base_swap = swap_edges;
    pulse_frame(2);
    wait (fbe_req === 1'b1);
    pulse_frame(2);
    wait (rendering === 1'b0);
    wait (fbw_busy === 1'b0);
    repeat (40) @(posedge clk);
    if (render_edges - base_render !== 1) begin
        errors = errors + 1;
        $display("  FAIL overrun replayed a missed boundary: %0d passes (want 1)",
                 render_edges - base_render);
    end
    if (swap_edges - base_swap !== 1) begin
        errors = errors + 1;
        $display("  FAIL overrun replayed a missed boundary: %0d swaps (want 1)",
                 swap_edges - base_swap);
    end
    pulse_and_settle(2);
    if (render_edges - base_render !== 2 || swap_edges - base_swap !== 2) begin
        errors = errors + 1;
        $display("  FAIL next real boundary did not start the deferred frame");
    end
    if (errors == 0) $display("SPRITE VBLANK PASS");
    else             $display("SPRITE VBLANK FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #20000000;
    $display("SPRITE VBLANK FAIL (timeout)");
    $finish;
end

endmodule
