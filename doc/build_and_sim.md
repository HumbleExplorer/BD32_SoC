# 构建与仿真

> 本页内容自 README 迁移整理，覆盖环境依赖、测试构建、仿真运行、CoreMark 与 Spike 差分测试。


## 环境依赖与第三方工具

以下工具用于本项目的构建、仿真与调试，**不随源码分发**，各自版权与许可证归其所属项目；请从官方渠道下载对应版本。

| 工具 | 用途 | 版本/路径 | 许可证 | 环境变量 |
|------|------|-----------|--------|----------|
| xPack RISC-V GCC | 固件编译（riscv-none-elf-gcc） | 15.2.0（`<工具链目录>/bin`，见 build.py 顶部 TOOLCHAIN） | GPL-3.0（工具链） | `RISCV_TOOLCHAIN` |
| LLVM/Clang（可选） | 固件编译 | 22.1.8（`<LLVM 目录>/bin`，见 build.py 顶部 LLVM_BIN） | Apache-2.0（工具链） | `LLVM_BIN` |
| ModelSim | RTL 仿真 | SE-64 2020.4（`<ModelSim 安装目录>/win64`，见各脚本顶部 MODELSIM_PATH） | Siemens EULA | `MODELSIM_PATH` |
| GDB | JTAG 在线调试 | `<工具链目录>/bin/riscv-none-elf-gdb`（随 xPack GCC 工具链） | GPL-3.0（工具链） | `RISCV_GDB` |
| OpenOCD | JTAG 在线调试（xPack 发行版） | 0.12.0（`SDK/tools/xpack-openocd-0.12.0-7/bin`，本体需单独下载） | GPL-2.0 | — |
| Xilinx Vivado | FPGA 综合/实现/烧录 | 2023.1 | Xilinx EULA（WebPACK 免费版可用） | — |
| Python | 脚本/自动化 | 3.x | PSF License | — |

工具路径可用环境变量覆盖：`RISCV_TOOLCHAIN`、`LLVM_BIN`、`MODELSIM_PATH`、`RISCV_GDB`；未设置时使用各脚本内的默认值。仓库内的 `SDK/tools/*.cfg` 为自研 OpenOCD 配置，随项目以 Apache-2.0 发布。

目标架构：`-march=rv32im_zicsr -mabi=ilp32`

## 构建自定义汇编测试

```bash
cd test_data/custom_asm
python build_asm.py <test_name>    # 单个测试
python build_asm.py all            # 全部 36 个测试
```

编译参数：`-march=rv32im -mabi=ilp32 -O0 -mno-relax -nostdlib -static`
产物：`.elf`、`.dump`、`.dat`（readmemh 格式）

## 构建 C 程序 / CoreMark

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

## 内存布局

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

## 运行仿真

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

## script/ 目录脚本索引

`script/` 集中存放仿真验证脚本；`SDK/` 只用于软件程序与上板工具。

**script/ 根目录（工具脚本）**

| 脚本 | 用途 | 用法 |
|------|------|------|
| `run_one.py` | 运行单个 custom_asm 测试 | `cd script && python run_one.py <test_name>` |
| `run_all_custom_asm.py` | custom_asm 全回归（tb_core_top） | `cd script && python run_all_custom_asm.py` |
| `run_all_riscv_tests.py` | riscv-tests ISA 兼容性回归（tb_core_top） | `cd script && python run_all_riscv_tests.py` |
| `cleanup_temp.py` | 清理 ModelSim work 库、transcript/*.log/wlftrs*/vsim.wlf/modelsim.ini、`__pycache__`、logs/ | `cd script && python cleanup_temp.py [--apply] [--keep-logs]`（默认 dry-run） |
| `run_periph_regression.bat` | 外设四合一 headless 回归（UART/GPIO/PLIC/Timer），输出 `logs/*_test_out.txt` | 直接运行，或任务计划程序（本机） |
| `run_soc_test.bat` | SoC headless 仿真（tb_soc_top，CoreMark 启动），输出 `logs/soc_test_out.txt` | 直接运行，或任务计划程序（本机） |

**script/<test>/ 仿真脚本**（每个测试目录含 `run.do` + `top_tb.bat` + `filelist.f` + `wave.do`）：

| 目录 | 测试对象 | 脚本 | 说明 |
|------|----------|------|------|
| `core_test/` | 核级 tb_core_top | `run.do`（GUI）；`core_run_batch.do`（batch）；`top_tb.bat`（GUI 启动） | custom_asm / riscv-tests 由根目录 Python 脚本驱动 |
| `debug_test/` | 调试模块 tb_debug | `run.do`（GUI）；`run_msim_debug.bat`（headless 回归，输出 `logs/msim_out.txt`）；`run_batch2.do` | Debug Spec 全功能 93 项回归 |
| `soc_test/` | SoC 级 tb_soc_top | `run.do`（主仿真）；`run_diag.do`（MROM 启动诊断）；`run_reset_test.do` / `run_reset_fast.do`（复位后重新下载）；`run_bus_timeout_test.do` / `run_bus_timeout_fast.do`（总线超时） | 各自带波形配置，batch 场景加 `quit -f` |
| `gpio_test/` `plic_test/` `timer_test/` `uart_test/` | 外设独立 tb_apb_* | `run.do`（GUI）；`top_tb.bat` | 独立于CPU的外设仿真 |

说明：
- `run.do` 第一行统一用 `file delete -force work` 清理旧库，不依赖 `vdel`/`modelsim.ini`，避免 GUI 锁库时报错。
- 本机 exec 环境 Winsock 受限，vsim 必须通过任务计划程序运行（见「OpenOCD + GDB 使用」章节说明）；`vlog`/`vopt` 可直接执行。
- 涉及 ModelSim 的批处理脚本输出统一重定向到仓库根 `logs/`（已加入 .gitignore）。

## CoreMark 基准

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

## Spike Diff-Test（差分测试）

使用 Spike ISA 模拟器作为黄金参考，与 RTL 仿真结果逐条对比写回序列，定位流水线功能 bug。

#### 环境

建议在 WSL（或任意 Linux 环境）中通过发行版软件源安装 Spike 与 dtc，确保 `spike`、`dtc` 在 `PATH` 中；若为本地构建，将安装目录加入 `PATH` 即可。

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
