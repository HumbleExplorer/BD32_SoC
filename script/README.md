# BD32 SoC 脚本使用说明

> 路径：`Working/script/`

---

## 脚本依赖关系一览

```
build.py  ───────────────── 独立（推荐，替代 elf2uartbin）
elf2uartbin.py  ─────────── 独立
build_c.bat  ───→ elf2uartbin.py  （第 2 步调用 elf2uartbin.py 生成 .uartbin）
bin2dat.py  ─────────────── 独立
run_all_riscv_tests.py  ─── 独立（仅依赖外部 ModelSim）
```

> 只有 `build_c.bat` **有依赖**（调用 `elf2uartbin.py`），其余脚本均可独立运行。
> `build.py` 内部整合了编译 + 格式生成全流程，是其他脚本的功能超集。

---

## 目录

- [1. build.py — 统一构建工具（推荐）](#1-buildpy--统一构建工具推荐)
- [2. elf2uartbin.py — UART 下载二进制生成器](#2-elf2uartbinpy--uart-下载二进制生成器)
- [3. build_c.bat — C 程序编译脚本（Windows）](#3-build_cbat--c-程序编译脚本windows)
- [4. bin2dat.py — 二进制 → Dat 格式转换](#4-bin2datpy--二进制--dat-格式转换)
- [5. run_all_riscv_tests.py — RISC-V CPU 批量测试](#5-run_all_riscv_testspy--risc-v-cpu-批量测试)
- [附录：测试子目录说明](#附录测试子目录说明)

---

## 1. build.py — 统一构建工具（推荐）

**路径：** `script/build.py`

这是最推荐使用的核心构建脚本。它将编译、链接、生成多种下载格式整合为一步，是 `elf2uartbin.py` 的超集替代。

### 基本用法

```bash
# 汇编程序 → 生成所有格式
python build.py myprog.s

# C 程序 → 生成所有格式（自动查找 lib/link.ld 和 lib/start.s）
python build.py main.c
```

### 指定输出格式

```bash
# 仅生成指定格式（逗号分隔）
python build.py main.c --formats elf,dump,mem

# 可用格式：all, dump, uartbin, mem, dat, hex
```

### 指定输出路径

```bash
python build.py main.c --output-dir ../test_data/custom --output-name demo
```

### C 编译时手动指定链接脚本和启动代码

```bash
python build.py main.c --ld ../lib/link.ld --start ../lib/start.s -I ../src
```

### 从已有 ELF 生成其他格式

```bash
python build.py program.elf --formats uartbin,mem,dump
```

### 参数说明

| 参数 | 缩写 | 说明 |
|------|------|------|
| `input` | — | 输入文件（.s / .c / .elf） |
| `--output-dir` | `-o` | 输出目录（默认：与输入文件同目录） |
| `--output-name` | `-n` | 输出文件名前缀（默认：输入文件名） |
| `--ld` | — | 链接脚本路径 |
| `--start` | — | 启动代码路径（C 程序必需） |
| `-I` | — | 头文件搜索路径（可重复使用） |
| `--formats` | — | 输出格式，逗号分隔。默认全部 |
| `--asm` | — | 强制汇编模式 |
| `--c` | — | 强制 C 模式 |
| `--verbose` | `-v` | 详细输出 |
| `--keep-elf` | — | 保留中间 ELF（默认清理） |

### 输出格式对照

| 格式 | 扩展名 | 用途 |
|------|--------|------|
| `dump` | `.dump` | 反汇编文本，调试用 |
| `uartbin` | `.uartbin` | **UART 下载二进制（含帧头），上板用** |
| `mem` | `_itcm.mem` / `_dtcm.mem` | hex 文本格式，仿真 `$readmemh` 加载 |
| `dat` | `.dat` | 裸 hex 文本，riscv-tests 风格 |
| `hex` | `.hex` | Intel HEX 格式 |
| `elf` | `.elf` | ELF 可执行文件（`--keep-elf` 保留） |

### 示例输出

```bash
$ python build.py ../test_data/asm/add.s --formats uartbin,mem --verbose

[BUILD] Assembling: add.s
  $ riscv64-unknown-elf-as -march=rv32im -mabi=ilp32 -o ...\add.o add.s
  $ riscv64-unknown-elf-ld -melf32lriscv -o ...\add.elf ...\add.o
  -> ...\add.elf

[GEN] Generating output formats: uartbin, mem
  [OK]  UART 下载二进制（含帧头） -> add.uartbin
  [OK]  hex 文本格式（$readmemh 兼容） -> add_itcm.mem, add_dtcm.mem

[DONE] Output directory: D:\Desktop\OpenClaw_Workspace\test_data\asm
       Formats generated: uartbin, mem

  提示：上板下载时直接发送 add.uartbin
```

---

## 2. elf2uartbin.py — UART 下载二进制生成器

**路径：** `script/elf2uartbin.py`

将 ELF 文件打包为带帧头的 `.uartbin` 格式，可直接通过串口发送到 FPGA 板。

### 格式说明

二进制布局（全部小端字节序）：
```
[0x00] START_FRAME  (4B) = 0xBBAABBAA
[0x04] ITCM_COUNT   (4B) = ITCM 数据字数
[0x08] ITCM 数据          = ITCM_COUNT × 4B
[...]  DTCM_COUNT   (4B) = DTCM 数据字数
[...]  DTCM 数据          = DTCM_COUNT × 4B
```

### 用法

```bash
# 从 ELF 生成
python elf2uartbin.py program.elf program.uartbin

# 从汇编源码一步到位
python elf2uartbin.py program.s program.uartbin --as

# 从 C 源码一步到位
python elf2uartbin.py main.c program.uartbin --c --start ../lib/start.s --ld ../lib/link.ld

# 指定头文件路径
python elf2uartbin.py main.c output.uartbin --c --start ../lib/start.s --ld ../lib/link.ld -I ../src
```

### 参数

| 参数 | 说明 |
|------|------|
| `--c` | C 模式（需要 `--start` 和 `--ld`） |
| `--start <file>` | 启动代码路径 |
| `--ld <file>` | 链接脚本路径 |
| `-I <dir>` | 头文件搜索路径 |

### 注意

- 输入 `.s`（汇编）或 `.elf`（已有 ELF）时无需 `--start`/`--ld`
- 未指定参数时自动从 `../lib/` 查找 `link.ld` 和 `start.s`
- **推荐直接使用 `build.py` 替代本脚本**（功能更全）

---

## 3. build_c.bat — C 程序编译脚本（Windows）

**路径：** `script/build_c.bat`

Windows Batch 脚本，一键编译 C 程序并生成 `.uartbin` 和 `.dump`。

### 用法

直接双击或命令行运行：
```cmd
build_c.bat
```

### 配置说明（编辑脚本中的变量）

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `SRC_DIR` | C 源码目录 | `..\src` |
| `LIB_DIR` | 库文件目录 | `..\lib` |
| `OUT_DIR` | 输出目录 | `..\test_data\custom` |
| `PROG` | 程序名（不包含扩展名） | `minimal` |

### 工作流程

1. 编译 `%SRC_DIR%\main.c` + `%LIB_DIR%\start.s` + `%LIB_DIR%\tinyprintf.c`
2. 调用 `elf2uartbin.py` 生成 `.uartbin`
3. 反汇编生成 `.dump`

### 注意

- 仅适用于 Windows 环境
- 硬编码了 `minimal` 程序名，修改其他程序需编辑 `PROG` 变量
- 输出文件位于 `../test_data/custom/`

---

## 4. bin2dat.py — 二进制 → Dat 格式转换

**路径：** `script/bin2dat.py`

将任意二进制文件转换为 `$readmemh` 兼容的 `.dat` 文本格式（每行一个 32 位 hex 字）。

### 用法

```bash
# 直接转换，输出文件名自动替换扩展名
python bin2dat.py input.bin

# 指定输出文件名
python bin2dat.py input.bin output.dat
```

### 注意事项

- 自动补齐到 4 字节对齐（末尾补 0）
- 小端字节序转换

---

## 5. run_all_riscv_tests.py — RISC-V CPU 批量测试

**路径：** `script/run_all_riscv_tests.py`

利用 ModelSim 批量运行 RISC-V 指令兼容性测试，输出 PASS/FAIL 汇总报告。

### 用法

```bash
cd Working/script
python run_all_riscv_tests.py
```

### 工作流程

1. 清理 `core_test/work/` 目录
2. 编译所有 RTL（带 `+define+CORE_TEST`）
3. 遍历 `../test_data/rv32*.dat` 逐个跑仿真
4. 收集结果 → 汇总表格

### 测试文件匹配规则

- `rv32ui-p-*.dat` — RV32I 用户级指令测试
- `rv32um-p-*.dat` — RV32M 乘除法扩展测试

### 配置项（脚本顶部可修改）

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `VSIM_PATH` | ModelSim vsim 所在目录 | `D:\modeltech64_2020.4\win64` |
| `SIM_TIME_US` | 每测试仿真时长（微秒） | `50` |
| `TIMEOUT_SEC` | 每测试超时（秒） | `60` |

### 依赖

- ModelSim SE-64 2020.4（vsim 需在 PATH 或通过 `VSIM_PATH` 指定）
- `Working/script/core_test/` 目录下需存在 `filelist.f`、`run.do` 等仿真文件

### 输出示例

```
╔══════════════════════════════════════════════════════════════╗
║  BD32 RISC-V CPU — 批量测试运行器                            ║
╚══════════════════════════════════════════════════════════════╝

  vsim: D:\modeltech64_2020.4\win64\vsim.exe
  vlog: D:\modeltech64_2020.4\win64\vlog.exe

  Found 48 test files

  Checking vsim license ... OK

============================================================
  Step 1: Compiling RTL with +define+CORE_TEST ...
============================================================
  [OK] Compilation successful

============================================================
  Step 2: Running 48 tests
============================================================

  [ 1/48] rv32ui-p-add ... PASS (2.4s)
  [ 2/48] rv32ui-p-addi ... PASS (2.1s)
  ...

============================================================
  RISC-V Tests Summary
============================================================
  Test Name                      Result     Detail
  -------------------------------------------------------
  rv32ui-p-add                   PASS
  rv32ui-p-addi                  PASS
  ...
  -------------------------------------------------------
  Passed:  48
  Total:   48  (elapsed: 112.3s)
============================================================
```

---

## 附录：测试子目录说明

`script/` 下还包含以下测试子目录，每个目录对应一个模块的 ModelSim 仿真环境：

| 目录 | 用途 |
|------|------|
| `core_test/` | CPU 核级仿真（含 `run.do`、`filelist.f`、`top_tb.bat`） |
| `gpio_test/` | GPIO 模块仿真 |
| `plic_test/` | PLIC 中断控制器仿真（另有 `run_xsim.tcl`） |
| `soc_test/` | SoC 系统级仿真 |
| `timer_test/` | Timer 模块仿真 |
| `uart_test/` | UART 模块仿真 |

每个子目录结构统一：
```
xxx_test/
├── filelist.f       # 文件列表
├── modelsim.ini     # ModelSim 配置
├── run.do           # ModelSim 运行脚本
├── top_tb.bat       # 一键仿真启动脚本（双击运行）
└── work/            # 编译输出目录（自动生成）
```

仿真只需进入对应目录，双击 `top_tb.bat` 或运行：
```cmd
cd Working/script/core_test
top_tb.bat
```

ModelSim 会自动编译、启动仿真并加载波形。
