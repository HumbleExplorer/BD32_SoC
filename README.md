# BD32 — RV32IM Pipelined RISC-V SoC

BD32 是一款自定义的 32 位 RISC-V (RV32IM) 流水线处理器 SoC，采用经典 5 级流水线架构并配备乱序退休机制（OITF），支持乘法/除法指令与短指令并行执行。项目包含完整的 RTL 设计、仿真验证环境、SDK 工具链和 FPGA 原型验证平台。

## 特性

- RV32IM 指令集（含 M 扩展乘除法）
- 5 级流水线：IF → ID → EX → MEM → WB
- OITF（Out-of-order Instruction Termination Facility）：深度 4 的 FIFO，允许多周期乘除法指令乱序退休
- 3 级流水 Booth-4 乘法器（3 拍出结果）
- 32 周期迭代恢复除法器
- 动态分支预测器 + 返回地址栈（RAS）
- AXI-Lite 总线 + APB 外设子系统
- 外设：UART（含 NCO 波特率发生器）、CLINT（mtime/mtip）、PLIC 中断控制器、APB Timer（PWM）、GPIO
- CoreMark 验证通过（-O2 和 -O3 均通过 CRC 校验）

## 目录结构

```
Working/
├── rtl/                        # RTL 源码
│   ├── SoC_Config.sv          # 全局配置（宏定义、内存映射、仿真文件路径）
│   ├── RV32_Inst_Define.sv    # 指令编码定义
│   ├── SoC_top.sv             # SoC 顶层（纯数字 IP）
│   ├── Core/                  # CPU 核
│   │   ├── RISC_V_Core.sv    # 核顶层（流水线连线）
│   │   ├── Pipeline_Ctrl.sv  # 流水线控制（stall/flush/OITF 调度）
│   │   ├── RegFile.sv        # 32×32 寄存器堆（双写端口 + 旁路）
│   │   ├── OITF.sv           # 乱序退休 FIFO
│   │   ├── Decoder.sv        # 指令译码
│   │   ├── Executer.sv       # ALU 执行单元
│   │   ├── Data_Hazard_Forward.sv  # 数据前递
│   │   ├── Dynamic_Branch_Predictor.sv  # 分支预测
│   │   ├── Mem_Access.sv     # 访存控制
│   │   ├── CSR_Reg_Access.sv # CSR 读写
│   │   ├── IF_ID/ID_EX/EX_MEM/MEM_WB.sv  # 流水级寄存器
│   │   ├── ITCM.sv / DTCM.sv / BootROM.sv  # 片上存储
│   │   └── Mul_Div/          # 乘法器 + 除法器
│   ├── Bus/                   # AXI-Lite 总线基础设施
│   ├── Periph/               # 外设
│   │   ├── CLINT.sv          # Core-Local Interruptor
│   │   ├── apb_gpio.sv       # GPIO
│   │   ├── plic/             # 中断控制器
│   │   ├── timer/            # APB Timer / PWM
│   │   └── uart/             # UART（TX/RX/FIFO/Download）
│   └── Common/               # 时钟/复位工具模块
├── sim/                       # Testbench
│   ├── tb_core_top.sv        # 核级 TB（x26/x27 判定，加载 .dat）
│   └── tb_soc_top.sv         # SoC 级 TB（UART 输出、WB_TRACE、PWM 监测）
├── script/                    # 仿真脚本
│   ├── core_test/            # 核级仿真（filelist.f, run.do）
│   ├── soc_test/             # SoC 级仿真
│   ├── uart_test/ gpio_test/ plic_test/ timer_test/  # 外设独立仿真
│   ├── run_one.py            # 运行单个 custom_asm 测试
│   ├── run_all_custom_asm.py # custom_asm 全回归（36 个测试）
│   └── run_all_riscv_tests.py # riscv-tests 全回归（rv32ui + rv32um）
├── test_data/
│   ├── custom_asm/           # 36 个自定义流水线压力测试（.S + .dat）
│   ├── riscv-tests/          # 标准 riscv-tests（rv32ui 48个 + rv32um 8个）
│   └── soc/c/                # CoreMark 内存文件（.mem）
├── SDK/
│   ├── tools/                # 构建工具（build.py, build_asm.py, build_riscv_tests.py）
│   ├── demos/nolibc/         # 裸机 demo（breathing, blink, uart_echo, cpuinfo）
│   ├── demos/newlib/coremark/ # CoreMark 基准测试（build_O2/ + build_O3/）
│   └── isa/env/p/            # riscv_test.h + link.ld
├── BD32_SoC/                  # Vivado FPGA 工程（Xilinx）
├── ip_repo/                   # 自定义 AXI IP 仓库
└── doc/                       # 文档
```

