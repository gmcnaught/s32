# Run verif/timing/worst_paths.tcl against stubbed Quartus commands.
#
#   tclsh verif/timing/test_worst_paths.tcl
#
# Why this exists: every Tcl mistake in this tree so far has been discovered
# 25 to 50 minutes into a Quartus run, because the script only ever executes
# there.  A wrong argument name, a proc that cannot see a global, a collection
# iterated the wrong way -- all of them are ordinary Tcl errors that a stub
# harness catches in under a second.
#
# The stubs model shape, not timing: two clocks, one clean and one violating,
# with distinct setup and hold slacks so the report cannot pass by printing the
# same numbers twice.
package provide quartus 1.0

proc is_project_open {} { return 0 }
proc project_open {args} {}
proc create_timing_netlist {args} {}
proc read_sdc {args} {}
proc update_timing_netlist {args} {}
proc delete_timing_netlist {args} {}
proc project_close {args} {}
proc post_message {args} {}
proc qexit {args} {}

# Collections are plain lists here.
proc get_clocks {} { return {clk_clean clk_tight} }
proc get_clock_info {ck args} { return $ck }
proc get_collection_size {c} { return [llength $c] }
proc foreach_in_collection {var coll body} {
    upvar 1 $var v
    foreach v $coll { uplevel 1 $body }
}

# path = {slack from to}
proc get_timing_paths {args} {
    set to_clock ""
    set kind "-setup"
    foreach {a b} $args {
        if {$a eq "-to_clock"} { set to_clock $b }
        if {$a eq "-setup" || $a eq "-hold"} { set kind $a }
    }
    # -setup/-hold arrive as a bare flag, so the pairwise walk above can miss
    # them; scan the flat list too.
    if {[lsearch -exact $args "-hold"] >= 0} { set kind "-hold" }
    if {$to_clock eq "clk_clean"} {
        if {$kind eq "-hold"} { return {{0.900 a_reg b_reg}} }
        return {{9.500 a_reg b_reg}}
    }
    if {$kind eq "-hold"} {
        return {{-0.304 emu:emu|s32_core:core|sprite|pixel_scrx[3] emu:emu|s32_core:core|sprite|indtab_rtl_0_bypass[8]}
                {-0.297 emu:emu|x_reg emu:emu|y_reg}}
    }
    return {{0.202 emu:emu|s32_core:core|lay0 emu:emu|s32_core:core|Mult1}
            {0.410 emu:emu|p_reg emu:emu|q_reg}}
}
proc get_path_info {p flag} {
    switch -- $flag {
        -slack { return [lindex $p 0] }
        -from  { return [lindex $p 1] }
        -to    { return [lindex $p 2] }
    }
}
proc get_node_info {n flag} { return $n }
proc package {args} {}

set ::argv0_dir [file dirname [file normalize [info script]]]
source [file join $::argv0_dir worst_paths.tcl]

# ---------------------------------------------------------------------------
set report [read [set f [open "output_files/worst_paths.txt" r]]]
close $f
file delete -force output_files/worst_paths.txt

set fails 0
proc want {report needle why} {
    if {[string first $needle $report] < 0} {
        puts "FAIL  $why -- expected to find: $needle"
        incr ::fails
    }
}

want $report "SETUP"                      "the setup section is labelled"
want $report "HOLD"                       "the hold section is labelled"
want $report "clk_clean"                  "a clean domain is still reported"
want $report "(clean)"                    "a clean domain is summarised, not listed"
want $report "=== clk_tight   worst   +0.202 ===" "the tight setup domain is listed with its worst slack"
want $report "=== clk_tight   worst   -0.304 ===" "the violating HOLD domain is listed with its worst slack"
want $report "indtab_rtl_0_bypass\[8\]"   "the failing hold endpoint is named"
want $report "sprite|pixel_scrx\[3\]"     "the failing hold startpoint is named"

# The hold pass must not silently re-report the setup numbers, which is what a
# copy-paste of the setup loop would do.
if {[string first "-0.304" $report] < [string first "HOLD" $report]} {
    puts "FAIL  the hold slack appears before the HOLD heading -- the sections are crossed"
    incr fails
}

if {$fails == 0} {
    puts "WORST-PATHS SELFTEST PASS"
    exit 0
}
puts "WORST-PATHS SELFTEST FAIL ($fails)"
exit 1
