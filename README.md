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
- RISC-V Debug Module（halt-in-place + 直接端口访问架构）：JTAG 在线调试，支持 halt/resume、单步、reset halt、GPR/CSR 抽象访问、SBA 内存读写（含 8/16/32-bit 写）
- 硬件断点：Trigger Module（mcontrol type=2）4 路地址匹配（tselect 选择），支持 ebreak 进调试模式（dcsr.ebreakm），OpenOCD `hbreak` / GDB 在线调试实测通过
- 完整调试回归：DMI 一键测试（10 项）、GDB 全功能套件、真实 demo 符号级在线调试
- 动态分支预测器调试支持：单步模式下自动门控预测跳转，保证 PC 严格 +4 递增

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
│   ├── Debug/                 # 调试模块
│   │   ├── jtag_tap.sv       # JTAG TAP（IEEE 1149.1 + DTM）
│   │   ├── debug_dm.sv       # Debug Module（abstract cmd / SBA / trigger）
│   │   ├── debug_top.sv      # 调试子系统顶层（TAP + DM + CDC）
│   │   └── debug_cdc.sv      # 跨时钟域同步（JTAG TCK ↔ CPU CLK）
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
│   ├── tb_soc_top.sv         # SoC 级 TB（UART 输出、WB_TRACE、PWM 监测）
│   └── tb_debug.sv           # Debug Module TB（DMI 激励、halt/step/GPR/trigger）
├── script/                    # 仿真脚本
│   ├── core_test/            # 核级仿真（filelist.f, run.do）
│   ├── soc_test/             # SoC 级仿真
│   ├── debug_test/           # Debug Module 仿真（run_msim_debug.bat 一键回归）
│   ├── uart_test/ gpio_test/ plic_test/ timer_test/  # 外设独立仿真
│   ├── run_one.py            # 运行单个 custom_asm 测试
│   ├── run_all_custom_asm.py # custom_asm 全回归（36 个测试）
│   └── run_all_riscv_tests.py # riscv-tests 全回归（rv32ui + rv32um）
├── test_data/
│   ├── custom_asm/           # 36 个自定义流水线压力测试（.S + .dat）
│   ├── riscv-tests/          # 标准 riscv-tests（rv32ui 48个 + rv32um 8个）
│   └── soc/c/                # CoreMark 内存文件（.mem）
├── SDK/
│   ├── tools/                # 构建与在线控制工具
│   │   ├── build.py         # C 程序构建（GCC/Clang）
│   │   ├── build_riscv_tests.py  # riscv-tests 编译
│   │   ├── fpga_reset.py    # FPGA 远程复位（FTDI ADBUS5）
│   │   ├── uart_send.py     # UART 程序烧录（发送 .uartbin）
│   │   ├── uart_cmd.py / uart_recv.py / uart_log.py  # UART 交互工具
│   │   ├── auto_coremark.py # CoreMark 自动化测试（复位+下载+解析）
│   │   ├── bd32_openocd.cfg       # OpenOCD 配置（FT2232H + BD32 TAP）
│   │   ├── bd32_debug_test.cfg    # DMI 全功能一键测试（OpenOCD TCL 脚本）
│   │   ├── bd32_debug_test.gdb    # GDB 全功能调试套件
│   │   ├── run_gdb_debug_test.bat # GDB 套件 runner
│   │   ├── bd32_demo_debug.gdb    # 真实 demo（breathing）在线调试脚本
│   │   └── run_demo_debug.bat     # demo 调试 runner
│   ├── bsp/                  # 板级支持包（startup, drivers, trap, linker）
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
CLINT:    0xF200_0000  (APB PSEL[0])
PLIC:     0xFC00_0000  (APB PSEL[1])
GPIO:     0xE000_0000  (APB PSEL[2])
UART:     0xE001_0000  (APB PSEL[3])
Timer:    0xE002_0000  (APB PSEL[4])
SPI:      0xE003_0000  (APB PSEL[5], 预留)
I2C:      0xE004_0000  (APB PSEL[6], 预留)
Flash:    0x9000_0000  (AXI 从机, 未实现, 访问返回错误)
DDR:      0xB000_0000  (AXI 从机, 未实现, 访问返回错误)
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

