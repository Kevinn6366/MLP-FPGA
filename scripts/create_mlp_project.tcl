set root [file normalize [file join [file dirname [info script]] ..]]
create_project mlp4_lab [file join $root build mlp4_lab] -part xc7z020clg400-1 -force
set boards [get_board_parts -quiet *zybo-z7-20*]
if {[llength $boards]} {set_property board_part [lindex $boards end] [current_project]}
add_files -norecurse [list [file join $root rtl mlp4.v] [file join $root rtl mlp4_weights.vh]]
set_property file_type {Verilog Header} [get_files mlp4_weights.vh]
set_property include_dirs [list [file join $root rtl]] [get_filesets sources_1]
set_property top mlp4 [get_filesets sources_1]
add_files -fileset sim_1 -norecurse [list [file join $root sim tb_mlp4.sv] [file join $root sim mlp4_vectors.vh]]
set_property file_type {Verilog Header} [get_files mlp4_vectors.vh]
set_property include_dirs [list [file join $root sim] [file join $root rtl]] [get_filesets sim_1]
set_property top tb_mlp4 [get_filesets sim_1]
set_property xsim.simulate.runtime {0ns} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "MLP_PROJECT_READY: [get_property PART [current_project]]"
