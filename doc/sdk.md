# SDK 构建工具与协议

> 本页内容自 README 迁移整理，覆盖 build.py、riscv-tests 构建、LLVM 集成、MROM 构建与 uartbin 下载协议。


## build.py — 主构建脚本

路径：`SDK/tools/build.py`

| 参数 | 说明 |
|------|------|
| `source` | demo 目录或 .c 文件路径 |
| `--newlib` | 链接 newlib-nano（支持 printf/malloc） |
| `--no-bin` | 跳过 .mem/.uartbin 生成 |
| `--opt O2` | 优化等级（默认 Os） |
| `--rvc` | 启用 C 压缩指令扩展（`-march=rv32imc_zicsr`；需 RTL 支持 RV32C，`rv32uc-p-rvc` 已通过） |
| `--zcb` | 启用 Zcb 压缩字节/半字子扩展（隐含 --rvc；`-march=rv32imc_zcb_zicsr`，需 RTL 已支持 Zcb） |
| `--zbb` | 启用 Zba+Zbb+Zbs 位操作扩展（`-march` 追加 `_zba_zbb_zbs`，可与 --rvc/--zcb/--zcmp 组合） |
| `--zcmp` | 启用 Zcmp 压缩堆栈操作扩展（隐含 --rvc；`-march` 追加 `_zcmp`，可与 --zcb/--zbb 组合） |
| `--clang` | 用 Clang 做前端代码生成（链接仍走 GCC） |
| `--clang-extra "..."` | 只传给 Clang .c 编译的附加参数（如 `-mllvm -enable-machine-outliner=0`；不会污染 GCC 汇编步骤） |
| `--ld-extra "..."` | 只传给链接阶段的附加参数（如 `-Wl,--icf=all`） |
| `--lld` | 用 LLVM LLD 链接（`--icf=all` 折叠相同代码；配合 `--clang` 额外启用 LTO，体积更小） |
| `--picolibc` | 链接 picolibc（整数程序体积更小；需先运行 `build_picolibc.bat` 构建） |
| `--picolibc-printf i/f/d` | picolibc printf 档位：`i` 整数（默认，最小）/ `f` 浮点 / `d` double（需对应档位已构建） |
| `--debug` | 启用 `-g` 调试信息（GDB 源码级单步/查看变量，需 GDB 在线调试） |
| `--extra "-DFLAG"` | 追加编译标志 |
| `--rtthread` | RT-Thread 模式（自动启用 newlib-nano 链接，编译 `bsp/rtthread*` 与 `third_party/` 内核） |
| `--rtthread-version 51` | RT-Thread 内核版本：默认 `315`（lts-v3.1.x）/ `51`（v5.1.0） |
| `--irq-mode unified` | RT-Thread 中断模式：默认 `ch32`（轻量入口 + 软件中断延迟切换）/ `unified`（统一入口，全量保存 + 直接切换） |

编译流程：AS start.S → CC board/init.c → CC drivers → CC trap → CC main.c → LD → OBJDUMP → 生成 .mem/.uartbin

## update_mrom.py — BootROM 一键更新（改 mrom.s 后必用）

改 `test_data/soc/mrom.s` 后**禁止只跑裸 as**——`call` 的 auipc+jalr 重定位需要链接器解析，跳过 ld 会留下 delta=0 自跳转死循环。两步：

```bash
cd SDK
tools\update_mrom_build.bat              # 1) gcc 完整链接 → mrom.elf + objdump 跳转检查
python tools/update_mrom.py             # 2) 解析 ELF → 校验 → 生成 mrom.dat + mrom.coe
```

要点：
- 第 2 步同时产出 `mrom.dat`（仿真用）与 `mrom.coe`（Vivado IP 用）；
- 校验规则（默认模式）：发现 mrom 引用了设计中已移除的 CSR、程序指针切进 ELF 头、或有链接器没解析掉的跳转，都会**报错退出、不产出文件**（防止把坏 BootROM 烧进板子）。

## build_run.py — 一键构建 + 上板运行

一条命令完成 **构建 → 复位 FPGA → UART 下载 → 监听运行输出**（板子需已连接，SDK/ 目录下执行）：

