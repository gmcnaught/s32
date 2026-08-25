# Verify, against a real Quartus timing netlist, that s32.sdc's V60 exceptions
# say what they are meant to say.
#
# verif/timing/check_v60_ce_premise.py checks the RTL and the SDC agree as TEXT.
# It cannot check that the SDC's get_registers patterns actually MATCH anything
# in a fitted design -- a pattern that matches nothing applies no constraint and
# reports no error, so a carve-out can silently do nothing.  That is what this
# script is for, and it needs a real netlist.
#
# Run under quartus_sta:  quartus_sta -t verif/timing/sdc_check.tcl
#
# Hard failures (these are unambiguous):
#   * v60_regs matches nothing              -> the two-cycle exception is dead
#   * v60_ungated matches nothing           -> the raw-clk_sys carve-out is dead
#   * an ungated register is missing from the carve-out
#
# Reported, not gated: slack.  This revision is documented as NOT YET
# TIMING-CLOSED (see the QSF header), so "timing closes" is the wrong gate.  The
# numbers are printed and written to a summary for human comparison across runs.

package require ::quartus::project
package require ::quartus::sta

set project  "Arcade-SegaSystem32"
set revision "Arcade-SegaSystem32"
set errors 0
set summary_path "output_files/v60_sdc_check.txt"

proc note {msg} { post_message -type info "v60-sdc: $msg" }
proc bad  {msg} {
    global errors
    incr errors
    post_message -type error "v60-sdc: $msg"
}

# quartus_sta may or may not have opened the project already, depending on how
# it was invoked; opening a second time is an error.
if {![is_project_open]} {
    project_open $project -revision $revision
}

# create_timing_netlist defaults to the POST-FIT netlist.  There is no
# -post_fit option -- the only mode flag is -post_map -- and passing one makes
# Quartus 17.0 try to parse it as an operating condition and die with
# "Values entered did not match any valid operating conditions".
create_timing_netlist
read_sdc
update_timing_netlist

# If read_sdc found nothing, every path is unconstrained and every check below
# would pass vacuously.  files.qip registers the SDC
# (set_global_assignment -name SDC_FILE Arcade-SegaSystem32.sdc), so no clocks
# means the constraints did not reach the analyser at all.
set n_clocks [get_collection_size [get_clocks]]
note "SDC defines $n_clocks clock(s)"
if {$n_clocks == 0} {
    bad "no clocks are defined after read_sdc -- the SDC did not reach TimeQuest, so nothing below would mean anything."
}

# ---------------------------------------------------------------------------
# The collections the SDC's exceptions are built from.  Patterns duplicated
# from Arcade-SegaSystem32.sdc deliberately: if someone edits the SDC without
# editing this file the sizes stop agreeing and the check fails, which is the
# point.
# ---------------------------------------------------------------------------
set v60_regs [get_registers -nowarn {*|s32_v60:v60|*}]
set n_v60 [get_collection_size $v60_regs]
note "v60_regs matches $n_v60 register(s)"
if {$n_v60 == 0} {
    bad "get_registers {*|s32_v60:v60|*} matched nothing -- the two-cycle V60 exception is applying to NOTHING. Either the instance name changed or the CPU was optimised away."
}

# The registers that run on the raw clk_sys and must keep a single-cycle
# requirement.  Keep in step with the SDC's foreach list and with the
# `// synthesis-timing: ungated-registers` markers in s32_v60.sv.
set ungated_names {nmi_s1 nmi_s2 nmi_lvl nmi_edge_cnt ext_fb_cnt ext_pv_cnt}
set v60_ungated [get_registers -nowarn "*|s32_v60:v60|[lindex $ungated_names 0]*"]
foreach pat [lrange $ungated_names 1 end] {
    set v60_ungated [add_to_collection $v60_ungated \
        [get_registers -nowarn "*|s32_v60:v60|${pat}*"]]
}
set n_ungated [get_collection_size $v60_ungated]
note "v60_ungated matches $n_ungated register(s)"
if {$n_ungated == 0} {
    bad "the raw-clk_sys carve-out matched nothing at all. Every register that runs on the raw clk_sys is being timed with two clk_sys cycles when it has one."
}

