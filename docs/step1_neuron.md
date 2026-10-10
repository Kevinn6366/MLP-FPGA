# 第一步 单神经元与行为仿真

## 本次做到哪里
实现 y = ReLU(b + x0*w0 + x1*w1 + x2*w2 + x3*w3)。这是完整MLP中的一个计算单元，还不是多层网络。

本阶段只有电脑行为仿真，没有综合、布局布线、生成bitstream或上板。无需连接板子，也不需要XDC引脚约束。

## 先看哪些文件
1. rtl/neuron4.v：准备配置到PL的硬件描述。
2. sim/tb_neuron4.sv：只用于电脑测试，产生时钟、输入并检查结果，不会下载到板子。
3. model/neuron_reference.py：Python整数参考计算，生成可复现的测试向量。
4. sim/vectors.vh：生成并纳入Git的41组测试，另有1组复位后重启检查。

## 本阶段数值格式
所有数值均为有符号整数，小数位为0；没有量化、缩放、舍入或饱和处理。真实网络的定点格式后续确定。

| 数值 | 位宽 | 说明 |
| --- | --- | --- |
| 每项输入及权重 | 8位 | -128至127 |
| 单项乘积 | 16位 | 精确保存8位有符号乘法结果 |
| 偏置 | 16位 | -32768至32767 |
| 累加器及输出 | 18位 | 覆盖完整四项累加，避免溢出 |

四项加偏置的范围为-97792至98303，18位有符号数足够。ReLU只将负数改成0，不改变非负值。

x_packed和w_packed各有32位，打包四个8位数。最低8位是第0项。例如输入[1,2,3,4]打包为32'h04030201。权重中的-1用8位补码FF表示。

## 时钟与接口约定
- reset：高有效同步复位，在时钟上升沿生效，清除输出并取消未完成计算。
- start：在空闲时被上升沿采样为1，开始一次计算。调用方应发送一个周期的脉冲。
- 开始时锁存输入、权重和偏置；之后外部数据变化不影响本次计算。
- busy为1时忽略新的start，不排队。
- done：结果更新时拉高一个周期，此时busy变为0，y有效。
- y：保存上一次完成结果，直到下次完成或复位。
- 持续把start保持为1，会在返回空闲后再次启动；因此它不是“只认上升沿”的输入。

## 教学例子的波形
输入[1,2,3,4]，权重[2,-1,1,0]，偏置1。

| 仿真时刻 | 动作 | acc | done | y |
| --- | --- | --- | --- | --- |
| 25ns | 接受start，锁存数据和偏置 | 1 | 0 | 0 |
| 35ns | 第0项乘加 | 3 | 0 | 0 |
| 45ns | 第1项乘加 | 1 | 0 | 0 |
| 55ns | 第2项乘加 | 4 | 0 | 0 |
| 65ns | 第3项乘加 | 4 | 0 | 0 |
| 75ns | 输出ReLU结果 | 4 | 1 | 4 |
| 85ns | 回到空闲，done恢复0 | 4 | 0 | 4 |

从接受请求的上升沿到结果有效，相隔5个时钟周期。testbench时钟周期为10ns，因此仿真中相隔50ns；这不是实际硬件达到100MHz的证明。

测试会故意在busy期间改动输入并再次拉高start，用来证明输入已锁存且重复请求被忽略。它不是操作失误。

## 三个状态与代码对应
- IDLE（0）：等start，并初始化acc。
- MAC（1）：复用一套乘加表达式，通过index依次选择四组输入。
- OUTPUT_RESULT（2）：将最终acc送入ReLU，并产生done。

always @(posedge clk)描述在上升沿更新的寄存器。非阻塞赋值“<=”使同一上升沿的计算基于更新前的值。

因此必须等最后一次乘加写回acc之后，再到OUTPUT_RESULT输出；若直接在最后一次MAC中使用旧acc输出，就会漏掉最后一项。

源代码仅有一个乘法表达式，是否映射为DSP、资源数量和可达到的频率需要后续综合与实现确认。

## 如何在Vivado查看
本阶段已生成 build/neuron_lab/neuron_lab.xpr，可用Vivado 2019.1打开。

- Sources → Design Sources：neuron4.v。
- Sources → Simulation Sources：tb_neuron4.sv。
- Run Simulation → Run Behavioral Simulation：启动行为仿真。工程默认停在0ns，便于添加信号。
- Scope中展开tb_neuron4/dut，观察acc、index、state。
- Wave窗口观察clk、reset、start、busy、acc、done、y。对有符号数选择Signed Decimal。
- 在Vivado Tcl Console执行 run 85ns，观察第一组计算；新开仿真后执行run all可跑全部测试。

scripts/view_wave.tcl可直接打开已完成测试的WDB波形，不重新运行测试。

## 如何重复验证
在项目根目录的PowerShell执行：

```powershell
.\scripts\run_sim.ps1
```

脚本只重建build目录中的生成工程。不要在另一个Vivado窗口仍打开该工程或WDB时运行；先关闭该工程及波形窗口。源码不放在build内。

成功标志为 ALL_PASS: 42 numerical cases plus reset/handshake checks。

更新Python参考后，可用Python3运行model/neuron_reference.py重新生成vectors.vh。现有测试向量已提交，常规仿真不需要先安装Python。

## 验证覆盖与限度
- 正负输入、零、正负偏置、上下界、正负抵消、32组固定种子随机向量。
- 每一次乘加的中间结果、最终ReLU、固定延迟、输出保持及done单周期。
- busy期间重复start、输入变化、计算中复位、复位优先及复位后重新启动。
- 这是有限测试集，不是形式化证明。未检查引脚、电气连接、硬件资源和真实时序。

## 本步学完应能回答
1. 为什么acc需要18位，而输入只有8位？
2. 为什么最后一次MAC之后还有一个输出状态？
3. testbench与要下载到PL的RTL有什么区别？

下一步先读第一组波形，再改一组输入预测结果；暂不自动扩展完整MLP。
