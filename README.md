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
- 数据观察点：复用 Trigger Module 4 路 tdata，支持 load/store 地址匹配（读/写观察点）与访问宽度过滤（sizelo），命中即 halt（store/load 不提交）；GDB `watch` 在线调试脚本已固化（`run_gdb_watchpoint.bat`）
- 完整调试回归：DMI 一键测试、GDB 全功能套件、真实 demo 符号级在线调试
- 动态分支预测器调试支持：单步模式下自动门控预测跳转，保证 PC 严格 +4 递增

## 已知限制

| 项目 | 说明 |
|------|------|
| 自修改代码（FENCE.I） | 不支持：FENCE.I 不刷新取指路径，`rv32ui-p-fence_i` 未通过（预期行为） |
| 非对齐访存 | 不支持：不产生 misaligned 异常，`rv32ui-p-ma_data` 未通过（预期行为） |
| Debug ROM / Park Loop | 未实现：采用 halt-in-place + 直接端口访问架构 |
| ProgBuf | 未实现（progbufsize=0），抽象命令不经程序缓冲执行 |
| 抽象内存访问（cmdtype=2） | 未实现：调试器内存访问走 SBA |
| 多 hart | 未实现：单 hart |
| 跟踪调试（trace） | 未实现：仅交互式调试（halt/step/断点/观察点） |
| 软件断点（GDB `break`） | 可设置/命中/单步越过/continue（OpenOCD 写 ebreak，需 `dcsr.ebreakm`），数量不受 4 路限制。OpenOCD 0.12 不声明 `swbreak` 特性，GDB 在 PC 位于断点地址时自动执行“删断点→单步→重插→继续”，实测 `continue` 可正常越过；回归脚本 `run_gdb_swbp_continue.bat`。若断点设在循环内反复调用的函数（如 `delay_ms`），continue 后再次命中是正常调试器行为（程序确实再次执行到该处，可观察 `$ra`/调用点区分） |
| SPI / I2C | 地址预留，未实现 |
| Flash / DDR | AXI 从机未实现，访问返回总线错误 |

## 快速开始

前置：安装 RISC-V 工具链、ModelSim、Python（见「环境依赖」）。

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

## 验证矩阵

| 类别 | 项目 | 结果 | 说明 |
|------|------|------|------|
| 仿真 | custom_asm 核级回归 | 通过 | tb_core_top + ModelSim |
| 仿真 | riscv-tests | 通过（fence_i/ma_data 未过） | 见「已知限制」 |
| 仿真 | Debug 模块回归（tb_debug） | 通过（93 项） | 无需板子 |
| 仿真 | 外设 PLIC / Timer / GPIO / UART | PASS | UART 含 NCO 位级 TX/RX 检查 |
| 仿真 | SoC CoreMark | 启动输出通过 | 完整 500 迭代 CRC 以上板为准 |
| 上板 | DMI 一键测试 | 通过 | `bd32_debug_test.cfg` |
| 上板 | 新功能专项 | 通过 | SBA 8/16-bit、双断点、ebreak |
| 上板 | SBA 外设总线 | 通过 | GPIO/UART/CLINT、sberror |
| 上板 | watchpoint | 通过 | `bd32_watchpoint_test.cfg` |
| 上板 | GDB 在线 watchpoint | PASS | `run_gdb_watchpoint.bat`（管道模式） |
| 上板 | GDB 套件 / demo 符号级调试 | PASS | 需 socket 环境（OpenOCD gdb server） |
| 上板 | 软/硬断点 continue 回归（S1–S5） | PASS | `run_gdb_swbp_continue.bat`（管道模式），含 hw bp 命中→reset→重插→continue 与软硬断点结合 |
| 上板 | CoreMark（多优化等级） | CRC 验证通过 | `auto_coremark.py` |

## 目录结构