## Debug Module（JTAG 在线调试）

BD32 实现了 RISC-V Debug Specification 的 0.13 风格子集（dcsr 读回按 1.0 位域），支持通过 JTAG 接口进行在线调试，并经 GDB 完成真实程序符号级调试验证。调试子系统位于 `rtl/Debug/`，由 `bd32_board_top` 在 `BD32_DEBUG_EN` 宏开启时例化。

调试采用 **halt-in-place + 直接端口访问** 架构（与 tinyriscv/Ibex 同类，区别于 E203/CVA6 的 Debug ROM + Park Loop）：
- halt 后流水线全级 stall + flush，CPU 原地冻结；无需 Debug ROM、不执行任何调试代码
- GPR/CSR 通过专用调试端口直连（RegFile / CSR_Reg_Access），不经 CPU 执行
- 内存访问走 SBA（32-bit 读；8/16/32-bit 写），在 halt 期间读写 ITCM/DTCM 以及外设总线（APB：UART/GPIO/CLINT/PLIC/Timer 等）

### 架构

```
PC (OpenOCD/GDB)
    │  USB
    ▼
FT2232H Channel A (JTAG: TCK/TDI/TDO/TMS)
    │
    ▼
┌─────────────────────────────────────────────────┐
│  debug_top                                      │
│  ┌───────────┐   ┌──────────┐   ┌───────────┐  │
│  │ jtag_tap  │──▶│ debug_dm │──▶│ debug_cdc │──│──▶ CPU (halt/resume/step)
│  │ (TAP+DTM) │◀──│ (DM)     │◀──│ (TCK↔CLK)│◀─│──◀ CPU (dbg_halted)
│  └───────────┘   └──────────┘   └───────────┘  │
└─────────────────────────────────────────────────┘
```

- **jtag_tap**：IEEE 1149.1 TAP 状态机 + DTM（Debug Transport Module），IDCODE = 0x1BD32003，IR 编码：IDCODE=0x01, DTMCS=0x10, DMI=0x11
- **debug_dm**：Debug Module 核心，实现 abstract command（GPR/CSR 读写）、SBA（System Bus Access）、halt/resume/step 控制、Trigger Module（mcontrol type=2）
- **debug_cdc**：JTAG TCK 域与 CPU CLK 域之间的跨时钟域同步（握手协议）

### 支持的调试功能

| 功能 | 状态 | 说明 |
|------|------|------|
| halt / resume | 已验证 | `dmcontrol.haltreq` / `resumereq` |
| 单步（stepi） | 已验证 | `dcsr.step=1`，门控分支预测保证 PC+4 |
| GPR 读写 | 已验证 | abstract command, regno 0x1000~0x101F |
| CSR 读写 | 已验证 | dcsr(0x7B0), dpc(0x7B1), mstatus 等 |
| reset halt | 已验证 | `ndmreset` + haltreq 驻留，停在复位向量 |
| GPR / CSR 读写 | 已验证 | abstract command，regno 0x1000~0x101F / 0xC000\|csr 与 1.0 直接编码 |
| dcsr / dpc | 已验证 | dcsr 按 1.0 位域读回（debugver/cause/step/ebreakm） |
| SBA | 已验证 | 32-bit 地址，8/16/32-bit 写 + 32-bit 读，读写 ITCM/DTCM + 外设总线（APB） |
| 硬件断点 | 已验证 | 4 路 tdata1/tdata2（tselect 选择），mcontrol type=2 地址匹配，OpenOCD `hbreak` + GDB |
| ebreak 进调试 | 已验证 | `dcsr.ebreakm=1` 时 ebreak 触发 halt，cause=1，dpc=ebreak 地址 |
| GDB 在线调试 | 已验证 | 真实 demo（breathing）符号级调试：加载/断点/单步/变量 |

未实现：Debug ROM / Park Loop、ProgBuf（progbufsize=0）、abstract 内存访问（cmdtype=2）、多 hart。

### Trigger Module（硬件断点）

DM 内部实现 4 路 trigger 寄存器组（tselect + 4×tdata1/tdata2），通过 abstract command 的 CSR 地址空间（0x7A0~0x7A3）访问：

