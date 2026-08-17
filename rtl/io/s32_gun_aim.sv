`timescale 1ns/1ps

module s32_gun_aim #(
    parameter integer TICK_BITS = 16
) (
    input              clk,
    input              rst,
    input              enable,
    input       [7:0]  p1_raw_x,
    input       [7:0]  p1_raw_y,
    input       [7:0]  p2_raw_x,
    input       [7:0]  p2_raw_y,
    input              invert_x,
    input              invert_y,
    output reg  [7:0]  p1_aim_x,
    output reg  [7:0]  p1_aim_y,
    output reg  [7:0]  p2_aim_x,
    output reg  [7:0]  p2_aim_y
);

localparam [8:0] GUN_INNER_R  = 9'd6;
localparam [8:0] GUN_OUTER_R  = 9'd122;
// Full stick deflection stops slightly short of the ADC end codes.  At the
// hardware limit the game's sight tracked past the visible border and vanished
// off screen, so the endpoint is pulled in to 0x08..0xf8.
localparam [7:0] GUN_PEAK_MAG = 8'd120;

// Precomputed curve magnitude for radii strictly between the two deadzones.
// Values are round(GUN_PEAK_MAG * (0.625*t + 0.375*t*t)), t=(r-6)/(122-6).
// The table is read by one shared processing state, so it synthesizes once.
function automatic [7:0] gun_curve_mag(input [8:0] radius);
begin
    if (radius <= GUN_INNER_R)
        gun_curve_mag = 8'd0;
    else if (radius >= GUN_OUTER_R)
        gun_curve_mag = GUN_PEAK_MAG;
    else begin
        case (radius)
            9'd7, 9'd8: gun_curve_mag = 8'd1;
            9'd9: gun_curve_mag = 8'd2;
            9'd10, 9'd11: gun_curve_mag = 8'd3;
            9'd12: gun_curve_mag = 8'd4;
            9'd13, 9'd14: gun_curve_mag = 8'd5;
            9'd15: gun_curve_mag = 8'd6;
            9'd16: gun_curve_mag = 8'd7;
            9'd17, 9'd18: gun_curve_mag = 8'd8;
            9'd19: gun_curve_mag = 8'd9;
            9'd20, 9'd21: gun_curve_mag = 8'd10;
            9'd22: gun_curve_mag = 8'd11;
            9'd23: gun_curve_mag = 8'd12;
            9'd24, 9'd25: gun_curve_mag = 8'd13;
            9'd26: gun_curve_mag = 8'd14;
            9'd27: gun_curve_mag = 8'd15;
            9'd28: gun_curve_mag = 8'd16;
            9'd29, 9'd30: gun_curve_mag = 8'd17;
            9'd31: gun_curve_mag = 8'd18;
            9'd32: gun_curve_mag = 8'd19;
            9'd33: gun_curve_mag = 8'd20;
            9'd34: gun_curve_mag = 8'd21;
            9'd35, 9'd36: gun_curve_mag = 8'd22;
            9'd37: gun_curve_mag = 8'd23;
            9'd38: gun_curve_mag = 8'd24;
            9'd39: gun_curve_mag = 8'd25;
            9'd40: gun_curve_mag = 8'd26;
            9'd41: gun_curve_mag = 8'd27;
            9'd42: gun_curve_mag = 8'd28;
            9'd43, 9'd44: gun_curve_mag = 8'd29;
            9'd45: gun_curve_mag = 8'd30;
            9'd46: gun_curve_mag = 8'd31;
            9'd47: gun_curve_mag = 8'd32;
            9'd48: gun_curve_mag = 8'd33;
            9'd49: gun_curve_mag = 8'd34;
            9'd50: gun_curve_mag = 8'd35;
            9'd51: gun_curve_mag = 8'd36;
            9'd52: gun_curve_mag = 8'd37;
            9'd53: gun_curve_mag = 8'd38;
            9'd54: gun_curve_mag = 8'd39;
            9'd55: gun_curve_mag = 8'd40;
            9'd56: gun_curve_mag = 8'd41;
            9'd57: gun_curve_mag = 8'd42;
            9'd58: gun_curve_mag = 8'd43;
            9'd59: gun_curve_mag = 8'd44;
            9'd60: gun_curve_mag = 8'd45;
            9'd61: gun_curve_mag = 8'd46;
            9'd62: gun_curve_mag = 8'd47;
            9'd63: gun_curve_mag = 8'd48;
            9'd64: gun_curve_mag = 8'd49;
            9'd65: gun_curve_mag = 8'd50;
            9'd66: gun_curve_mag = 8'd51;
            9'd67: gun_curve_mag = 8'd52;
            9'd68: gun_curve_mag = 8'd53;
            9'd69: gun_curve_mag = 8'd54;
            9'd70: gun_curve_mag = 8'd55;
            9'd71: gun_curve_mag = 8'd56;
            9'd72: gun_curve_mag = 8'd57;
            9'd73: gun_curve_mag = 8'd58;
            9'd74: gun_curve_mag = 8'd59;
            9'd75: gun_curve_mag = 8'd61;
            9'd76: gun_curve_mag = 8'd62;
            9'd77: gun_curve_mag = 8'd63;
            9'd78: gun_curve_mag = 8'd64;
            9'd79: gun_curve_mag = 8'd65;
            9'd80: gun_curve_mag = 8'd66;
            9'd81: gun_curve_mag = 8'd67;
            9'd82: gun_curve_mag = 8'd68;
            9'd83: gun_curve_mag = 8'd70;
            9'd84: gun_curve_mag = 8'd71;
            9'd85: gun_curve_mag = 8'd72;
            9'd86: gun_curve_mag = 8'd73;
            9'd87: gun_curve_mag = 8'd74;
            9'd88: gun_curve_mag = 8'd76;
            9'd89: gun_curve_mag = 8'd77;
            9'd90: gun_curve_mag = 8'd78;
            9'd91: gun_curve_mag = 8'd79;
            9'd92: gun_curve_mag = 8'd80;
            9'd93: gun_curve_mag = 8'd82;
            9'd94: gun_curve_mag = 8'd83;
            9'd95: gun_curve_mag = 8'd84;
            9'd96: gun_curve_mag = 8'd85;
            9'd97: gun_curve_mag = 8'd87;
            9'd98: gun_curve_mag = 8'd88;
            9'd99: gun_curve_mag = 8'd89;
            9'd100: gun_curve_mag = 8'd90;
            9'd101: gun_curve_mag = 8'd92;
            9'd102: gun_curve_mag = 8'd93;
            9'd103: gun_curve_mag = 8'd94;
            9'd104: gun_curve_mag = 8'd95;
            9'd105: gun_curve_mag = 8'd97;
            9'd106: gun_curve_mag = 8'd98;
            9'd107: gun_curve_mag = 8'd99;
            9'd108: gun_curve_mag = 8'd101;
            9'd109: gun_curve_mag = 8'd102;
            9'd110: gun_curve_mag = 8'd103;
            9'd111: gun_curve_mag = 8'd105;
            9'd112: gun_curve_mag = 8'd106;
            9'd113: gun_curve_mag = 8'd107;
            9'd114: gun_curve_mag = 8'd109;
            9'd115: gun_curve_mag = 8'd110;
            9'd116: gun_curve_mag = 8'd112;
            9'd117: gun_curve_mag = 8'd113;
            9'd118: gun_curve_mag = 8'd114;
            9'd119: gun_curve_mag = 8'd116;
            9'd120: gun_curve_mag = 8'd117;
            9'd121: gun_curve_mag = 8'd119;
            default: gun_curve_mag = 8'd0;
        endcase
    end
end
endfunction

function automatic [7:0] gun_offset_axis(
    input negative,
    input [7:0] magnitude
);
begin
    if (negative)
        gun_offset_axis = (magnitude >= GUN_PEAK_MAG)
                        ? (8'd128 - GUN_PEAK_MAG) : (8'd128 - magnitude);
    else
        gun_offset_axis = (magnitude >= GUN_PEAK_MAG)
                        ? (8'd128 + GUN_PEAK_MAG) : (8'd128 + magnitude);
end
endfunction

// Error-sensitive smoothing: large moves consume half the error per update;
// fine motion consumes a rounded quarter; the last three codes snap exactly.
function automatic [7:0] gun_filter(input [7:0] current, input [7:0] target);
    logic signed [9:0] err;
    logic signed [9:0] step;
    logic signed [10:0] next_value;
begin
    err = $signed({2'b00, target}) - $signed({2'b00, current});
    if (err >= -3 && err <= 3)
        gun_filter = target;
    else begin
        if (err >= 16)
            step = (err + 10'sd1) >>> 1;
        else if (err <= -16)
            step = -(((-err) + 10'sd1) >>> 1);
        else if (err > 0)
            step = (err + 10'sd3) >>> 2;
        else
            step = -(((-err) + 10'sd3) >>> 2);
        next_value = $signed({3'b000, current}) + step;
        if (next_value < 0)
            gun_filter = 8'h00;
        else if (next_value > 11'sd255)
            gun_filter = 8'hff;
        else
            gun_filter = next_value[7:0];
    end
end
endfunction

reg [TICK_BITS-1:0] tick_div;
reg signed [8:0] sample_x0, sample_y0, sample_x1, sample_y1;
reg player;

wire signed [8:0] selected_x = player ? sample_x1 : sample_x0;
wire signed [8:0] selected_y = player ? sample_y1 : sample_y0;
wire [8:0] selected_abs_x = selected_x[8] ? (~selected_x + 1'b1) : selected_x;
wire [8:0] selected_abs_y = selected_y[8] ? (~selected_y + 1'b1) : selected_y;
wire [8:0] selected_max = (selected_abs_x >= selected_abs_y)
                        ? selected_abs_x : selected_abs_y;
wire [8:0] selected_min = (selected_abs_x >= selected_abs_y)
                        ? selected_abs_y : selected_abs_x;
wire [10:0] selected_min_x3 = {2'b00, selected_min}
                           + ({2'b00, selected_min} << 1);
wire [2:0] unused_selected_min_fraction = selected_min_x3[2:0];
// max + 3/8*min is a close, shift-friendly Euclidean-radius approximation.
wire [8:0] selected_radius = selected_max + selected_min_x3[10:3];
// MAME's PORT_SENSITIVITY is host-input tuning, not an electrical limit on
// the cabinet ADC.  Feed the complete conditioned radius to the 8-bit ADC so
// 95% physical stick throw reaches the game's full 0x00..0xff aim range.
wire [7:0] selected_magnitude = gun_curve_mag(selected_radius);

typedef enum logic [2:0] {G_IDLE, G_PREP, G_DIV_X, G_DIV_Y, G_FILTER} gun_state_t;
gun_state_t state;
reg [8:0]  div_den;
reg [7:0]  div_rem;
reg [14:0] div_quot;
reg [3:0]  div_count;
wire [8:0] div_rem_shift = {div_rem, div_quot[14]};
wire       div_take = div_rem_shift >= div_den;
wire [8:0] div_rem_next = div_take ? div_rem_shift - div_den
                                   : div_rem_shift;
wire unused_div_rem_msb = div_rem_next[8];
wire [14:0] div_quot_next = {div_quot[13:0], div_take};

reg [7:0] work_magnitude;
reg       work_negative_x, work_negative_y;
reg [7:0] work_out_x, work_out_y;

always @(posedge clk) begin
    if (rst) begin
        tick_div <= {TICK_BITS{1'b0}};
        state <= G_IDLE;
        player <= 1'b0;
        sample_x0 <= 9'sd0; sample_y0 <= 9'sd0;
        sample_x1 <= 9'sd0; sample_y1 <= 9'sd0;
        div_den <= 9'd1; div_rem <= 8'd0; div_quot <= 15'd0;
        div_count <= 4'd0;
        work_magnitude <= 8'd0;
        work_negative_x <= 1'b0; work_negative_y <= 1'b0;
        work_out_x <= 8'd0; work_out_y <= 8'd0;
        p1_aim_x <= 8'h80; p1_aim_y <= 8'h80;
        p2_aim_x <= 8'h80; p2_aim_y <= 8'h80;
    end
    else if (!enable) begin
        tick_div <= {TICK_BITS{1'b0}};
        state <= G_IDLE;
        p1_aim_x <= 8'h80; p1_aim_y <= 8'h80;
        p2_aim_x <= 8'h80; p2_aim_y <= 8'h80;
    end
    else begin
        tick_div <= tick_div + 1'b1;
        case (state)
            G_IDLE: if (tick_div == {TICK_BITS{1'b0}}) begin
                sample_x0 <= invert_x ? -$signed({p1_raw_x[7], p1_raw_x})
                                      :  $signed({p1_raw_x[7], p1_raw_x});
                sample_y0 <= invert_y ? -$signed({p1_raw_y[7], p1_raw_y})
                                      :  $signed({p1_raw_y[7], p1_raw_y});
                sample_x1 <= invert_x ? -$signed({p2_raw_x[7], p2_raw_x})
                                      :  $signed({p2_raw_x[7], p2_raw_x});
                sample_y1 <= invert_y ? -$signed({p2_raw_y[7], p2_raw_y})
                                      :  $signed({p2_raw_y[7], p2_raw_y});
                player <= 1'b0;
                state <= G_PREP;
            end

            G_PREP: begin
                work_negative_x <= selected_x[8];
                work_negative_y <= selected_y[8];
                work_magnitude <= selected_magnitude;
                if (selected_radius <= GUN_INNER_R) begin
                    work_out_x <= 8'd0;
                    work_out_y <= 8'd0;
                    state <= G_FILTER;
                end
                else begin
                    div_den <= selected_radius;
                    div_rem <= 8'd0;
                    div_quot <= selected_abs_x * selected_magnitude;
                    div_count <= 4'd0;
                    state <= G_DIV_X;
                end
            end

            G_DIV_X: begin
                div_rem <= div_rem_next[7:0];
                div_quot <= div_quot_next;
                if (div_count == 4'd14) begin
                    work_out_x <= (div_quot_next > {7'd0, GUN_PEAK_MAG})
                                ? GUN_PEAK_MAG : div_quot_next[7:0];
                    div_rem <= 8'd0;
                    div_quot <= selected_abs_y * work_magnitude;
                    div_count <= 4'd0;
                    state <= G_DIV_Y;
                end
                else
                    div_count <= div_count + 1'b1;
            end

            G_DIV_Y: begin
                div_rem <= div_rem_next[7:0];
                div_quot <= div_quot_next;
                if (div_count == 4'd14) begin
                    work_out_y <= (div_quot_next > {7'd0, GUN_PEAK_MAG})
                                ? GUN_PEAK_MAG : div_quot_next[7:0];
                    state <= G_FILTER;
                end
                else
                    div_count <= div_count + 1'b1;
            end

            G_FILTER: begin
                if (!player) begin
                    p1_aim_x <= gun_filter(p1_aim_x,
                        gun_offset_axis(work_negative_x, work_out_x));
                    p1_aim_y <= gun_filter(p1_aim_y,
                        gun_offset_axis(work_negative_y, work_out_y));
                    player <= 1'b1;
                    state <= G_PREP;
                end
                else begin
                    p2_aim_x <= gun_filter(p2_aim_x,
                        gun_offset_axis(work_negative_x, work_out_x));
                    p2_aim_y <= gun_filter(p2_aim_y,
                        gun_offset_axis(work_negative_y, work_out_y));
                    state <= G_IDLE;
                end
            end

            default: state <= G_IDLE;
        endcase
    end
end

endmodule

// ---------------------------------------------------------------------------
