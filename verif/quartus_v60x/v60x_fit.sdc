# clk_ram's period: 96.634615 MHz, 10.348 ns (Arcade-SegaSystem32.sdc).  The
# core advances on ce_rise / ce_fall, one V60 clock every six of these, but
# every register is clocked by clk, so the whole design is held to one period
# with no multicycle relief -- the pessimistic reading, on purpose, so the
# number this fit reports is the one that has to close before the s32.sdc
# exceptions are even discussed.
create_clock -name clk -period 10.348 [get_ports clk]
derive_clock_uncertainty

# Reset is a level held for many clocks; the pins are the bench's and the
# board's, sampled at the instants v60_biu names, so they get a full period.
set_false_path -from [get_ports rst]
set_input_delay  -clock clk 0.0 [all_inputs]
set_output_delay -clock clk 0.0 [all_outputs]
