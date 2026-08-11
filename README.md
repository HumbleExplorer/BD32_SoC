# BD32 — RV32IM Pipelined RISC-V SoC

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

BD32 是一款自定义的 32 位 RISC-V (RV32IM) 流水线处理器 SoC，采用经典 5 级流水线架构并配备乱序退休机制（OITF），支持乘法/除法指令与短指令并行执行。项目包含完整的 RTL 设计、仿真验证环境、SDK 工具链和 FPGA 原型验证平台。

## 特性

- RV32IM 指令集（含 M 扩展乘除法）
- 5 级流水线：IF → ID → EX → MEM → WB
- OITF（Out-of-order Instruction Termination Facility）：深度 4 的 FIFO，允许多周期乘除法指令乱序退休
- 流水 Booth-4 乘法器
- 32 周期迭代恢复除法器
- 动态分支预测器 + 返回地址栈（RAS）
- AXI-Lite 总线 + APB 外设子系统
- 外设：CLINT、PLIC 中断控制器、UART（含 NCO 波特率发生器和程序数据下载）、APB Timer（PWM）、GPIO
- CoreMark 验证通过
- RISC-V Debug Module（halt-in-place + 直接端口访问架构）：JTAG 在线调试，支持 halt/resume、单步、reset halt、GPR/CSR 抽象访问、SBA 内存读写（含 8/16/32-bit 写）、硬件断点 Trigger Module（mcontrol type=2）4 路地址匹配（tselect 选择）、ebreak 进调试模式（dcsr.ebreakm）、数据观察点
- 完整调试回归：DMI 一键测试、GDB 全功能套件、真实 demo 符号级在线调试

## 已知限制

| 项目 | 说明 |
|------|------|
| 自修改代码（FENCE.I） | 不支持：FENCE.I 不刷新取指路径，`rv32ui-p-fence_i` 未通过（预期行为） |
| 非对齐访存 | 不支持：不产生 misaligned 异常，`rv32ui-p-ma_data` 未通过（预期行为） |
| Debug ROM / Park Loop | 未实现：采用 halt-in-place + 直接端口访问架构 |
| ProgBuf | 未实现（progbufsize=0），抽象命令不经程序缓冲执行 |
| 抽象内存访问（cmdtype=2） | 未实现：调试器内存访问走 SBA |
| 多 hart | 未实现：单 hart |
| 异常断点（action=0） | 未实现：硬件 trigger 命中仅进 debug mode（action=1），不会产生 breakpoint 异常；软件断点（ebreak 指令）不受影响，走 `dcsr.ebreakm` 通路 |
| 跟踪调试（trace） | 未实现：仅交互式调试（halt/step/断点/观察点） |
| SPI / I2C | 地址预留，未实现 |
| Flash / DDR | AXI 从机未实现，访问返回总线错误 |

## 快速开始

前置：安装 RISC-V 工具链、ModelSim、Python（见 [构建与仿真](doc/build_and_sim.md)「环境依赖与第三方工具」）。

```bash
# 1) 编译固件（hello，产物同步到 test_data/soc/c/）
cd SDK
python tools/build.py demos/newlib/hello --newlib
cd ..

# 2) Debug 模块仿真回归（无需板子，ModelSim）
./script/debug_test/run_msim_debug.bat      # 结果：logs/msim_out.txt

# 3) 核级 ISA 回归（custom_asm）
cd script
python run_all_custom_asm.py
cd ..

# 4) 上板（可选）：UART 下载固件并观察串口输出
python SDK/tools/uart_send.py test_data/soc/c/hello.uartbin --reset
```

## 目录结构

```
./
├── rtl/                      # RTL 源码
│   ├── SoC_Config.sv         # 全局配置（宏定义、内存映射、仿真文件路径）
│   ├── RV32_Inst_Define.sv   # 指令编码定义
│   ├── SoC_top.sv            # SoC 顶层（纯数字 IP）
│   ├── Core/                 # CPU 核
│   ├── Debug/                # 调试模块
│   ├── Bus/                  # AXI-Lite 总线基础设施
│   ├── Periph/               # 外设
│   └── Common/               # 常用基础模块
├── sim/                      # Testbench
├── script/                   # 仿真脚本
│   ├── core_test/            # 核级仿真（filelist.f, run.do）
│   ├── soc_test/             # SoC 级仿真
│   ├── debug_test/           # Debug Module 仿真（run_msim_debug.bat 一键回归）
│   ├── uart_test/ gpio_test/ plic_test/ timer_test/  # 外设独立仿真
│   ├── run_one.py            # 运行单个 custom_asm 测试
│   ├── run_all_custom_asm.py # custom_asm 全回归（36 个测试）
│   └── run_all_riscv_tests.py # riscv-tests 全回归（rv32ui + rv32um）
├── test_data/
│   ├── custom_asm/           # 36 个自定义流水线压力测试（.S + .dat）
│   ├── riscv-tests/          # 标准 riscv-tests .dat（rv32ui 42个 + rv32um 8个；fence_i/ma_data 已知不过）
│   └── soc/c/                # CoreMark 内存文件（.mem）
├── SDK/
│   ├── tools/                # 构建与在线控制工具
│   ├── bsp/                  # 板级支持包（startup, drivers, trap, linker）
│   ├── demos/                # 测试demo
├── BD32_SoC/                  # Vivado FPGA 工程（Xilinx）
└── doc/                       # 文档（架构/调试/外设/验证，见 doc/README.md）
```


## 文档

详细内容已拆分至 `doc/`：

| 文档 | 内容 |
|------|------|
| [架构](doc/architecture.md) | 微架构、流水线、OITF、存储器与总线 |
| [调试模块](doc/debug_module.md) | 调试架构、DMI 位域、Trigger、OpenOCD/GDB 手册、仿真与上板验证 |
| [外设](doc/peripherals.md) | 外设寄存器与编程要点 |
| [验证](doc/verification.md) | 仿真与上板验证方法、回归脚本 |
| [构建与仿真](doc/build_and_sim.md) | 环境依赖、测试构建、仿真运行、CoreMark、Spike 差分测试 |
| [FPGA 原型验证与在线工具](doc/fpga.md) | 上板验证、硬件连接、UART 自动化工具 |
| [SDK 构建工具与协议](doc/sdk.md) | build.py、riscv-tests、MROM、uartbin 协议 |
## 常见问题

**Q: 编译报错 `riscv-none-elf-gcc: command not found`**
检查 xPack 工具链路径是否正确（`build.py` 顶部 `TOOLCHAIN` 配置）。

**Q: ModelSim 找不到 `vsim`**
确认 ModelSim 路径正确（各脚本顶部 `MODELSIM_PATH` 或系统 PATH 配置）。

**Q: 仿真时 ITCM 全 X，CPU 不运行**
确保 vlog 编译时传入 `+define+DIRECT_LOAD`。

**Q: CoreMark 仿真输出不完整**
CoreMark 为 500 次迭代的 performance run，完整 CRC 输出需约几秒仿真时间，若要仿真验证建议将轮数改为1；完整验证请上板运行。

**Q: `--clang` 链接报错找不到 `libclang_rt.builtins.a`**
预期行为。链接阶段一律走 xPack GCC，不要加 `-fuse-ld=lld`。
