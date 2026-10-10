# 控制台输入张量：只运行 RTL 仿真

## 开始

在 PowerShell 运行：

```powershell
cd 'C:\Users\wxg51\Desktop\labsp_MLP_FPGA'
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\mlp_console.ps1
```

看到 `Tensor [1,4]:` 后输入：

```text
[1,2,3,4]
```

实际输出：

```text
RESULT input=[1,2,3,4] output=[-59,-139] cycles=229
```

随后可以继续输入下一组；输入 `q` 退出。每个请求启动一次 XSim，会有几秒的工具启动等待，229 拍表示电路模拟延迟，不是电脑上命令的运行时长。

## 输入规则

一次四个 -128～127 的十进制整数，可用以下任一种写法：

```text
[1,2,3,4]
[[1,2,3,4]]
1,2,3,4
1 2 3 4
```

`[[...]]` 显式表示形状 [1,4]；这里只支持一个样本。三个/五个元素、小数、超出范围的值、表达式都会报错，不送入电路。
输出是形状 [1,2] 的两个有符号 32 位整数，固定随机权重，只推理不训练。

## 单次执行

也可以直接把输入写在命令上，执行一次后退出：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\mlp_console.ps1 -Tensor '[1,2,3,4]'
```

强制重新编译：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\mlp_console.ps1 -Rebuild
```

默认首次编译，以后复用快照。RTL、权重 ROM、测试台或入口脚本内容发生变化时自动重新编译。
一次只打开一个这个交互入口，第二个会提示已有会话占用；退出第一个后再启动。

## 谁在计算

```text
PowerShell 读取四个整数
  → 检查范围、打包成 32 位位串
  → XSim 参数传给 tb_mlp_console.sv
  → 测试台复位并驱动 mlp4.v 的 start 和 x_packed
  → mlp4.v 逐拍完成四层计算
  → 测试台在 done 时读取 y_packed
  → PowerShell 显示仿真器输出
```

入口不调用 Python 参考模型，也不在 PowerShell 中计算网络答案。使用的电路仍是已验证的 rtl/mlp4.v，未复制另一套神经网络实现。
编译使用 Vivado 2019.1 自带的 xvlog、xelab，执行使用 xsim。输入通过 `$value$plusargs` 进入仿真，不修改权重或电路源文件。

## 日志与自检区别

生成文件独立放在 build/mlp_console，不覆盖旧单神经元和四层回归工程。
最近一次结果和执行日志：build/mlp_console/last_console.log、last_simulation.log。下一次输入会覆盖这两份日志。

此入口检查复位、握手、229 拍延迟和输出无未知值，但任意新输入没有附带预期答案，因此展示结果不等于与参考值自动比较通过。
整套数值回归仍用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_mlp_sim.ps1
```

以上全部为电脑上的 RTL 行为仿真；没有通过串口给板子发数据，也没有下载 bitstream。

## 已验证例子

| 输入 | RTL 输出 |
| --- | --- |
| [1,2,3,4] | [-59,-139] |
| [0,0,0,0] | [147,0] |
| [-128,-128,-128,-128] | [11600,-4051] |
| [127,127,127,127] | [-2179,-533] |

这些结果与已有回归数据一致；交互连续输入、q 退出、编译缓存、错误输入拒绝已实际测试。
