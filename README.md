# labsp_MLP_FPGA

在 Zybo Z7-20 的可编程逻辑（PL）上实现一个多层感知机的前向推理，作为第一次 FPGA 与嵌入式学习项目。

目标流程：电脑参考计算 → 定点量化 → Verilog 仿真 → 综合与实现 → JTAG 上板验证。

## 当前状态
已实现四输入单神经元RTL，并用Vivado 2019.1行为仿真通过42次数值测试及复位/握手检查。尚未实现完整MLP、训练、综合或板上推理。

## 初步范围
- 小型 4 → 8 → 2 网络，隐藏层采用 ReLU。
- 先用固定测试数据验证计算，再训练简单模型。
- 推理计算放在PL，电脑端承担训练与参考计算。
- 工具以已安装的 Vivado 2019.1 为起点，暂不要求SD卡或Linux。

## 学习与协作
先阅读 [协作规则](AGENTS.md)、[阶段计划](docs/plan.md) 和 [进度记录](docs/progress.md)。每次只完成一个小里程碑，讲解相关知识并验证结果，不一口气完成整个工程。

## 目录
- rtl/：Verilog设计
- sim/：仿真与测试向量
- model/：参考模型和权重导出
- constraints/：板卡及时间约束
- scripts/：工程生成与验证脚本
- docs/：计划、笔记和验证记录
- build/：生成工程和缓存（Git忽略）

## 第一步已经可以运行
先阅读 [单神经元学习说明](docs/step1_neuron.md)。

在项目根目录的PowerShell执行 `.\scripts\run_sim.ps1`，成功时输出 `ALL_PASS: 42 numerical cases plus reset/handshake checks`。运行前先关闭本项目已有Vivado工程/波形窗口。

生成工程：`build/neuron_lab/neuron_lab.xpr`。GUI的Run Behavioral Simulation默认停在0ns，添加信号后运行85ns即可观察第一组计算。

完整MLP、量化和上板步骤尚未开始。