```bash
cd SDK

# 构建 hello（newlib-nano）→ 复位 → 下载 → 监听，输出空闲 3 秒即停
python tools/build_run.py demos/newlib/hello --newlib

# RT-Thread（默认 lts-v3.1.x；--irq-mode unified 切统一入口）
python tools/build_run.py demos/rtthread --rtthread --idle-timeout 5
python tools/build_run.py demos/rtthread --rtthread --irq-mode unified
python tools/build_run.py demos/rtthread --rtthread --picolibc
python tools/build_run.py demos/rtthread51 --rtthread --rtthread-version 51 --idle-timeout 5
python tools/build_run.py demos/rtthread51 --rtthread --rtthread-version 51 --picolibc

# 只下载不监听 / 下载前不复位
python tools/build_run.py demos/nolibc/breathing --no-listen
python tools/build_run.py demos/nolibc/breathing --no-reset
```

构建参数（`--newlib` / `--clang` / `--clang-extra` / `--ld-extra` / `--lld` / `--rtthread` / `--rtthread-version` / `--irq-mode` / `--opt` / `--debug` / `--extra`）透传 build.py，运行参数（`--port` / `--baud` / `--idle-timeout`（默认 3s） / `--timeout` / `--until` / `--early-warn`（0 字节超 N 秒打印一次挂死/不匹配诊断，默认 6s） / `--log` / `--no-reset` / `--no-listen`）透传 uart_send.py。产物命名与 build.py 一致（默认 Os → `<demo>_os.uartbin`；`--opt O2` → `<demo>_o2.uartbin`；`--clang` → `<demo>_clang_<opt>.uartbin`）。

## build_riscv_tests.py — riscv-tests 编译