```
./
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
│   ├── riscv-tests/          # 标准 riscv-tests .dat（rv32ui 42个 + rv32um 8个；fence_i/ma_data 已知不过）
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
│   │   ├── bd32_new_feat_test.cfg # 新功能专项：SBA 8/16bit、双断点、ebreak
│   │   ├── bd32_sba_periph.cfg    # SBA 外设总线上板测试
│   │   ├── bd32_debug_test.gdb    # GDB 全功能调试套件
│   │   ├── run_gdb_debug_test.bat # GDB 套件 runner
│   │   ├── bd32_demo_debug.gdb    # 真实 demo（breathing）在线调试脚本
│   │   ├── run_demo_debug.bat     # demo 调试 runner
│   │   ├── bd32_watchpoint_test.cfg  # 数据观察点上板测试
│   │   ├── bd32_watchpoint_test.gdb  # GDB 在线 watchpoint 脚本
│   │   ├── run_gdb_watchpoint.bat    # GDB watchpoint 管道模式 runner
│   │   ├── run_watchpoint_test.bat   # watchpoint TCL runner
│   │   └── bd32_clean_itcm.cfg       # ITCM 清理维护工具
│   ├── bsp/                  # 板级支持包（startup, drivers, trap, linker）
│   ├── demos/nolibc/         # 裸机 demo（breathing, blink, uart_echo, cpuinfo）
│   ├── demos/newlib/coremark/ # CoreMark 基准测试（build_O2/ + build_O3/）
│   └── isa/env/p/            # riscv_test.h + link.ld
├── BD32_SoC/                  # Vivado FPGA 工程（Xilinx）
├── ip_repo/                   # 自定义 AXI IP 仓库
└── doc/                       # 文档（架构/调试/外设/验证，见 doc/README.md）
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
| RISC-V GCC | xPack riscv-none-elf-gcc 15.2.0（`<工具链目录>/bin`，见 build.py 顶部 TOOLCHAIN） |
| Clang（可选） | LLVM 22.1.8（`<LLVM 目录>/bin/clang`，见 build.py 顶部 LLVM_BIN） |
| ModelSim | SE-64 2020.4（`<ModelSim 安装目录>/win64`，见各脚本顶部 VSIM_PATH） |
| Python | 3.x |
| Vivado | 2023.1（FPGA 综合） |

工具路径可用环境变量覆盖：`RISCV_TOOLCHAIN`（GCC 工具链）、`LLVM_BIN`（Clang）、`MODELSIM_PATH`（ModelSim）、`RISCV_GDB`（GDB）；未设置时使用各脚本内的默认值。

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

riscv-tests 回归已知限制：`rv32ui-p-fence_i` 与 `rv32ui-p-ma_data` 未通过——BD32 **不支持自修改代码**（FENCE.I 不刷新取指路径）与**非对齐访存**（不产生 misaligned 异常），其余通过，属预期行为。

判定约定：x26=1 表示完成，x27=1 表示通过；x3(gp) 记录失败的子测试编号。

#### SoC 级测试（tb_soc_top）

```bash
cd script/soc_test
# 编译
vlog -f filelist.f +define+DIRECT_LOAD
# 运行（CoreMark 启动后打印 "CoreMark running..." 即验证 CPU/UART 通路；
#   完整 500 迭代需约 2.4s 仿真时间，CRC 结果以上板验证为准）
vsim -c -voptargs=+acc tb_soc_top -do "run 55ms; quit -f"
```

UART 输出通过 TB 中的 `$write("%c", ...)` 打印到控制台。
添加 `+define+WB_TRACE` 可启用写回追踪（输出到 `wb_trace.log`）。

#### 外设独立仿真

各 `script/xxx_test/` 目录下双击 `top_tb.bat` 或命令行运行：
```bash
cd script/uart_test
<ModelSim 安装目录>\win64\modelsim -do run.do   # 或 modelsim -do run.do（已加入 PATH）
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

仿真配置：修改 `SoC_Config.sv` 中 `ITCM_FILE`/`DTCM_FILE` 为 `"coremark_o3_itcm.mem"`/`"coremark_o3_dtcm.mem"`（或 o2），仿真时长设为 55ms。

注意：默认固件为 500 次迭代的 performance run（板上约 2.34s），55ms 仿真仅能观察到启动输出（`CoreMark running...`）；完整 CRC 校验请以上板运行 `auto_coremark.py` 为准。

UART 配置机制：`soc_init()` 在启动时通过 `mcycle` vs CLINT `mtime`（10ms 窗口）实测 CPU 主频并写入 `g_cpu_freq_hz`，`uart_init()` 用该实测值计算 NCO FCW，不依赖编译期常量 `CPU_FREQ_HZ`（仅测量失败时回退）——换主频/改归一缩后 UART 自动适应。

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
| reset halt | 已验证 | `ndmreset` + haltreq 驻留，停在复位向量 |
| GPR / CSR 读写 | 已验证 | abstract command，regno 0x1000~0x101F / 0xC000\|csr 与 1.0 直接编码 |
| dcsr / dpc | 已验证 | dcsr 按 1.0 位域读回（debugver/cause/step/ebreakm） |
| SBA | 已验证 | 32-bit 地址，8/16/32-bit 写 + 32-bit 读，读写 ITCM/DTCM + 外设总线（APB） |
| 硬件断点 | 已验证 | 4 路 tdata1/tdata2（tselect 选择），mcontrol type=2 地址匹配，OpenOCD `hbreak` + GDB |
| 数据观察点 | 已验证 | load/store 地址匹配（tdata1 bit0/bit1）+ sizelo 宽度过滤（8/16/32-bit），命中 halt（dpc=访存指令、不提交），GDB `watch` |
| ebreak 进调试 | 已验证 | `dcsr.ebreakm=1` 时 ebreak 触发 halt，cause=1，dpc=ebreak 地址 |
| GDB 在线调试 | 已验证 | 真实 demo（breathing）符号级调试：加载/断点/单步/变量 |

