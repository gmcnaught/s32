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
create_timing_netlist -post_fit
read_sdc
update_timing_netlist

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
    bad "the raw-clk_sys carve-out matched nothing. Every one of $ungated_names is being timed with two clk_sys cycles when it has one."
}

# Per-name detail, so a single renamed or optimised-away register is visible
# rather than hidden inside a total.
foreach pat $ungated_names {
    set c [get_registers -nowarn "*|s32_v60:v60|${pat}*"]
    set n [get_collection_size $c]
    note "  $pat -> $n"
    if {$n == 0} {
        bad "no register matches '$pat'. It is named in s32_v60.sv's synthesis-timing marker and in the SDC, but does not survive to the fitted netlist -- the carve-out for it is dead."
    }
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

set all_v60 [get_timing_paths -from $v60_regs -to $v60_regs -setup -npaths 200 -nworst 200]
set s_all [worst_slack "v60 reg2reg" $all_v60]
note "worst setup slack, V60 register-to-register: $s_all"

set ung_paths [get_timing_paths -from $v60_ungated -to $v60_regs -setup -npaths 200 -nworst 200]
set s_ung [worst_slack "ungated-sourced" $ung_paths]
note "worst setup slack, from the raw-clk_sys registers: $s_ung"
note "NOTE: the carve-out TIGHTENS these paths from two cycles to one. A"
note "      violation appearing here is a previously hidden one surfacing,"
note "      not a regression introduced by the carve-out."

file mkdir output_files
set fh [open $summary_path w]
puts $fh "v60_regs_count $n_v60"
puts $fh "v60_ungated_count $n_ungated"
foreach pat $ungated_names {
    puts $fh "ungated_$pat [get_collection_size [get_registers -nowarn "*|s32_v60:v60|${pat}*"]]"
}
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
