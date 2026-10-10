# labsp_MLP_FPGA

在 Zybo Z7-20 的 PL 中实现四层 MLP 推理，面向第一次学习 FPGA 的小项目。

## 当前交付
- 网络：4→8→8→8→2，输入张量 [1,4]，输出张量 [1,2]。
- 前三层 ReLU，末层保留正负数；固定随机权重，只推理、不训练。
- 整数 RTL、Python 整数/浮点参考、参数 ROM、Vivado 2019.1 自检仿真。
- 186 次完整推理、4836 个神经元核对、5 次复位取消全部通过；每次延迟 229 拍。
- 示例输入 [1,2,3,4] → 输出 [-59,-139]。
- 尚未综合、实现、生成 bitstream 或上板；随机权重输出不代表预测能力。

## 控制台自由输入张量

在项目根目录 PowerShell 执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\mlp_console.ps1
```

输入 `[1,2,3,4]` 会调用真实 RTL 仿真并显示 `[-59,-139]`；可连续输入，`q` 退出。只接受四个 -128～127 的整数，不调用 Python 参考程序。
首次编译，源码或权重变化后自动重编译。用 `-Tensor '[1,2,3,4]'` 可单次执行。
详见 [控制台使用说明](docs/console_usage.md)。当前仍为电脑上的行为仿真，尚未上板。

## 开始使用
先读 [四层 MLP 学习说明](docs/step2_mlp.md)，包括位宽、层间存储、状态机、周期数和波形步骤。

在项目根目录 PowerShell 执行（先关闭 mlp4_lab 工程）：

```powershell
.\scripts\run_mlp_sim.ps1
```

工程生成在 `build/mlp4_lab/mlp4_lab.xpr`。成功终止信息：

```text
ALL_PASS: 186 tensors, 4836 neurons, 5 reset aborts, latency 229 cycles
```

在 GUI 打开该工程，Run Behavioral Simulation 后，用 `scripts/add_mlp_waves.tcl` 添加波形，再运行 2400ns 看第一组结果。完整说明见上文链接。

## 目录
- rtl/：神经元与四层 MLP 电路、固定权重 ROM。
- sim/：testbench、输入及预期值。
- model/：参考模型、固定参数 JSON、参考摘要。
- scripts/：创建工程、运行仿真、添加波形。
- docs/：学习说明、计划、进度和真实验证记录。
- constraints/：后续上板约束；本轮尚未添加。
- build/：可重建工程、日志与波形，不纳入 Git。

## 保留的第一步
[单神经元说明](docs/step1_neuron.md) 与 `scripts/run_sim.ps1` 保持独立，可重跑原来的 42 次测试。

## 学习约定
见 [AGENTS.md](AGENTS.md)、[计划](docs/plan.md) 和 [进度](docs/progress.md)。每轮一个小里程碑；下一步先读四层波形，再学习综合，随后另行安排实现与上板。