- `tdata1` 复位值 = 0x2000_0000（type=2 mcontrol, dmode=0, 默认 disabled；dmode=0 避免 OpenOCD 0.12 枚举时清零导致 hbreak 失败）
- OpenOCD 通过 `hbreak *<addr>` 命令编程 tdata2 = 目标地址，置 tdata1[2]（execute match enable）；tselect 越界写自动钳位，用于枚举 trigger 数量（4 路）
- CPU 侧多路并行比较 `trigger_hit = |(trigger_en[i] & (inst_addr_if == trigger_addr[i]))`，命中后触发 halt
- **trigger halt 锁存**：命中时 DM 自动拉高 haltreq，删除断点（清 tdata1）不会让 CPU 自动恢复运行，直到调试器发 `resumereq`
- **ebreak 进调试**：`dcsr.ebreakm=1` 时 ID 级 ebreak 不产生异常，CPU 原地 halt（ID 保持、不冲刷），DM 锁存 haltreq 并置 `dcsr.cause=1`、`dpc=ebreak 地址`；调试器恢复原指令后 resume 即可继续执行（软件断点通路）

### OpenOCD + GDB 使用

配置文件：`SDK/tools/bd32_openocd.cfg`（gdb 端口 3333，默认开启）

手动流程：

```bash
# 终端 1：启动 OpenOCD
openocd -f SDK/tools/bd32_openocd.cfg

# 终端 2：启动 GDB（NucleiStudio riscv64-unknown-elf-gdb）
riscv64-unknown-elf-gdb program.elf
(gdb) target extended-remote :3333
(gdb) monitor reset halt
(gdb) hbreak *0x10020        # 硬件断点
(gdb) continue
(gdb) stepi                  # 单步
```

**一键回归脚本**（SDK/tools/，输出统一到工作区 `logs/` 目录）：

| 脚本 | 内容 | 结果文件 |
|------|------|----------|
| `bd32_debug_test.cfg`（OpenOCD 直接运行） | DMI 全功能：JTAG、halt/PC、GPR/CSR、单步、SBA、Trigger、reset halt（10 项） | 终端输出 |
| `run_gdb_debug_test.bat` | GDB 全功能套件：reset halt、寄存器/CSR、单步、内存读写、hbreak | `logs/gdb_test_result.txt` |
| `run_demo_debug.bat` | 真实 demo（breathing）符号级调试：加载、hbreak main、单步、变量 | `logs/demo_debug_result.txt` |
| `run_msim_debug.bat`（script/debug_test/） | ModelSim 回归（tb_debug，31 项断言，无需板子） | `logs/msim_out.txt` |

```bash
# 正常环境直接运行：
openocd -f Working/SDK/tools/bd32_debug_test.cfg
Working/SDK/tools/run_gdb_debug_test.bat
Working/SDK/tools/run_demo_debug.bat
Working/script/debug_test/run_msim_debug.bat
```

本机环境说明（Windows exec 环境 Winsock 损坏，进程无法创建 TCP socket / 运行 Node）：
- 所有涉及 socket 的工具（OpenOCD gdb server、GDB、ModelSim 的 vsim）需通过**任务计划程序**运行：
  - `schtasks /run /tn BD32_GDB` —— GDB 全功能套件
  - `schtasks /run /tn GDBDEMO2` —— demo 在线调试
  - `schtasks /run /tn BD32_MSIM` —— ModelSim 回归（结果 `logs/msim_out.txt`）
- FT2232H Channel A 必须绑定 WinUSB 驱动（Zadig），否则 libusb 无法访问
- Vivado hw_server 会占用 JTAG 适配器，使用前需关闭 Hardware Target
- 强制终止 OpenOCD 后可能需要拔插 USB 释放设备句柄
- adapter speed 设为 500 kHz（杜邦线连接），正式 PCB 可提高

### Debug 仿真验证

```bash
# 正常环境：
cd Working/sim
vsim -c -do run_debug.do

# 本机（exec 环境 Winsock 损坏，走计划任务）：
schtasks /run /tn BD32_MSIM     # 结果在 logs/msim_out.txt
```