## 微架构

### 流水线概览

```
┌────┐   ┌────┐   ┌────┐   ┌────┐   ┌────┐
│ IF │──▶│ ID │──▶│ EX │──▶│MEM │──▶│ WB │──▶ Port1 写回
└────┘   └────┘   └────┘   └────┘   └────┘
                       │                              ▲
                       ▼                              │
                 ┌──────────┐    retire               │
                 │   OITF   │────────────────────────▶ Port2 写回
                 │ (depth=4)│
                 └──────────┘
                   ▲       ▲
                   │       │
              ┌────┴┐  ┌──┴───┐
              │ MUL │  │ DIV  │
              │3-cyc│  │32-cyc│
              └─────┘  └──────┘
```

- 短指令（ALU/Load/Store/Branch）走正常 5 级流水，从 Port1 写回
- 长指令（MUL/DIV/REM）在 EX 阶段分发到 OITF，由独立功能单元执行，完成后从 Port2 乱序退休写回
- OITF 维护 RAW/WAW 冒险检测，必要时 stall 整条流水线

### 寄存器堆双写端口

- Port1：正常 WB 路径（短指令）
- Port2：OITF 退休路径（长指令结果）
- 同地址冲突时 Port2 优先（OITF WAW 检查保证不会产生合法的同地址同时写）
- 旁路读取优先级：Port2 > Port1 > 寄存器阵列

### 关键配置宏（SoC_Config.sv）

| 宏 | 功能 |
|---|---|
| `DIRECT_LOAD` | 从 .mem 文件直接加载程序（否则走 UART 下载） |
| `CORE_TEST` | 核级测试模式 |
| `CUSTOM_ASM` | 使用 custom_asm 测试路径 |
| `MULT_PIPELINE` | 启用 3 级流水乘法器（默认状态机 4 拍） |
| `XILINX` | FPGA 综合模式 |
| `WB_TRACE` | 使能写回追踪输出 |

## 构建与仿真

### 环境依赖

| 组件 | 路径/版本 |
|------|-----------|
| RISC-V GCC | xPack riscv-none-elf-gcc 15.2.0（`D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin`） |
| Clang（可选） | LLVM 22.1.8（`D:/RISCV_Tool/llvm-22.1.8/bin/clang`） |
| ModelSim | SE-64 2020.4（`D:\modeltech64_2020.4\win64`） |
| Python | 3.x |
| Vivado | 2023.1（FPGA 综合） |

目标架构：`-march=rv32im_zicsr -mabi=ilp32`

### 构建自定义汇编测试

```bash
cd test_data/custom_asm
python build_asm.py <test_name>    # 单个测试
python build_asm.py all            # 全部 36 个测试
```

编译参数：`-march=rv32im -mabi=ilp32 -O0 -mno-relax -nostdlib -static`
产物：`.elf`、`.dump`、`.dat`（readmemh 格式）

### 构建 C 程序 / CoreMark

```bash
cd SDK

# 裸机 demo
python tools/build.py demos/nolibc/breathing
python tools/build.py demos/nolibc/breathing --newlib    # 链接 newlib-nano
python tools/build.py demos/nolibc/breathing --clang     # 用 Clang 前端

# CoreMark（产物含优化等级后缀：coremark_o2_*.mem / coremark_o3_*.mem）
python tools/build.py demos/newlib/coremark --newlib --opt O2
python tools/build.py demos/newlib/coremark --newlib --opt O3
```

产物：`.elf`、`.dump`、`*_itcm.mem`、`*_dtcm.mem`、`.uartbin`（CoreMark 文件名含 `_o2`/`_o3` 后缀）

### 内存布局

```
BootROM:  0x0000_0000 ~ 0x0000_0FFF (4KB, 启动代码)
ITCM:     0x0001_0000 ~ 0x0001_FFFF (64KB, 代码段)
DTCM:     0x0002_0000 ~ 0x0002_FFFF (64KB, 数据段)
UART:     0xE001_0000
CLINT:    0xE000_0000
PLIC:     0xE100_0000
Timer:    0xE002_0000
GPIO:     0xE003_0000
```

### 运行仿真

#### 核级测试（tb_core_top）

