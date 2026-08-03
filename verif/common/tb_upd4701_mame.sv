`timescale 1ns/1ps

// Focused uPD4701 behavioral check against MAME's upd4701.cpp:
// reset_xy captures the current origin, and every byte read latches the
// current relative counter rather than reusing the previous low-byte latch.
module tb_upd4701_mame;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;
    reg delta_valid = 1'b0;
    reg signed [8:0] dx = 9'sd0;
    reg signed [8:0] dy = 9'sd0;
    reg cs = 1'b0;
    reg we = 1'b0;
    reg [1:0] addr = 2'd0;
    wire [7:0] rdata;

    s32_upd4701 dut (
        .clk(clk), .rst(rst),
        .delta_valid(delta_valid), .dx(dx), .dy(dy),
        .cs(cs), .we(we), .addr(addr), .rdata(rdata),
        .buttons(8'h00)
    );

    integer errors = 0;

    task automatic apply_delta(input integer x, input integer y);
        begin
            @(negedge clk);
            dx = x;
            dy = y;
            delta_valid = 1'b1;
            @(negedge clk);
            delta_valid = 1'b0;
            dx = 9'sd0;
            dy = 9'sd0;
        end
    endtask

    task automatic read_byte(input [1:0] a, input [7:0] expected);
        begin
            @(negedge clk);
            addr = a;
            cs = 1'b1;
            we = 1'b0;
            @(posedge clk);
            #1;
            if (rdata !== expected) begin
                $display("FAIL: read addr=%0d got=%02x expected=%02x", a, rdata, expected);
                errors = errors + 1;
            end
            @(negedge clk);
            cs = 1'b0;
        end
    endtask

    task automatic reset_origin;
        begin
            @(negedge clk);
            addr = 2'd0;
            cs = 1'b1;
            we = 1'b1;
            @(posedge clk);
            @(negedge clk);
            cs = 1'b0;
            we = 1'b0;
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst = 1'b0;

        // Cross a byte boundary between XL and XH reads. MAME relatches on
        // both reads, so XH must see 0x0100 rather than the old 0x00ff.
        apply_delta(255, 3);
        read_byte(2'd0, 8'hff);
        apply_delta(1, 0);
        read_byte(2'd1, 8'h01);
        read_byte(2'd2, 8'h03);

        // Reset captures the current physical position, then motion is
        // reported relative to that origin and wraps at 12 bits.
        reset_origin();
        apply_delta(2, -1);
        read_byte(2'd0, 8'h02);
        read_byte(2'd1, 8'h00);
        read_byte(2'd2, 8'hff);
        read_byte(2'd3, 8'h0f);

        if (errors != 0)
            $fatal(1, "uPD4701 MAME-equivalence test failed with %0d errors", errors);
        $display("UPD4701 MAME PASS");
        $finish;
    end
endmodule