Testbench `sim/tb_debug.sv` 通过 DMI 接口直接激励 DM，无需 JTAG 物理连接，覆盖：
- Test 1~12：IDCODE、halt/resume、GPR/CSR 读写、SBA、单步
- Test 13：reset halt（停在复位向量）
- Test 14：reset halt 后改 dpc 再 resume 的取指对齐（`resume_hold` 回归）
- Test 15：trigger halt 锁存（清断点后 CPU 保持 halt）
- Test 16：ebreak 进调试模式（halt / cause=1 / dpc / 锁存 / resume 后正确执行）
- Test 17：多硬件断点（tselect 选择，双断点依次命中，逐个清除）
- Test 18：SBA 字节/半字写（ITCM/DTCM RMW 合并验证）

上板验证（新 bitstream，2026-08-06）全部通过：
- DMI 一键测试 10/10（`bd32_debug_test.cfg`，OpenOCD 枚举识别 4 个 trigger）
- GDB 套件 10 项（`run_gdb_debug_test.bat`：reset halt / 单步 / GPR / CSR / SBA / hbreak）
- 真实 demo（breathing.elf）符号级调试（`run_demo_debug.bat`）
- 新功能专项 12/12（`bd32_new_feat_test.cfg`：SBA 8/16-bit 写、双硬件断点、ebreak 进调试模式）
- SBA 外设总线 6/6（`bd32_sba_periph.cfg`：SBA 访问 GPIO/UART/CLINT 外设、字节使能、未映射 sberror、halt 保持）

当前回归结果：**49 PASS / 0 FAIL**。

## FPGA 在线控制工具（SDK/tools）

通过 USB 连接 Sipeed RV-Debugger（FTDI FT2232H）和板载 CH340 USB-UART，可以在 PC 端用 Python 脚本完成复位、程序烧录、串口收发等操作，无需手动按复位键或打开串口助手。

### 硬件连接与驱动

| 设备 | 用途 | 驱动 |
|------|------|------|
| Sipeed RV-Debugger (FT2232H) Ch.A | JTAG 调试（OpenOCD） | WinUSB（Zadig 替换） |
| Sipeed RV-Debugger (FT2232H) Ch.A | FPGA 复位（ADBUS5 bit-bang） | D2XX (ftd2xx) |
| 板载 CH340 USB-UART | 程序下载 + 输出接收 | Windows VCP（COM 口） |

Python 依赖：

```bash
pip install ftd2xx pyserial
```

注意：Windows 下 fpga_reset.py 使用 ftd2xx（D2XX 库）控制 FTDI 芯片，需要 FTDI VCP 驱动；而 OpenOCD 使用 libusb，需要 WinUSB 驱动。两者互斥——同一时刻 Channel A 只能绑定一种驱动。切换方法：用 Zadig 在 WinUSB 和 FTDI VCP（libusbK 也可）之间替换。日常调试建议保持 WinUSB（OpenOCD），复位功能可改用 Vivado 或板载按键。

所有串口工具默认自动检测 CH340（通过 USB VID:PID = 1A86:7523 匹配），无需手动指定 COM 口号。该编号标识的是 CH340 芯片型号而非特定板卡，因此更换任何使用 CH340 的开发板均可自动识别。若同时连接多块 CH340 板，需用 `--port COMx` 手动指定。

### FPGA 复位（fpga_reset.py）

通过 FTDI bit-bang 模式驱动 ADBUS5（高电平有效）实现软件复位：

```bash
cd SDK

# 复位一次（拉高 0.5 秒后自动释放）
python tools/fpga_reset.py

# 保持复位 3 秒后释放
python tools/fpga_reset.py --hold 3

# 仅拉高复位（不释放，用于调试）
python tools/fpga_reset.py --assert

# 仅释放复位
python tools/fpga_reset.py --release
```

原理：FT2232H Channel A 设为 bit-bang 模式（0x01），ADBUS5 作为输出。写 `0x20` 拉高触发复位，写 `0x00` 释放。FPGA 端 `bd32_board_top` 中 `dbg_rst` 信号参与复位逻辑：`rst_async_n = sys_rst_n && (~dbg_rst) && clk_wiz_locked`。

### 自动化程序烧录与测试（auto_coremark.py）

一键完成：复位 → UART 下载程序 → 等待运行完成 → 解析输出结果。

