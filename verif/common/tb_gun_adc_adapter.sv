// Exhaustive regression for the Alien 3/Jurassic Park ADC range split.
`timescale 1ns/1ps

module tb_gun_adc_adapter;

reg alien3_range;
reg p1_snac_valid, p2_snac_valid;
reg [7:0] p1_x_in, p1_y_in, p2_x_in, p2_y_in;
reg [7:0] p1_snac_x, p1_snac_y, p2_snac_x, p2_snac_y;
wire [7:0] p1_x, p1_y, p2_x, p2_y;
integer value;
integer errors = 0;
integer alien_trace_fd, alien_final_fd, jpark_trace_fd, jpark_final_fd;
reg [1023:0] alien_trace_path, alien_final_path;
reg [1023:0] jpark_trace_path, jpark_final_path;

s32_gun_adc_adapter dut (
    .alien3_range(alien3_range),
    .p1_snac_valid(p1_snac_valid), .p2_snac_valid(p2_snac_valid),
    .p1_snac_x(p1_snac_x), .p1_snac_y(p1_snac_y),
    .p2_snac_x(p2_snac_x), .p2_snac_y(p2_snac_y),
    .p1_x_in(p1_x_in), .p1_y_in(p1_y_in),
    .p2_x_in(p2_x_in), .p2_y_in(p2_y_in),
    .p1_x(p1_x), .p1_y(p1_y), .p2_x(p2_x), .p2_y(p2_y)
);

function automatic [7:0] alien3_expected(input [7:0] sample);
begin
    if (sample < 8'h08) alien3_expected = 8'h08;
    else if (sample > 8'hf8) alien3_expected = 8'hf8;
    else alien3_expected = sample;
end
endfunction

task automatic check(input condition, input [511:0] name);
begin
    if (condition !== 1'b1) begin
        errors = errors + 1;
        $display("FAIL: %0s", name);
    end
end
endtask

task automatic emit_sample(input integer fd, input integer seq,
                           input [7:0] sample);
begin
    p1_x_in = sample;
    #1;
    $fdisplay(fd,
        "{\"domain\":\"adc\",\"seq\":%0d,\"event\":\"input\",\"phase\":\"applied\",\"requested\":%0d,\"data\":%0d}",
        seq, sample, p1_x);
end
endtask

task automatic emit_trace(input integer fd);
begin
    emit_sample(fd, 0, 8'h80);
    emit_sample(fd, 1, 8'h00);
    emit_sample(fd, 2, 8'h01);
    emit_sample(fd, 3, 8'h08);
    emit_sample(fd, 4, 8'hf8);
    emit_sample(fd, 5, 8'hff);
end
endtask

initial begin
    p1_snac_valid = 1'b0;
    p2_snac_valid = 1'b0;
    p1_snac_x = 8'h00; p1_snac_y = 8'h00;
    p2_snac_x = 8'h00; p2_snac_y = 8'h00;
    alien3_range = 1'b0;
    for (value = 0; value < 256; value = value + 1) begin
        p1_x_in = value[7:0];
        p1_y_in = (8'hff - value[7:0]);
        p2_x_in = (value[7:0] ^ 8'h55);
        p2_y_in = (value[7:0] ^ 8'haa);
        #1;
        check(p1_x == p1_x_in && p1_y == p1_y_in &&
              p2_x == p2_x_in && p2_y == p2_y_in,
              "Jurassic Park preserves the full 0x00..0xff range");
    end

    alien3_range = 1'b1;
    for (value = 0; value < 256; value = value + 1) begin
        p1_x_in = value[7:0];
        p1_y_in = (8'hff - value[7:0]);
        p2_x_in = (value[7:0] ^ 8'h55);
        p2_y_in = (value[7:0] ^ 8'haa);
        #1;
        check(p1_x == alien3_expected(p1_x_in) &&
              p1_y == alien3_expected(p1_y_in) &&
              p2_x == alien3_expected(p2_x_in) &&
              p2_y == alien3_expected(p2_y_in),
              "Alien 3 constrains every channel to its calibrated envelope");
    end

    p1_x_in = 8'h00; p1_y_in = 8'h07;
    p2_x_in = 8'hf9; p2_y_in = 8'hff;
    #1;
    check(p1_x == 8'h08 && p1_y == 8'h08 &&
          p2_x == 8'hf8 && p2_y == 8'hf8,
          "old disappearing endpoint fingerprint is absent");
    p1_x_in = 8'h08; p1_y_in = 8'h80;
    p2_x_in = 8'hf8; p2_y_in = 8'h81;
    #1;
    check(p1_x == 8'h08 && p1_y == 8'h80 &&
          p2_x == 8'hf8 && p2_y == 8'h81,
          "interior coordinates and center remain byte exact");

    p1_snac_valid = 1'b1;
    p2_snac_valid = 1'b1;
    p1_snac_x = 8'h00; p1_snac_y = 8'hff;
    p2_snac_x = 8'h01; p2_snac_y = 8'hfe;
    #1;
    check(p1_x == 8'h00 && p1_y == 8'hff &&
          p2_x == 8'h01 && p2_y == 8'hfe,
          "GunCon SNAC bypasses the analog-stick endpoint envelope");
    p1_snac_valid = 1'b0;
    p2_snac_valid = 1'b0;

    if ($value$plusargs("ALIEN_TRACE=%s", alien_trace_path) &&
        $value$plusargs("ALIEN_FINAL=%s", alien_final_path)) begin
        alien3_range = 1'b1;
        alien_trace_fd = $fopen(alien_trace_path, "w");
        alien_final_fd = $fopen(alien_final_path, "w");
        check(alien_trace_fd != 0 && alien_final_fd != 0,
              "Alien 3 trace artifacts open");
        if (alien_trace_fd != 0) begin
            emit_trace(alien_trace_fd);
            $fclose(alien_trace_fd);
        end
        if (alien_final_fd != 0) begin
            $fdisplay(alien_final_fd,
                "{\"schema\":\"mister-trace-finalization-v1\",\"events\":6,\"max_events\":6,\"overflow\":false,\"closed\":true}");
            $fclose(alien_final_fd);
        end
    end

    if ($value$plusargs("JPARK_TRACE=%s", jpark_trace_path) &&
        $value$plusargs("JPARK_FINAL=%s", jpark_final_path)) begin
        alien3_range = 1'b0;
        jpark_trace_fd = $fopen(jpark_trace_path, "w");
        jpark_final_fd = $fopen(jpark_final_path, "w");
        check(jpark_trace_fd != 0 && jpark_final_fd != 0,
              "Jurassic Park trace artifacts open");
        if (jpark_trace_fd != 0) begin
            emit_trace(jpark_trace_fd);
            $fclose(jpark_trace_fd);
        end
        if (jpark_final_fd != 0) begin
            $fdisplay(jpark_final_fd,
                "{\"schema\":\"mister-trace-finalization-v1\",\"events\":6,\"max_events\":6,\"overflow\":false,\"closed\":true}");
            $fclose(jpark_final_fd);
        end
    end

    if (errors == 0)
        $display("GUN ADC ADAPTER PASS");
    else begin
        $display("GUN ADC ADAPTER FAIL: %0d errors", errors);
        $fatal(1);
    end
    $finish;
end

endmodule
