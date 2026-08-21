# BD32 — RV32IM Pipelined RISC-V SoC

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

BD32 是一款自定义的 32 位 RISC-V (RV32IM) 流水线处理器 SoC，采用经典 5 级流水线架构并配备乱序执行机制（OITF），支持乘法/除法指令与短指令并行执行。项目包含完整的 RTL 设计、仿真验证环境、SDK 工具链和 FPGA 原型验证平台。

## 特性

- RV32IM 指令集（含 M 扩展乘除法）
- 5 级流水线：IF → ID → EX → MEM → WB
- OITF（Out-of-order Instruction Termination Facility）：深度 4 的 FIFO，允许多周期乘除法指令乱序执行
- 流水线型 Booth-4 乘法器
- 32 周期迭代恢复余数除法器
- 基于Gshare的动态分支预测器：GHR+BTB+RAS
- AXI-Lite 总线 + APB 外设子系统
- 外设：CLINT、PLIC 中断控制器、UART（含程序、数据下载功能）、APB Timer（含输入捕获和输出比较功能）、GPIO
- CoreMark 验证通过，跑分达2.8CoreMark/MHz
- 支持自修改代码和非对齐访存
- RT-Thread 移植：v5.1.0 与 lts-v3.1.x（v3.1.5）双版本，`--rtthread` 一键构建（默认 lts-v3.1.x，`--rtthread-version 51` 切 v5.1.0），双线程 demo 已仿真与上板验证，详见 [SDK 构建工具与协议](doc/sdk.md)「RT-Thread 应用开发」
- RISC-V Debug Module（halt-in-place + 直接端口访问架构）：JTAG 在线调试，支持 halt/resume、单步、reset halt、GPR/CSR 抽象访问、SBA 内存读写（含 8/16/32-bit 写）、硬件断点 Trigger Module（mcontrol type=2）4 路地址匹配（tselect 选择）、ebreak 进调试模式（dcsr.ebreakm）、数据观察点
- 完整调试回归：DMI 一键测试、GDB 全功能套件、真实 demo 符号级在线调试
- 代码体积优化：picolibc 精简 C 库 + LLVM LTO/ICF（`--picolibc` / `--lld`），CoreMark 体积减 37%，RT-Thread 两版本均支持 `--picolibc`，详见 [SDK 构建工具与协议](doc/sdk.md)「LLVM/Clang 集成与代码体积优化」

## 已知限制

| 项目 | 说明 |
|------|------|
| Debug ROM / Park Loop | 未实现：采用 halt-in-place + 直接端口访问架构 |
| ProgBuf | 未实现（progbufsize=0），抽象命令不经程序缓冲执行 |
| 抽象内存访问（cmdtype=2） | 未实现：调试器内存访问走 SBA |
| 多 hart | 未实现：单 hart |
| 异常断点（action=0） | 未实现：硬件 trigger 命中仅进 debug mode（action=1），不会产生 breakpoint 异常；软件断点（ebreak 指令）不受影响，走 `dcsr.ebreakm` 通路 |
| 跟踪调试（trace） | 未实现：仅交互式调试（halt/step/断点/观察点） |
| SPI / I2C | 地址预留，未实现 |
| Flash / DDR | AXI 从机未实现，访问返回总线错误 |

## 快速开始

### 1. 环境准备

以下工具用于构建、仿真与调试，**不随源码分发**，各自版权与许可证归其所属项目；请从官方渠道下载对应版本。