未实现：Debug ROM / Park Loop、ProgBuf（progbufsize=0）、abstract 内存访问（cmdtype=2）、多 hart。

### 未实现能力说明（调试扩展点）

以下 Debug Spec 能力未实现。当前调试操作全部由 DM 硬件直连完成（GPR/CSR 直读、SBA 访存），无需 CPU 执行任何调试代码；列于此便于后续完善时对照。

| 能力 | 概念 | 当前影响 / 补充时机 |
|------|------|------|
| ProgBuf | DM 内小块 RAM（典型 1~16 字），调试器写入任意 RISC-V 指令，CPU 在 debug mode 下取指执行 | 无“任意代码注入”通道；flash 在线编程、复杂寄存器序列等需 CPU 执行的操作受限 |
| 抽象内存访问（cmdtype=2） | 调试器发抽象命令，由 CPU 自身执行一次 load/store，走 CPU 视角（PMP、地址翻译、CPU 私有存储） | SBA 仅总线视角；启用 PMP 或 CPU 私有存储后需补充 |
| 多 hart | 多核调试（dmcontrol.hasel / hart 选择） | 当前单 hart，不涉及 |

**Trigger 高级特性**（当前仅 4 路 mcontrol type=2 地址匹配）：

- priv 过滤（mcontrol6）：指定只在某特权级触发，避免 ISR 中同地址误命中；当前纯 M-mode 不受影响，增加 U/S-mode 后需要
- match 模式扩展：NAPOT 地址范围 / 大于小于 / 掩码匹配，一路 trigger 可覆盖一段地址区间
- chain：两路 trigger 条件“与”（如地址 + 数据值同时匹配）
- timing / hit 计数：第 N 次命中才触发（循环计数场景）
- icount（type=3）：执行 N 条指令后触发
- itrigger（type=4）/ etrigger（type=5）：中断 / 外部信号触发

**dcsr 控制位**（当前读回固定为 0）：

- `stepie`（单步时中断使能）：为 0 时单步不响应中断；为 1 时可单步进入中断处理流程
- `stopcount`：debug mode 下 mcycle / instret / 性能计数器停止，避免调试暂停计入性能测量
- `stoptime`：debug mode 下时间类计数器（mtime 等）停止

### Trigger Module（硬件断点）

DM 内部实现 4 路 trigger 寄存器组（tselect + 4×tdata1/tdata2），通过 abstract command 的 CSR 地址空间（0x7A0~0x7A3）访问：

- `tdata1` 复位值 = 0x2000_0000（type=2 mcontrol, dmode=0, 默认 disabled；dmode=0 避免 OpenOCD 0.12 枚举时清零导致 hbreak 失败）
- OpenOCD 通过 `hbreak *<addr>` 命令编程 tdata2 = 目标地址，置 tdata1[2]（execute match enable）；tselect 越界写自动钳位，用于枚举 trigger 数量（4 路）
- CPU 侧多路并行比较 `trigger_hit = |(trigger_en[i] & (inst_addr_if == trigger_addr[i]))`，命中后触发 halt
- **trigger halt 锁存**：命中时 DM 自动拉高 haltreq，删除断点（清 tdata1）不会让 CPU 自动恢复运行，直到调试器发 `resumereq`
- **ebreak 进调试**：`dcsr.ebreakm=1` 时 ID 级 ebreak 不产生异常，CPU 原地 halt（ID 保持、不冲刷），DM 锁存 haltreq 并置 `dcsr.cause=1`、`dpc=ebreak 地址`；调试器恢复原指令后 resume 即可继续执行（软件断点通路）
- **数据观察点**：EX 级访存有效地址匹配（tdata2），tdata1[0]=load（读观察点）/ tdata1[1]=store（写观察点），sizelo[17:16] 过滤访问宽度（0=任意、1=8bit、2=16bit、3=32bit）；命中时流水线停在 EX、store/load 不落盘（总线请求被抑制），`dpc` 取访存指令自身、`dcsr.cause=2`；清 trigger 后 resume 才完成访问

### OpenOCD + GDB 使用（调试功能使用手册）

#### 1. 准备工作

**硬件与驱动**

| 项目 | 说明 |
|------|------|
| 板卡 | 烧录含调试子系统的 bitstream（`BD32_DEBUG_EN` 宏开启，`rtl/Debug/` 例化） |
| 调试器 | Sipeed RV-Debugger（FT2232H），Channel A 四线 JTAG：TCK / TDI / TDO / TMS + GND |
| 驱动 | FT2232H Channel A 需绑定 WinUSB（Zadig），否则 libusb 无法访问；与 Vivado hw_server 冲突时先关闭 Hardware Target |
| 速率 | 杜邦线连接时 `adapter speed 500`（`bd32_openocd.cfg` 已配置），正式 PCB 可提高 |

