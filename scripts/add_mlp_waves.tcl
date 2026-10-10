# Run inside an active tb_mlp4 simulation before running time forward.
add_wave /tb_mlp4/clk /tb_mlp4/reset /tb_mlp4/start /tb_mlp4/busy /tb_mlp4/done
add_wave -radix hex /tb_mlp4/x_packed /tb_mlp4/y_packed
add_wave -radix unsigned /tb_mlp4/dut/state /tb_mlp4/dut/layer /tb_mlp4/dut/neuron /tb_mlp4/dut/input_index
add_wave -radix dec /tb_mlp4/dut/operand /tb_mlp4/dut/weight_value /tb_mlp4/dut/bias_value
add_wave -radix dec /tb_mlp4/dut/product /tb_mlp4/dut/acc /tb_mlp4/dut/neuron_value
add_wave -radix dec /tb_mlp4/dut/bank_a /tb_mlp4/dut/bank_b
