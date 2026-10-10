set root [file normalize [file join [file dirname [info script]] ..]]
set out [file join $root build board]
file mkdir $out
create_project mlp_board [file join $out project] -part xc7z020clg400-1 -force
set boards [get_board_parts -quiet *zybo-z7-20*]
if {[llength $boards]} {set_property board_part [lindex $boards end] [current_project]}
add_files -norecurse [list [file join $root rtl mlp4.v] [file join $root rtl mlp4_weights.vh] \
    [file join $root rtl mlp_jtag_bridge.v] [file join $root rtl mlp_board_top.v]]
set_property file_type {Verilog Header} [get_files mlp4_weights.vh]
set_property include_dirs [list [file join $root rtl]] [get_filesets sources_1]
add_files -fileset constrs_1 -norecurse [file join $root constraints zybo_z7_clock.xdc]
create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name mlp_clock
set_property -dict [list CONFIG.PRIM_IN_FREQ {125.000} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25.000} \
    CONFIG.USE_RESET {false} CONFIG.USE_LOCKED {true}] [get_ips mlp_clock]
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name mlp_vio
set_property -dict [list CONFIG.C_NUM_PROBE_IN {4} CONFIG.C_NUM_PROBE_OUT {3} \
    CONFIG.C_PROBE_IN0_WIDTH {64} CONFIG.C_PROBE_IN1_WIDTH {32} \
    CONFIG.C_PROBE_IN2_WIDTH {32} CONFIG.C_PROBE_IN3_WIDTH {32} \
    CONFIG.C_PROBE_OUT0_WIDTH {32} CONFIG.C_PROBE_OUT1_WIDTH {1} CONFIG.C_PROBE_OUT2_WIDTH {1} \
    CONFIG.C_PROBE_OUT0_INIT_VAL {0x00000000} CONFIG.C_PROBE_OUT1_INIT_VAL {0x0} \
    CONFIG.C_PROBE_OUT2_INIT_VAL {0x1}] [get_ips mlp_vio]
generate_target all [get_ips]
set_property top mlp_board_top [get_filesets sources_1]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {error "Synthesis failed"}
open_run synth_1
report_utilization -file [file join $out utilization_synth.rpt]
close_design
launch_runs impl_1 -to_step route_design -jobs 2
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {error "Implementation failed"}
open_run impl_1
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $out timing.rpt]
report_utilization -file [file join $out utilization.rpt]
report_drc -file [file join $out drc.rpt]
set setup [get_timing_paths -delay_type max -max_paths 1]
set hold [get_timing_paths -delay_type min -max_paths 1]
if {[llength $setup] == 0 || [llength $hold] == 0} {error "Timing paths missing"}
if {[get_property SLACK $setup] < 0 || [get_property SLACK $hold] < 0} {error "Timing failed; do not program"}
set errors [get_drc_violations -quiet -filter {SEVERITY == Error}]
if {[llength $errors]} {error "DRC errors: $errors"}
write_debug_probes -force [file join $out mlp_board.ltx]
write_bitstream -force [file join $out mlp_board.bit]
puts "BOARD_BUILD_PASS setup_slack=[get_property SLACK $setup] hold_slack=[get_property SLACK $hold]"
close_project