**工具链**

- OpenOCD（xPack 0.12.0+dev）：`./SDK/tools/xpack-openocd-0.12.0-7/bin/openocd.exe`
- GDB（xPack GDB 16.3）：`<xPack 工具链>/bin/riscv-none-elf-gdb.exe`
- 目标程序 ELF：如 `./SDK/demos/nolibc/breathing/build/breathing.elf`

**启动 OpenOCD**（默认开 gdb 3333 / telnet 4444 / tcl 6666 端口）：

```bash
.\SDK\tools\xpack-openocd-0.12.0-7\bin\openocd.exe -f .\SDK\tools\bd32_openocd.cfg
```

正常日志应出现 `tap/device found: 0x1bd32003`。随后启动 GDB：

```bash
<xPack 工具链>/bin/riscv-none-elf-gdb.exe program.elf
(gdb) target extended-remote :3333
```

若当前环境无法创建 TCP socket（如受限 shell / 沙箱），可改用**管道模式**：GDB 直接拉起 OpenOCD，通过 stdin/stdout 走 GDB Remote 协议，不依赖 3333 端口（`run_gdb_watchpoint.bat` 即此方式）：

```text
(gdb) target extended-remote | .../openocd.exe -c "gdb port pipe" -f .../bd32_openocd.cfg
```

#### 2. 基本控制：halt / resume / reset halt / 单步

| 功能 | GDB 命令 | 机制与预期 |
|------|----------|------------|
| 暂停 | `monitor halt` | `dmcontrol.haltreq=1`，流水线全级 stall + flush，CPU 原地冻结；dpc = 当前 PC |
| 继续 | `monitor resume` / `continue` | 清 haltreq 后从 dpc 取指继续执行 |
| 复位并暂停 | `monitor reset halt` | `ndmreset` 复位 SoC，haltreq 驻留，复位释放后停在复位向量 PC = 0x0 |
| 单步 | `stepi` | `dcsr.step=1`，执行 1 条指令后重新 halt；单步时门控分支预测，保证 PC 严格 +4 |

示例：

```bash
(gdb) monitor reset halt     # 停在 0x0（BootROM 起点）
(gdb) stepi                  # 每条指令 PC+4
(gdb) p/x $pc
```

#### 3. 寄存器访问（GPR / CSR）

halt 后通过 abstract command 直连 RegFile / CSR 专用端口，不经 CPU 执行任何调试代码：

```bash
(gdb) info registers         # 全部 GPR
(gdb) p/x $a0                # 读 x10
(gdb) set $a0 = 0x12345678   # 写 x10，再 p/x $a0 读回验证
(gdb) p/x $mstatus           # 读 CSR（abstract 通路）
(gdb) p/x $mtvec
(gdb) p/x $dcsr              # dcsr 按 1.0 位域读回
(gdb) p/x $dpc               # 停顿时 PC（断点/ebreak 命中时指向命中指令）
```

#### 4. 内存访问（SBA）

halt 期间通过 SBA 访问整个 SoC 地址空间（32-bit 地址；读为 32-bit，写支持 8/16/32-bit）：

```bash
(gdb) x/4wx 0x10000                          # 读 ITCM
(gdb) set {int}0x20000 = 0xdeadbeef          # 32-bit 写 DTCM
(gdb) set {char}0x20000 = 0x11               # 8-bit 写（RMW 合并）
(gdb) set {short}0x20002 = 0x1234            # 16-bit 写
(gdb) x/1wx 0x20000
```

可访问区域（与 SoC 内存映射一致）：

| 区域 | 地址 | 说明 |
|------|------|------|
| BootROM | 0x0000_0000 | 只读（SBA 子字读不误报 sberror） |
| ITCM | 0x0001_0000 | 代码段，可读写 |
| DTCM | 0x0002_0000 | 数据段，可读写 |
| GPIO | 0xE000_0000 | APB 外设（OUTPUT 0xE000_0008） |
| UART | 0xE001_0000 | APB 外设（LSR 0xE001_0014） |
| Timer / SPI / I2C | 0xE002_0000 / 0xE003_0000 / 0xE004_0000 | APB 外设 |
| CLINT | 0xF200_0000 | APB 外设（mtime 0xF200_BFF8） |
| PLIC | 0xFC00_0000 | APB 外设 |

访问未映射地址（如 0x12345678）时 SBA 置 `sberror`（sbcs[14:12]=2）并读回 0，halt 状态保持，可继续调试。

#### 5. 硬件断点（hbreak，4 路 Trigger）

```bash
(gdb) hbreak *0x10204        # 编程 tdata2=地址、tdata1 置 execute 使能
(gdb) continue
(gdb) p/x $pc                # 命中后停在 0x10204（dpc = 断点地址）
(gdb) info breakpoints
(gdb) delete breakpoints     # 清断点后需 resume 才恢复运行
```

