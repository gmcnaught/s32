`timescale 1ns/1ps

module tb_driving_controls;
    reg  [7:0] left_x;
    reg  [7:0] right_y;
    reg        digital_accel;
    reg        digital_brake;
    wire [7:0] wheel;
    wire [7:0] accel;
    wire [7:0] brake;

    s32_driving_controls dut (
        .left_x(left_x),
        .right_y(right_y),
        .digital_accel(digital_accel),
        .digital_brake(digital_brake),
        .wheel(wheel),
        .accel(accel),
        .brake(brake)
    );

    task automatic check(input condition, input [255:0] message);
        if (!condition) begin
            $display("FAIL: %0s", message);
            $fatal(1);
        end
    endtask

    task automatic drive(input [7:0] right_y_value, input [31:0] buttons);
        right_y = right_y_value;
        digital_accel = buttons[4];
        digital_brake = buttons[5];
        #1;
    endtask

    task automatic drive_wheel(input [7:0] left_x_value);
        left_x = left_x_value;
        #1;
    endtask

    initial begin
        integer position;
        integer expected;
        reg [7:0] previous;

        left_x = 8'h00;

        drive(8'h00, 32'd0);
        check(accel == 8'h00 && brake == 8'h00,
              "center releases both pedals");

        drive(8'hc0, 32'd0); // -64: right stick halfway up
        check(accel == 8'h80 && brake == 8'h00,
              "right-stick up drives accelerator only");

        drive(8'h81, 32'd0); // -127: full up
        check(accel == 8'hff && brake == 8'h00,
              "full right-stick up saturates accelerator");

        drive(8'h40, 32'd0); // +64: right stick halfway down
        check(accel == 8'h00 && brake == 8'h80,
              "right-stick down drives brake only");

        drive(8'h7f, 32'd0); // +127: full down
        check(accel == 8'h00 && brake == 8'hff,
              "full right-stick down saturates brake");

        drive(8'h00, 32'h0000_0010); // A / B1
        check(accel == 8'hff && brake == 8'h00,
              "A is the full-scale digital accelerator");

        drive(8'h00, 32'h0000_0020); // B / B2
        check(accel == 8'h00 && brake == 8'hff,
              "B is the full-scale digital brake");

        drive(8'h00, 32'h0000_0040); // X / B3: Gear Change
        check(accel == 8'h00 && brake == 8'h00,
              "Gear Change does not press either pedal");

        // Sweep every signed MiSTer X coordinate in physical order. Each
        // coordinate must appear immediately, monotonically, with no clocked
        // state that can retain a random intermediate wheel position.
        previous = 8'h00;
        for (position = -127; position <= 127; position = position + 1) begin
            drive_wheel(position[7:0]);
            if (position < -6)
                expected = 128 + position + 6;
            else if (position > 6)
                expected = 128 + position - 6;
            else
                expected = 128;
            check(wheel == expected[7:0],
                  "wheel follows every current signed-stick coordinate");
            check(position == -127 || wheel >= previous,
                  "wheel sweep is monotonic");
            previous = wheel;
        end

        drive_wheel(8'hc0); // -64
        check(wheel == 8'h46, "left intermediate coordinate is immediate");
        drive_wheel(8'h40); // +64, direct reversal
        check(wheel == 8'hba, "right reversal cannot retain old left value");
        drive_wheel(8'h00); // center
        check(wheel == 8'h80, "return to center is immediate");

        $display("PASS: System 32 driving controls");
        $finish;
    end
endmodule
