# Recreate only the generated project under build/.
set root [file normalize [file join [file dirname [info script]] ..]]
create_project neuron_lab [file join $root build neuron_lab] -part xc7z020clg400-1 -force
set boards [get_board_parts -quiet *zybo-z7-20*]
if {[llength $boards]} {set_property board_part [lindex $boards end] [current_project]}
add_files -norecurse [file join $root rtl neuron4.v]
set_property top neuron4 [get_filesets sources_1]
add_files -fileset sim_1 -norecurse [list [file join $root sim tb_neuron4.sv] [file join $root sim vectors.vh]]
set_property file_type {Verilog Header} [get_files vectors.vh]
set_property include_dirs [list [file join $root sim]] [get_filesets sim_1]
set_property top tb_neuron4 [get_filesets sim_1]
set_property xsim.simulate.runtime {0ns} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
puts "PROJECT_READY: [get_property PART [current_project]]"
