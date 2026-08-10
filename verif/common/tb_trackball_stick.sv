`timescale 1ns/1ps

module tb_trackball_stick;
    reg [15:0] analog;
    wire signed [8:0] dx;
    wire signed [8:0] dy;
    integer errors = 0;

    s32_trackball_stick dut (
        .analog(analog), .dx(dx), .dy(dy)
    );

    task automatic check;
        input signed [7:0] x;
        input signed [7:0] y;
        input signed [8:0] expected_dx;
        input signed [8:0] expected_dy;
        begin
            analog = {y, x};
            #1;
            if (dx !== expected_dx || dy !== expected_dy) begin
                $display("FAIL x=%0d y=%0d dx=%0d/%0d dy=%0d/%0d",
                         x, y, dx, expected_dx, dy, expected_dy);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        check(    0,    0,   0,   0);
        check(   15,  -15,   0,   0); // deadzone edge
        check(   16,  -16,  -1,  -1);
        check(   25,   25,  -2,   2); // about 20% stick
        check(   51,   51,  -5,   5); // about 40% stick
        check(   76,   76, -11,  11); // about 60% stick
        check(  102,  102, -20,  20); // about 80% stick
        check(  112,  112, -23,  23); // high-band ramp start
        check(  127,  127, -30,  30); // maximum positive input
        check( -127, -127,  30, -30); // sign symmetry and reversed X
        check( -128, -128,  30, -30); // defensive negative saturation

        if (errors)
            $fatal(1, "trackball stick test failed with %0d errors", errors);
        $display("TRACKBALL STICK PASS");
        $finish;
    end
endmodule