riscv-tests 源码不随本仓库分发，需先获取到 `third_party/riscv-tests`（官方仓库 [riscv/riscv-tests](https://github.com/riscv/riscv-tests)，BSD-3-Clause）：

```bash
git clone https://github.com/riscv/riscv-tests.git third_party/riscv-tests
```

构建以 `SDK/isa` 为工作目录，`third_party/riscv-tests` 只作为第三方源码来源（路径可用环境变量 `RISCV_TESTS_SRC` 覆盖）：

- `SDK/isa/env/`（`link.ld`、`riscv_test.h`、`ending.h`）是仓库内维护的 BD32 测试环境，随仓库提交；
- `SDK/isa/rv32ui`、`rv32um`、`rv64ui`、`macros` 是可再生成的官方源码与宏（不入库），缺失时脚本自动从 `third_party/riscv-tests/isa/` 复制补齐；`build_asm.py`（custom_asm）首次运行也会做同样处理。

其中 `riscv_test.h` 基于官方版本精简：去掉 PMP/SATP/陷阱向量等特权初始化，pass/fail 上报改为 x26/x27 以匹配 tb_core_top 判定；CSR/异常编码使用官方 `env/encoding.h`。

```bash
cd SDK
python tools/build_riscv_tests.py          # GCC
python tools/build_riscv_tests.py --clang  # Clang 汇编
```

产物输出到 `test_data/riscv-tests/`：`<test>.elf`、`<test>.dump`、`<test>.dat`（readmemh 字流）。

## LLVM/Clang 集成与代码体积优化

通过 `--clang` 开关启用。设计原则：Clang 只负责 `.c`/`.S` 的代码生成，链接默认仍由 xPack GCC 完成（因为官方 LLVM Windows 包不含 RISC-V compiler-rt builtins，需复用 xPack 的 libgcc）。

### 体积优化总览（三种途径可叠加）

1. **picolibc 精简 C 库**（`--picolibc`）——整数 printf 档，比 newlib-nano 小30%-60%；
1. **LLVM LTO**（`--clang --lld`，`-flto`）——跨文件优化，可以再减小约 5%，是体积优化的主力；
1. **ICF 相同代码折叠**（`--lld`，`--icf=all`）——折叠完全相同的代码段（对模板/库代码密集场景收益更大）。

**链接器选择**：默认（含 `--clang`）由 xPack GCC 驱动调用 `GNU ld` 链接，只有加 `--lld` 时才改用 LLVM 的链接器`ld.lld`——配合 `--clang` 的 `-flto` 启用 LTO，并始终开启 `--icf=all`。纯 GCC对象也可用 `--lld`（ICF 生效、无 LTO）。

极致最小组合：

```bash
cd SDK
python tools/build.py demos/newlib/coremark --picolibc --clang --lld
```

效果速览（CoreMark ITCM 词数，越小越好）：

| 配置 | 词数 |
|------|------|
| GCC `-Os`（newlib，基线） | 4379 |
| Clang `-Os`（newlib） | 4302 |
| Clang `-Os --lld`（newlib，LTO+ICF） | 4034 |
| Clang `-Os`（picolibc） | 2921 |
| **Clang `-Os --lld`（picolibc，LTO+ICF）** | **2739** |

注意：`--lld` 建议与 `-Os`/`-Oz` 搭配——LTO 在 O1/O2/O3 档内联激进，体积可能会反增。

### 三个体积优化开关

| 开关 | 作用 | 适用范围 |
|------|------|----------|
| `--clang-extra "..."` | 只传给 Clang .c 编译的参数（如关掉 MachineOutliner）；不会污染 GCC 汇编步骤 | 编译阶段 |
| `--ld-extra "..."` | 只传给链接阶段的参数，默认 GNU ld 时需带 `-Wl,` 前缀；`--lld` 时会自动转成 lld 参数 | 链接阶段 |
| `--lld` | 改用 LLVM LLD 链接：始终开启 `--gc-sections --icf=all`（相同代码折叠）；配合 `--clang` 时自动对 .c 加 `-flto`，实现 LTO | 链接阶段 |

`--lld` 不强制依赖 `--clang`：纯 GCC 对象也能用 LLD 链接并获得 ICF 收益，只是没有 LTO（GCC 的 `-flto` 在 xPack newlib-nano 上会丢 syscalls 符号，暂不支持）。GNU ld 本身不支持 `--icf`，所以 ICF 必须走 LLD。

## picolibc — 更小的 C 库（可选）

[picolibc](https://github.com/picolibc/picolibc) 是面向嵌入式系统的精简 C 库，比 newlib-nano 小得多。

### 构建（一次性）

```bash
SDK/tools/build_picolibc.bat              # 整数 printf 档（默认，最小）
SDK/tools/build_picolibc.bat f            # 浮点 printf 档
SDK/tools/build_picolibc.bat d            # double printf 档
```

### 使用

```bash
cd SDK
python tools/build.py demos/newlib/hello --picolibc
python tools/build.py demos/newlib/hello --picolibc --clang --lld   # 极致体积组合
python tools/build.py demos/newlib/hello --picolibc --picolibc-printf f  # 需要 %f 时
python tools/build_run.py demos/newlib/hello --picolibc             # 一键构建 + 上板
```

安装目录可用环境变量 `PICOLIBC_ROOT` 覆盖（默认 `third_party/picolibc-install`）。

### 限制

- 默认整数档（`format-default=i`）**不支持 `%f`/`%lf`**；确实需要浮点输出的程序先用 `build_picolibc.bat f` 构建浮点档，再以 `--picolibc-printf f` 链接。注意浮点档体积明显更大，能用整数格式（含 `print_fixed` 定点）就不要开浮点。CoreMark 的 `HAS_FLOAT=0`，因此`--picolibc` 整数档即可完整运行（CRC 与 newlib 版一致）。
- RT-Thread：两个内核版本均支持 `--rtthread [--rtthread-version 315|51] --picolibc`，适配方式、注意事项与实测收益见「RT-Thread 应用开发」→「picolibc 适配」。
- 不支持 `--picolibc` 与 `--newlib` 同时使用。

### CoreMark 23 配置自动对比

`tools/auto_coremark.py` 自动完成 **23 个配置**（GCC/LLVM × Os/O1/O2/O3/Oz × newlib-nano/picolibc，另含 picolibc LLVM 的 LLD（LTO+ICF）5 档变体）的构建产物上板测试：复位 → UART 下载 → 运行 → 解析输出（CoreMark/MHz、Iterations/Sec、Total ticks、分支预测率），ITCM/DTCM 词数从`.uartbin` 帧头解析，结果自动写入 `BD32_CoreMark_Compiler_Comparison.xlsx`（主表 + 以各 C 库 GCC O2 为基准的归一化对比 + Charts 数据页；目标文件被WPS/Excel 占用时自动写为带时间戳的备用文件，不中断测试）。

```bash
cd SDK
python tools/auto_coremark.py                        # 全部 23 配置
python tools/auto_coremark.py --libc picolibc        # 只跑 picolibc 配置
python tools/auto_coremark.py --compiler gcc --opt o2  # 只跑单个配置
python tools/auto_coremark.py --xlsx <输出路径>      # 自定义 Excel 路径
```

## HPM 性能计数器（固件视角）

计数器走**标准 RISC-V 地址**，复位即全计数（零配置），软件只需在需要时停止/清零。

### 地址表

| CSR | 语义 | CSR | 语义 |
|-----|------|-----|------|
| 0xB00/0xB80 | mcycle（64 位低/高半） | 0xB02/0xB82 | minstret |
| 0xB03 | ALU 指令数 | 0xB04 | LOAD 数 |
| 0xB05 | STORE 数 | 0xB06 | 条件分支数 |
| 0xB07 | JUMP 数 | 0xB08 | MUL/DIV 数（OITF 退休拍计数） |
| 0xB09 | 分支预测失败数 | 0xB0A/0xB0B/0xB0C | Zcb / B / Zcmp 指令数 |
| 0xB0D | CSR 指令数 | 0xB0E | 系统指令数（ecall/ebreak/mret/wfi/fence） |
| 0xB0F | load-use 停顿周期 | 0xB10 | OITF 等待周期 | 
| 0xB11 | 取指等待周期 | 0xBC0 | mcounterclr（按位写 1 清零，单拍脉冲，可读回） |

### 门控与清零语义

- **计数门控 = mcountinhibit(0x320)**，位号 = 计数器号（0=mcycle、2=minstret、3-17=mhpmcounter3-17）；**复位值全 0 = 上电即全计数**（刻意设计：BootROM 测频依赖 mcycle 复位后自动计数，若复位为停，启动代码必须先配置 CSR 才能测频；性能分析一律用窗口差值，上电段多计不影响口径），写 1 停对应计数器。WARL：只有位 0/2/3-17 可写。
- **mcounterclr(0xBC0) 按位写 1 清零**，单拍脉冲语义：写后下一拍自动归零，不会把计数器钉住。0xBC0 可读回。
- 停顿计数器（0xB0F-0xB11）为周期型：不依赖指令退休，仅受 mcountinhibit 门控。

### 固件用法示例

```c
#include "soc.h"   // 提供 read_csr/write_csr
#define CSR_MCYCLE      0xB00
#define CSR_MINSTRET    0xB02
#define CSR_MCOUNTINHIBIT 0x320
#define CSR_MCOUNTERCLR   0xBC0

write_csr(CSR_MCYCLE, 0);            // mcycle 清零（mcounterclr 位 0 亦可）
uint32_t t0 = read_csr(CSR_MCYCLE);
uint32_t i0 = read_csr(CSR_MINSTRET);
/* ... 被测代码 ... */
uint32_t cyc = read_csr(CSR_MCYCLE) - t0;
uint32_t ins = read_csr(CSR_MINSTRET) - i0;
// CPI = cyc / ins；停顿归因读 0xB0F/0xB10/0xB11（同窗口差值）
```

要点：
- **读差值口径**：做窗口测量时起止都要读，别拿复位以来绝对值当窗口值（否则 BootROM/启动代码全被计入）。**读 CSR 自身会 +1**：窗口内每次 `csrr` 也退休、也被计数，精确计数时按 K+1 计。
- **CoreMark 移植层（`core_main.c`）有可直接照抄的完整测量示例**：测量前后各读一次计数器取差值；除总周期/指令数外，把 ALU/访存/分支/乘除等每一类指令分别计数，并读停顿计数器（0xB0F-0xB11）做归因。它自带一个**自检**：所有分类计数相加必须等于 minstret（实际退休的指令总数）——对不上就说明 HPM 的计数语义变了（通常是 RTL 改动引入的回归），先把计数器修对再相信测量数字。

## MROM 构建

```bash
bash test_data/soc/build_mrom.sh
```

MROM（0x00000000，4KB）负责：上电测量 CPU 主频 → 计算 UART NCO 系数 → 跳转 ITCM 执行用户程序。

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

## RT-Thread 应用开发

BD32 内置 RT-Thread 双版本移植（lts-v3.1.x / v5.1.0），两种中断模式可选：CLINT mtime 系统节拍（1ms）、UART 控制台。验证流程（仿真/上板矩阵）见 [验证手册](verification.md)。

### 版本与目录

| 内核版本 | 内核源码（`third_party/`） | BSP（`SDK/bsp/`） | demo（`SDK/demos/`） |
|---|---|---|---|
| lts-v3.1.x（v3.1.5，默认） | `rt-thread-3.1.5` | `rtthread` | `rtthread` |
| v5.1.0 | `rt-thread-5.1.0` | `rtthread51` | `rtthread51` |

### 中断模式（`--irq-mode`）

RISC-V 机器模式中断编码（`mcause[11:0]`）中本移植用到三种：

- **3 号 = 机器软件中断（MSI）**：由 CLINT `msip` 触发，RT-Thread 用它请求"延迟切换"（PendSV 角色）；- **7 号 = 机器定时器中断（MTI）**：由 CLINT `mtime ≥ mtimecmp` 触发，驱动 1ms 系统 tick；- **11 号 = 机器外部中断（MEI）**：由 PLIC 转发外设中断（UART / GPIO / Timer 等）。

| 模式 | 工作方式 | 优点 | 缺点 | 适用场景 |
|---|---|---|---|---|
| `ch32`（默认） | 7/11 号走轻量入口，只保存 17 个 caller 寄存器；需要切换时写 `CLINT_MSIP` 触发 3 号软件中断，由 SW_handler 全量保存并延迟切换 | 常态中断只存 caller 寄存器，中断开销小、响应快 | 依赖软件中断与 `mscratch`；需要切换时多一次软件中断（两次 trap 路径） | 中断频繁、对中断延迟敏感（默认推荐） |
| `unified` | 3/7/11 全部走统一入口，全量保存 30 个寄存器，中断返回时检查切换 flag 直接切换 | 实现简单、代码量小；无软件中断依赖、不依赖 `mscratch`；切换单次 trap 完成 | 每次中断（含不需要切换的）都全量保存/恢复，常态中断开销大 | 中断不频繁、精简优先，或不想依赖软件中断/`mscratch` |

### 构建 / 仿真 / 上板

```bash
# 构建（默认 lts-v3.1.x + ch32 中断模式；--irq-mode unified 切换统一入口）
cd SDK
python tools/build.py demos/rtthread --rtthread
python tools/build.py demos/rtthread --rtthread --irq-mode unified
python tools/build.py demos/rtthread --rtthread --picolibc
python tools/build.py demos/rtthread51 --rtthread --rtthread-version 51
python tools/build.py demos/rtthread51 --rtthread --rtthread-version 51 --irq-mode unified
python tools/build.py demos/rtthread51 --rtthread --rtthread-version 51 --picolibc

# 仿真（80ms 窗口，输出 t1/t2 交替即通过；产物名不区分中断模式）
cd ../script/soc_test
vsim -batch -do "do rtthread_sim.do"             # lts-v3.1.x newlib：加载 rtthread_os_*.mem
vsim -batch -do "do rtthread_sim315_pico.do"     # lts-v3.1.x + picolibc：加载 rtthread_picolibc_os_*.mem
vsim -batch -do "do rtthread_sim51.do"           # v5.1.0 newlib：加载 rtthread51_os_*.mem
vsim -batch -do "do rtthread_sim51_pico.do"      # v5.1.0 + picolibc：加载 rtthread51_picolibc_os_*.mem

# 上板（COM8 举例；先构建再下载）
cd ../../..
python SDK/tools/uart_send.py test_data/soc/c/rtthread_os.uartbin --port COM8 --reset --idle-timeout 5
python SDK/tools/uart_send.py test_data/soc/c/rtthread_picolibc_os.uartbin --port COM8 --reset --idle-timeout 5
python SDK/tools/uart_send.py test_data/soc/c/rtthread51_os.uartbin --port COM8 --reset --idle-timeout 5
python SDK/tools/uart_send.py test_data/soc/c/rtthread51_picolibc_os.uartbin --port COM8 --reset --idle-timeout 5
```

四个组合也各有一键仿真脚本 `script/soc_test/run_rtthread_sim.bat` / `run_rtthread_sim315_pico.bat` / `run_rtthread_sim51.bat` / `run_rtthread_sim51_pico.bat`（输出 `logs/rtthread_sim*_out.txt`）；也可用 `python tools/build_run.py demos/rtthread --rtthread [--picolibc]` 一键构建 + 上板运行。串口输出 RT-Thread banner 后 t1/t2 持续交替打印即验证通过，仿真窗口取 80ms（soc_init 频率测量约占 10ms、UART 打印约占 11ms，需覆盖至少两轮 `mdelay` 毫秒延时唤醒以确认轮转稳定）。

### picolibc 适配

两个内核版本都支持 `--picolibc`，适配方式不同：v5.1.0 使用官方 `components/libc/compilers/picolibc` 适配层（`syscall.c` 提供每线程 errno 与 malloc 族 → `rt_malloc`，`exit.c` 提供 `_exit`）；lts-v3.1.x 使用 SDK 自带等价适配（`SDK/bsp/porting/picolibc_rtthread_syscall.c` + `picolibc_rtthread_exit.c`，官方适配层仅 v5.1.0 才有，且其 `exit.c` 依赖 `posix/stdlib.h` 与 `__rt_libc_exit`，3.1.x 均无）。

两者都跳过依赖设备控制台的 `iob.c`，改用 `picolibc_console.c`（stdin/stdout/stderr 直通 UART）；errno 走 `__PICOLIBC_ERRNO_FUNCTION` 钩子映射到线程 `error` 字段，不依赖 TLS。

体积收益取决于程序是否真正调用 C 标准库：调用 `printf`/`sprintf`/`malloc`/字符串函数的 RT-Thread 程序实测体积将大幅减小；只用 `rt_kprintf`/`rt_malloc`（libc 未被链接）时两库体积基本相同。

### 编写 RT-Thread 程序

一个 RT-Thread demo 就是一个带 `src/main.c` 的目录（如 `SDK/demos/<name>/src/main.c`），构建命令：`python tools/build.py demos/<name> --rtthread`（默认 lts-v3.1.x；加 `--rtthread-version 51` 用 v5.1.0）。

线程编写模板（每个线程独立配置栈大小 / 优先级 / 时间片）：

```c
#include <rtthread.h>

/* 线程参数：每个线程独立配置（栈大小、优先级、时间片可各不相同） */
#define T1_STACK_SIZE   4096
#define T1_PRIORITY     5
#define T1_TIMESLICE    20
#define T2_STACK_SIZE   2048
#define T2_PRIORITY     6
#define T2_TIMESLICE    10

static struct rt_thread t1, t2;
static rt_uint8_t t1_stack[T1_STACK_SIZE];
static rt_uint8_t t2_stack[T2_STACK_SIZE];

static void t1_entry(void *param)
{
    while (1) {
        rt_kprintf("t1\n");
        rt_thread_mdelay(100);          /* 主动让出 CPU，100ms 后恢复 */
    }
}

static void t2_entry(void *param)
{
    while (1) {
        rt_kprintf("t2\n");
        rt_thread_mdelay(100);
    }
}

int main(void)                          /* main 线程（RT_USING_USER_MAIN 自动创建） */
{
    rt_thread_init(&t1, "t1", t1_entry, RT_NULL,
                   t1_stack, sizeof(t1_stack), T1_PRIORITY, T1_TIMESLICE);
    rt_thread_init(&t2, "t2", t2_entry, RT_NULL,
                   t2_stack, sizeof(t2_stack), T2_PRIORITY, T2_TIMESLICE);
    rt_thread_startup(&t1);
    rt_thread_startup(&t2);
    return 0;
}
```

> RT-Thread 优先级数值越小优先级越高；只有**同优先级**线程之间才会发生时间片轮转，不同优先级是抢占调度（高优先级就绪即运行）。

要点：

- 入口 `main()` 由内核自动创建为 main 线程；业务线程用 `rt_thread_init`（静态栈）或 `rt_thread_create`（动态，从 8KB 系统堆分配）。
- 打印用 `rt_kprintf`（经 UART 控制台）；`rt_thread_mdelay` 让出 CPU。RT 模式已链接 newlib-nano，`printf`/`malloc` 也可用，但推荐统一走内核的 `rt_kprintf`/`rt_malloc`。
- 已开启的机制：信号量 / 互斥 / 事件 / 邮箱（见各版本 `rtconfig.h`）、系统堆 8KB、tick=1ms、优先级 0~7。
- 中断服务函数中不要调用会阻塞或触发调度的 API；时间片调度由 7 号定时器中断（+ 3 号软件中断，仅 ch32 模式）自动完成，用户无需干预。
- 内核源码（`third_party/`）只读，不做修改；板级适配在 `SDK/bsp/rtthread*`，移植细节见各文件注释（系统节拍、堆、栈、`RT_USING_SMALL_MEM_AS_HEAP` 等版本差异）。

> lts-v3.1.x 源码说明：官方 v3.1.5 tag 的 `include/libc/libc_signal.h` 无条件 `#include <signal.h>`，与新版 newlib 的 `sigevent`/`siginfo_t` 定义冲突；需按 lts-v3.1.x 分支改为 `#ifdef RT_USING_NEWLIB / #include <sys/signal.h> / #endif`（本次构建已应用）。