```bash
cd script
python run_one.py <test_name>              # 单个测试
python run_all_custom_asm.py               # custom_asm 全回归
python run_all_riscv_tests.py              # riscv-tests ISA 兼容性
```

判定约定：x26=1 表示完成，x27=1 表示通过；x3(gp) 记录失败的子测试编号。

#### SoC 级测试（tb_soc_top）

```bash
cd script/soc_test
# 编译
vlog -f filelist.f +define+DIRECT_LOAD
# 运行（CoreMark 需要 ~55ms 完成 UART 输出）
vsim -c -voptargs=+acc tb_soc_top -do "run 55ms; quit -f"
```

UART 输出通过 TB 中的 `$write("%c", ...)` 打印到控制台。
添加 `+define+WB_TRACE` 可启用写回追踪（输出到 `wb_trace.log`）。

#### 外设独立仿真

各 `script/xxx_test/` 目录下双击 `top_tb.bat` 或命令行运行：
```bash
cd script/uart_test
D:\modeltech64_2020.4\win64\modelsim -do run.do
```

### CoreMark 基准

CoreMark 源码位于 `SDK/demos/newlib/coremark/`，分别以 -O2 和 -O3 编译验证。

```bash
cd SDK
python tools/build.py demos/newlib/coremark --newlib --opt O2   # → build_O2/
python tools/build.py demos/newlib/coremark --newlib --opt O3   # → build_O3/
```

产物命名规则（含优化等级后缀，避免相互覆盖）：

| 优化等级 | 文件 |
|---------|------|
| -O2 | `coremark_o2.elf`、`coremark_o2_itcm.mem`、`coremark_o2_dtcm.mem`、`coremark_o2.uartbin` |
| -O3 | `coremark_o3.elf`、`coremark_o3_itcm.mem`、`coremark_o3_dtcm.mem`、`coremark_o3.uartbin` |

`test_data/soc/c/` 中同时保留两套 .mem 文件，通过 `SoC_Config.sv` 的 `ITCM_FILE`/`DTCM_FILE` 切换加载哪一套。

预期正确输出（2K 规模，标准种子）：
```
CoreMark Size    : 666
seedcrc          : 0xe9f5
[0]crclist       : 0xe714
[0]crcmatrix     : 0x1fd7
[0]crcstate      : 0x8e3a
[0]crcfinal      : 0xe714
Correct operation validated
```

仿真配置：修改 `SoC_Config.sv` 中 `ITCM_FILE`/`DTCM_FILE` 为 `"coremark_o3_itcm.mem"`/`"coremark_o3_dtcm.mem"`（或 o2），仿真时长设为 55ms（80MHz CPU + 115200 baud UART）。

### Spike Diff-Test（差分测试）

使用 Spike ISA 模拟器作为黄金参考，与 RTL 仿真结果逐条对比写回序列，定位流水线功能 bug。

#### 环境

Spike 安装于 WSL：`/home/bluedream/.local/spike/bin/spike`
dtc（设备树编译器）：`/home/bluedream/.local/usr/bin/dtc`

#### 运行 Spike 获取参考 trace

```bash
# WSL 中执行
spike --isa=rv32im -m0x10000:0x30000,0xe0010000:0x1000 \
  --log-commits <program>.elf 2> spike_trace.txt
```

参数说明：`-m` 指定内存区域（ITCM+DTCM 192KB，UART MMIO 4KB），`--log-commits` 输出每条指令的寄存器写回。

注意事项：
- 自定义 CSR（如 0xbc6 性能计数器）会导致 Spike 触发 illegal instruction trap，trap 之前的 trace 仍然有效
- 若固件含 UART polling 循环（等待 TX ready），Spike 会死循环。解决方法：用 ELF patch 将 polling 分支替换为 NOP（`0x00000013`）
- WSL 输出为 UTF-16LE 编码，处理时需 `iconv -f UTF-16LE -t UTF-8`

#### 获取 RTL 写回 trace

在 vlog 编译时添加 `+define+WB_TRACE`，仿真结束后生成 `wb_trace.log`，格式为 `PC rd data`（十六进制 PC，十进制 rd，十六进制 data），记录 Port1（正常 WB）和 Port2（OITF 退休）的所有写回事件。

#### 对比方法