| 工具 | 用途 | 版本/路径 | 许可证 | 环境变量 |
|------|------|-----------|--------|----------|
| xPack RISC-V GCC | 固件编译（riscv-none-elf-gcc） | 15.2.0（[xPack riscv-none-elf-gcc Releases](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases)，`<工具链目录>/bin`） | GPL-3.0（工具链） | `RISCV_TOOLCHAIN` |
| LLVM/Clang（可选） | 固件编译（`--clang`） | 22.1.8（[llvm-project Releases](https://github.com/llvm/llvm-project/releases)，`<LLVM 目录>/bin`） | Apache-2.0（工具链） | `LLVM_BIN` |
| ModelSim | RTL 仿真 | SE-64 2020.4（`<安装目录>/win64`） | Siemens EULA | `MODELSIM_PATH` |
| GDB | JTAG 在线调试 | `<工具链目录>/bin/riscv-none-elf-gdb`（随 xPack GCC） | GPL-3.0（工具链） | `RISCV_GDB` |
| OpenOCD | JTAG 在线调试（xPack 发行版） | 0.12.0（`third_party/xpack-openocd-0.12.0-7/bin`，从 [xPack OpenOCD Releases](https://github.com/xpack-dev-tools/openocd-xpack/releases) 下载 win32-x64 包解压） | GPL-2.0 | `OPENOCD`（fpga_reset.py） |
| Xilinx Vivado | FPGA 综合/实现/烧录 | 2023.1 | Xilinx EULA（WebPACK 免费版可用） | — |
| Python | 脚本/自动化 | 3.x | PSF License | — |
| riscv-tests 源码 | ISA 兼容性测试用例（rv32ui / rv32um / rv64ui） | `third_party/riscv-tests`（clone 官方仓库 [riscv/riscv-tests](https://github.com/riscv/riscv-tests)） | BSD-3-Clause | `RISCV_TESTS_SRC` |
| picolibc 源码（可选） | 精简 C 库（`--picolibc`，程序体积更小） | 1.8.12（`third_party/picolibc-1.8.12`，从 [picolibc Releases](https://github.com/picolibc/picolibc/releases) 下载源码包；由 `SDK/tools/build_picolibc.bat` 构建到 `third_party/picolibc-install`） | BSD-3-Clause | `PICOLIBC_ROOT` |
| RT-Thread 5.1.0 源码 | RTOS 内核（`--rtthread --rtthread-version 51`） | `third_party/rt-thread-5.1.0`（从官方 [Releases](https://github.com/RT-Thread/rt-thread/releases) 下载源码包解压） | Apache-2.0 | — |
| RT-Thread 3.1.5 源码 | RTOS 内核（`--rtthread` 默认） | `third_party/rt-thread-3.1.5`（同上，v3.1.5） | Apache-2.0 | — |

目标架构：`-march=rv32im_zicsr -mabi=ilp32`；C 库默认使用 **newlib-nano**（`-specs=nano.specs` 精简版，`printf`/`malloc` 可用），可选 **picolibc**（`--picolibc`，整数程序体积更小，用法见 [SDK 构建工具与协议](doc/sdk.md)「picolibc」）。工具路径未设置时使用各脚本内的默认值。

- **第三方源码**（统一放在 `third_party/`，不随仓库分发）：

  ```bash
  mkdir third_party && cd third_party
  git clone https://github.com/riscv/riscv-tests.git       # ISA 测试源码
  # RT-Thread：从官方 Releases 下载源码包解压到 third_party/，目录名保持 rt-thread-<版本>：
  #   https://github.com/RT-Thread/rt-thread/releases
  # 版本选择（长期维护分支 lts-v3.1.x / 最新版）见官方文档：
  #   https://www.rt-thread.org/document/site/#/rt-thread-version/rt-thread-standard/application-note/setup/rt-thread-version/an0030-rtthread-version
  # v5.1.0 → rt-thread-5.1.0（--rtthread --rtthread-version 51 构建用）
  # v3.1.5 → rt-thread-3.1.5（--rtthread 默认构建）
  # OpenOCD（在线调试用）：从 https://github.com/xpack-dev-tools/openocd-xpack/releases
  # 下载 xpack-openocd-0.12.0-7-win32-x64.zip，解压到 third_party/
  # picolibc（可选，代码体积优化）：从 https://github.com/picolibc/picolibc/releases
  # 下载 1.8.12 源码包解压到 third_party/picolibc-1.8.12，
  # 然后运行 SDK/tools/build_picolibc.bat [i|f|d] 构建（i=整数/ f=浮点/ d=double printf 档）
  cd ..
  ```

### 2. 构建、上板与仿真

```bash
# 1) 核级 ISA 回归（custom_asm）
cd script
python run_all_custom_asm.py               # custom_asm 全回归
python run_all_riscv_tests.py              # riscv-tests ISA 兼容性
cd ..

# 2) 一键构建 + 上板运行（构建 → 复位 → 下载 → 监听，板子需已连接）
cd SDK
python tools/build_run.py demos/newlib/hello --newlib --idle-timeout 3     # hello（newlib-nano）
python tools/build_run.py demos/rtthread --rtthread --idle-timeout 3       # RT-Thread（默认 lts-v3.1.x）
python tools/build_run.py demos/rtthread51 --rtthread --rtthread-version 51 --idle-timeout 3  # v5.1.0
cd ..
```

> 提示：`test_data/` 下的 `.dat` / `.elf` / `.dump` 均由构建脚本生成。

## RT-Thread 与 picolibc

RT-Thread 双版本移植（lts-v3.1.x / v5.1.0）的版本目录、中断模式、构建/仿真/上板命令与 picolibc 适配详见 [SDK 构建工具与协议](doc/sdk.md)「RT-Thread 应用开发」；仿真与上板验证矩阵见 [验证手册](doc/verification.md)。

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
├── tb/                       # Testbench
├── script/                   # 仿真脚本
│   ├── core_test/            # 核级仿真（filelist.f, run.do）
│   ├── soc_test/             # SoC 级仿真
│   ├── debug_test/           # Debug Module 仿真（run_msim_debug.bat 一键回归）
│   ├── uart_test/ gpio_test/ plic_test/ timer_test/  # 外设独立仿真
│   ├── run_one.py            # 运行单个 custom_asm 测试
│   ├── run_all_custom_asm.py # custom_asm 全回归（38 个测试）
│   └── run_all_riscv_tests.py # riscv-tests 全回归（rv32ui + rv32um）
├── test_data/
│   ├── custom_asm/           # 38 个自定义流水线压力测试源码（.S；.dat/.elf/.dump 由 build_asm.py 生成）
│   ├── riscv-tests/          # riscv-tests 测试产物（rv32ui 42 + rv32um 8 全过；源码来自官方 riscv-tests 仓库，见 doc/sdk.md）
│   └── soc/c/                # 固件构建产物（.uartbin / .mem，由 build.py 同步）
├── third_party/              # 第三方源码依赖（riscv-tests、rt-thread-3.1.5 / rt-thread-5.1.0、picolibc-1.8.12、OpenOCD，不随仓库分发）
├── SDK/
│   ├── tools/                # 构建与在线控制工具
│   ├── isa/                  # 测试环境（env 随仓库提交；rv32ui 等源码由脚本从 third_party 同步）
│   ├── bsp/                  # 板级支持包（startup, drivers, trap, linker）
│   ├── demos/                # 测试demo（含 RT-Thread demo：rtthread / rtthread51）
├── BD32_SoC/                  # Vivado FPGA 工程（Xilinx）
└── doc/                       # 文档（架构/调试/外设/验证，索引见 README「文档」表）
```


## 文档

详细内容已拆分至 `doc/`：

| 文档 | 内容 |
|------|------|
| [架构](doc/architecture.md) | 微架构、流水线、OITF、存储器与总线 |
| [调试模块](doc/debug_module.md) | 调试架构、DMI 位域、Trigger、OpenOCD/GDB 手册、仿真与上板验证 |
| [外设](doc/peripherals.md) | 外设寄存器与编程要点 |
| [验证](doc/verification.md) | 环境依赖、构建、仿真与上板验证、回归脚本、CoreMark、Spike 差分测试 |
| [SDK 构建工具与协议](doc/sdk.md) | build.py、riscv-tests、MROM、uartbin 协议、代码体积优化（LLD/picolibc）、CoreMark 自动对比、RT-Thread 应用开发 |

## TODO_LIST

> 后续计划（ISA 扩展、RTOS、SoC 外设、工程化）。

- [x] **FENCE.I / 自修改代码**：已实现（ITCM 字节写使能 + FENCE.I 冲刷取指路径），`rv32ui-p-fence_i` 通过
- [x] **非对齐访存**：已实现（DTCM/总线内存拆分为两次对齐访问），`rv32ui-p-ma_data` 通过
- [ ] **RV32C：C 压缩指令扩展**（取指 2/4 字节对齐 + 译码改造，代码体积大幅减小）
- [ ] **RV32A：A 原子扩展**（LR/SC + AMO，为 RTOS/多核同步铺路）
- [ ] **RV32F / D：F/D 浮点扩展**（FPU 数据通路 + ABI 切换）
- [x] **RT-Thread 移植**：v5.1.0 与 lts-v3.1.x 双版本（仅 M-mode，无 U-mode / MPU / SMP）
- [ ] **SPI / QSPI Flash 启动**：片外 Flash 引导
- [ ] **总线取指（XIP）**：支持经 AXI 总线从 Flash/DDR 取指执行，而非仅从 ITCM 取指
- [ ] **DMA 控制器**：UART/SPI 等外设内存搬运
- [ ] **自定义指令**：AI加速器或加解密协处理器
- [ ] **SV 工程化重构**：package 、interface、SVA等高级语法特性
- [ ] **SDK 完善**：构建脚本、驱动分层、demo 库、文档
- [ ] **其他外设**：I2C / WDT / RTC / PMU……
- [ ] **详细PDF设计文档**：正在写……

## 常见问题

**Q: 编译报错 `riscv-none-elf-gcc: command not found`**
检查 xPack 工具链路径是否正确（`build.py` 顶部 `TOOLCHAIN` 配置）。

**Q: ModelSim 找不到 `vsim`**
确认 ModelSim 路径正确（各脚本顶部 `MODELSIM_PATH` 或系统 PATH 配置）。

**Q: 仿真时 ITCM 全 X，CPU 不运行**
确保 vlog 编译时传入 `+define+DIRECT_LOAD`。

**Q: 构建报错 "picolibc 未构建"**
先运行 `SDK/tools/build_picolibc.bat`（默认整数 printf 档；`f`/`d` 分别为浮点/double 档）构建 picolibc，或用环境变量 `PICOLIBC_ROOT` 指向已安装目录。

**Q: CoreMark 仿真输出不完整**
CoreMark 为 500 次迭代的 performance run，完整 CRC 输出需约几秒仿真时间，若要仿真验证建议将轮数改为1；完整验证请上板运行。

**Q: `--clang` 链接报错找不到 `libclang_rt.builtins.a`**
预期行为。链接阶段一律走 xPack GCC，不要加 `-fuse-ld=lld`。
