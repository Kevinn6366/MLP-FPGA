source [file join [file dirname [info script]] create_mlp_project.tcl]
set result [file join $root build mlp4_lab mlp4_lab.sim sim_1 behav xsim mlp4_result.txt]
if {[file exists $result]} {file delete $result}
launch_simulation -simset sim_1 -mode behavioral
log_wave -r /tb_mlp4/*
run all
if {![file exists $result]} {error "MLP self-check produced no success marker"}
set f [open $result r]
set result_text [string trim [read $f]]
close $f
if {$result_text ne "ALL_PASS: 186 tensors, 4836 neurons, 5 reset aborts, latency 229 cycles"} {
    error "Unexpected MLP result: $result_text"
}
puts $result_text
close_sim
close_project