```bash
cd SDK

# 跑全部 9 个 CoreMark 配置（GCC Os/O1/O2/O3 + LLVM Os/Oz/O1/O2/O3）
python tools/auto_coremark.py

# 只跑单个配置（按文件名匹配）
python tools/auto_coremark.py --config coremark_o2

# 指定串口和波特率
python tools/auto_coremark.py --port COM8 --baud 115200

# 指定 uartbin 文件目录
python tools/auto_coremark.py --data-dir D:/path/to/uartbin/files
```

输出示例：

```
============================================================
  Config: GCC O2
  File:   D:\...\test_data\soc\c\coremark_o2.uartbin
============================================================
  [1/4] Resetting FPGA...
  [2/4] Downloading program...
    Sending 22824 bytes (90 chunks)...
    Send complete.
  [3/4] Running CoreMark...
  [4/4] Parsing results...
    CoreMark/MHz:   2.7906
    Iterations/Sec: 223.2513
    Total ticks:    179170236
    Branch hit:     0.9756
```

运行前确保：COM 口未被其他程序（串口助手等）占用；Sipeed RV-Debugger 已插入 USB。

### 手动 UART 发送程序（uart_send.py）

将 .uartbin 文件通过串口下载到 FPGA（发送前需先复位，或加 `--reset` 自动复位）：

```bash
cd SDK

# 先复位再下载（推荐）
python tools/uart_send.py test_data/soc/c/coremark_o2.uartbin --reset

# 仅下载（需提前手动复位）
python tools/uart_send.py test_data/soc/c/coremark_o2.uartbin

# 指定串口
python tools/uart_send.py coremark_o2.uartbin --port COM8 --baud 115200
```

uartbin 文件格式（由 build.py 自动生成）：

```
START_FRAME (4B: 0xBBAABBAA)
ITCM_COUNT  (4B: uint32 LE, 字数)
ITCM_DATA   (ITCM_COUNT × 4B)
DTCM_COUNT  (4B: uint32 LE, 字数)
DTCM_DATA   (DTCM_COUNT × 4B)
```

### 手动 UART 发送命令/文本（uart_cmd.py）

向串口发送任意文本或原始字节：

```bash
cd SDK

# 发送文本（自动加换行）
python tools/uart_cmd.py "hello"

# 不加换行
python tools/uart_cmd.py "hello" --no-newline

# 发送原始十六进制字节
python tools/uart_cmd.py --hex "AA BB CC 01"

# 发送文件内容
python tools/uart_cmd.py --file cmd.txt
```

### 手动 UART 接收输出（uart_recv.py）

监听串口并实时打印到终端：

```bash
cd SDK

# 监听 30 秒（默认）
python tools/uart_recv.py

# 监听 60 秒
python tools/uart_recv.py --timeout 60

# 收到包含指定字符串后自动停止
python tools/uart_recv.py --until "CoreMark/MHz"
```

按 Ctrl+C 可随时中断。

### 将接收数据写入文件（uart_log.py）

监听串口并将输出保存到日志文件：

```bash
cd SDK

# 监听 30 秒，写入 output.log
python tools/uart_log.py output.log

# 监听 60 秒
python tools/uart_log.py result.txt --timeout 60

# 收到 "DONE" 后停止
python tools/uart_log.py log.txt --until "DONE"

# 追加模式（不覆盖已有内容）
python tools/uart_log.py log.txt --append

# 静默模式（只写文件，不打印到终端）
python tools/uart_log.py log.txt --quiet
```

### 典型组合用法

```bash
cd SDK

# 复位 → 下载 → 接收结果到文件（三条命令）
python tools/fpga_reset.py
python tools/uart_send.py test_data/soc/c/coremark_o2.uartbin
python tools/uart_log.py result.log --until "CoreMark/MHz" --timeout 30

# 或者一步到位（uart_send 自带 --reset）
python tools/uart_send.py test_data/soc/c/coremark_o2.uartbin --reset
python tools/uart_log.py result.log --until "CoreMark/MHz"

# 全自动 9 配置跑分（含复位+下载+解析+汇总）
python tools/auto_coremark.py 2>&1 | tee tools/coremark_results.log
```

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
