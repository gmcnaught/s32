//============================================================================
//  tb_v60_ce_alignment -- the premise the clk_ram adapter exception rests on.
//
//  s32.sdc grants clk_sys <-> adapter paths two clk_ram cycles, justified by:
//  "every clk_sys edge coincides with an EVEN clk_ram tick, and the adapter's
//  registers only ever launch on its ce_rise, which lands on an even tick for
//  both production divisors (6 ticks = 3 clk_sys, 4 = 2)."
//
//  That is a LOGICAL claim, and nothing checked it.  No simulator can see the
//  timing violation the constraint enables -- an RTL sim is zero-delay, so a
//  path with twice its real budget behaves exactly like a correct one -- but
//  the premise underneath it is ordinary combinational logic, and if the
//  premise is false the constraint is wrong no matter what the fitter does.
//
//  Part 2 is the negative case: an enable that arrives ONE clk_ram tick late,
//  which is what a missed setup requirement on that path produces.  It lands
//  on odd ticks, i.e. halfway through a clk_sys cycle, where the clk_sys
//  memory subsystem the adapter talks to has no edge at all.  The bench proves
//  the delayed enable really does break the alignment, so the property is
//  load-bearing rather than incidentally true.
//============================================================================
`timescale 1ns/1ps

module tb_v60_ce_alignment;

reg clk_ram = 1'b0;
always #5 clk_ram = ~clk_ram;          // 100 MHz stand-in for 96.6 MHz

// clk_sys is exactly clk_ram/2 from the same PLL at phase 0: it toggles on
// every clk_ram rising edge.  Its PRE-edge value is the phase reference -- a
// tick where clk_sys is currently 0 is the one that carries its rising edge.
//
// Read, never written outside this one block, and only through the value every
// other block sees before the non-blocking update lands.  An earlier version
// kept a separate `tick_parity` register and zeroed it with a blocking
// assignment from a task at the same posedge.  That is a race: the two
// simulators scheduled it differently, and Icarus happened to resolve it the
// way the author intended.  Running both is how it was caught -- and note a
// comment line here must not BEGIN with the name of the other simulator, which
// reads it as a pragma and refuses to elaborate.
reg clk_sys = 1'b0;
always @(posedge clk_ram) clk_sys <= ~clk_sys;

reg        rst   = 1'b1;
reg        pause = 1'b0;
reg  [2:0] div   = 3'd6;
wire       ce_rise, ce_fall;
wire [2:0] phase;

s32_v60_timebase tb_dut (
    .clk_ram(clk_ram), .rst(rst), .pause(pause), .div(div),
    .ce_rise(ce_rise), .ce_fall(ce_fall), .phase(phase)
);

// The late enable: one clk_ram tick of delay, the functional shadow of a
// missed setup requirement on timebase -> adapter.
reg ce_rise_late = 1'b0;
always @(posedge clk_ram) ce_rise_late <= ce_rise;

integer errors     = 0;
integer rises      = 0;
integer late_same  = 0;
integer late_opp   = 0;
reg     measuring  = 1'b0;
reg     ref_valid  = 1'b0;
reg     ref_phase  = 1'b0;             // clk_sys phase seen at the first ce_rise

// The property is parity CONSISTENCY, not an absolute phase: with an even
// divisor every ce_rise falls on the same clk_sys phase, whichever one reset
// happened to leave it on.  Checking consistency needs no assumption about the
// reset alignment, so there is nothing to force and nothing to race.
always @(posedge clk_ram) if (measuring) begin
    // PART 1: every ce_rise sees the same clk_sys phase as the first one.
    if (ce_rise) begin
        rises = rises + 1;
        if (!ref_valid) begin
            ref_valid <= 1'b1;
            ref_phase <= clk_sys;
        end
        else if (clk_sys !== ref_phase) begin
            errors = errors + 1;
            $display("FAIL  ce_rise moved to the other clk_sys phase at t=%0t (div=%0d)",
                     $time, div);
        end
    end
    // PART 2: the one-tick-late enable always sees the OPPOSITE phase.
    if (ce_rise_late && ref_valid) begin
        if (clk_sys === ref_phase) late_same = late_same + 1;
        else                       late_opp  = late_opp + 1;
    end
end

task run_divisor(input [2:0] d, input [8*24:1] name);
begin
    measuring = 1'b0;
    div = d;
    rst = 1'b1; @(negedge clk_ram); @(negedge clk_ram);
    rst = 1'b0;
    @(negedge clk_ram);
    rises = 0; late_same = 0; late_opp = 0;
    ref_valid = 1'b0;
    measuring = 1'b1;
    repeat (600) @(posedge clk_ram);
    measuring = 1'b0;
    $display("      %0s div=%0d: %0d ce_rise pulses, all on one clk_sys phase; delayed enable landed %0d opposite / %0d same",
             name, d, rises, late_opp, late_same);
    if (rises == 0) begin
        errors = errors + 1;
        $display("FAIL  %0s produced no ce_rise at all", name);
    end
    // The negative case has to actually fire, or it proves nothing.
    if (late_opp == 0) begin
        errors = errors + 1;
        $display("FAIL  %0s: a one-tick-late enable never changed phase -- the alignment property is not load-bearing here",
                 name);
    end
    if (late_same != 0) begin
        errors = errors + 1;
        $display("FAIL  %0s: the late enable sometimes kept the right phase (%0d times)",
                 name, late_same);
    end
end
endtask

initial begin
    @(negedge clk_ram);
    run_divisor(3'd6, "System 32 / GA2");     // 16.108 MHz, 6 ticks
    run_divisor(3'd4, "Arabian Fight");       // 24.159 MHz, 4 ticks

    if (errors == 0) $display("V60 CE ALIGNMENT PASS");
    else             $display("V60 CE ALIGNMENT FAIL (%0d errors)", errors);
    $finish;
end

initial begin
    #500_000;
    $display("V60 CE ALIGNMENT FAIL (timeout)");
    $finish;
end

endmodule