要点：

- 4 路 mcontrol trigger（tselect 0~3）自动分配，可同时下多个 `hbreak` 形成多断点，命中后逐个 `delete` 再 `resume`。
- **命中锁存**：trigger 命中时 DM 自动锁存 haltreq；删除断点不会自动恢复运行，必须显式 resume。
- **不要断在当前 PC**：trigger halt 后 dpc = 命中地址，resume 从 dpc 重新取指，若断点仍在同一地址会再次命中而卡死（OpenOCD 报 unable to resume）。上板测试用"NOP 滑道 + 断点设在下一地址"规避。
- tdata1 复位值 0x2000_0000（type=2、dmode=0、disabled）；dmode=0 避免 OpenOCD 0.12 枚举 trigger 时清零导致 hbreak 失效。

#### 6. 数据观察点（watch，load/store 地址匹配）

```bash
(gdb) watch *(int*)0x20000   # 观察 DTCM 0x20000
(gdb) continue
(gdb) p/x $pc                # 命中：停在访存指令（dpc = load/store 自身）
(gdb) p/x *(int*)0x20000     # store 观察点：新值尚未落盘，读到旧值
(gdb) delete breakpoints
(gdb) continue               # 清观察点后 resume，该次访问才完成
```

要点：

- tdata1[0]=load（读观察点）、[1]=store（写观察点）、[2]=execute（断点）；sizelo[17:16] 过滤访问宽度：0=任意、1=8bit、2=16bit、3=32bit。例如只监视 32-bit 访问时，sb（8bit）不命中、sw（32bit）命中。
- 命中时流水线停在 EX：store 不落盘 / load 不写回（总线请求被抑制），dcsr.cause=2；清除观察点后 resume 才完成该访问。

#### 7. ebreak 进调试模式（软件断点通路）

`dcsr.ebreakm=1` 时 ebreak 指令不产生异常，CPU 原地 halt（ID 保持不冲刷），`dcsr.cause=1`、`dpc = ebreak 地址`，DM 锁存 haltreq。

手动软件断点：用 SBA 把目标指令临时替换为 ebreak（0x0010_0073），命中后恢复原指令再 resume：

```bash
(gdb) set {int}0x10200 = 0x00100073   # 写 ebreak
(gdb) set $pc = 0x10200
(gdb) continue                        # 命中：cause=1，dpc=0x10200
(gdb) set {int}0x10200 = 0x00000013   # 恢复原指令（NOP）
(gdb) continue
```

GDB 的软件断点命令（`break`）完整可用：OpenOCD 把 ebreak 写入目标地址（自动设置 `dcsr.ebreakm`），可设置、命中、`stepi` 单步越过、`continue` 继续运行。OpenOCD 0.12 不声明 `swbreak` 特性，GDB 在 PC 位于软件断点地址时自动执行“删断点→单步→重插→继续”，因此 `continue` 不会原地重命中；回归脚本 `run_gdb_swbp_continue.bat`。注意：若断点设在循环内被反复调用的函数（如 `delay_ms`/`uart_init`），continue 后再次停在同地址属正常现象（程序确实再次执行到该处），可通过 `$ra`/`$sp` 与调用点确认，并非无法越过。数量不受 4 路限制；上述手动替换 ebreak 的方式仍然可用。

#### 8. 真实 demo 符号级调试（breathing）

```bash
(gdb) file ./SDK/demos/nolibc/breathing/build/breathing.elf
(gdb) target extended-remote :3333
(gdb) monitor reset halt
(gdb) load                          # SBA 写入 ITCM/DTCM
(gdb) set $pc = 0x10000             # 程序入口
(gdb) hbreak main                 # 符号断点（重建后地址自动跟随）
(gdb) continue
(gdb) stepi
(gdb) print <变量名>
```

`bd32_demo_debug.gdb` 已固化该流程（hbreak main、单步、全局变量 / .data / mtime 读取）。

**C 语言级调试**：用 `build.py --debug` 重建固件后，除了符号断点 + `stepi`，还可以源码行 `next`/查看变量（`run_gdb_c_debug.bat` 一键验证）。硬件断点最多 4 路（同时最多 4 个 hbreak）；多次 `next` 依赖触发槽可复用，需 bitstream 含 tdata1 修复（type=0 写入 -> 0x20000000）。

#### 9. OpenOCD TCL 直接操作（DMI 寄存器级）

不经过 GDB，直接用 OpenOCD 的 RISC-V 命令读写 DMI 寄存器（`bd32_debug_test.cfg`、`bd32_watchpoint_test.cfg` 等测试脚本即此类用法）。交互模式：启动 OpenOCD 后 `telnet localhost 4444`；批处理：`openocd -f xxx.cfg`（测试脚本内 telnet/gdb/tcl 端口均 disabled，避免 socket）。

