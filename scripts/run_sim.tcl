source [file join [file dirname [info script]] create_project.tcl]
set result [file join $root build neuron_lab neuron_lab.sim sim_1 behav xsim simulation_result.txt]
# Remove only a stale success marker in this generated simulation directory.
if {[file exists $result]} {file delete $result}
launch_simulation -simset sim_1 -mode behavioral
log_wave -r /tb_neuron4/*
run all
if {![file exists $result]} {error "Self-check did not produce a success marker; inspect simulation log"}
set f [open $result r]
set result_text [string trim [read $f]]
close $f
if {$result_text ne "ALL_PASS: 42 numerical cases plus reset/handshake checks"} {error "Unexpected result: $result_text"}
puts $result_text
close_sim
close_project
