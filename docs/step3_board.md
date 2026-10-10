# 真实 FPGA 推理：使用与原理

## 当前结构

四层网络 `4→8→8→8→2`，前三层 ReLU，末层输出原始有符号值。权重固定随机，保存在 `rtl/mlp4_weights.vh`，不进行训练。

```text
PowerShell 输入四个整数
  → USB JTAG → VIO → 请求控制桥
  → PL 中的 mlp4 四层乘加电路
  → VIO 读取两个结果 → PowerShell 显示
```

VIO 是配置到真实 FPGA 的调试电路，通过 JTAG 访问内部信号。PC 负责传输和显示，乘加与 ReLU 由 PL 执行，不运行 Python、XSim 或 ARM 推理程序。

## 运行命令

```powershell
cd 'C:\Users\wxg51\Desktop\labsp_MLP_FPGA'
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\board_console.ps1
```

输入 `[1,2,3,4]`，得到 `[-59,-139]`；可继续输入，`q` 退出。也支持 `[[1,2,3,4]]`、`1,2,3,4` 或空格分隔。
一次四个 -128～127 的整数；小数、元素个数不符、超范围、表达式都会被拒绝。

单次执行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\board_console.ps1 -Tensor '[1,2,3,4]'
```

## 日志怎么看

控制台显示实际执行阶段，并在每行前显示本次主机请求已用时间：

1. 检查硬件服务、启动 Vivado。
2. 连接 JTAG，确认芯片与 VIO 探针。
3. 确认电路标识 MLP4，复位、写入输入、确认空闲。
4. 触发推理，读取 `busy=0 / done=1 / completed_count=1`。
5. 读回输出，立即打印 `BOARD_RESULT`。
6. 释放 JTAG、等待工具进程退出，显示主机总耗时。

FPGA 计算很快，触发、完成和读回可能显示相同的十分之一秒时间。这些时间表示主机观察，不是逐拍采样。
核心在25MHz下按设计需要229拍（9.16µs），保持完成状态多一拍。控制台的秒级等待主要包含工具启动、JTAG连接、传输与退出。
现有接口没有逐层调试探针，日志不会声称实时观测了某一层的进度。

完整工具输出（包括被控制台省略的信息）保存在：

- `build/board/last_request_console.log`
- `build/board/last_request.log`

每次请求覆盖这些日志。警告和错误会在控制台显示；失败时附带末尾工具输出。出现结果后仍可能需要等待几秒释放工具资源。

## 断电与重新下载

板子供电并连接USB JTAG后：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\program_board.ps1
```

该脚本只下载现有位流并检查设计标识、时钟锁定和空闲状态，不运行批量测试，也不需要sim/或model/目录。
看到 `PROGRAM_READY` 后再启动控制台。本次只配置易失PL，未写Flash，断电或被其他位流覆盖后需要重新下载。
脚本固定匹配JTAG序列号210351B10585A；换板时先核对再修改。

## 修改电路后构建

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\build_board.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\program_board.ps1
```

构建步骤：综合 → 布局布线 → 时序/DRC报告 → bitstream和探针文件。构建成功后才下载；不要在失败后误用残留旧位流。
不计算文件哈希，不自动检测源码变化。构建工程为build/board/project/mlp_board.xpr，重建前关闭该工程。

## 数值、时钟和资源

- 输入int8，权重int8（-3～3），偏置int16（-8～8）；层间/输出int32，乘积/累加40位有符号整数。
- 小数位0，不缩放、舍入或饱和。各层绝对值保守上界：1544、37064、889544、21349064，均在int32范围内。
- 输入时钟引脚K17/LVCMOS33，125MHz；Clocking Wizard生成25MHz。引脚依据[Digilent官方约束](https://github.com/Digilent/digilent-xdc/blob/master/Zybo-Z7-Master.xdc)。
- VIO/JTAG请求较慢，因此控制桥将完成标志保持，主机确认完成次数后读取结果，避免错过单拍done或误读旧结果。
- 本版本已完成真实PL的93组历史数值检查，证据见board_validation.txt。清理后不保留自动测试脚本。
- 最终时序WNS=26.059ns、WHS=0.030ns，全部用户时序约束满足，内部未约束端点为0。
- 含调试接口整体资源1716 LUT、2558寄存器、0 DSP、0 BRAM、1 MMCM。小整数乘法映射为LUT逻辑，仍由PL执行。
- DRC保留两项Warning：RTSTAT-10为生成debug hub的无负载信号，ZPS7-1为未实例化PS7；没有Error。该版本使用独立PL时钟，实际板上验证已通过。

随机权重只验证推理计算过程，不能宣称具备训练模型的分类准确率。当前JTAG接口用于学习和调试，不是吞吐性能基准。