常用命令：

```text
halt / resume / step / reg / reset halt
bd32.cpu riscv dmi_read <addr>
bd32.cpu riscv dmi_write <addr> <val>
```

**DMI 寄存器地址**（Debug Spec 0.13 布局）：

| 地址 | 寄存器 | 说明 |
|------|--------|------|
| 0x04 | data0 | abstract command 数据 |
| 0x10 | dmcontrol | bit0=dmactive、bit1=ndmreset、bit30=resumereq、bit31=haltreq、[25:16]=hartsel |
| 0x11 | dmstatus | bit8=anyhalted、bit9=allhalted、bit11=allrunning |
| 0x16 | abstractcs | bit11=busy、[9:7]=cmderr |
| 0x17 | command | aarsize[23:20]（0=8/1=16/2=32bit）、transfer[17]、write[16]、regno[15:0] |
| 0x38 | sbcs | [19:17]=sbaccess（0=8/1=16/2=32bit）、[20]=sbreadonaddr、[16]=sbautoincrement、[15]=sbreadondata、[14:12]=sberror、[21]=sbbusy、[22]=sbbusyerror |
| 0x39 | sbaddress0 | SBA 地址 |
| 0x3c | sbdata0 | SBA 数据 |

**Abstract command 的 regno 编码**：

- GPR：`0x1000|n`（n=0~31）
- DM 内部寄存器：`0x7A0`=tselect、`0x7A1`=tdata1、`0x7A2`=tdata2、`0x7B0`=dcsr、`0x7B1`=dpc、`0x7B2`=dscratch0
- CPU CSR：`0xC000|csr`（0.13 风格）或 `0x0000|csr`（1.0 直接编码）

读写示例（与上板验证脚本一致）：

```text
# 读 x10：command=0x0022_100A（aarsize=2=32bit、transfer=1、regno=0x100A），再读 data0
dmi_write 0x17 0x0022100A
dmi_read  0x04

# 写 x10=0x12345678：先写 data0，再 command=0x0023_100A（transfer+write）
dmi_write 0x04 0x12345678
dmi_write 0x17 0x0023100A

# 读 mstatus（CSR 0x300）：command=0x0022_C300
# 读 dcsr：0x0022_07B0；读 dpc：0x0022_07B1
# 写 dpc：先写 data0，再 command=0x0023_07B1
```

**SBA 访问示例**：

```text
# 32-bit 写 DTCM 0x20000 = 0xDEADBEEF
dmi_write 0x38 0x00040000   # sbaccess=2（32bit）
dmi_write 0x39 0x00020000   # 地址
dmi_write 0x3c 0xDEADBEEF   # 数据

# 32-bit 读（sbreadonaddr=1，写地址后自动发起读）
dmi_write 0x38 0x00140000
dmi_write 0x39 0x00020000
dmi_read  0x3c

# 8-bit 写：sbcs=0x00000；16-bit 写：0x00020000
# 未映射地址：sbcs[14:12] sberror=2
```

**Trigger 编程示例**（4 路，tselect 越界写自动钳位到 3）：

```text
# 选择 trigger0，写断点 0x10204
dmi_write 0x04 0x00000000 ; dmi_write 0x17 0x002307A0   # tselect=0
dmi_write 0x04 0x28000004 ; dmi_write 0x17 0x002307A1   # tdata1: type=2、dmode=1、execute
dmi_write 0x04 0x00010204 ; dmi_write 0x17 0x002307A2   # tdata2=断点地址

# 数据观察点 tdata1：0x2800_0002=store、0x2800_0001=load、0x2803_0002=store+仅32bit
# 清除：tdata1=0x2800_0000（type=2、无使能）
```

tdata1 位域：`[31:28]=type(2=mcontrol)`、`[27]=dmode`、`[17:16]=sizelo`、`[2]=execute`、`[1]=store`、`[0]=load`。

dcsr 位域（1.0 布局）：`[31:28]=debugver(4)`、`[15]=ebreakm`、`[8:6]=cause`（1=ebreak、2=trigger、3=haltreq、4=step、5=resethaltreq）、`[2]=step`。

#### 10. 一键回归脚本

SDK/tools/ 下所有脚本输出统一到仓库根 `logs/` 目录（已加入 .gitignore）：

