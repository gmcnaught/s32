//============================================================================
//  tb_hud_encoding -- the painter and the decoder must agree, bit for bit.
//
//  s32_debug_hud exists to be believed during an investigation in which
//  nothing else can be: a black screen, a wedged CPU, a build whose timing may
//  or may not have closed.  A HUD that paints a correct word and a decoder
//  that reads it back shifted by one cell would produce a confident wrong
//  answer, which is worse than no HUD at all.  Nothing else in the gate
//  elaborates this module -- verif/run_core_gate.sh builds s32_core, and the
//  HUD sits above it in Arcade-SegaSystem32.sv.
//
//  So this bench drives real video timing at it, captures the painted frame,
//  and reconstructs the word using tools/decode_hud.py's EXACT sampling rule
//  (sample the middle of each cell, MSB first, band row = rule row / 2).  If
//  either side moves, this fails.
//============================================================================
`timescale 1ns/1ps

module tb_hud_encoding;

localparam integer CELL_W  = 4;
localparam integer ROWS    = 6;
localparam integer HACTIVE = 320;
localparam integer HTOTAL  = 400;
localparam integer VACTIVE = 224;
localparam integer VTOTAL  = 240;
localparam [23:0]  BG      = 24'h123456;   // distinct from every HUD colour

reg clk = 1'b0;
always #5 clk = ~clk;

reg [9:0] hx = 10'd0;
reg [9:0] vy = 10'd0;
wire hblank = (hx >= HACTIVE);
wire vblank = (vy >= VACTIVE);

always @(posedge clk) begin
    if (hx == HTOTAL-1) begin
        hx <= 10'd0;
        vy <= (vy == VTOTAL-1) ? 10'd0 : vy + 10'd1;
    end
    else hx <= hx + 10'd1;
end

reg  [63:0] dbg = 64'd0;
wire [23:0] rgb_out;

s32_debug_hud #(.CELL_W(CELL_W), .ROWS(ROWS)) dut (
    .clk(clk), .ce_pix(1'b1),
    .hblank(hblank), .vblank(vblank),
    .dbg(dbg), .rgb_in(BG), .rgb_out(rgb_out)
);

// Captured top-left corner of the picture: enough rows to cover the band, the
// rule, and one line of plain picture under it.
localparam integer CAP_ROWS = ROWS + 2;
reg [23:0] fb [0:CAP_ROWS-1][0:HACTIVE-1];

always @(posedge clk)
    if (!hblank && !vblank && vy < CAP_ROWS) fb[vy][hx] <= rgb_out;

integer errors = 0;

task fail(input [255:0] what, input integer a, input integer b);
begin
    errors = errors + 1;
    $display("FAIL  %0s: got %0d expected %0d", what, a, b);
end
endtask

// One frame with `word` on the bus, then every check against the capture.
task check_word(input [63:0] word);
    integer i, x, y, row;
    reg [63:0] readback;
    reg [23:0] want;
begin
    dbg = word;
    // Two frames: the first re-synchronises the DUT's counters after the
    // previous pass, the second is the one measured.
    repeat (2) @(negedge vblank);
    @(posedge vblank);          // frame complete, capture is stable

    // --- the band -------------------------------------------------------
    for (row = 0; row < ROWS; row = row + 1)
      for (i = 0; i < 64; i = i + 1) begin
        want = word[63-i] ? 24'hFFFFFF : 24'h000060;
        // every pixel of the cell, not just its centre: a one-pixel shift
        // still decodes correctly at the centre and would go unnoticed.
        for (x = i*CELL_W; x < (i+1)*CELL_W; x = x + 1)
          if (fb[row][x] !== want)
            fail({"band cell ", 8'h30+i[3:0]}, fb[row][x], want);
      end

    // --- the rule, which is how the decoder finds the band ---------------
    for (x = 0; x < 64*CELL_W; x = x + 1)
      if (fb[ROWS][x] !== 24'hFF0000) fail("rule pixel", fb[ROWS][x], 24'hFF0000);

    // --- everything else is the picture, untouched -----------------------
    for (x = 64*CELL_W; x < HACTIVE; x = x + 1) begin
        if (fb[0][x]      !== BG) fail("band row right of band", fb[0][x], BG);
        if (fb[ROWS][x]   !== BG) fail("rule row right of band", fb[ROWS][x], BG);
    end
    for (x = 0; x < HACTIVE; x = x + 1)
        if (fb[ROWS+1][x] !== BG) fail("row below the rule", fb[ROWS+1][x], BG);

    // --- decode exactly as tools/decode_hud.py does ----------------------
    // rule row / 2 for the sample line, cell centre for x, MSB first.
    y = ROWS / 2;
    readback = 64'd0;
    for (i = 0; i < 64; i = i + 1) begin
        x = i*CELL_W + CELL_W/2;
        readback = {readback[62:0],
                    (fb[y][x][23:16] > 8'd128 && fb[y][x][15:8] > 8'd128
                                              && fb[y][x][7:0] > 8'd128)};
    end
    if (readback !== word) begin
        errors = errors + 1;
        $display("FAIL  decoder readback %016h, painted %016h", readback, word);
    end
    else $display("      decoded %016h", word);
end
endtask

initial begin
    @(posedge vblank);
    check_word(64'hA5C3_0F12_3456_789A);   // asymmetric: catches bit reversal
    check_word(64'h8000_0000_0000_0001);   // the two end bits, alone
    check_word(64'hFFFF_FFFF_FFFF_FFFF);
    check_word(64'h0000_0000_0000_0000);

    if (errors == 0) $display("HUD ENCODING PASS");
    else             $display("HUD ENCODING FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #20_000_000;
    $display("HUD ENCODING FAIL (timeout)");
    $finish;
end

endmodule
