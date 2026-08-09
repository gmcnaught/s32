// System 32 driving-cabinet pedal adapter.
// MiSTer analog-stick axes are signed -128..+127 with zero at rest.
module s32_driving_controls (
    input  [15:0] right_analog,
    input         digital_accel,
    input         digital_brake,
    output  [7:0] accel,
    output  [7:0] brake
);
    wire signed [8:0] stick_y =
        $signed({right_analog[15], right_analog[15:8]});
    wire [8:0] accel_mag = (stick_y < 0) ? -stick_y : 9'd0;
    wire [8:0] brake_mag = (stick_y > 0) ?  stick_y : 9'd0;

    function automatic [7:0] pedal(input [8:0] magnitude);
        pedal = (magnitude >= 9'd127) ? 8'hff : {magnitude[6:0], 1'b0};
    endfunction

    assign accel = digital_accel ? 8'hff : pedal(accel_mag);
    assign brake = digital_brake ? 8'hff : pedal(brake_mag);
endmodule
