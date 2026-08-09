`timescale 1ns/1ps

module tb_driving_controls;
    reg [15:0] right_analog;
    reg        digital_accel;
    reg        digital_brake;
    wire [7:0] accel;
    wire [7:0] brake;

    s32_driving_controls dut (
        .right_analog(right_analog),
        .digital_accel(digital_accel),
        .digital_brake(digital_brake),
        .accel(accel),
        .brake(brake)
    );

    task automatic check(input condition, input [255:0] message);
        if (!condition) begin
            $display("FAIL: %0s", message);
            $fatal(1);
        end
    endtask

    task automatic drive(input [7:0] right_y, input [31:0] buttons);
        right_analog = {right_y, 8'h00};
        digital_accel = buttons[4];
        digital_brake = buttons[5];
        #1;
    endtask

    initial begin
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

        $display("PASS: Slip Stream driving controls");
        $finish;
    end
endmodule