# Per-name expectations, checked in BOTH directions.
#
#   present  the register exists and its carve-out is load-bearing.  If it
#            disappears, either it was renamed (the pattern is now stale and
#            silently constrains nothing) or it was optimised away (and the
#            marker in s32_v60.sv is lying about what runs on the raw clock).
#
#   absent   the register is expected NOT to survive synthesis, for the reason
#            recorded below.  Failing when one of these APPEARS is the point:
#            it means the thing that made it dead has changed, and its
#            single-cycle carve-out just became load-bearing without anyone
#            deciding that.
#
# The four NMI registers are absent because s32_core ties .nmi_n(1'b1) at the
# only instantiation of s32_v60.  ~nmi_n is then a constant, the two-flop
# synchroniser and the level history fold to constants with it, and the edge
# counter can never increment -- so synthesis removes the lot.  The D7 NMI fix
# is real but DORMANT in this design: it starts costing silicon, and starts
# needing its carve-out, the moment anything drives nmi_n.
array set expect_reg {
    nmi_s1        absent
    nmi_s2        absent
    nmi_lvl       absent
    nmi_edge_cnt  absent
    ext_fb_cnt    present
    ext_pv_cnt    present
}

foreach pat $ungated_names {
    set c [get_registers -nowarn "*|s32_v60:v60|${pat}*"]
    set n [get_collection_size $c]
    set want $expect_reg($pat)
    note "  $pat -> $n (expected $want)"
    if {$want eq "present" && $n == 0} {
        bad "no register matches '$pat', but it is expected to exist. Either it was renamed -- in which case the SDC pattern for it now constrains nothing -- or it was optimised away, in which case s32_v60.sv's synthesis-timing marker is wrong."
    }
    if {$want eq "absent" && $n != 0} {
        bad "'$pat' now exists ($n register(s)) but was expected to be optimised away. Something is driving nmi_n. That is fine, but its single-cycle carve-out is now load-bearing rather than dormant: re-read the note above and update this expectation deliberately."
    }
}

# The clk_ram bus adapter (audit S07.3).  Same silent-failure risk as above: if
# this pattern stops matching, the adapter's cross-domain paths silently fall
# back to a single clk_ram period -- half the budget they had on clk_sys.
set v60_bus_regs [get_registers -nowarn {*|s32_v60_bus:vbus|*}]
set n_bus [get_collection_size $v60_bus_regs]
note "v60_bus_regs matches $n_bus register(s)"
if {$n_bus == 0} {
    bad "get_registers {*|s32_v60_bus:vbus|*} matched nothing -- the clk_ram adapter's multicycle exceptions are applying to NOTHING, so its cross-domain paths are being timed at one clk_ram period instead of two."
}

# ---------------------------------------------------------------------------
# Slack, reported not gated.
# ---------------------------------------------------------------------------
proc worst_slack {label paths} {
    if {[get_collection_size $paths] == 0} { return "none" }
    set worst ""
    foreach_in_collection p $paths {
        set s [get_path_info $p -slack]
        if {$worst eq "" || $s < $worst} { set worst $s }
    }
    return $worst
}

# Slack reporting must not be able to abort the run: the collection checks
# above are the actual gate, and losing them to a Tcl error in a diagnostic
# would waste a ~25-minute fit.
set s_all "unavailable"
if {[catch {
    set all_v60 [get_timing_paths -from $v60_regs -to $v60_regs -setup -npaths 200 -nworst 200]
    set s_all [worst_slack "v60 reg2reg" $all_v60]
} err]} {
    note "could not collect V60 register-to-register paths: $err"
}
note "worst setup slack, V60 register-to-register: $s_all"

set s_ung "unavailable"
if {[catch {
    set ung_paths [get_timing_paths -from $v60_ungated -to $v60_regs -setup -npaths 200 -nworst 200]
    set s_ung [worst_slack "ungated-sourced" $ung_paths]
} err]} {
    note "could not collect paths from the raw-clk_sys registers: $err"
}
note "worst setup slack, from the raw-clk_sys registers: $s_ung"
note "NOTE: the carve-out TIGHTENS these paths from two cycles to one. A"
note "      violation appearing here is a previously hidden one surfacing,"
note "      not a regression introduced by the carve-out."

file mkdir output_files
set fh [open $summary_path w]
puts $fh "v60_regs_count $n_v60"
puts $fh "v60_ungated_count $n_ungated"
foreach pat $ungated_names {
    puts $fh "ungated_$pat [get_collection_size [get_registers -nowarn "*|s32_v60:v60|${pat}*"]] expected_$expect_reg($pat)"
}
puts $fh "v60_bus_regs_count $n_bus"
puts $fh "worst_setup_slack_v60_reg2reg $s_all"
puts $fh "worst_setup_slack_from_ungated $s_ung"
puts $fh "errors $errors"
close $fh
note "summary written to $summary_path"

delete_timing_netlist
project_close

if {$errors > 0} {
    post_message -type error "v60-sdc: FAIL ($errors problem(s))"
    qexit -error
}
post_message -type info "v60-sdc: PASS"
qexit -success
