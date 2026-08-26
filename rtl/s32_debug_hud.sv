//============================================================================
//  s32_debug_hud -- paint a 64-bit debug word into the top of the picture.
//
//  Deliberately dumb and deliberately last.  It sits at the very end of the
//  video path, downstream of the tilemap, sprite, mixer and CRT-adjust logic,
//  so it still renders when everything it is meant to observe is broken.  It
//  reads no memory, shares no clock domain with the suspect logic beyond the
//  pixel clock it is handed, and holds no state that a wedged core can stall.
//
//  Encoding, chosen so a 320x224 PNG screenshot decodes by eye AND by script:
//
//    rows 0..ROWS-1   64 cells, MSB first, each CELL_W pixels wide
//                     white = 1, dark blue = 0
//    row  ROWS        solid red rule, so the band is unmistakable and its
//                     exact height is measurable
//
//  64 cells x 4 px = 256 px, inside 320.  Cells start at x=0.
//============================================================================
`timescale 1ns/1ps

module s32_debug_hud #(
    parameter integer CELL_W = 4,
    parameter integer ROWS   = 6
) (
    input             clk,
    input             ce_pix,
    input             hblank,
    input             vblank,
    input      [63:0] dbg,
    input      [23:0] rgb_in,
    output     [23:0] rgb_out
);

// Pixel coordinates, counted locally.  hblank/vblank are the only inputs from
// the core's video timing; if those stop, the overlay stops, which is itself
// a reading.
reg [9:0] x = 10'd0;
reg [9:0] y = 10'd0;
reg       hb_d = 1'b0;
reg       vb_d = 1'b0;

always @(posedge clk) begin
    if (ce_pix) begin
        hb_d <= hblank;
        vb_d <= vblank;
        if (hblank) begin
            x <= 10'd0;
            if (!hb_d) y <= y + 10'd1;      // falling into hblank: next line
        end
        else x <= x + 10'd1;
        if (vblank) begin
            y <= 10'd0;
            if (!vb_d) y <= 10'd0;
        end
    end
end

localparam integer BAND_W = 64 * CELL_W;

// CELL_W is a power of two in every configuration used, so the cell_idx index is a
// shift rather than a divide -- keeps this out of the way of the fitter.
localparam integer CELL_SH = (CELL_W == 1) ? 0 : (CELL_W == 2) ? 1 :
                             (CELL_W == 4) ? 2 : (CELL_W == 8) ? 3 : 4;

wire        in_band = (y < ROWS)  && (x < BAND_W);
wire        in_rule = (y == ROWS) && (x < BAND_W);
wire [5:0]  cell_idx    = x >> CELL_SH;
wire        bit_val = dbg[63 - cell_idx];

// White on dark blue reads clearly on both a CRT and a PNG, and neither value
// occurs as a flat background in the failure modes seen so far (pure black
// 1034 B, flat olive 1464 B, flat 1316 B).
assign rgb_out = in_rule ? 24'hFF0000
               : in_band ? (bit_val ? 24'hFFFFFF : 24'h000060)
                         : rgb_in;

endmodule