| 脚本 | 内容 | 结果文件 |
|------|------|----------|
| `bd32_debug_test.cfg`（OpenOCD 直接运行） | DMI 全功能：JTAG、halt/PC、GPR/CSR、单步、SBA、Trigger、reset halt | 终端输出 |
| `bd32_new_feat_test.cfg`（OpenOCD 直接运行） | 新功能专项：SBA 8/16-bit 写、双硬件断点（tselect0/1 依次命中）、ebreak 进调试 | 终端输出 |
| `bd32_sba_periph.cfg`（OpenOCD 直接运行） | SBA 外设总线：GPIO/UART/CLINT 读写、字节使能、未映射 sberror、halt 保持 | 终端输出 |
| `run_gdb_debug_test.bat` | GDB 全功能套件：reset halt、寄存器/CSR、单步、内存读写、hbreak（socket 模式） | `logs/gdb_test_result.txt` |
| `run_demo_debug.bat` | 真实 demo（breathing）符号级调试：加载、hbreak main、单步、变量（socket 模式） | `logs/demo_debug_result.txt` |
| `bd32_watchpoint_test.cfg`（OpenOCD 直接运行） | 数据观察点上板测试：写/读观察点命中、宽度过滤、无访问不误命中 | 终端输出 |
| `run_watchpoint_test.bat` | watchpoint TCL 测试包装 | `logs/watchpoint_test.log` |
| `run_gdb_watchpoint.bat` | GDB 在线 watchpoint（管道模式，无需 socket） | `logs/gdb_watchpoint_result.txt` |
| `run_gdb_c_debug.bat` | GDB C 语言级调试：hbreak main → continue → 源码行 next → 变量，及软件断点（break）命中验证（自动 --debug --opt O0 重建） | `logs/gdb_c_debug_result.txt` |
| `run_gdb_swbp_continue.bat` | GDB 软件断点 continue 回归：直接 continue 越过软件断点、stepi 后 continue、与 hbreak 结合使用（管道模式，无需 socket） | `logs/gdb_swbp_continue_result.txt` |
| `bd32_clean_itcm.cfg`（OpenOCD 直接运行） | 维护工具：将 ITCM 0x10200~0x10300 写回 NOP，清理探针/自循环残留 | 终端输出 |
| `run_msim_debug.bat`（script/debug_test/） | ModelSim 回归（tb_debug，无需板子） | `logs/msim_out.txt` |

```bash
# 正常环境直接运行：
openocd -f ./SDK/tools/bd32_debug_test.cfg
openocd -f ./SDK/tools/bd32_new_feat_test.cfg
openocd -f ./SDK/tools/bd32_sba_periph.cfg
openocd -f ./SDK/tools/bd32_watchpoint_test.cfg
./SDK/tools/run_watchpoint_test.bat
./SDK/tools/run_gdb_watchpoint.bat
./SDK/tools/run_gdb_debug_test.bat
./SDK/tools/run_demo_debug.bat
./script/debug_test/run_msim_debug.bat
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
# 一键回归（-batch 无界面模式，不依赖 Winsock；从 script/debug_test 运行，
# 保证 SoC_Config.sv 中 ../../test_data 相对路径正确解析 mrom.dat / .mem）：
./script/debug_test/run_msim_debug.bat
# 结果：logs/msim_out.txt（进度标记 logs/msim_mark.txt）

# 交互式波形调试：
cd ./script/debug_test
vsim -do run.do
```

Testbench `sim/tb_debug.sv` 通过 DMI 接口直接激励 DM，无需 JTAG 物理连接，覆盖：
- Test 1~12：IDCODE、halt/resume、GPR/CSR 读写、SBA、单步
- Test 13：reset halt（停在复位向量）
- Test 14：reset halt 后改 dpc 再 resume 的取指对齐（`resume_hold` 回归）
- Test 15：trigger halt 锁存（清断点后 CPU 保持 halt）
- Test 16：ebreak 进调试模式（halt / cause=1 / dpc / 锁存 / resume 后正确执行）
- Test 17：多硬件断点（tselect 选择，双断点依次命中，逐个清除）
- Test 18：SBA 字节/半字写（ITCM/DTCM RMW 合并验证）
- Test 19：SBA 外设总线访问（APB GPIO 0xE000_0000 读写）
- Test 20：数据观察点（load/store 地址匹配 + 宽度过滤）
- Test 22：SBA 读 BootROM（0x0 区，GDB/OpenOCD 在线 stop 判定路径）+ BootROM 只读写保护
- Test 23：reset halt（CPU 停 0x0）后 2 字节 SBA 读 BootROM，验证子字读不误报 sberror

上板验证（2026-08-06/07 新 bitstream）全部通过：
- DMI 一键测试（`bd32_debug_test.cfg`，OpenOCD 枚举识别 4 个 trigger）
- GDB 套件（`run_gdb_debug_test.bat`：reset halt / 单步 / GPR / CSR / SBA / hbreak）
- 真实 demo（breathing.elf）符号级调试（`run_demo_debug.bat`）
- 新功能专项（`bd32_new_feat_test.cfg`：SBA 8/16-bit 写、双硬件断点、ebreak 进调试模式）
- SBA 外设总线（`bd32_sba_periph.cfg`：SBA 访问 GPIO/UART/CLINT 外设、字节使能、未映射 sberror、halt 保持）
- 数据观察点（`bd32_watchpoint_test.cfg`：写/读观察点、宽度过滤、无访问不误命中）
- GDB 在线数据观察点（`run_gdb_watchpoint.bat`：watch 0x20000 → continue → 命中停止，SBA 读 BootROM 判定路径完整）

