# Inspect the saved regression waveform without rerunning tests.
set root [file normalize [file join [file dirname [info script]] ..]]
open_project [file join $root build neuron_lab neuron_lab.xpr]
open_wave_database [file join $root build neuron_lab neuron_lab.sim sim_1 behav xsim tb_neuron4_behav.wdb]
add_wave /tb_neuron4/clk
add_wave /tb_neuron4/reset
add_wave /tb_neuron4/start
add_wave /tb_neuron4/busy
add_wave /tb_neuron4/dut/state
add_wave /tb_neuron4/dut/index
add_wave -radix dec /tb_neuron4/dut/product
add_wave -radix dec /tb_neuron4/dut/acc
add_wave /tb_neuron4/done
add_wave -radix dec /tb_neuron4/y
