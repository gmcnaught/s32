// Sega System 32 analog-stick positional-gun coordinate adapter.
//
// Jurassic Park accepts the complete 8-bit MSM6253 coordinate range. Alien 3
// does not: hardware testing showed that the sight moves beyond the visible
// border at the host endpoints and disappears. Its calibrated usable envelope
// is 0x08..0xf8. Keep that cabinet-level difference at the host-axis adapter
// instead of compensating in the renderer or altering the shared ADC. GunCon
// SNAC uses its own calibration path and bypasses the endpoint adaptation.
module s32_gun_adc_adapter (
    input             alien3_range,
    input             p1_snac_valid,
    input             p2_snac_valid,
    input       [7:0] p1_snac_x,
    input       [7:0] p1_snac_y,
    input       [7:0] p2_snac_x,
    input       [7:0] p2_snac_y,
    input       [7:0] p1_x_in,
    input       [7:0] p1_y_in,
    input       [7:0] p2_x_in,
    input       [7:0] p2_y_in,
    output      [7:0] p1_x,
    output      [7:0] p1_y,
    output      [7:0] p2_x,
    output      [7:0] p2_y
);

function automatic [7:0] adapt_axis(input [7:0] value);
begin
    if (!alien3_range) adapt_axis = value;
    else if (value < 8'h08) adapt_axis = 8'h08;
    else if (value > 8'hf8) adapt_axis = 8'hf8;
    else adapt_axis = value;
end
endfunction

assign p1_x = p1_snac_valid ? p1_snac_x : adapt_axis(p1_x_in);
assign p1_y = p1_snac_valid ? p1_snac_y : adapt_axis(p1_y_in);
assign p2_x = p2_snac_valid ? p2_snac_x : adapt_axis(p2_x_in);
assign p2_y = p2_snac_valid ? p2_snac_y : adapt_axis(p2_y_in);

endmodule
