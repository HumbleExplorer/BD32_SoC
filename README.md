# BD32 RISC-V SoC 构建与仿真脚本

> 路径：`Working/script/`（仿真脚本） + `Working/SDK/tools/`（构建工具）
>
> 环境：Windows 10/11，ModelSim SE-64，Python 3，RISC-V GCC 工具链

---

## 目录

- [1. 依赖与环境](#1-依赖与环境)
- [2. SDK 构建工具（SDK/tools/）](#2-sdk-构建工具sdktools)
  - [2.1 build.py — 主构建脚本](#21-buildpy--主构建脚本)
  - [2.2 build_riscv_tests.py — RISC-V 兼容性测试编译](#22-build_riscv_testspy--risc-v-兼容性测试编译)
  - [2.3 LLVM/Clang 集成（--clang）](#23-llvmclang-集成clang)
- [3. MROM 构建](#3-mrom-构建)
- [4. 仿真脚本（script/）](#4-仿真脚本script)
  - [4.1 各测试子目录一览](#41-各测试子目录一览)
  - [4.2 运行仿真](#42-运行仿真)
  - [4.3 run_all_riscv_tests.py — 批量 RISC-V 指令测试](#43-run_all_riscv_testspy--批量-risc-v-指令测试)
- [5. 输出产物说明](#5-输出产物说明)
- [6. 常见问题](#6-常见问题)

---

## 1. 依赖与环境

### 工具链

BD32 目前使用 **xPack RISC-V GCC 15.2.0** 工具链。代码路径中硬编码：

| 组件 | 路径 |
|------|------|
| GCC 工具链 | `D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin` |
| CC | `riscv-none-elf-gcc` |
| OBJCOPY | `riscv-none-elf-objcopy` |
| OBJDUMP | `riscv-none-elf-objdump` |
| **Clang（可选前端）** | `D:/RISCV_Tool/llvm-22.1.8/bin/clang`（官方 LLVM 22.1.8） |

> **Clang 集成（可选）：** 通过 `build.py` / `build_riscv_tests.py` 的 `--clang` 开关，可用官方 LLVM/clang 替代 GCC 做 `.c` 代码生成，链接仍复用 xPack 的 `libgcc` 与 `link.ld`。详见 [2.3 LLVM/Clang 集成](#23-llvmclang-集成clang)。

备选：NucleiStudio 捆绑工具链也可用
（`D:/NucleiStudio/toolchain/gcc/bin/riscv64-unknown-elf-gcc`，需修改 `build.py` 中的路径）。

### 仿真器

ModelSim SE-64 2020.4，路径 `D:\modeltech64_2020.4\win64`。

### 运行时参数

| 架构 | march | mabi |
|------|-------|------|
| RV32IM | `rv32im_zicsr` | `ilp32` |

---

## 2. SDK 构建工具（SDK/tools/）

### 2.1 build.py — 主构建脚本

**路径：** `Working/SDK/tools/build.py`

一键编译应用 demo，生成 ELF、反汇编、ITCM/DTCM 内存初始化文件和 UART 下载镜像。

#### 基本用法

```bash
cd Working/SDK

# 自动查找 demos/nolibc/breathing/src/main.c 并编译
python tools/build.py demos/nolibc/breathing

# 其他 demo
python tools/build.py demos/nolibc/blink
python tools/build.py demos/nolibc/uart_echo
python tools/build.py demos/nolibc/cpuinfo
```

#### 参数

| 参数 | 说明 |
|------|------|
| `source` | demo 目录或 .c 文件路径 |
| `--newlib` | 链接 newlib-nano（`-specs=nano.specs`，支持 printf / malloc 等标准库） |
| `--no-bin` | 跳过 .mem / .uartbin 生成（仅生成 ELF） |
| `--opt O2` | 优化等级（默认 Os） |
| `--extra "-DBAR"` | 追加额外 GCC 编译标志 |

#### 编译流程

```
AS start.S                      ← 启动汇编（设 SP、清零 bss）
CC board/init.c                 ← 板级初始化（测主频、设 mtvec）
CC drivers/bd32_uart.c          ← UART 驱动
CC trap/trap_handler.c          ← 中断/异常处理
AS startup/vector_table.S       ← 中断向量表
AS drivers/bd32_clint_asm.S     ← CLINT 汇编接口
CC main.c                       ← 用户主程序
LD → breathing.elf              ← 链接（link.ld 指定内存布局）
OBJDUMP → out.dump              ← 反汇编
→ breathing_itcm.mem            ← ITCM 初始化（$readmemh 格式）
→ breathing_dtcm.mem            ← DTCM 初始化
→ breathing.uartbin             ← UART 下载镜像
→ test_data/custom/*            ← 同步到仿真目录
```

#### --newlib 模式

当应用需要 `printf`, `malloc` 等标准库函数时使用（基于 **newlib-nano**，链接 `-specs=nano.specs`）：

```bash
python tools/build.py demos/nolibc/breathing --newlib
```

> **注意：** `--newlib` 模式会额外编译 `porting/syscalls.c` 与 `utils/printf_fixed.c`，
> 并链接 `-lc -lm -lgcc`（C 库 / 数学库 / GCC 运行时）。**无需任何外部 picolibc 安装**，
> 头文件与库直接来自 xPack 工具链自带的新版 newlib-nano。

#### 输出产物

编译完成后，产物位于 `demos/<name>/build/`：

| 文件 | 格式 | 用途 |
|------|------|------|
| `breathing.elf` | ELF | 调试/分析 |
| `out.dump` | 文本 | 反汇编（调试用） |
| `breathing_itcm.mem` | 十六进制文本 | ITCM 初始化（ModelSim `$readmemh`） |
| `breathing_dtcm.mem` | 十六进制文本 | DTCM 初始化 |
| `breathing.uartbin` | 二进制 | UART 下载镜像（含 START_FRAME 头） |

`.uartbin` 和 `.mem` 同时自动同步到 `test_data/custom/`，供仿真脚本直接使用。

#### 内存布局

```
ITCM: 0x0001_0000 ~ 0x0001_FFFF (64KB, 代码段)
DTCM: 0x0002_0000 ~ 0x0002_FFFF (64KB, 数据段)
```

- **ITCM**：`.text`（含 `.init`、`.trap.vector`）
- **DTCM**：`.data` + `.rodata` + `.bss` + `.heap` + `.stack`

### 2.2 build_riscv_tests.py — RISC-V 兼容性测试编译

**路径：** `Working/SDK/tools/build_riscv_tests.py`

从 `riscv-tests` 源码编译官方 RISC-V 指令兼容性测试。

#### 依赖

- 上游 riscv-tests 源码（`D:\Desktop\毕业设计\参考资料和工具\RISC-V软件\riscv-tests`）
- tinyriscv 的 isa 补充环境（`Ref/tinyriscv-master/tests/isa`）

#### 用法

```bash
cd Working/SDK

# 默认：gcc 一步编链所有 riscv-tests
python tools/build_riscv_tests.py

# 可选：用 clang 汇编 .S，gcc 链接（详见 2.3）
python tools/build_riscv_tests.py --clang
```

产物输出到 `Working/test_data/riscv-tests/`（.dat 格式，供 `$readmemh` 加载）。

### 2.3 LLVM/Clang 集成（--clang）

**涉及脚本：** `Working/SDK/tools/build.py`、`Working/SDK/tools/build_riscv_tests.py`

BD32 在默认 xPack GCC 工具链之外，额外支持官方 **LLVM/Clang 22.1.8** 作为前端代码生成器。
启用方式是在两个构建脚本上加 `--clang` 开关；**默认仍用 GCC**，现有行为完全不变。

#### 设计原则

| 阶段 | 默认（无 `--clang`） | 加 `--clang` 后 |
|------|---------------------|----------------|
| `.c` 编译（build.py） | xpack gcc | **clang**（`--target=riscv32-unknown-elf`） |
| `.S` 启动文件汇编 | xpack gcc | xpack gcc（**始终 gcc**：保证 `.option norelax` / `%pcrel_hi` 等 GNU 语法正确） |
| riscv-tests `.S`（build_riscv_tests.py） | xpack gcc | **clang** 汇编 |
| 链接 | xpack gcc | xpack gcc（**始终 gcc**：复用 `link.ld` + `libgcc`） |

> **为什么链接仍走 gcc？** 官方 LLVM 22.1.8 的 Windows 包**不含 RISC-V 的 compiler-rt builtins**
> （`libclang_rt.builtins.a`）。若用纯 clang 链接会报找不到该库。因此 clang 只负责生成 `.o`，
> 最终链接统一交给 xpack gcc（自带 `libgcc` / newlib / crt0），产物与纯 GCC 流程二进制等价。

#### 工具链路径

| 组件 | 路径 |
|------|------|
| Clang | `D:/RISCV_Tool/llvm-22.1.8/bin/clang` |
| newlib 头/库（sysroot，`--newlib` + `--clang` 时用） | `D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/riscv-none-elf` |

#### 用法示例

```bash
cd Working/SDK

# build.py：用 clang 编译 .c，gcc 链接（默认 medlow / Os）
python tools/build.py demos/nolibc/breathing --clang

# build.py：clang + newlib-nano（clang 额外 --sysroot 找 newlib 头）
python tools/build.py demos/nolibc/uart_echo --newlib --clang

# build_riscv_tests.py：用 clang 汇编 riscv-tests .S，gcc 链接
python tools/build_riscv_tests.py --clang
```

#### 验证状态

- `build.py --clang`：在 `nolibc/empty`、`newlib/hello`（printf）下通过，
  反汇编（`out.dump`）与 ITCM/DTCM `.mem` 与纯 GCC 流程一致。
- `build_riscv_tests.py --clang`：rv32ui（48 个）+ rv32um（8 个）全部编链通过，
  后续 `run_all_riscv_tests.py` 仿真 PASS/FAIL 结果与纯 GCC 流程一致。

---

## 3. MROM 构建

**路径：** `Working/test_data/build_mrom.sh`

MROM（Mask ROM / Boot ROM）是 SoC 上电后第一条指令所在位置，
负责 CPU 主频测量和 UART NCO 系数计算。

#### 用法

```bash
# Git Bash
bash Working/test_data/build_mrom.sh
```

#### 输入/输出

| 文件 | 说明 |
|------|------|
| `test_data/mrom.s` | MROM 汇编源码（手写） |
| `test_data/mrom.elf` | 链接产物 |
| `test_data/mrom.dump` | 反汇编（用于人工验证） |
| `test_data/mrom.dat` | Hex 格式初始化文件（`$readmemh`，80 words） |

#### MROM 功能

1. 设置 `mcounteren[0]=1`（用户态可读 mcycle）
2. 读取 mtime（1MHz 基准）和 mcycle
3. 等待 10000 个 mtime ticks（10ms）
4. 计算 `freq_hz = Δmcycle × 100`
5. 存储频率到 DTCM 预留地址
6. 若为 Download 模式：计算 UART DLL + NCO FCW 并写入 UART 寄存器
7. 跳转到 ITCM 0x10000 执行用户程序

> **注意：** MROM 地址固定在 0x00000000，大小限制为 1K words (4096 bytes)。

#### 构建依赖

```bash
# 工具链（Nuclei）
D:/NucleiStudio/toolchain/gcc/bin/riscv64-unknown-elf-gcc
D:/NucleiStudio/toolchain/gcc/bin/llvm-objcopy
```

---

## 4. 仿真脚本（script/）

### 4.1 各测试子目录一览

| 目录 | 用途 |
|------|------|
| `core_test/` | CPU 核级仿真（riscv-tests 指令兼容性测试） |
| `soc_test/` | SoC 系统级仿真（CPU + 总线 + 外设） |
| `uart_test/` | UART 模块独立仿真 |
| `gpio_test/` | GPIO 模块独立仿真 |
| `plic_test/` | PLIC 中断控制器仿真（含 XSim Tcl） |
| `timer_test/` | APB Timer 模块仿真 |

### 4.2 运行仿真

每个子目录结构统一：

```
xxx_test/
├── filelist.f       # 文件列表（Verilog 源文件）
├── run.do           # ModelSim 运行脚本（编译 + 加载波形）
├── top_tb.bat       # 一键启动（双击运行）
└── work/            # 编译输出（自动生成）
```

#### 方式一：双击运行

```bash
# 进入对应的测试目录，双击
Working/script/soc_test/top_tb.bat
```

#### 方式二：命令行

```bash
cd Working/script/soc_test
D:\modeltech64_2020.4\win64\modelsim -do run.do
```

#### 仿真的波形信号

| 测试 | 关注信号 |
|------|---------|
| `core_test` | clk, rst_n, itcm_addr, itcm_rdata, pc, instr, reg_waddr, reg_wdata |
| `soc_test` | sys_clk, sys_rst_n, uart_tx, gpio_io, timer_clk |
| `uart_test` | uart_clk, tx, rx, lsr, fcw |
| `plic_test` | irq_src, claim, eip |

#### soc_test 特殊说明

`soc_test` 的仿真顶层直接例化 `SoC_top`（纯数字 IP），
TB 中需提供：

| 信号 | 频率 | 生成方式 |
|------|------|----------|
| `sys_clk` | 90MHz | `always #5555 clk = ~clk` |
| `timer_clk` | 1MHz | `always #500 timer_clk = ~timer_clk` |
| `sys_rst_n` | 复位 | `initial` 块中拉低再释放 |

`SoC_top` 为纯数字 IP，不包含 clk_wiz/clk_div/BUFG/Cdc_Sync——这些在 FPGA 板级顶层 `bd32_board_top` 中。

### 4.3 run_all_riscv_tests.py — 批量 RISC-V 指令测试

**路径：** `Working/script/run_all_riscv_tests.py`

利用 ModelSim 批量运行 RISC-V 指令兼容性测试，输出 PASS/FAIL 汇总报告。

#### 用法

```bash
cd Working/script
python run_all_riscv_tests.py
```

#### 工作流程

1. 清理 `core_test/work/` 目录
2. 编译所有 RTL（带 `+define+CORE_TEST +define+DIRECT_LOAD`）
3. 遍历 `../test_data/rv32*.dat` 逐个跑仿真
4. 收集结果 → 汇总表格

#### 测试文件匹配规则

- `rv32ui-p-*.dat` — RV32I 用户级指令测试（add, sub, lw, sw, jal, beq 等）
- `rv32um-p-*.dat` — RV32M 乘除法扩展测试（mul, div, rem 等）

#### 配置项（脚本顶部可修改）

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `VSIM_PATH` | ModelSim vsim 所在目录 | `D:\modeltech64_2020.4\win64` |
| `SIM_TIME_US` | 每测试仿真时长（微秒） | `50` |
| `TIMEOUT_SEC` | 每测试超时（秒） | `60` |

#### 输出示例

```
╔══════════════════════════╗
║  批量测试运行器           ║
╚══════════════════════════╝

  Found 48 test files

============================================================
  Step 1: Compiling RTL with +define+CORE_TEST ...
============================================================
  [OK] Compilation successful

============================================================
  Step 2: Running 48 tests
============================================================

  [ 1/48] rv32ui-p-add ... PASS (2.4s)
  ...

============================================================
  RISC-V Tests Summary
============================================================
  Passed:  48
  Total:   48  (elapsed: 112.3s)
============================================================
```

---

## 5. 输出产物说明

### 流程图

```
SDK/tools/build.py (GCC, 可选 --clang)   test_data/build_mrom.sh (Nuclei LLVM)
        │                                      │
        ▼                                      ▼
  breathing.elf  ← ELF 可执行文件         mrom.elf  ← MROM ELF
        │                                      │
        ▼                                      ▼
  *.itcm.mem ← 内存初始化（$readmemh）    mrom.dat ← 内存初始化
  *.dtcm.mem                                       （$readmemh）
  *.uartbin ← UART 下载镜像
        │
        ▼
  test_data/custom/*  ← 同步到仿真目录

SDK/tools/build_riscv_tests.py (GCC, 可选 --clang)
        │
        ▼
  test_data/riscv-tests/*.dat  ← 指令兼容性测试 (.dat)
        │
        ▼
  script/run_all_riscv_tests.py  ← ModelSim 批量仿真 (PASS/FAIL)
```

> 注：`--clang` 仅改变 `.c` / `.S` 的**前端代码生成器**（clang 替代 gcc），
> 链接阶段始终由 xpack gcc 完成。

### 各产物的使用场景

| 产物 | 使用场景 |
|------|---------|
| `.elf` | GDB 调试、objdump 分析 |
| `.dump` | 反汇编人工审查 |
| `.itcm.mem` | ModelSim `$readmemh` 加载指令内存 |
| `.dtcm.mem` | ModelSim `$readmemh` 加载数据内存 |
| `.uartbin` | UART 下载到 FPGA（MROM + Download 模式） |
| `mrom.dat` | 仿真时 MROM 初始化 |

### uartbin 格式

```
+---------------+----------------+---------------------+----------+
| START_FRAME   | ITCM word count | ITCM data (N words) | DTCM ... |
| 0xBBAABBAA    | uint32_t       | uint32_t[]          | ...      |
+---------------+----------------+---------------------+----------+
```

---

## 6. 常见问题

### Q: 编译报错 `riscv-none-elf-gcc: command not found`

xPack 工具链未安装或路径不正确。检查 `D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin/` 是否存在。
备选：修改 `build.py` 中的 `TOOLCHAIN` 路径为 Nuclei 工具链。

### Q: ModelSim 找不到 `vsim`

确保 ModelSim 安装在 `D:\modeltech64_2020.4\win64`，或修改 `run_all_riscv_tests.py` 顶部的 `VSIM_PATH`。

### Q: 仿真时 ITCM 全 X，CPU 不运行

`run_all_riscv_tests.py` 需传入 `+define+DIRECT_LOAD`。旧版脚本漏了此宏，已修复。

### Q: 仿真时 UART 没有输出/FCW 为 0

程序可能是用旧 BSP 编译的（缺少 FCW 写入）。用最新 BSP 重新编译 demo：

```bash
cd Working/SDK
python tools/build.py demos/nolibc/breathing
```

### Q: 如何在 SoC 仿真中加载自定义程序？

```bash
# 1. 编译程序
cd Working/SDK
python tools/build.py demos/nolibc/my_demo

# 2. 产物自动同步到 test_data/custom/
#    修改 soc_test 的 run.do 或 TB，加载 custom/my_demo_itcm.mem

# 3. 运行仿真
cd Working/script/soc_test
top_tb.bat
```

### Q: 用 `--clang` 时报 `'string.h' file not found`（仅 --newlib 场景）

clang 默认不带 newlib 头，需通过 `--sysroot` 指向 xPack 的 newlib。`build.py` 在
`--newlib --clang` 时已自动追加 `--sysroot=D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/riscv-none-elf`。
若手动调用 clang，请确认该 sysroot 路径存在。

### Q: 用 `--clang` 时链接报错找不到 `libclang_rt.builtins.a`

这是预期行为。官方 LLVM 22.1.8 Windows 包不含 RISC-V 的 compiler-rt builtins，
因此**链接阶段一律走 xpack gcc**（提供 `libgcc`）。`build.py` / `build_riscv_tests.py`
已硬编码此策略，无需手动处理；除非你自行引入 compiler-rt，否则不要加 `-fuse-ld=lld`。

### Q: 如何对比 GCC 与 Clang 产物是否一致？

分别用两种流程编同一 demo / 同一批 riscv-tests，再用 `llvm-objdump`（或
`riscv-none-elf-objdump`）反汇编 `.elf` 对比，或直接跑 `run_all_riscv_tests.py`
看 PASS/FAIL 汇总是否一致。两者生成的 ITCM/DTCM `.mem` 内容应等价。