当前回归结果：**ModelSim 仿真全部通过**；上板 DMI、新功能、外设 SBA、watchpoint、GDB 在线 watchpoint 全部 PASS。

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

注意：fpga_reset.py 默认通过 OpenOCD 驱动 FTDI ADBUS5 实现复位（参考 E203 SDK openocd_evalsoc.cfg，配置见 `bd32_reset.cfg`），**WinUSB 模式即可，无需切换驱动**。仅 `--assert/--release`（跨会话保持复位）才需要 ftd2xx（FTDI VCP 驱动，与 OpenOCD/WinUSB 互斥）。日常流程（复位 → UART 下载 → 调试）保持 WinUSB 即可。

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
python tools/auto_coremark.py --data-dir <uartbin 文件目录>
```

输出示例：

```
============================================================
  Config: GCC O2
  File:   <工作目录>\test_data\soc\c\coremark_o2.uartbin
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

uartbin 文件格式（由 build.py 自动生成，完整协议见下文「下载协议」节）：

```
START_FRAME (4B: 0xBBAABBAA, 小端) → ITCM_COUNT (4B LE) → ITCM_DATA → DTCM_COUNT (4B LE) → DTCM_DATA
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
| `--debug` | 启用 `-g` 调试信息（GDB 源码级单步/查看变量，需 GDB 在线调试） |
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
bash test_data/soc/build_mrom.sh
```

MROM（0x00000000，4KB）负责：设置 mcounteren → 测量 CPU 主频 → 计算 UART NCO 系数 → 跳转 ITCM 执行用户程序。

## uartbin 下载协议

由 `build.py` 生成（ELF `.text` → ITCM 段，`.data + .rodata` → DTCM 段），经串口由 BootROM 下载模式接收（MROM 读 GPIO[0]=1 后置 `DBG_EN=1`），写入 ITCM/DTCM 后跳转运行。

帧结构（无地址字段、无结束帧，纯计数协议，避免数据内容与帧标记冲突）：

| 字段 | 字节数 | 说明 |
|------|------|------|
| START_FRAME | 4 | 帧头 `0xBBAABBAA`（小端字节序发送：AA BB AA BB） |
| ITCM_COUNT | 4 | uint32 LE，ITCM 数据字数 |
| ITCM_DATA | ITCM_COUNT×4 | 依次写入 ITCM，起始地址 `0x0001_0000`，每字地址 +4 |
| DTCM_COUNT | 4 | uint32 LE，DTCM 数据字数（=0 表示无 DTCM 段） |
| DTCM_DATA | DTCM_COUNT×4 | 依次写入 DTCM，起始地址 `0x0002_0000`，每字地址 +4 |

要点：
- 所有 32 位字段均为**小端字节序**（LSB 先发），接收端按 `{new_byte, old[31:8]}` 左移拼装，第 4 字节到达时完成帧头检测。
- `DTCM_COUNT == 0` 时跳过 DTCM 段，直接进入运行。
- 下载完成后 UART `DBG_STAT[0]`（0x20）置 1，MROM 轮询到后点亮 LED 并跳转 ITCM（0x10000）运行。
- 下载仅在上电处于下载模式时生效（GPIO[0]=1）；正常模式（GPIO[0]=0）跳过下载直接运行 ITCM。

生成示例（build.py）：`struct.pack('<I', 0xBBAABBAA)` 为帧头；ITCM 数据取自 ELF `.text`，DTCM 数据取自 `.data` + `.rodata`。

## 常见问题

**Q: 编译报错 `riscv-none-elf-gcc: command not found`**
检查 xPack 工具链路径是否正确（`build.py` 顶部 `TOOLCHAIN` 配置）。

**Q: ModelSim 找不到 `vsim`**
确认 ModelSim 路径正确（各脚本顶部 `VSIM_PATH` 或系统 PATH 配置）。

**Q: 仿真时 ITCM 全 X，CPU 不运行**
确保 vlog 编译时传入 `+define+DIRECT_LOAD`。

**Q: CoreMark 仿真输出不完整**
CoreMark 为 500 次迭代的 performance run，完整 CRC 输出需约 2.4s 仿真时间（55ms 只能看到启动输出 `CoreMark running...`）；完整验证请上板运行。

**Q: 修改 SoC_Config.sv 后其他测试异常**
`ITCM_FILE`/`DTCM_FILE` 是全局宏，改完后记得恢复默认值。

**Q: `--clang` 链接报错找不到 `libclang_rt.builtins.a`**
预期行为。链接阶段一律走 xPack GCC，不要加 `-fuse-ld=lld`。
