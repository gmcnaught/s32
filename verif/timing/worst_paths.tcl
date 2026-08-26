# Report the worst setup AND hold paths per clock domain, with endpoints.
#
# quartus_sta's default output is a summary: it says clk_ram misses by 0.546 ns
# and nothing about WHERE.  That is enough to know there is a problem and not
# enough to fix one, and re-running a 40-minute fit to learn the same thing
# twice is the expensive way to find out.
#
# Hold was the half this script did not cover, and hold is what has actually
# been rejecting bitstreams: PR #14 fails at all four corners on clk_ram, worst
# -0.304 / TNS -0.601, and the summary names the DOMAIN and nothing else.  A
# hold violation is data racing the clock -- it does not improve at a slower
# clock and it fails at every corner -- so the fix is always a specific path,
# and finding it must not cost another fit.
#
# The hold pass runs at the timing netlist's default corner.  That is where the
# worst hold currently is (Slow 100C, -0.304), but it is one corner: the gate
# in verif/timing/check_timing_gate.py is what reads all four, and a corner
# this pass calls clean can still be fatal there.
#
# Run under quartus_sta:  quartus_sta -t verif/timing/worst_paths.tcl
package require ::quartus::project
package require ::quartus::sta

set project  "Arcade-SegaSystem32"
set revision "Arcade-SegaSystem32"
set NPATHS 8

if {![is_project_open]} { project_open $project -revision $revision }
create_timing_netlist
read_sdc
update_timing_netlist

proc short {n} {
    # Strip the leading hierarchy that every node shares, so the interesting
    # part of the name is not pushed off the line.
    set s [string map {"emu:emu|s32_core:core|" "" "emu:emu|" ""} $n]
    if {[string length $s] > 88} { set s "...[string range $s end-85 end]" }
    return $s
}

set out "output_files/worst_paths.txt"
file mkdir output_files
set fh [open $out w]

# One pass over every clock domain for one check type.  clean_bar is the slack
# above which a domain is summarised in a line instead of listed path by path,
# and it differs by an order of magnitude between the two: setup slacks here
# run to tens of nanoseconds, hold slacks live in tenths.
proc report {fh kind clean_bar} {
    global NPATHS
    foreach_in_collection ck [get_clocks] {
        set name  [get_clock_info $ck -name]
        set paths [get_timing_paths -to_clock $ck $kind -npaths $NPATHS -nworst $NPATHS]
        if {[get_collection_size $paths] == 0} { continue }
        set worst ""
        foreach_in_collection p $paths {
            set s [get_path_info $p -slack]
            if {$worst eq "" || $s < $worst} { set worst $s }
        }
        if {$worst > $clean_bar} {
            puts $fh [format "%-58s worst %+8.3f  (clean)" $name $worst]
            continue
        }
        puts $fh ""
        puts $fh [format "=== %s   worst %+8.3f ===" $name $worst]
        set n 0
        foreach_in_collection p $paths {
            incr n
            set s  [get_path_info $p -slack]
            set fr [get_node_info [get_path_info $p -from] -name]
            set to [get_node_info [get_path_info $p -to] -name]
            puts $fh [format "  %+8.3f  from %s" $s [short $fr]]
            puts $fh [format "            to   %s" [short $to]]
            if {$n >= $NPATHS} break
        }
    }
}

puts $fh "=============================== SETUP ==============================="
report $fh -setup 2.0

puts $fh ""
puts $fh "================================ HOLD ================================"
puts $fh "(default corner only -- check_timing_gate.py reads all four)"
report $fh -hold 0.5

close $fh
post_message -type info "worst-path report written to $out"

set fh [open $out r]
puts [read $fh]
close $fh

delete_timing_netlist
project_close
qexit -success
