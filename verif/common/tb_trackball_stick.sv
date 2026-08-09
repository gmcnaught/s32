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
        check(   16,  -16,   0,   0);
        check(   24,   24,  -1,   1);
        check(  -24,  -24,   1,  -1);
        check(  127,  127, -13,  13);
        check( -127, -127,  13, -13);
        check( -128, -128,  14, -14);

        if (errors)
            $fatal(1, "trackball stick test failed with %0d errors", errors);
        $display("TRACKBALL STICK PASS");
        $finish;
    end
endmodule