1. **预处理**：RTL trace 中流水线 stall 会导致同一条写回重复记录多个周期，需先去除连续重复项
2. **对齐**：RTL 会执行 BootROM 代码（Spike 不执行），需跳过 RTL trace 开头的 boot 段
3. **乱序处理**：OITF 使长指令（MUL/DIV）乱序退休，RTL trace 中写回顺序与 Spike 不完全一致。使用 lookahead 窗口（8~16 条）进行模糊匹配
4. **定位**：第一个无法匹配的写回即为 bug 的入口点，后续所有差异都是连锁反应

#### 典型调试流程

```
1. 复现：O2 通过 / O3 失败 → 确认是流水线冒险 bug
2. 静态分析：解析 objdump，找 MUL/DIV 的 RAW 依赖链
3. Trace 对比：Spike vs RTL 写回序列，定位第一个 divergence
4. 关联：将 divergence 对应的 PC 映射回反汇编，确认是哪条指令拿到错误值
5. 根因：检查该时刻的流水线状态（stall/forward/write-port 冲突）
6. 修复 + 定向测试 + 回归验证
```

## FPGA 原型验证

Vivado 工程位于 `BD32_SoC/`，目标平台为 Xilinx FPGA。

- 板级顶层：`bd32_board_top`（含 clk_wiz、BUFG、CDC 同步）
- 约束文件：`BD32_SoC.srcs/constrs_1/new/BD32_SoC.xdc`
- IP：clk_wiz_0（时钟生成）、imem/dmem/mrom（Block Memory Generator）
- 支持 ILA 在线调试（`mark_debug` 属性标注关键信号）
- 支持 UART 下载模式（MROM 自动计算波特率并配置 UART）

## SDK 构建工具详细说明

### build.py — 主构建脚本

路径：`SDK/tools/build.py`

| 参数 | 说明 |
|------|------|
| `source` | demo 目录或 .c 文件路径 |
| `--newlib` | 链接 newlib-nano（支持 printf/malloc） |
| `--no-bin` | 跳过 .mem/.uartbin 生成 |
| `--opt O2` | 优化等级（默认 Os） |
| `--clang` | 用 Clang 做前端代码生成（链接仍走 GCC） |
| `--extra "-DFLAG"` | 追加编译标志 |

编译流程：AS start.S → CC board/init.c → CC drivers → CC trap → CC main.c → LD → OBJDUMP → 生成 .mem/.uartbin

### build_riscv_tests.py — riscv-tests 编译

```bash
cd SDK
python tools/build_riscv_tests.py          # GCC
python tools/build_riscv_tests.py --clang  # Clang 汇编
```

产物输出到 `test_data/riscv-tests/`（.dat 格式）。

### LLVM/Clang 集成

通过 `--clang` 开关启用。设计原则：Clang 只负责 `.c`/`.S` 的代码生成，链接始终由 xPack GCC 完成（因为官方 LLVM Windows 包不含 RISC-V compiler-rt builtins）。

## MROM 构建

```bash
bash test_data/build_mrom.sh
```

MROM（0x00000000，4KB）负责：设置 mcounteren → 测量 CPU 主频 → 计算 UART NCO 系数 → 跳转 ITCM 执行用户程序。

## uartbin 下载格式

```
+---------------+----------------+---------------------+----------+
| START_FRAME   | ITCM word count| ITCM data (N words) | DTCM ... |
| 0xBBAABBAA    | uint32_t       | uint32_t[]          | ...      |
+---------------+----------------+---------------------+----------+
```

## 常见问题

**Q: 编译报错 `riscv-none-elf-gcc: command not found`**
检查 xPack 工具链路径 `D:/RISCV_Tool/xpack-riscv-none-elf-gcc-15.2.0-1/bin/` 是否存在。

**Q: ModelSim 找不到 `vsim`**
确认 ModelSim 安装在 `D:\modeltech64_2020.4\win64`，或修改脚本顶部的 `VSIM_PATH`。

**Q: 仿真时 ITCM 全 X，CPU 不运行**
确保 vlog 编译时传入 `+define+DIRECT_LOAD`。

**Q: CoreMark 仿真输出不完整**
仿真时长需设为 55ms（不是 15ms），否则 UART 来不及打印完 CRC 结果。

**Q: 修改 SoC_Config.sv 后其他测试异常**
`ITCM_FILE`/`DTCM_FILE` 是全局宏，改完后记得恢复默认值。

**Q: `--clang` 链接报错找不到 `libclang_rt.builtins.a`**
预期行为。链接阶段一律走 xPack GCC，不要加 `-fuse-ld=lld`。
