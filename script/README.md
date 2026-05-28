# BD32 SoC 脚本使用说明

> 路径：`Working/script/`

---

## 脚本一览

```
run_all_riscv_tests.py  ← 独立（RISC-V CPU 批量测试，仅依赖外部 ModelSim）
core_test/              ← CPU 核级仿真
gpio_test/              ← GPIO 模块仿真
plic_test/              ← PLIC 中断控制器仿真
soc_test/               ← SoC 系统级仿真
timer_test/             ← Timer 模块仿真
uart_test/              ← UART 模块仿真
```

> **构建工具已迁移至 `SDK/tools/build.py`**，请使用：
> ```bash
> cd Working/SDK
> python tools/build.py demos/<demo_name>
> python tools/build.py demos/<demo_name> --newlib
> ```

---

## 目录

- [1. run_all_riscv_tests.py — RISC-V CPU 批量测试](#1-run_all_riscv_testspy--risc-v-cpu-批量测试)
- [附录：测试子目录说明](#附录测试子目录说明)

---

## 1. run_all_riscv_tests.py — RISC-V CPU 批量测试

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
